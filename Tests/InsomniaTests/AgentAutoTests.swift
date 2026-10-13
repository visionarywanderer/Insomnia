import Foundation
import XCTest
@testable import Insomnia

/// Auto mode end to end against a real manager: hook reports in, an Auto
/// session starts, ends after the idle grace, and the Mac is asked to sleep
/// only when nobody is using it.
@MainActor
final class AgentAutoTests: XCTestCase {
    private var h: Harness!
    private var manager: SessionManager!
    private let userIdle = Locked<TimeInterval>(3600)

    override func setUp() async throws {
        h = Harness()
        manager = h.makeManager()
        manager.config.autoMode = true
        manager.config.autoIdleGrace = 60
    }

    override func tearDown() async throws {
        h.home.destroy()
    }

    private func makeAuto() -> AutoController {
        let clock = h.clock
        let lid = h.clamshell
        let idle = userIdle
        return AutoController(
            manager: manager,
            paths: h.home.paths,
            sleeper: h.lidSleep,
            clock: { clock.now },
            lidClosed: { lid.closed },
            userIdleSeconds: { idle.value },
            alive: { _ in true }
        )
    }

    private func report(_ busy: Bool, source: String = "claude", session: String = "s1") {
        let json = Data("{\"session_id\":\"\(session)\"}".utf8)
        XCTAssertEqual(AgentActivity.run(["--agent", busy ? "busy" : "idle", "--source", source], stdin: json, paths: h.home.paths, now: h.clock.now, owner: getpid()), 0)
    }

    func testABusyAgentStartsAnAutoSessionAndItEndsAfterTheGraceThenSleeps() async {
        let auto = makeAuto()
        await auto.tick()
        XCTAssertFalse(manager.isActive, "nothing working, nothing started")

        report(true)
        await auto.tick()
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.isAuto, true)
        XCTAssertEqual(auto.busyAgents.map(\.source), ["claude"])

        h.clock.advance(30)
        report(false)
        await auto.tick()
        XCTAssertTrue(manager.isActive, "inside the grace")

        h.clock.advance(31)
        await auto.tick()
        XCTAssertFalse(manager.isActive, "every agent idle for the grace")
        XCTAssertEqual(h.lidSleep.requests.count, 1, "lid open and nobody at the Mac: sleep asked")
    }

    func testSomeoneUsingTheMacGetsSleepBackButNoForcedSleep() async {
        let auto = makeAuto()
        userIdle.value = 5
        report(true)
        await auto.tick()
        h.clock.advance(1)
        report(false)
        h.clock.advance(61)
        await auto.tick()
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(h.lidSleep.requests.isEmpty)
    }

    func testAnyAgentStillWorkingKeepsTheSessionAndATimedSessionIsLeftAlone() async {
        let auto = makeAuto()
        report(true, source: "claude", session: "a")
        report(true, source: "codex", session: "b")
        await auto.tick()
        report(false, source: "claude", session: "a")
        h.clock.advance(120)
        report(true, source: "codex", session: "b")
        await auto.tick()
        XCTAssertTrue(manager.isActive, "codex is still working")
        _ = await manager.end(reason: .user)

        await manager.start(duration: 3600)
        report(false, source: "codex", session: "b")
        h.clock.advance(120)
        await auto.tick()
        XCTAssertTrue(manager.isActive, "a timed session is not Auto's to end")
        XCTAssertEqual(manager.session?.isAuto, false)
    }

    func testAutoOffIgnoresReports() async {
        manager.config.autoMode = false
        let auto = makeAuto()
        report(true)
        await auto.tick()
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(auto.busyAgents.isEmpty)
    }
}
