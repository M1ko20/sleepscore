import SwiftUI

struct FeedView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store
    @State private var editing: FeedPost?
    @State private var path: [UUID] = []

    private var me: UUID? { session.profile?.id }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Metrics.cardSpacing) {
                    if store.loaded && store.posts.isEmpty {
                        emptyState
                    }
                    if let error = store.error, store.posts.isEmpty {
                        Text(error).captionStyle().padding(.top, 40)
                    }
                    ForEach(store.ordered(me: me)) { post in
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
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Color.app.bg)
            .navigationTitle("Feed")
            .navigationDestination(for: UUID.self) { id in
                NightDetailView(postID: id)
            }
            .refreshable { await store.load() }
            .task {
                if !store.loaded { await store.load() }
                #if DEBUG
                // Screenshoty ze simulátoru: `simctl launch … -debugOpen 1` otevře n-tou kartu.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-debugOpen"), i + 1 < args.count, let n = Int(args[i + 1]),
                   path.isEmpty, n >= 1, n <= store.posts.count {
                    path = [store.ordered(me: me)[n - 1].id]
                }
                #endif
            }
            .sheet(item: $editing) { post in
                EditPostSheet(post: post)
            }
        }
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
