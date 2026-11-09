import SwiftUI

/// Dvě zaškrtávátka před založením profilu a při nových podmínkách: podmínky + výslovný souhlas
/// se zdravotními údaji. Bez obou nejde pokračovat (souhlas musí být aktivní, ne předvyplněný).
struct ConsentChecks: View {
    @Binding var terms: Bool
    @Binding var health: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(isOn: $terms, id: "consentTerms") {
                Text(.init(Legal.termsConsentMarkdown))
            }
            row(isOn: $health, id: "consentHealth") {
                Text(Legal.healthConsent)
            }
        }
    }

    private func row<L: View>(isOn: Binding<Bool>, id: String, @ViewBuilder label: () -> L) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { isOn.wrappedValue.toggle() } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn.wrappedValue ? Color.app.textPrimary : Color.app.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn.wrappedValue ? "Zaškrtnuto" : "Nezaškrtnuto")
            .accessibilityIdentifier(id)
            label()
                .font(Font.app.caption)
                .foregroundStyle(Color.app.textSecondary)
                .tint(Color.app.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
