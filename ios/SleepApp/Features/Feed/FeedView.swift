import SwiftUI

struct FeedView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store
    @State private var editing: FeedPost?
    @State private var showRecap = false
    @State private var wrapped: SleepWrapped?
    @State private var path = NavigationPath()
    /// Žádná moje noc ve feedu ani spánek ve Zdraví → nejspíš zakázaný přístup (#22).
    @State private var healthMissing = false
    /// Recap otevřený z pushe (konkrétní týden).
    @State private var pushRecap: RecapItem?

    private var me: UUID? { session.profile?.id }

    private func open(_ link: PushLink) {
        Push.shared.pendingLink = nil
        path = NavigationPath()
        switch link {
        case .post(let id): path.append(id)
        case .challenge(let id): path.append(ChallengeLink(id: id))
        case .profile(let p): path.append(p)
        case .notifications: path.append(FeedRoute.notifications)
        case .recap(let weekStart):
            Task {
                if let r = try? await API.weeklyRecap(weekStart: weekStart) { pushRecap = RecapItem(recap: r) }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Metrics.cardSpacing) {
                    if let year = WrappedWindow.year {
                        WrappedCard(year: year) {
                            Task { wrapped = try? await API.sleepWrapped(year: year) }
                        }
                    }
                    if let recap = store.recap {
                        RecapCard(recap: recap, onOpen: { showRecap = true }, onDismiss: { store.dismissRecap() })
                    }
                    if healthMissing {
                        HealthMissingCard()
                    }
                    // Nabídka notifikací až ve chvíli, kdy je ve feedu co sledovat (ne hned po přihlášení).
                    if Push.shared.shouldOfferPermission, !store.posts.isEmpty {
                        PushAskCard()
                    }
                    if store.loaded && store.isEmpty {
                        emptyState
                    }
                    if let error = store.error, store.isEmpty {
                        Text(error).captionStyle().padding(.top, 40)
                    }
                    ForEach(store.items(me: me)) { item in
                        switch item {
                        case .result(let r):
                            ChallengeResultCard(post: r, me: me)
                        case .night(let post):
                            nightCard(post)
                        }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Color.app.bg)
            .navigationTitle("Feed")
            .navigationDestination(for: UUID.self) { id in
                NightDetailView(postID: id)
            }
            .navigationDestination(for: ProfileLite.self) { UserProfileView(profile: $0) }
            .navigationDestination(for: ChallengeLink.self) { ChallengeDetailView(challengeID: $0.id) }
            .navigationDestination(for: FeedRoute.self) { route in
                switch route {
                case .notifications: NotificationsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: FeedRoute.notifications) {
                        BellButton(unread: store.unreadNotifications)
                    }
                }
            }
            .refreshable { await store.load() }
            .task {
                if !store.loaded { await store.load() }
                if let me, HealthSync.shared.isAvailable, !store.posts.contains(where: { $0.author.id == me }) {
                    healthMissing = !(await HealthSync.shared.hasRecentSleep())
                }
                #if DEBUG
                // Screenshoty ze simulátoru: `simctl launch … -debugOpen 1` otevře n-tou kartu noci.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-debugNotifications"), path.isEmpty { path.append(FeedRoute.notifications) }
                let nights = store.items(me: me).compactMap { if case .night(let p) = $0 { p.id } else { nil } }
                if let i = args.firstIndex(of: "-debugOpen"), i + 1 < args.count, let n = Int(args[i + 1]),
                   path.isEmpty, n >= 1, n <= nights.count {
                    path.append(nights[n - 1])
                }
                #endif
            }
            .fullScreenCover(item: $wrapped) { WrappedView(wrapped: $0) }
            .sheet(isPresented: $showRecap) {
                if let recap = store.recap { RecapView(recap: recap) }
            }
            .task {
                await store.loadRecap()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-debugRecapOpen"), store.recap != nil { showRecap = true }
                if ProcessInfo.processInfo.arguments.contains("-debugWrappedOpen"), let y = WrappedWindow.year {
                    wrapped = try? await API.sleepWrapped(year: y)
                }
                #endif
            }
            .sheet(item: $editing) { post in
                EditPostSheet(post: post)
            }
            .sheet(item: $pushRecap) { RecapView(recap: $0.recap) }
            // Klepnutí na push (i při studeném startu – proto initial).
            .onChange(of: Push.shared.pendingLink, initial: true) { _, link in
                if let link { open(link) }
            }
        }
    }

    private func nightCard(_ post: FeedPost) -> some View {
        NightCard(
            post: post, me: me,
            streak: store.streakBadge(for: post),
            tagLine: store.tagLine(post.night.tags),
            achievementNames: post.night.achievementCodes.compactMap { store.achievementNames[$0] },
            onEdit: { editing = post },
            onOpen: { path.append(post.id) },
            onReact: { kind in
                guard let me else { return }
                Task { await store.react(post.id, me: me, kind: kind) }
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(session.profile?.invitedBy != nil
                 ? "První noc se ukáže zítra ráno."
                 : "Zatím tu nikdo není. Pošli pozvánku.")
                .captionStyle()
            if session.profile?.invitedBy == nil {
                NavigationLink("Pozvánky") { InvitesView() }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.top, 120)
    }
}

/// Feed bez mojí noci a Zdraví bez spánku: vysvětlit, kde povolit přístup (#22, HealthKit odmítnutý).
struct HealthMissingCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nevidíme tvůj spánek")
                .font(Font.app.body.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
            Text("Z Apple Health nám za poslední dva týdny nepřišla žádná noc. Povol přístup ke Spánku a Tepu v Nastavení → Zdraví → Přístup k datům a zařízení → Bedrival. Spánek musí zapisovat hodinky nebo prsten.")
                .captionStyle()
                .fixedSize(horizontal: false, vertical: true)
            Button("Otevřít Nastavení") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.app.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .accessibilityIdentifier("healthMissingCard")
    }
}

/// Vlastní nabídka před systémovým dialogem: vysvětlí, k čemu notifikace jsou, a nechá odmítnout bez dialogu.
struct PushAskCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ať ti nic neuteče")
                .font(Font.app.body.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
            Text("Dáme vědět, když ti někdo okomentuje noc, vyzve tě nebo tě v souboji předběhne. Co chodí, si nastavíš v Nastavení → Notifikace.")
                .captionStyle()
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Zapnout") { Task { await Push.shared.requestPermission() } }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("pushAskEnable")
                Button("Teď ne") { Push.shared.askDismissed = true }
                    .buttonStyle(.plainText)
                    .accessibilityIdentifier("pushAskDismiss")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.app.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .accessibilityIdentifier("pushAskCard")
    }
}

enum FeedRoute: Hashable {
    case notifications
}
