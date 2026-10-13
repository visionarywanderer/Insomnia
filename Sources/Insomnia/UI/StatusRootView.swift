import AppKit
import SwiftUI

/// Everything drawn inside the status item: the eye, and the countdown while
/// a timed session runs. A click opens the popover (`StatusPopoverView`).
///
/// It reports its width when that changes; the controller writes the status
/// item's length to it once (`StatusWidthWriter`).
struct StatusRootView: View {
    let manager: SessionManager
    let onTap: () -> Void
    let onWidthChange: (CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    private var reduceMotion: Bool { reduceMotionEnv || Motion.reduceMotion }

    var body: some View {
        HStack(spacing: 5) {
            EyeMarkView(isRunning: manager.isActive, reduceMotion: reduceMotion)
                .frame(width: 20, height: 20)
            if manager.isActive, !manager.countdownText.isEmpty {
                Text(manager.countdownText)
                    .font(.system(size: 13).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.tick(reduceMotion: reduceMotion), value: manager.countdownText)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: NSStatusBar.system.thickness)
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            onWidthChange(width)
        }
        // The host is kept as wide as the widest content it has held, so the
        // content must sit at its leading edge rather than centred in it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manager.isActive ? "Insomnia, \(manager.countdownText) left" : "Insomnia")
        .accessibilityAddTraits(.isButton)
    }
}
