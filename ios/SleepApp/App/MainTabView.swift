import SwiftUI

struct MainTabView: View {
    @State private var feed = FeedStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "moon.stars") }
            ChallengesView()
                .tabItem { Label("Výzvy", systemImage: "flag.2.crossed") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
        }
        .environment(feed)
        .task {
            let health = HealthSync.shared
            health.onUploaded = { [feed] in Task { await feed.load() } }
            // Už rozhodnuté oprávnění se znovu neptá.
            try? await health.requestAuthorization()
            health.startObserving()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-debugSeedHealth") {
                do { try await DebugHealthSeeder.insertNight() } catch { log.error("seed: \(String(describing: error))") }
            }
            #endif
            await health.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await HealthSync.shared.sync() } }
        }
    }
}
