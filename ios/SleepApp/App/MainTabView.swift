import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "moon.stars") }
            ChallengesView()
                .tabItem { Label("Výzvy", systemImage: "flag.2.crossed") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
        }
    }
}
