import SwiftUI

/// Můj profil: bilance, série, průměr, vitrína duší, odznaky, přátelé, pozvánky. Nastavení pod ozubeným kolem.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var feed
    @Environment(FriendsStore.self) private var friends

    @State private var summary: ProfileSummary?
    @State private var error: String?
    @State private var showSettings = false
    @State private var recap: WeeklyRecap?
    @State private var loadingRecap = false
    @State private var wrapped: SleepWrapped?
    @State private var path = NavigationPath()

    enum Route: Hashable { case friends, invites }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let profile = session.profile {
                        ProfileHeader(profile: profile.lite)
                    }
                    if let summary {
                        ProfileStatsSections(summary: summary, catalog: feed.achievementCatalog)
                    } else if let error {
                        Text(error).captionStyle()
                    } else {
                        ProgressView().tint(Color.app.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
                    }
                    links
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .tint(Color.app.textPrimary)
                        .accessibilityLabel("Nastavení")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $wrapped) { WrappedView(wrapped: $0) }
            .sheet(item: Binding(get: { recap.map(RecapItem.init) }, set: { if $0 == nil { recap = nil } })) {
                RecapView(recap: $0.recap)
            }
            .navigationDestination(for: ProfileLite.self) { UserProfileView(profile: $0) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .friends: FriendsView()
                case .invites: InvitesView()
                }
            }
            .task {
                await load()
                #if DEBUG
                // Screenshoty: `-debugProfile friends` / `-debugProfile <přezdívka>` otevře přátele / profil přítele.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-debugPrivacy") { showSettings = true }
                if let i = args.firstIndex(of: "-debugProfile"), i + 1 < args.count, path.isEmpty {
                    if args[i + 1] == "friends" { path.append(Route.friends) }
                    else if let p = friends.entries.first(where: { $0.other.username == args[i + 1] })?.other { path.append(p) }
                }
                #endif
            }
            .refreshable { await load() }
        }
    }

    private var links: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.app.hairline)
            NavigationLink(value: Route.friends) {
                ProfileRow(title: "Přátelé (\(friends.friends.count))", badge: friends.incoming.count)
            }
            Divider().overlay(Color.app.hairline)
            Button {
                Task {
                    loadingRecap = true
                    recap = try? await API.weeklyRecap()
                    loadingRecap = false
                }
            } label: {
                ProfileRow(title: loadingRecap ? "Minulý týden…" : "Minulý týden v číslech")
            }
            .buttonStyle(.plain)
            .disabled(loadingRecap)
            Divider().overlay(Color.app.hairline)
            if let year = WrappedWindow.year {
                Button {
                    Task { wrapped = try? await API.sleepWrapped(year: year) }
                } label: {
                    ProfileRow(title: "Sleep Wrapped \(String(year))")
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.app.hairline)
            }
            NavigationLink(value: Route.invites) {
                ProfileRow(title: "Pozvánky · zbývá \(session.profile?.invitesAvailable ?? 0)")
            }
            Divider().overlay(Color.app.hairline)
        }
    }

    private func load() async {
        guard let me = session.profile?.id else { return }
        async let s = API.profileSummary(me)
        async let f: Void = friends.load(me: me)
        async let p: Void = session.reloadProfile()
        async let c: Void? = try? feed.loadCatalogs()
        do {
            summary = try await s
            error = nil
        } catch {
            log.error("profile load failed: \(String(describing: error))")
            if summary == nil { self.error = "Profil se nenačetl. Stáhni dolů a zkus to znovu." }
        }
        _ = await (f, p, c)
    }
}

struct ProfileRow: View {
    let title: String
    var badge: Int = 0

    var body: some View {
        HStack {
            Text(title).statLabel().foregroundStyle(Color.app.textPrimary)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(Font.app.label.monospacedDigit())
                    .foregroundStyle(Color.app.accentInk)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.app.accent, in: Capsule())
                    .accessibilityLabel("\(badge) nových žádostí")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.app.textTertiary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Stav synchronizace s Apple Health + ruční synchronizace.
struct HealthSection: View {
    @State private var health = HealthSync.shared
    #if DEBUG
    @State private var seeding = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health").statLabel()
            Text(statusText).captionStyle()
            Button(health.status == .syncing ? "Synchronizuju…" : "Synchronizovat") {
                Task { await health.sync(force: true) }
            }
            .buttonStyle(.secondary)
            .disabled(health.status == .syncing || !health.isAvailable)
            #if DEBUG
            Button(seeding ? "Vkládám…" : "DEBUG: vložit noc do Zdraví") {
                seeding = true
                Task {
                    try? await health.requestAuthorization()
                    do { try await DebugHealthSeeder.insertNight() } catch { log.error("seed: \(String(describing: error))") }
                    seeding = false
                    await health.sync()
                }
            }
            .buttonStyle(.plainText)
            #endif
        }
    }

    private var statusText: String {
        guard health.isAvailable else { return "Apple Health na tomhle zařízení není." }
        switch health.status {
        case .idle: return "Noci se nahrávají samy po synchronizaci hodinek."
        case .syncing: return "Nahrávám…"
        case .done(let d, let n): return n == 0 ? "\(Fmt.time(d)) · beze změny" : "\(Fmt.time(d)) · nahráno nocí: \(n)"
        case .nothingNew(let d): return "\(Fmt.time(d)) · nic nového"
        case .failed(let msg): return msg
        }
    }
}

/// Obal pro `.sheet(item:)` (recap nemá vlastní id).
struct RecapItem: Identifiable {
    let recap: WeeklyRecap
    var id: String { recap.weekStart }
}
