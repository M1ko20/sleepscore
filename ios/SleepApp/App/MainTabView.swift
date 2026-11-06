import SwiftUI

struct MainTabView: View {
    @State private var feed = FeedStore()

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
    }
}
