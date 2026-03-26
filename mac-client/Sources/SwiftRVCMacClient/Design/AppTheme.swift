import SwiftUI

enum AppTheme {
    static let shellRadius: CGFloat = 18
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12

    static let aluminumTop = Color(hex: 0xF0F0F2)
    static let aluminumBottom = Color(hex: 0xD6D7DB)
    static let aluminumBorder = Color(hex: 0xFBFBFC)
    static let panelShadow = Color.black.opacity(0.22)
    static let contactShadow = Color.black.opacity(0.28)
    static let liftShadow = Color.black.opacity(0.18)
    static let hardShadow = Color.black.opacity(0.26)
    static let labelInk = Color(hex: 0x66676B)
    static let valueInk = Color(hex: 0x4E5259)

    static let knobBlue = Color(hex: 0x1E3246)
    static let knobOchre = Color(hex: 0xB59257)
    static let knobGrey = Color(hex: 0x858585)
    static let knobOrange = Color(hex: 0xE84A1B)
    static let knobWhite = Color(hex: 0xF0F0F2)
    static let ledGreen = Color(hex: 0x4AF626)
    static let busyTrack = Color(hex: 0x090B10)
    static let busyGlowIndigo = Color(hex: 0x231557)
    static let busyGlowViolet = Color(hex: 0x44107A)
    static let busyGlowPink = Color(hex: 0xFF1361)
    static let busyGlowYellow = Color(hex: 0xFFF800)

    static let highlight = Color.white.opacity(0.92)
    static let shadowColor = Color.black.opacity(0.22)

    static let windowGradient = LinearGradient(
        colors: [
            Color(hex: 0xF7F7F8),
            Color(hex: 0xF2F2F4),
            Color(hex: 0xF7F7F8),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let consoleShellGradient = LinearGradient(
        colors: [
            Color(hex: 0xF3F3F5),
            aluminumTop,
            Color(hex: 0xE1E2E6),
            aluminumBottom,
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let controlWellGradient = LinearGradient(
        colors: [
            Color(hex: 0xF8F8F9),
            Color(hex: 0xE7E8EC),
            Color(hex: 0xD5D8DE),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelGradient = LinearGradient(
        colors: [
            Color(hex: 0xFAFAFB),
            Color(hex: 0xECEEF2),
            Color(hex: 0xD9DCE2),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let selectedNavigationGradient = LinearGradient(
        colors: [
            Color(hex: 0xF7F7F8),
            Color(hex: 0xE7E7EA),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
