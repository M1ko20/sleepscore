import SwiftUI

/// Přátelé: hledání podle přezdívky, žádosti (přijmout/odmítnout), seznam přátel.
struct FriendsView: View {
    @Environment(Session.self) private var session
    @Environment(FriendsStore.self) private var store
    @Environment(ChallengeStore.self) private var challenges

    @State private var query = ""
    @State private var results: [ProfileLite] = []
    @State private var searching = false
    @State private var busy: Set<UUID> = []
    @State private var error: String?

    private var me: UUID? { session.profile?.id }
    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TextField("Hledat přezdívku", text: $query)
                    .textFieldStyle(AppTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if let error { Text(error).captionStyle() }

                if isSearching {
                    section("Výsledky") {
                        if results.isEmpty {
                            Text(searching ? "Hledám…" : "Nikdo takový tu není.").captionStyle()
                        }
                        ForEach(results) { p in row(p) { searchAction(p) } }
                    }
                } else {
                    if !store.incoming.isEmpty {
                        section("Žádosti") {
                            ForEach(store.incoming) { p in
                                row(p) {
                                    HStack(spacing: 8) {
                                        smallButton("Přijmout", primary: true) {
                                            act(p.id) { try await store.respond(p.id, accept: true, me: $0) }
                                        }
                                        Button {
                                            act(p.id) { try await store.respond(p.id, accept: false, me: $0) }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.app.textSecondary)
                                                .frame(width: 32, height: 32)
                                                .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Odmítnout")
                                    }
                                }
                            }
                        }
                    }
                    if !store.outgoing.isEmpty {
                        section("Odeslané") {
                            ForEach(store.outgoing) { p in
                                row(p) {
                                    smallButton("Stáhnout") { act(p.id) { try await store.remove(p.id, me: $0) } }
                                }
                            }
                        }
                    }
                    section("Přátelé (\(store.friends.count))") {
                        if store.friends.isEmpty && store.loaded {
                            Text("Zatím nikdo. Najdi kamaráda podle přezdívky, nebo mu pošli pozvánku.").captionStyle()
                        }
                        ForEach(store.friends) { p in
                            row(p) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.app.textTertiary)
                            }
                        }
                    }
                    if !store.blocked.isEmpty {
                        section("Zablokovaní") {
                            ForEach(store.blocked) { p in
                                row(p) {
                                    smallButton("Zrušit blok") { act(p.id) { try await store.unblock(p.id, me: $0) } }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Metrics.screenPadding)
        }
        .background(Color.app.bg)
        .navigationTitle("Přátelé")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) { await search() }
        .task { if let me { await store.load(me: me) } }
        .refreshable { if let me { await store.load(me: me) } }
    }

    // MARK: Části

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).statLabel().padding(.bottom, 4)
            content()
        }
    }

    /// Řádek: avatar + jméno vede na profil, vpravo akce.
    private func row<Trailing: View>(_ p: ProfileLite, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: p) {
                HStack(spacing: 12) {
                    Avatar(profile: p, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.displayName).font(Font.app.body.weight(.semibold))
                            .foregroundStyle(Color.app.textPrimary).lineLimit(1)
                        Text("@\(p.username)").captionStyle().lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .frame(minHeight: 56)
        .opacity(busy.contains(p.id) ? 0.5 : 1)
        .disabled(busy.contains(p.id))
    }

    @ViewBuilder
    private func searchAction(_ p: ProfileLite) -> some View {
        if store.isBlocked(p.id) {
            Text("zablokováno").captionStyle()
        } else {
            friendshipAction(p)
        }
    }

    @ViewBuilder
    private func friendshipAction(_ p: ProfileLite) -> some View {
        switch store.entry(p.id) {
        case .some(let e) where e.status == .accepted:
            Text("přítel").captionStyle()
        case .some(let e) where e.incoming:
            smallButton("Přijmout", primary: true) {
                act(p.id) { try await store.respond(p.id, accept: true, me: $0) }
            }
        case .some:
            Text("odesláno").captionStyle()
        case .none:
            smallButton("Přidat", primary: true) { act(p.id) { try await store.send(p.id, me: $0) } }
        }
    }

    private func smallButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font.app.caption.weight(.semibold))
                .foregroundStyle(primary ? Color.app.accentInk : Color.app.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(primary ? Color.app.accent : Color.app.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private func search() async {
        guard isSearching, let me else { results = []; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(350))   // debounce: task(id:) zruší předchozí
        guard !Task.isCancelled else { return }
        do {
            results = try await API.searchProfiles(query.trimmingCharacters(in: .whitespaces), me: me)
            error = nil
        } catch {
            if !Task.isCancelled { self.error = serverMessage(error) }
        }
        searching = false
    }

    private func act(_ id: UUID, _ op: @escaping (UUID) async throws -> Void) {
        guard let me else { return }
        busy.insert(id)
        Task {
            do {
                try await op(me)
                error = nil
                await challenges.load(me: me)
            } catch {
                self.error = serverMessage(error)
            }
            busy.remove(id)
        }
    }
}
