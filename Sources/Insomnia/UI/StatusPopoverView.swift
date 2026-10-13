import AppKit
import SwiftUI

/// What the eye opens: a standard popover to start a session, or to see,
/// extend and end the one running. System colors and controls only, so it
/// follows light and dark mode and the accent color like any Mac app.
struct StatusPopoverView: View {
    let manager: SessionManager
    let auto: AutoController?
    let onSetAuto: (Bool) -> Void
    let onStart: (TimeInterval) -> Void
    let onExtend: (TimeInterval) -> Void
    let onEnd: () -> Void
    let onSettings: () -> Void

    /// A preset's length, or nil for "Until" (the time picker).
    @State private var choice: TimeInterval??
    @State private var until = Self.defaultUntil()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if auto != nil {
                autoSection
                Divider()
            }
            if manager.isActive { running } else { idle }
            if let error = manager.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Settings\u{2026}", action: onSettings)
                Spacer()
                Button("Quit Insomnia") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.isActive ? "eye" : "eye.slash")
                .font(.title2)
                .foregroundStyle(manager.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.isActive ? "Keeping your Mac awake" : "Your Mac can sleep")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var subtitle: String {
        guard let s = manager.session else { return "Start a session to keep it awake, lid closed too." }
        if s.isAuto { return "Auto \u{00B7} until your agents are done" }
        return "Until \(s.endsAt.formatted(date: .omitted, time: .shortened)) \u{00B7} \(manager.countdownText) left"
    }

    // MARK: Auto

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { manager.config.autoMode }, set: { onSetAuto($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto")
                    Text("Stay awake while agents work, then sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if manager.config.autoMode, let auto {
                if auto.busyAgents.isEmpty {
                    Text("No agent working right now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(auto.busyAgents) { agent in
                        Label {
                            Text("\(Self.displayName(agent.source)) working")
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func displayName(_ source: String) -> String {
        switch source {
        case "claude": "Claude Code"
        case "codex": "Codex"
        default: source
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Keep awake for", selection: selection) {
                ForEach(manager.config.presets, id: \.self) { p in
                    Text(chipLabel(for: p)).tag(Optional(p))
                }
                Divider()
                Text("Until a time\u{2026}").tag(TimeInterval?.none)
            }
            if selection.wrappedValue == nil {
                DatePicker("Until", selection: $until, displayedComponents: .hourAndMinute)
            }
            Button {
                if let duration = startDuration { onStart(duration) }
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(startDuration == nil)
        }
    }

    /// The picked preset, starting on the default one.
    private var selection: Binding<TimeInterval?> {
        Binding(
            get: {
                if let picked = choice { return picked }
                return manager.config.defaultPreset
            },
            set: { choice = .some($0) }
        )
    }

    private var startDuration: TimeInterval? {
        if let preset = selection.wrappedValue { return preset }
        return Self.duration(until: until, now: Date())
    }

    /// Seconds from `now` to the next time the clock reads `until`'s hour
    /// and minute: later today, or tomorrow when that time has passed.
    static func duration(until: Date, now: Date, calendar: Calendar = .current) -> TimeInterval? {
        let hm = calendar.dateComponents([.hour, .minute], from: until)
        guard let next = calendar.nextDate(after: now, matching: hm, matchingPolicy: .nextTime) else { return nil }
        return next.timeIntervalSince(now)
    }

    static func defaultUntil(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
    }

    // MARK: Running

    private var running: some View {
        HStack {
            if manager.session?.isAuto != true {
                extendMenu
            }
            Spacer()
            Button("End Session", role: .destructive, action: onEnd)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private var extendMenu: some View {
        Menu("Extend") {
            ForEach(manager.config.presets, id: \.self) { p in
                Button("+ \(chipLabel(for: p))") { onExtend(p) }
            }
        }
        .fixedSize()
    }
}
