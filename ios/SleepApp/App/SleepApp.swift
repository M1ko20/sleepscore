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
                DevLoginView()
            case .needsProfile, .ready:
                MainTabView()
            }
        }
    }
}
