import SwiftUI

@main
struct SleepApp: App {
    @State private var session = Session()

    init() {
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Color.app.textPrimary)
                .task { session.start() }
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        ZStack {
            Color.app.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                EmptyView()
            case .signedOut:
                WelcomeFlow()
            case .needsProfile:
                OnboardingFlow()
            case .ready:
                MainTabView()
            case .offline:
                OfflineView()
            }
        }
    }
}

struct OfflineView: View {
    @Environment(Session.self) private var session
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Bez připojení").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
            Text("Server neodpovídá. Zkus to za chvíli.").captionStyle()
            Spacer()
            Button(busy ? "Zkouším…" : "Zkusit znovu") {
                busy = true
                Task { await session.retry(); busy = false }
            }
            .buttonStyle(.secondary)
            .disabled(busy)
            Button("Odhlásit") { Task { await session.signOut() } }
                .buttonStyle(.plainText)
        }
        .padding(Metrics.screenPadding)
    }
}
