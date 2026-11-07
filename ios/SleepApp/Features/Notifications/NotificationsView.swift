import SwiftUI

/// Zvoneček: výpis notifikací. Otevření označí vše jako přečtené (1 call);
/// tečka u řádku ukazuje, co bylo nové při tomhle otevření.
struct NotificationsView: View {
    @Environment(FeedStore.self) private var feed
    @State private var items: [AppNotification] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var recap: WeeklyRecap?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loaded && items.isEmpty && error == nil {
                    Text("Ticho. Až někdo zareaguje, uvidíš to tady.")
                        .captionStyle()
                        .padding(.top, 120)
                }
                if let error, items.isEmpty {
                    Text(error).captionStyle().padding(.top, 120)
                }
                ForEach(items) { n in
                    row(n)
                    Rectangle().fill(Color.app.hairline).frame(height: 1)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .background(Color.app.bg)
        .navigationTitle("Upozornění")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .sheet(item: Binding(get: { recap.map(RecapItem.init) }, set: { if $0 == nil { recap = nil } })) {
            RecapView(recap: $0.recap)
        }
    }

    @ViewBuilder
    private func row(_ n: AppNotification) -> some View {
        switch n.target {
        case .post(let id):
            NavigationLink(value: id) { NotificationRow(n: n) }.buttonStyle(.plain)
        case .challenge(let id):
            NavigationLink(value: ChallengeLink(id: id)) { NotificationRow(n: n) }.buttonStyle(.plain)
        case .profile(let p):
            NavigationLink(value: p) { NotificationRow(n: n) }.buttonStyle(.plain)
        case .recap(let weekStart):
            Button {
                Task { recap = try? await API.weeklyRecap(weekStart: weekStart) }
            } label: { NotificationRow(n: n) }
            .buttonStyle(.plain)
        case .none:
            NotificationRow(n: n)
        }
    }

    private func load() async {
        do {
            items = try await API.notifications()
            error = nil
            if items.contains(where: { $0.readAt == nil }) {
                try? await API.markNotificationsRead()
            }
            feed.unreadNotifications = 0
        } catch {
            log.error("notifications load failed: \(String(describing: error))")
            self.error = "Upozornění se nenačetla."
        }
        loaded = true
    }
}

private struct NotificationRow: View {
    let n: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let actor = n.actor {
                Avatar(profile: actor, size: 36)
            } else {
                Circle()
                    .fill(Color.app.surfaceRaised)
                    .overlay(
                        Image(systemName: n.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.app.textPrimary)
                    )
                    .overlay(Circle().strokeBorder(Color.app.hairline, lineWidth: 1))
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(n.text)
                    .font(Font.app.body)
                    .foregroundStyle(Color.app.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(Fmt.postStamp(n.createdAt)).captionStyle()
            }
            Spacer(minLength: 8)
            if n.readAt == nil {
                Circle().fill(Color.app.accent).frame(width: 8, height: 8)
                    .padding(.top, 8)
                    .accessibilityLabel("Nové")
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Zvoneček v liště feedu s počtem nepřečtených.
struct BellButton: View {
    let unread: Int

    var body: some View {
        Image(systemName: "bell")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.app.textPrimary)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.app.accentInk)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.app.accent, in: RoundedRectangle(cornerRadius: 8.5))
                        .offset(x: -4, y: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(unread > 0 ? "Upozornění, \(unread) nových" : "Upozornění")
    }
}
