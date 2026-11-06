import SwiftUI

struct MainTabView: View {
    @State private var feed = FeedStore()
    @State private var challenges = ChallengeStore()
    @State private var rematch: ProfileLite?
    @State private var tab: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-debugTab"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return 0
    }()
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "moon.stars") }
                .tag(0)
            ChallengesView()
                .tabItem { Label("Výzvy", systemImage: "flag.2.crossed") }
                .badge(pendingInvites)
                .tag(1)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(2)
        }
        .environment(feed)
        .environment(challenges)
        .fullScreenCover(item: Binding(get: { challenges.unseenResult }, set: { _ in })) { c in
            if let me = session.profile?.id {
                ChallengeResultView(
                    challenge: c, me: me,
                    onClose: { challenges.markSeen(c.id) },
                    onRematch: { p in
                        challenges.markSeen(c.id)
                        rematch = p
                    }
                )
            }
        }
        .sheet(item: $rematch) { p in
            NewChallengeFlow(prefill: p).environment(challenges)
        }
        .task {
            if let me = session.profile?.id { await challenges.load(me: me) }
        }
        .task {
            let health = HealthSync.shared
            health.onUploaded = { [feed, challenges, session] in
                Task { await feed.load() }
                if let me = session.profile?.id { Task { await challenges.load(me: me) } }
            }
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
            guard phase == .active else { return }
            Task { await HealthSync.shared.sync() }
            if let me = session.profile?.id { Task { await challenges.load(me: me) } }
        }
    }

    private var pendingInvites: Int {
        guard let me = session.profile?.id else { return 0 }
        return challenges.waitingForMe(me).count
    }
}
