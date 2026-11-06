import SwiftUI

/// Avatar: zatím iniciála (fotky profilů přijdou se Storage).
struct Avatar: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Color.app.surfaceRaised)
            .overlay(Circle().strokeBorder(Color.app.hairline, lineWidth: 1))
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.app.textPrimary)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Popisek + hodnota (sportovní statistika).
struct StatBlock: View {
    let value: String
    let label: String
    var font: Font = Font.app.stat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(font).foregroundStyle(Color.app.textPrimary).lineLimit(1)
            Text(label).statLabel()
        }
        .accessibilityElement(children: .combine)
    }
}
