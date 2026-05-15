import SwiftUI

/// iOS 26 Liquid Glass shell palette from docs/browser-ui-mobile.html.
/// Dark base, white-tinted glass, violet AI accent.
enum DarkPalette {
    static let bg0 = Color(hex: 0x0B0B0F)
    static let bg1 = Color(hex: 0x111118)
    static let bg2 = Color(hex: 0x16161F)

    static let surface   = Color.white.opacity(0.05)
    static let surfaceHi = Color.white.opacity(0.09)
    static let border    = Color.white.opacity(0.07)
    static let borderHi  = Color.white.opacity(0.18)

    static let text     = Color(hex: 0xECECEE)
    static let textDim  = Color(hex: 0x9A9AA5)
    static let textSoft = Color(hex: 0x6B6B76)

    static let accent  = Color(hex: 0xB69CFF)
    static let accent2 = Color(hex: 0x7FB8FF)
    static let ok      = Color(hex: 0x7FE0B0)
}
