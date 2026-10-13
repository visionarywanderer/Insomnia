import CoreGraphics
import Foundation
import Observation

/// Auto mode. While it is on, a hooked agent starting work starts an Auto
/// session, and once every agent has been done or waiting for
/// `autoIdleGrace` the session ends and the Mac sleeps:
///
/// - lid closed: the end owes a sleep (`EndReason.agentIdle`), asked by
///   `SessionManager` as for a timer end;
/// - lid open: asked here, but only when nobody has touched the keyboard or
///   mouse for the grace period. Someone using the Mac only gets sleep
///   back to normal.
///
/// Timed sessions are never touched. Polls the reports every few seconds;
/// each is a small file, and nothing runs when Auto is off.
@MainActor
@Observable
final class AutoController {
    static let pollInterval: TimeInterval = 5

    /// The agents working at the last poll, oldest report first.
    private(set) var busyAgents: [AgentReport] = []

    @ObservationIgnored private let manager: SessionManager
    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private let sleeper: any ClosedLidSleeping
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let lidClosed: @Sendable () -> Bool?
    @ObservationIgnored private let userIdleSeconds: @Sendable () -> TimeInterval
    @ObservationIgnored private let alive: (AgentReport) -> Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticking = false
    /// When an agent was last seen working; the idle grace counts from here.
    @ObservationIgnored private(set) var lastBusyAt: Date?
    @ObservationIgnored private let launchedAt: Date

    init(
        manager: SessionManager,
        paths: Paths,
        sleeper: any ClosedLidSleeping = IOKitClosedLidSleep(),
        clock: @escaping @Sendable () -> Date = { Date() },
        lidClosed: @escaping @Sendable () -> Bool? = { LidObserver.readClamshellState() },
        userIdleSeconds: @escaping @Sendable () -> TimeInterval = AutoController.secondsSinceLastInput,
        alive: @escaping (AgentReport) -> Bool = { AgentActivity.isAlive($0) }
    ) {
        self.manager = manager
        self.paths = paths
        self.sleeper = sleeper
        self.clock = clock
        self.lidClosed = lidClosed
        self.userIdleSeconds = userIdleSeconds
        self.alive = alive
        launchedAt = clock()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One poll. Internal so tests drive it with a fake clock.
    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        let config = manager.config
        guard config.autoMode else {
            busyAgents = []
            return
        }
        let now = clock()
        busyAgents = AgentActivity.busyAgents(paths: paths, now: now, alive: alive)
        if !busyAgents.isEmpty {
            lastBusyAt = now
            if manager.session == nil {
                Log.info("auto: \(busyAgents.map(\.source).joined(separator: ", ")) working, starting an Auto session")
                await manager.start(duration: config.autoMaxDuration, auto: true)
            }
            return
        }
        guard let session = manager.session, session.isAuto else { return }
        // A session restored at launch has no busy time seen yet: it
        // counts from whichever is later, its start or this launch.
        let idleSince = lastBusyAt ?? max(session.startedAt, launchedAt)
        guard now.timeIntervalSince(idleSince) >= config.autoIdleGrace else { return }
        let closed = lidClosed() == true
        let userAway = userIdleSeconds() >= config.autoIdleGrace
        Log.info("auto: no agent working for \(Int(config.autoIdleGrace)) s, ending the Auto session")
        _ = await manager.end(reason: .agentIdle)
        lastBusyAt = nil
        guard !closed, manager.session == nil else { return }
        guard userAway else {
            Log.info("auto: the Mac is in use, so it is left awake")
            return
        }
        do {
            try sleeper.requestSleep()
            Log.info("auto: sleep requested")
        } catch {
            Log.error("auto: sleep request refused: \(error.localizedDescription)")
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }
}
