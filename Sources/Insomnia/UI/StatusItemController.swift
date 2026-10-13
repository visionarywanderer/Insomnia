import AppKit
import SwiftUI

/// Owns the NSStatusItem: the eye (and the countdown) in the menu bar, a
/// standard popover on a left click, and the status NSMenu on a right click.
@MainActor
final class StatusItemController: NSObject {
    /// Builds the width writer over `apply` (which sets the item's length);
    /// tests inject one that records every write.
    typealias WidthWriterFactory = @MainActor (_ apply: @escaping (CGFloat) -> Void) -> StatusWidthWriter

    let manager: SessionManager
    let status: any StatusSource
    /// Auto mode, shown and switched in the popover; nil in tests that do
    /// not need it.
    let auto: AutoController?
    let reminder = ReminderScheduler()
    /// Opens the settings window. Injected because the window is owned by the
    /// app delegate, which outlives any one status item.
    private let showSettings: () -> Void
    private let makeWidthWriter: WidthWriterFactory?
    /// Asks before a browser is quit for a relaunch; true means go ahead.
    /// Injected so tests never see the NSAlert.
    private let confirmRelaunch: @MainActor (String) -> Bool

    private let statusItem: NSStatusItem
    private var hostingView: StatusHostingView?
    private var widthWriter: StatusWidthWriter?
    let popover = NSPopover()

    /// The width the status item is heading for.
    private(set) var widthTarget: CGFloat = 0
    /// The width the hosting view is laid out at (the widest content it has held).
    var hostWidth: CGFloat { hostingView?.frame.width ?? 0 }

    /// Autosave name so macOS remembers where the user drags the item.
    static let autosaveName = "insomnia.status"

    init(
        manager: SessionManager,
        status: any StatusSource,
        auto: AutoController? = nil,
        showSettings: @escaping () -> Void,
        makeWidthWriter: WidthWriterFactory? = nil,
        confirmRelaunch: (@MainActor (String) -> Bool)? = nil
    ) {
        self.manager = manager
        self.status = status
        self.auto = auto
        self.showSettings = showSettings
        self.makeWidthWriter = makeWidthWriter
        self.confirmRelaunch = confirmRelaunch ?? Self.askBeforeRelaunch
        Self.seedPreferredPositionIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = [.terminationOnRemoval]
        super.init()
        installHostingView()
        installPopover()
        observeManager()
    }

    // MARK: Status item

    /// New status items are appended at the left of the existing group. On a
    /// crowded menu bar (notch Macs) that lands in the hidden overflow, so the
    /// item exists but is never seen. Seed a position near the right end the
    /// first time only; after that macOS keeps whatever the user drags to.
    static func seedPreferredPositionIfNeeded(defaults: UserDefaults = .standard) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(40, forKey: key)
    }

    private func installHostingView() {
        guard let button = statusItem.button else { return }
        let apply: (CGFloat) -> Void = { [statusItem] width in statusItem.length = width }
        widthWriter = makeWidthWriter?(apply) ?? StatusWidthWriter(apply: apply)
        let root = StatusRootView(
            manager: manager,
            onTap: { [weak self] in self?.iconTapped() },
            onWidthChange: { [weak self] w in self?.retargetWidth(w) }
        )
        let host = Self.makeHostingView(root)
        host.onRightMouseDown = { [weak self] in self?.showMenu() }
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.height]
        host.frame = NSRect(x: 0, y: 0, width: 0, height: button.bounds.height)
        button.addSubview(host)
        button.title = ""
        button.image = nil
        // SwiftUI handles the clicks; the cell must not paint a highlight.
        (button.cell as? NSButtonCell)?.highlightsBy = []
        hostingView = host
        // The layout may already have reported while the host was measured
        // above, before `hostingView` was set: size the host here.
        host.frame.size.width = max(widthTarget, host.fittingSize.width.rounded(.up), 24)
        retargetWidth(host.fittingSize.width)
    }

    /// Centralizes the AppKit/SwiftUI boundary so its sizing contract can be
    /// regression-tested independently of a live menu bar.
    static func makeHostingView(_ root: StatusRootView) -> StatusHostingView {
        let host = StatusHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        return host
    }

    /// Set the item's length to `width`, once; a repeat of the current
    /// target is ignored. The host only ever grows, so the countdown on its
    /// way out has room while the length narrows over it.
    private func retargetWidth(_ width: CGFloat) {
        let w = max(width.rounded(.up), 24)
        guard w != widthTarget else { return }
        widthTarget = w
        if let host = hostingView, host.frame.width < w {
            host.frame.size.width = w
        }
        widthWriter?.write(w)
    }

    private var button: NSStatusBarButton? { statusItem.button }

    // MARK: Popover

    private func installPopover() {
        popover.behavior = .transient
        popover.animates = !Motion.reduceMotion
        popover.contentViewController = NSHostingController(rootView: StatusPopoverView(
            manager: manager,
            auto: auto,
            onSetAuto: { [weak self] on in self?.setAutoMode(on) },
            onStart: { [weak self] d in self?.start(duration: d) },
            onExtend: { [weak self] d in self?.extend(by: d) },
            onEnd: { [weak self] in self?.endNow() },
            onSettings: { [weak self] in self?.menuOpenSettings() }
        ))
    }

    /// Left click on the eye or the countdown: toggle the popover.
    func iconTapped() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button else { return }
        // An accessory app is never active on its own; without this the
        // popover's buttons and Return would not reach it.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: Manager observation

    /// Sessions can start or end without the UI (reconcile at launch, the
    /// deadline timer, the battery floor). Keep the reminder in step.
    private func observeManager() {
        withObservationTracking {
            _ = manager.session
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reminder.sync(endsAt: self.manager.session?.endsAt)
                self.observeManager()
            }
        }
    }

    // MARK: Session actions

    func start(duration: TimeInterval) {
        popover.performClose(nil)
        Task { @MainActor in await manager.start(duration: duration) }
    }

    func extend(by duration: TimeInterval) {
        guard manager.isActive else { return }
        Task { @MainActor in await manager.extend(by: duration) }
    }

    /// The popover's Auto switch, saved like a Settings change.
    func setAutoMode(_ on: Bool) {
        guard manager.config.autoMode != on else { return }
        manager.config.autoMode = on
        do {
            try manager.store.saveConfig(manager.config)
        } catch {
            Log.error("could not save config: \(error.localizedDescription)")
        }
        Task { @MainActor in await auto?.tick() }
    }

    func endNow() {
        guard manager.isActive else { return }
        popover.performClose(nil)
        Task { @MainActor in _ = await manager.end(reason: .user) }
    }

    // MARK: Right-click menu

    /// Right-click (or ctrl-click) on the status item. Not assigned to
    /// `statusItem.menu`, which would swallow the left click the pills need.
    private func showMenu() {
        guard let button else { return }
        // The lid, the battery and the watts are read right here, so the menu
        // opens on what the machine is doing now. The SSID and the throttled
        // browser list are whatever the last scan found: both have to be
        // awaited, and an open NSMenu blocks the main actor, so there is no
        // moment at which they could be filled into a menu that is already up.
        // Kick that scan off anyway, for the next opening.
        status.refreshInstant()
        status.refreshOnDemand()
        // Same for the foreign-sleep line: re-read the bit now, and let the
        // next opening drop the line if sleep is enabled again.
        Task { await manager.recheckForeignSleep() }
        let menu = StatusMenu.menu(
            Self.menuItems(manager: manager, status: status),
            target: self,
            settings: #selector(menuOpenSettings),
            quit: #selector(menuQuit),
            relaunchBrowser: #selector(menuRelaunchBrowser(_:)),
            stopWaitingForOutput: #selector(menuStopWaitingForOutput(_:))
        )
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// The menu's lines from what the session and the status source report
    /// now. Static, so a test can check them without a status item.
    static func menuItems(manager: SessionManager, status: any StatusSource) -> [StatusMenu.Item] {
        StatusMenu.items(
            sessionActive: manager.isActive,
            sleepHeld: manager.state.sleepDisabledByUs,
            machine: StatusLines.machine(
                lidClosed: status.lidClosed,
                watts: status.instantWatts(),
                wifiSSID: WiFiStatusName.display(
                    ssid: status.wifiSSID,
                    locationAuthorized: (status as? LiveStatusSource)?.locationPermission.isAuthorized ?? true
                ),
                batteryPercent: status.batteryPercent,
                isCharging: status.isCharging
            ),
            actions: StatusLines.actions(
                frozenCount: status.frozenCount,
                dockerPaused: status.dockerPaused,
                lastGap: status.lastGap
            ),
            throttledBrowsers: status.throttledBrowsers,
            relaunchProblems: status.relaunchProblems,
            // A report about an SSID edited away since is not shown.
            hotspotWarning: status.hotspotPasswordReport?.problem(for: manager.config.hotspotSSID)?.menuLine,
            error: manager.lastError,
            commandRunning: manager.commandWarning,
            foreignSleep: manager.foreignSleepWarning,
            outputsWaiting: manager.outputsWaitingForRestore,
            lidSimulationBuild: LidSimulationBuild.isCompiledIn
        )
    }

    @objc private func menuStopWaitingForOutput(_ sender: NSMenuItem) {
        guard let waiting = sender.representedObject as? SavedAudioOutput else { return }
        Task { await manager.stopWaitingForOutput(waiting) }
    }

    @objc private func menuRelaunchBrowser(_ sender: NSMenuItem) {
        guard let browser = sender.representedObject as? ThrottledBrowser else { return }
        relaunchBrowser(browser)
    }

    /// The relaunch item: ask first, since the browser is quit and its
    /// windows come back only through its own session restore. Cancel does
    /// nothing. Confirming hands on the bundle id and name the item
    /// carried; a scan that replaced the browser list while the alert was
    /// up does not change them.
    func relaunchBrowser(_ browser: ThrottledBrowser) {
        guard confirmRelaunch(browser.name) else { return }
        status.relaunchUnthrottled(browser)
    }

    private static func askBeforeRelaunch(_ name: String) -> Bool {
        let prompt = RelaunchPrompt(browser: name)
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: RelaunchPrompt.confirmTitle)
        alert.addButton(withTitle: RelaunchPrompt.cancelTitle)
        // A menu bar app has no window to carry the alert; bring the app
        // forward so the alert is not behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func menuOpenSettings() {
        openSettings()
        showSettings()
    }

    // MARK: Settings

    private func openSettings() {
        popover.performClose(nil)
    }
}

/// The SwiftUI host covers the status bar button, so the right click has to
/// be caught here rather than on the button. Ctrl-click is the same gesture
/// on a one-button mouse.
final class StatusHostingView: NSHostingView<StatusRootView> {
    var onRightMouseDown: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightMouseDown?()
            return
        }
        super.mouseDown(with: event)
    }
}
