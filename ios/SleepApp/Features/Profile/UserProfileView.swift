import SwiftUI

/// Profil jiného uživatele. Přítel: vzájemná bilance + Vyzvat + statistiky.
/// Ne-přítel: jen hlavička a žádost o přátelství (profil vidí jen přátelé).
struct UserProfileView: View {
    let profile: ProfileLite

    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var feed
    @Environment(FriendsStore.self) private var friends
    @Environment(ChallengeStore.self) private var challenges

    @State private var summary: ProfileSummary?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var busy = false
    @State private var challengeTarget: ProfileLite?
    @State private var confirmRemove = false

    private var me: UUID? { session.profile?.id }
    private var friendship: ProfileSummary.Friendship? { summary?.friendship }
    private var isFriend: Bool { friendship?.status == .accepted }
    private var shown: ProfileLite { summary?.profile ?? profile }
    private var firstName: String { shown.displayName.split(separator: " ").first.map(String.init) ?? shown.displayName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProfileHeader(profile: shown)
                if let summary {
                    if isFriend {
                        headToHead(summary.h2h ?? .zero)
                        Button("Vyzvat") { challengeTarget = shown }
                            .buttonStyle(.primary)
                        if let actionError { Text(actionError).captionStyle() }
                        ProfileStatsSections(summary: summary, catalog: feed.achievementCatalog)
                    } else {
                        friendshipBlock
                    }
                } else if let loadError {
                    Text(loadError).captionStyle()
                } else {
                    ProgressView().tint(Color.app.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(Metrics.screenPadding)
        }
        .background(Color.app.bg)
        .navigationTitle("@\(shown.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isFriend {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Odebrat z přátel", role: .destructive) { confirmRemove = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(Color.app.textPrimary)
                    .accessibilityLabel("Další možnosti")
                }
            }
        }
        .confirmationDialog("Odebrat \(shown.displayName) z přátel?", isPresented: $confirmRemove,
                            titleVisibility: .visible) {
            Button("Odebrat", role: .destructive) { act { try await friends.remove(shown.id, me: $0) } }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Přestanete si vidět noci. Výzvy a bilance zůstanou.")
        }
        .sheet(item: $challengeTarget) { p in
            NewChallengeFlow(prefill: p, rematch: false).environment(challenges)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Části

    private func headToHead(_ r: Record) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ty vs \(firstName)").statLabel()
            Text(r.text)
                .font(Font.app.scoreL)
                .foregroundStyle(Color.app.textPrimary)
            Text(r.isEmpty ? "Ještě jste se neměřili." : h2hLine(r)).captionStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func h2hLine(_ r: Record) -> String {
        if r.wins > r.losses { return "Vedeš." }
        if r.wins < r.losses { return "\(firstName) vede." }
        return "Nerozhodně."
    }

    @ViewBuilder
    private var friendshipBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch (friendship?.status, friendship?.requestedBy == me) {
            case (.pending, false):
                Text("\(firstName) ti posílá žádost o přátelství.").font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                Button(busy ? "Přijímám…" : "Přijmout") {
                    act { try await friends.respond(shown.id, accept: true, me: $0) }
                }
                .buttonStyle(.primary)
                Button("Odmítnout") { act { try await friends.respond(shown.id, accept: false, me: $0) } }
                    .buttonStyle(.secondary)
            case (.pending, true):
                Text("Žádost odeslaná. Až ji \(firstName) přijme, uvidíte si navzájem noci a můžete se vyzvat.").captionStyle()
                Button("Stáhnout žádost") { act { try await friends.remove(shown.id, me: $0) } }
                    .buttonStyle(.secondary)
            default:
                Text("Profil a noci vidí jen přátelé.").captionStyle()
                Button(busy ? "Posílám…" : "Přidat do přátel") {
                    act { try await friends.send(shown.id, me: $0) }
                }
                .buttonStyle(.primary)
            }
            if let actionError { Text(actionError).captionStyle() }
        }
        .disabled(busy)
    }

    // MARK: Data

    private func load() async {
        do {
            summary = try await API.profileSummary(profile.id)
            loadError = nil
        } catch {
            log.error("user profile load failed: \(String(describing: error))")
            if summary == nil { loadError = "Profil se nenačetl. Stáhni dolů a zkus to znovu." }
        }
    }

    /// Akce s přátelstvím → znovu načíst profil i seznam přátel pro výzvy.
    private func act(_ op: @escaping (UUID) async throws -> Void) {
        guard let me, !busy else { return }
        busy = true
        Task {
            do {
                try await op(me)
                actionError = nil
                await load()
                await challenges.load(me: me)
            } catch {
                actionError = serverMessage(error)
            }
            busy = false
        }
    }
}
