import SwiftUI

struct MainTabView: View {
    @State private var feed = FeedStore()
    @State private var challenges = ChallengeStore()
    @State private var friends = FriendsStore()
    @State private var rematch: ProfileLite?
    /// Výsledek výzvy přes celou obrazovku až po dotazu na Zdraví – jinak systémové okno
    /// o povolení zavře (vyskočí a hned zmizí, viděno na iPhonu s nevideným výsledkem).
    @State private var healthAsked = false
    /// Změna spustí žádost o přístup ke Zdraví (`healthAccessRequest`).
    @State private var healthRequest = 0
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
                .badge(friends.incoming.count)
                .tag(2)
        }
        .environment(feed)
        .environment(challenges)
        .environment(friends)
        .fullScreenCover(item: Binding(get: { healthAsked ? challenges.unseenResult : nil }, set: { _ in })) { c in
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
            if let me = session.profile?.id {
                async let c: Void = challenges.load(me: me)
                async let f: Void = friends.load(me: me)
                _ = await (c, f)
            }
        }
        .task {
            let health = HealthSync.shared
            health.onUploaded = { [feed, challenges, session] in
                Task { await feed.load() }
                if let me = session.profile?.id { Task { await challenges.load(me: me) } }
            }
            // Žádost o přístup jen, když se uživatel ještě nevyjádřil (pokračuje v `onFinish`).
            // Kdo už rozhodl, synchronizuje hned – nespoléhá se na to, že modifikátor zavolá zpět.
            if await health.needsAuthorizationPrompt() { healthRequest += 1 } else { await healthAccessReady() }
            // Jen zjistí stav a registruje token; o povolení se appka ptá až kartou ve feedu.
            await Push.shared.start()
        }
        .healthAccessRequest(trigger: healthRequest) {
            Task { await healthAccessReady() }
        }
        .onChange(of: Push.shared.pendingLink) { _, link in
            if link != nil { tab = 0 }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await HealthSync.shared.sync()
                // Nová vlastní noc už feed načetla (onUploaded); jinak jen když je starý.
                await feed.loadIfStale()
            }
            // Povolení se mohlo změnit v Nastavení iOS.
            Task { await Push.shared.start() }
            if let me = session.profile?.id { Task { await challenges.load(me: me) } }
        }
    }

    private var pendingInvites: Int {
        guard let me = session.profile?.id else { return 0 }
        return challenges.waitingForMe(me).count
    }

    /// Po žádosti o přístup ke Zdraví: sledování nových nocí a první synchronizace.
    private func healthAccessReady() async {
        guard !healthAsked else { return }
        let health = HealthSync.shared
        healthAsked = true
        health.startObserving()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugSeedHealth") {
            do { try await DebugHealthSeeder.insertNight() } catch { log.error("seed: \(String(describing: error))") }
        }
        #endif
        await health.sync()
    }
}
