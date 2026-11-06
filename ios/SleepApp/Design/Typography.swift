import SwiftUI

/// Typografie podle docs/design.md. Systémové SF Pro.
struct AppFonts {
    let scoreXL = Font.system(size: 72, weight: .black).width(.condensed).monospacedDigit()
    let scoreL = Font.system(size: 44, weight: .heavy).width(.condensed).monospacedDigit()
    let stat = Font.system(size: 22, weight: .bold).monospacedDigit()
    let title = Font.system(size: 20, weight: .bold)
    let body = Font.system(.body).weight(.regular)          // 16–17 pt, dynamic type
    let label = Font.system(size: 11, weight: .semibold)
    let caption = Font.system(.footnote)                    // 13 pt, dynamic type
}

extension Font {
    static let app = AppFonts()
}

/// Rozměry: mřížka 4 pt.
enum Metrics {
    static let screenPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let buttonHeight: CGFloat = 50
}

extension View {
    /// Sportovní popisek statistik: VERZÁLKY, prostrkání.
    func statLabel() -> some View {
        self.font(Font.app.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Color.app.textSecondary)
    }

    func captionStyle() -> some View {
        self.font(Font.app.caption).foregroundStyle(Color.app.textSecondary)
    }

    /// Karta: tón pozadí + tenká linka, žádný stín.
    func cardStyle(highlighted: Bool = false) -> some View {
        self.padding(Metrics.screenPadding)
            .background(Color.app.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius)
                    .strokeBorder(highlighted ? Color.app.accent : Color.app.hairline, lineWidth: 1)
            )
    }
}
