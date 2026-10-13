import CoreGraphics

/// The app icon's two colours, as plain values. The icon generator compiles
/// this file directly, so it needs neither SwiftUI nor AppKit. Everything
/// drawn in the app itself uses system colours, so it follows light and
/// dark mode and the accent colour.
enum BrandPalette {
    struct RGB: Equatable, Sendable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        init(hex: UInt32) {
            red = CGFloat((hex >> 16) & 0xFF) / 255
            green = CGFloat((hex >> 8) & 0xFF) / 255
            blue = CGFloat(hex & 0xFF) / 255
        }

        var cgColor: CGColor {
            CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])!
        }
    }

    /// App icon tile: a mid charcoal grey.
    static let midnight = RGB(hex: 0x303336)
    /// The mark on the app icon: a warm off-white.
    static let moonWhite = RGB(hex: 0xE6E3DD)
}
