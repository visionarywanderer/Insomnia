import AppKit
import XCTest
@testable import Insomnia

final class UIStatusTests: XCTestCase {
    @MainActor
    func testStatusHostUsesIntrinsicSizingAndHasAnIdleFittingSize() {
        let harness = Harness()
        defer { harness.home.destroy() }
        let root = StatusRootView(
            manager: harness.makeManager(),
            onTap: {},
            onWidthChange: { _ in }
        )

        let host = StatusItemController.makeHostingView(root)

        XCTAssertTrue(host.sizingOptions.contains(.intrinsicContentSize))
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    @MainActor
    func testTickAnimationIsShorterThanBaseAndHoldIsSubSecond() {
        XCTAssertEqual(Motion.holdDuration, 0.6, accuracy: 0.0001)
        XCTAssertLessThan(Motion.holdDuration, 1)
        XCTAssertEqual(Motion.tick(reduceMotion: true), Motion.reduced)
        XCTAssertNotEqual(Motion.tick(reduceMotion: false), Motion.base)
    }

    /// The blink was over in a handful of frames and barely read. It has to
    /// be slower than the baseline spring so the lid lift and the lash
    /// hand-over are seen, and slower than the Reduce Motion crossfade too.
    @MainActor
    func testTheBlinkIsSlowerThanTheBaseSpring() {
        XCTAssertGreaterThan(Motion.blinkResponse, Motion.baseResponse)
        XCTAssertEqual(Motion.blink(opening: true, reduceMotion: false), .spring(response: 0.95, dampingFraction: 0.9))
        XCTAssertEqual(Motion.blink(opening: false, reduceMotion: false), .spring(response: 0.8, dampingFraction: 0.95))
        XCTAssertEqual(Motion.blink(opening: true, reduceMotion: false), Motion.blink)
        XCTAssertNotEqual(Motion.blink, Motion.base)
        XCTAssertEqual(Motion.blink(opening: true, reduceMotion: true), .easeInOut(duration: 0.3))
        XCTAssertEqual(Motion.blink(opening: false, reduceMotion: true), .easeInOut(duration: 0.3))
        XCTAssertGreaterThan(Motion.reducedBlinkDuration, 0.15)
    }

    func testCountdownShapeIsDerivedFromSessionSpan() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Session(startedAt: t0, endsAt: t0.addingTimeInterval(30 * 60)).countdownShape, .minutes)
        XCTAssertEqual(Session(startedAt: t0, endsAt: t0.addingTimeInterval(3600)).countdownShape, .hours)
        XCTAssertEqual(Session(startedAt: t0, endsAt: t0.addingTimeInterval(4 * 3600)).countdownShape, .hours)
        XCTAssertEqual(Session(startedAt: t0, endsAt: t0.addingTimeInterval(2 * 86400)).countdownShape, .days)
        // The shape rides on the persisted span, so it comes back identical after a reload.
        let s = Session(startedAt: t0, endsAt: t0.addingTimeInterval(4 * 3600))
        let data = try! JSONEncoder().encode(s)
        XCTAssertEqual(try! JSONDecoder().decode(Session.self, from: data).countdownShape, .hours)
    }

    @MainActor
    func testCountdownTextTicksInHoursShapeAndPausesWithLid() async {
        let h = Harness()
        defer { h.home.destroy() }
        let m = h.makeManager()
        await m.start(duration: 4 * 3600)
        XCTAssertEqual(m.countdownText, "4:00:00")
        XCTAssertEqual(m.remainingText, "4h")

        h.clock.advance(3 * 3600 + 55 * 60 + 53)
        m.refreshCountdown()
        XCTAssertEqual(m.countdownText, "0:04:07")
        XCTAssertEqual(m.remainingText, "4m")

        m.pauseCountdown()
        h.clock.advance(60)
        XCTAssertEqual(m.countdownText, "0:04:07")
        m.resumeCountdown()
        XCTAssertEqual(m.countdownText, "0:03:07")

        await m.end(reason: .user)
        XCTAssertEqual(m.countdownText, "")
    }

    @MainActor
    func testCountdownTextUsesMinutesShapeForShortSession() async {
        let h = Harness()
        defer { h.home.destroy() }
        let m = h.makeManager()
        await m.start(duration: 30 * 60)
        XCTAssertEqual(m.countdownText, "30:00")
        h.clock.advance(29 * 60 + 51)
        m.refreshCountdown()
        XCTAssertEqual(m.countdownText, "00:09")
    }

    func testSleepHeldLine() {
        XCTAssertEqual(
            SleepHeldLine.line(sessionActive: true, sleepHeld: true),
            SleepHeldLine.Line(text: "Sleep held per journal \u{2014} not verified live", isWarning: false)
        )
        XCTAssertEqual(
            SleepHeldLine.line(sessionActive: true, sleepHeld: false),
            SleepHeldLine.Line(text: "Sleep is not held \u{2014} this session is not keeping the Mac awake", isWarning: true)
        )
        XCTAssertEqual(
            SleepHeldLine.line(sessionActive: false, sleepHeld: true),
            SleepHeldLine.Line(text: "Sleep still held with no session", isWarning: true)
        )
        XCTAssertNil(SleepHeldLine.line(sessionActive: false, sleepHeld: false))
    }

    @MainActor
    func testPlaceholderReportsNothing() {
        let s = PlaceholderStatus()
        XCTAssertFalse(s.lidClosed)
        XCTAssertNil(s.batteryPercent)
        XCTAssertFalse(s.isCharging)
        XCTAssertNil(s.wifiSSID)
        XCTAssertNil(s.lastGap)
        XCTAssertEqual(s.frozenCount, 0)
        XCTAssertFalse(s.dockerPaused)
        XCTAssertTrue(s.throttledBrowsers.isEmpty)
        XCTAssertNil(s.hotspotPasswordReport)
        XCTAssertNil(s.instantWatts())
        s.refreshInstant()
        s.refreshOnDemand()
        s.relaunchUnthrottled(ThrottledBrowser(bundleId: "com.google.Chrome", name: "Chrome"))
    }

    func testMachineLine() {
        XCTAssertEqual(
            StatusLines.machine(lidClosed: true, watts: 4.12, wifiSSID: "iPhone", batteryPercent: nil, isCharging: false),
            "Lid: closed \u{00B7} 4.1 W \u{00B7} Wi-Fi: iPhone"
        )
        XCTAssertEqual(
            StatusLines.machine(lidClosed: false, watts: nil, wifiSSID: nil, batteryPercent: nil, isCharging: false),
            "Lid: open"
        )
        XCTAssertEqual(
            StatusLines.machine(lidClosed: false, watts: nil, wifiSSID: "", batteryPercent: 82, isCharging: true),
            "Lid: open \u{00B7} 82% charging"
        )
    }

    func testActionsLine() {
        XCTAssertNil(StatusLines.actions(frozenCount: 0, dockerPaused: false, lastGap: nil))
        XCTAssertEqual(StatusLines.actions(frozenCount: 3, dockerPaused: true, lastGap: nil), "3 apps frozen \u{00B7} Docker paused")
        XCTAssertEqual(StatusLines.actions(frozenCount: 1, dockerPaused: false, lastGap: 12.4), "1 app frozen \u{00B7} last gap 12s")
        XCTAssertEqual(StatusLines.actions(frozenCount: 0, dockerPaused: true, lastGap: 0), "Docker paused")
    }

    func testThrottleWarning() {
        XCTAssertNil(StatusLines.throttleWarning([]))
        XCTAssertEqual(StatusLines.throttleWarning(["Chrome"]), "\u{26A0} Chrome is throttled")
        XCTAssertEqual(StatusLines.throttleWarning(["Chrome", "Arc"]), "\u{26A0} Chrome and Arc are throttled")
        XCTAssertEqual(StatusLines.throttleWarning(["Chrome", "Arc", "Chromium"]), "\u{26A0} Chrome, Arc, and Chromium are throttled")
    }

    func testMenuListsStatusThenSettingsAndQuit() {
        let items = StatusMenu.items(
            sessionActive: true,
            sleepHeld: true,
            machine: "Lid: closed \u{00B7} 82%",
            actions: "3 apps frozen",
            throttledBrowsers: [Self.chrome],
            error: nil
        )
        XCTAssertEqual(items, [
            StatusMenu.Item(title: "Sleep held per journal \u{2014} not verified live", kind: .info),
            StatusMenu.Item(title: "Lid: closed \u{00B7} 82%", kind: .info),
            StatusMenu.Item(title: "3 apps frozen", kind: .info),
            StatusMenu.Item(title: "\u{26A0} Chrome is throttled", kind: .warning),
            StatusMenu.Item(title: "Relaunch Chrome unthrottled", kind: .relaunchBrowser(Self.chrome)),
            StatusMenu.Item(title: "", kind: .separator),
            StatusMenu.Item(title: StatusMenu.settingsTitle, kind: .settings),
            StatusMenu.Item(title: StatusMenu.quitTitle, kind: .quit),
        ])
    }

    func testIdleMenuIsJustSettingsAndQuitWithNoLeadingSeparator() {
        let items = StatusMenu.items(
            sessionActive: false,
            sleepHeld: false,
            machine: nil,
            actions: nil,
            throttledBrowsers: [],
            error: ""
        )
        XCTAssertEqual(items, [
            StatusMenu.Item(title: StatusMenu.settingsTitle, kind: .settings),
            StatusMenu.Item(title: StatusMenu.quitTitle, kind: .quit),
        ])
        XCTAssertFalse(items.contains { $0.kind == .separator })
    }

    func testMenuShowsTheLastErrorAsAWarning() {
        let items = StatusMenu.items(
            sessionActive: false,
            sleepHeld: false,
            machine: nil,
            actions: nil,
            throttledBrowsers: [],
            error: "sudo: a password is required"
        )
        XCTAssertEqual(items.first, StatusMenu.Item(title: "\u{26A0} sudo: a password is required", kind: .warning))
        XCTAssertEqual(items.map(\.kind), [.warning, .separator, .settings, .quit])
    }

    /// A hotspot join skipped for want of a password is a warning line in
    /// the menu, between the browser items and the session error, so the
    /// failure is never silent.
    func testMenuShowsTheHotspotPasswordProblemAsAWarning() {
        let items = StatusMenu.items(
            sessionActive: true,
            sleepHeld: true,
            machine: nil,
            actions: nil,
            throttledBrowsers: [Self.chrome],
            hotspotWarning: HotspotPasswordProblem.unreadable.menuLine,
            error: "sudo: a password is required"
        )
        XCTAssertEqual(
            items.map(\.kind),
            [.info, .warning, .relaunchBrowser(Self.chrome), .warning, .warning, .separator, .settings, .quit]
        )
        XCTAssertEqual(items[3], StatusMenu.Item(
            title: "\u{26A0} Hotspot password unreadable by this build: enter it again in Settings",
            kind: .warning
        ))
        XCTAssertEqual(
            StatusMenu.items(sessionActive: false, sleepHeld: false, machine: nil, actions: nil, throttledBrowsers: [], hotspotWarning: nil, error: nil).map(\.kind),
            [.settings, .quit]
        )
    }

    /// Each problem has a menu line, a sentence for the notification, and a
    /// Settings notice except for a missing item, where the empty field is
    /// the notice.
    func testHotspotPasswordProblemCopy() {
        XCTAssertEqual(HotspotPasswordProblem.missing.menuLine, "\u{26A0} Hotspot password not saved: enter it in Settings")
        XCTAssertNil(HotspotPasswordProblem.missing.settingsNotice)
        XCTAssertTrue(HotspotPasswordProblem.unreadable.settingsNotice?.contains("Enter it again and save") ?? false)
        XCTAssertTrue(HotspotPasswordProblem.unreadable.explanation.hasSuffix("Enter it again in Settings."))
        XCTAssertEqual(HotspotPasswordProblem.error("keychain: boom").menuLine, "\u{26A0} Hotspot password unreadable: keychain: boom")
        XCTAssertEqual(HotspotPasswordProblem.error("keychain: boom").settingsNotice, "The saved password can't be read: keychain: boom")
        XCTAssertEqual(KeychainError(status: errSecAuthFailed).problem, .unreadable)
        XCTAssertEqual(KeychainError(status: errSecInteractionNotAllowed).problem, .unreadable)
        XCTAssertEqual(KeychainError(status: errSecInvalidOwnerEdit).problem, .unreadable)
        XCTAssertEqual(KeychainError(status: errSecParam).problem, .error("keychain: One or more parameters passed to a function were not valid."))
    }

    /// The relaunch item asks first, since the browser is quit and its
    /// windows come back only through its own session restore. Cancel
    /// hands nothing on; confirming hands on the bundle id and name the
    /// item carried, even when a scan emptied the list during the alert.
    @MainActor
    func testRelaunchAsksBeforeQuittingAndCancelDoesNothing() {
        _ = NSApplication.shared
        let h = Harness()
        defer { h.home.destroy() }
        let source = RecordingStatusSource()
        source.throttledBrowsers = [Self.chrome, Self.arc]
        let asked = Locked<[String]>([])
        let answer = Locked(false)
        let controller = StatusItemController(
            manager: h.makeManager(),
            status: source,
            showSettings: {},
            confirmRelaunch: { name in
                asked.value.append(name)
                source.throttledBrowsers = []
                return answer.value
            }
        )

        controller.relaunchBrowser(Self.chrome)
        XCTAssertEqual(asked.value, ["Chrome"])
        XCTAssertEqual(source.relaunched, [])

        answer.value = true
        controller.relaunchBrowser(Self.arc)
        XCTAssertEqual(asked.value, ["Chrome", "Arc"])
        XCTAssertEqual(source.relaunched, [Self.arc])
    }

    private static let chrome = ThrottledBrowser(bundleId: "com.google.Chrome", name: "Chrome")
    private static let arc = ThrottledBrowser(bundleId: "company.thebrowser.Browser", name: "Arc")

    /// The prompt names the browser, says the windows depend on the
    /// browser's own startup setting, and gives the 10 s rule.
    func testRelaunchPromptCopy() {
        let prompt = RelaunchPrompt(browser: "Chrome")
        XCTAssertEqual(prompt.title, "Quit and relaunch Chrome?")
        XCTAssertEqual(
            prompt.message,
            "Insomnia quits Chrome and opens it again with the two flags that stop it throttling hidden windows. Your windows and tabs come back only if Chrome is set to reopen them on startup. If Chrome has not quit after 10 s, nothing is relaunched."
        )
        XCTAssertEqual(RelaunchPrompt.confirmTitle, "Quit and relaunch")
        XCTAssertEqual(RelaunchPrompt.cancelTitle, "Cancel")
    }

    /// Greptile caught this as a regression: replacing the popover with a
    /// menu left the throttle warning with no way to act on it.
    func testEveryThrottledBrowserGetsItsOwnRelaunchItem() {
        let items = StatusMenu.items(
            sessionActive: true,
            sleepHeld: true,
            machine: nil,
            actions: nil,
            throttledBrowsers: [Self.chrome, Self.arc],
            error: nil
        )
        XCTAssertEqual(items.filter { $0.kind == .relaunchBrowser(Self.chrome) }.count, 1)
        XCTAssertEqual(items.filter { $0.kind == .relaunchBrowser(Self.arc) }.count, 1)
        XCTAssertEqual(
            items.map(\.kind),
            [.info, .warning, .relaunchBrowser(Self.chrome), .relaunchBrowser(Self.arc), .separator, .settings, .quit]
        )
    }

}

/// A status source that records relaunch requests and reports nothing else.
@MainActor
@Observable
final class RecordingStatusSource: StatusSource {
    var lidClosed = false
    var batteryPercent: Int? = nil
    var isCharging = false
    var wifiSSID: String? = nil
    var lastGap: TimeInterval? = nil
    var frozenCount = 0
    var dockerPaused = false
    var throttledBrowsers: [ThrottledBrowser] = []
    var relaunchProblems: [String] = []
    var hotspotPasswordReport: HotspotPasswordReport? = nil
    private(set) var relaunched: [ThrottledBrowser] = []

    func refreshOnDemand() {}
    func refreshInstant() {}
    func instantWatts() -> Double? { nil }
    func relaunchUnthrottled(_ browser: ThrottledBrowser) { relaunched.append(browser) }
}
