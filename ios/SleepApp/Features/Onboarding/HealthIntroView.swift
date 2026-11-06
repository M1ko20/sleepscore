import SwiftUI

/// Krok 4: Apple Health – co čteme a co nikdy.
/// TODO(krok 4 – HealthKit): tlačítko spustí HKHealthStore.requestAuthorization.
struct HealthIntroView: View {
    var onDone: () -> Void

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
            Button("Povolit", action: onDone).buttonStyle(.primary)
        }
        .padding(Metrics.screenPadding)
    }

    private func row(_ text: String) -> some View {
        Text(text).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
    }
}
