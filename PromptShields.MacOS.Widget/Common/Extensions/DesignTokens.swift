import SwiftUI

// Design tokens from the Feb 2025 macOS app redesign (see PRD `prompt-shields-app-redesign.html`).
// These supersede the ad-hoc colors in `Color.swift` for new UI. Existing call sites remain valid.

extension Color {
    // Surfaces
    static let psBg = Color(hex: "F7F6F3")       // --bg
    static let psBg2 = Color(hex: "EFEDE8")      // --bg2 (sidebar, titlebar)
    static let psBg3 = Color(hex: "E5E3DC")      // --bg3 (hover, inactive tag)
    static let psSurface = Color(hex: "FFFFFF")

    // Borders
    static let psBorder = Color(hex: "DDDBD4")
    static let psBorder2 = Color(hex: "C8C6BE")

    // Text
    static let psText = Color(hex: "1A1916")
    static let psText2 = Color(hex: "4A4840")
    static let psText3 = Color(hex: "8C8A82")

    // Primary blue
    static let psBlue = Color(hex: "1A5CFF")
    static let psBlueHover = Color(hex: "1550E8")
    static let psBlueLight = Color(hex: "E8EEFF")
    static let psBlueMid = Color(red: 26 / 255, green: 92 / 255, blue: 255 / 255, opacity: 0.12)

    // Active / success
    static let psGreen = Color(hex: "0A7C4E")
    static let psGreenLight = Color(hex: "E6F5EF")

    // Amber (permission banner)
    static let psAmber = Color(hex: "B45309")
    static let psAmberLight = Color(hex: "FEF3C7")
    static let psAmberBorder = Color(red: 180 / 255, green: 83 / 255, blue: 9 / 255, opacity: 0.2)

    // Red (risk)
    static let psRed = Color(hex: "C0392B")
    static let psRedLight = Color(red: 192 / 255, green: 57 / 255, blue: 43 / 255, opacity: 0.08)
}

// Radius scale from --r-sm..--r-xl in the mockup.
enum PSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let pill: CGFloat = 100
}

enum PSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let panel: CGFloat = 24
}
