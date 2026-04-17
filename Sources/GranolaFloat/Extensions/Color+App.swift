import SwiftUI
import OatsCore

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

extension Attendee {
    var avatarColor: Color {
        Color(hex: Attendee.avatarPalette[avatarPaletteIndex])
    }
}

extension Color {
    static let cream          = Color(red: 0.925, green: 0.906, blue: 0.851)  // #ECE7D9
    static let creamHover     = Color(red: 0.890, green: 0.863, blue: 0.784)  // #E3DCC8
    static let creamDivider   = Color(red: 0.831, green: 0.804, blue: 0.722)  // #D4CDB8
    static let textPrimary    = Color(red: 0.157, green: 0.149, blue: 0.122)  // #28261F
    static let textSecondary  = Color(red: 0.659, green: 0.639, blue: 0.604)  // #A8A39A
    static let granolaGreen   = Color(red: 0.314, green: 0.478, blue: 0.275)  // #507A46
    static let granolaLight   = Color(red: 0.918, green: 0.949, blue: 0.910)  // #EBF2E8
    static let checkboxBorder = Color(red: 0.710, green: 0.686, blue: 0.627)  // #B5AFA0
    static let sectionLabel   = Color(red: 0.659, green: 0.639, blue: 0.604)  // #A8A39A
    static let badgeBg        = Color(red: 0.851, green: 0.824, blue: 0.737)  // #D9D2BC
    static let fieldBg        = Color(red: 0.980, green: 0.973, blue: 0.957)  // #FAF8F4 — warm white for input fields
}
