import AppKit
import XCTest
@testable import Insomnia

/// The popover's actions, through the controller, against a real manager.
final class UIPopoverTests: XCTestCase {
    @MainActor
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), what)
    }

    @MainActor
    func testStartExtendAndEndGoThroughTheManager() async {
        _ = NSApplication.shared
        let h = Harness()
        defer { h.home.destroy() }
        let manager = h.makeManager()
        let controller = StatusItemController(manager: manager, status: PlaceholderStatus(), showSettings: {})

        controller.extend(by: 3600)
        controller.endNow()
        XCTAssertFalse(manager.isActive, "extend and end do nothing without a session")

        controller.start(duration: 2 * 3600)
        await waitUntil("the session started") { manager.isActive }
        let first = manager.session?.endsAt

        controller.extend(by: 3600)
        await waitUntil("the session was extended") { manager.session?.endsAt != first }
        XCTAssertEqual(manager.session?.endsAt, first?.addingTimeInterval(3600))

        controller.endNow()
        await waitUntil("the session ended") { !manager.isActive }
    }

    @MainActor
    func testTheStatusItemShowsTheCountdownOnlyWhileASessionRuns() async {
        _ = NSApplication.shared
        let h = Harness()
        defer { h.home.destroy() }
        let manager = h.makeManager()
        func width() -> CGFloat {
            StatusItemController.makeHostingView(StatusRootView(manager: manager, onTap: {}, onWidthChange: { _ in })).fittingSize.width
        }
        let idle = width()
        await manager.start(duration: 3600)
        XCTAssertGreaterThan(width(), idle, "the countdown is drawn beside the eye")
        _ = await manager.end(reason: .user)
        XCTAssertEqual(width(), idle, accuracy: 0.5)
    }
}
