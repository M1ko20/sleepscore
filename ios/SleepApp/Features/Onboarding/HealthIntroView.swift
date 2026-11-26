import SwiftUI

/// Krok 4: Apple Health – co čteme a co nikdy.
struct HealthIntroView: View {
    var onDone: () -> Void
    @State private var busy = false
    @State private var request = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Apple Health").font(Font.app.title).foregroundStyle(Color.app.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Čteme").statLabel()
                row("Spánek: fáze a probuzení")
                row("Tep během spánku")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Nikdy").statLabel()
                row("Nic dalšího z Apple Health")
                row("Nic do reklamy, nic nikomu dalšímu")
            }
            Text("Ruční záznamy se nepočítají. Jen data z hodinek nebo prstenu.").captionStyle()

            Spacer()
            Button(busy ? "Čekám na Zdraví…" : "Povolit") {
                busy = true
                Task {
                    // Už rozhodnuté (nebo bez Zdraví) → dál bez okna, nečekat na modifikátor.
                    if await HealthSync.shared.needsAuthorizationPrompt() { request += 1 }
                    else { busy = false; onDone() }
                }
            }
            .buttonStyle(.primary)
            .disabled(busy)
        }
        .padding(Metrics.screenPadding)
        // Odmítnutí není chyba – appka jen nebude mít data. iOS neřekne, co uživatel povolil.
        .healthAccessRequest(trigger: request) {
            busy = false
            onDone()
        }
    }

    private func row(_ text: String) -> some View {
        Text(text).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
    }
}
