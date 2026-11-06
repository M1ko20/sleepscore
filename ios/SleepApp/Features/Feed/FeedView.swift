import SwiftUI

struct FeedView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store
    @State private var editing: FeedPost?
    @State private var showRecap = false
    @State private var path = NavigationPath()

    private var me: UUID? { session.profile?.id }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Metrics.cardSpacing) {
                    if let recap = store.recap {
                        RecapCard(recap: recap, onOpen: { showRecap = true }, onDismiss: { store.dismissRecap() })
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
            .refreshable { await store.load() }
            .task {
                if !store.loaded { await store.load() }
                #if DEBUG
                // Screenshoty ze simulátoru: `simctl launch … -debugOpen 1` otevře n-tou kartu noci.
                let args = ProcessInfo.processInfo.arguments
                let nights = store.items(me: me).compactMap { if case .night(let p) = $0 { p.id } else { nil } }
                if let i = args.firstIndex(of: "-debugOpen"), i + 1 < args.count, let n = Int(args[i + 1]),
                   path.isEmpty, n >= 1, n <= nights.count {
                    path.append(nights[n - 1])
                }
                #endif
            }
            .sheet(isPresented: $showRecap) {
                if let recap = store.recap { RecapView(recap: recap) }
            }
            .task {
                await store.loadRecap()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-debugRecapOpen"), store.recap != nil { showRecap = true }
                #endif
            }
            .sheet(item: $editing) { post in
                EditPostSheet(post: post)
            }
        }
    }

    private func nightCard(_ post: FeedPost) -> some View {
                        NavigationLink(value: post.id) {
                            NightCard(
                                post: post, me: me,
                                streak: store.streakBadge(for: post),
                                tagLine: store.tagLine(post.night.tags),
                                achievementNames: post.night.achievementCodes.compactMap { store.achievementNames[$0] },
                                onEdit: { editing = post },
                                onReact: { kind in
                                    guard let me else { return }
                                    Task { await store.react(post.id, me: me, kind: kind) }
                                }
                            )
                        }
                        .buttonStyle(.plain)
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
