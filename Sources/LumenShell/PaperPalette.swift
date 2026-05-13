import SwiftUI

/// Paper-edition палитра из docs/browser-ui-mobile-paper.html.
/// Warm paper background, ink text, vermilion/sage/gold акценты.
/// Используется shell-chrome'ом (AddressBar, BrowserView) и теми
/// lumen-fast-app'ами что хотят жить «в комнате» с браузером.
enum PaperPalette {
    // Background tones
    static let paper   = Color(hex: 0xF2EDE2)
    static let paper2  = Color(hex: 0xEAE3D2)
    static let paper3  = Color(hex: 0xDDD3BE)
    static let card    = Color(hex: 0xFBF7EC)

    // Foreground / ink
    static let ink     = Color(hex: 0x1A1612)
    static let ink2    = Color(hex: 0x5B5347)
    static let ink3    = Color(hex: 0x8A8275)
    static let ink4    = Color(hex: 0xB5AC9B)

    // Rules / dividers
    static let rule    = Color.black.opacity(0.10)
    static let ruleHi  = Color.black.opacity(0.18)

    // Accents
    static let vermilion = Color(hex: 0xB33B26)
    static let sage      = Color(hex: 0x4A6B5C)
    static let gold      = Color(hex: 0xC9963A)

    // Glass overlay tones (background для blur-капсулы)
    static let glassFillTop    = Color(red: 1, green: 0.992, blue: 0.961).opacity(0.85)
    static let glassFillBottom = Color(red: 1, green: 0.992, blue: 0.961).opacity(0.55)
    static let glassStroke     = Color.black.opacity(0.12)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
