import SwiftUI

/// Barevné tokeny podle docs/design.md. Jen tmavý režim, nikde jinde natvrdo hex.
struct AppColors {
    let bg = Color(hex: 0x0B0D12)
    let surface = Color(hex: 0x14171F)
    let surfaceRaised = Color(hex: 0x1C2029)
    let hairline = Color(hex: 0x262B36)
    let textPrimary = Color(hex: 0xF2F1EC)
    let textSecondary = Color(hex: 0x9AA0AB)
    let textTertiary = Color(hex: 0x5D636E)
    let accent = Color(hex: 0xF5C542)
    let accentInk = Color(hex: 0x0B0D12)
    let destructive = Color(hex: 0xFF5A4E)

    /// Fáze spánku (hypnogram), od nejmělčí po nejhlubší.
    let stageAwake = Color(hex: 0xE8E4D8)
    let stageREM = Color(hex: 0x7FB4FF)
    let stageCore = Color(hex: 0x3D6FD1)
    let stageDeep = Color(hex: 0x2A4BB0)
    var heartRate: Color { textPrimary.opacity(0.4) }
}

extension Color {
    static let app = AppColors()

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension ShapeStyle where Self == Color {
    static var app: AppColors { Color.app }
}
