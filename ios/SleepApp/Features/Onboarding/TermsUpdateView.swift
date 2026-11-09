import SwiftUI

/// Člen bez souhlasu s aktuální verzí podmínek (beta účty, změna podmínek) – #20.
struct TermsUpdateView: View {
    @Environment(Session.self) private var session
    @State private var busy = false
    @State private var error: String?
    @State private var termsOK = false
    @State private var healthOK = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Nové podmínky")
                .font(Font.app.title)
                .foregroundStyle(Color.app.textPrimary)
            Text("Upravili jsme podmínky a zásady ochrany soukromí. Než budeš pokračovat, potvrď prosím obojí.")
                .captionStyle()
            ConsentChecks(terms: $termsOK, health: $healthOK)
                .padding(.top, 12)
            if let error {
                Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary)
            }
            Spacer()
            Button(busy ? "Ukládám…" : "Souhlasím") { accept() }
                .buttonStyle(.primary)
                .disabled(busy || !termsOK || !healthOK)
                .accessibilityIdentifier("acceptTerms")
            Button("Odhlásit") { Task { await session.signOut() } }
                .buttonStyle(.plainText)
                .frame(maxWidth: .infinity)
        }
        .padding(Metrics.screenPadding)
    }

    private func accept() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await session.acceptTerms() } catch { self.error = serverMessage(error) }
        }
    }
}
