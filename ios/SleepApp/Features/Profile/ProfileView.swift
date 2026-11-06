import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let profile = session.profile {
                        header(profile)
                    }
                    stats
                    VStack(spacing: 0) {
                        Divider().overlay(Color.app.hairline)
                        NavigationLink {
                            InvitesView()
                        } label: {
                            row("Pozvánky · zbývá \(session.profile?.invitesAvailable ?? 0)")
                        }
                        Divider().overlay(Color.app.hairline)
                    }
                    Button("Odhlásit") { Task { await session.signOut() } }
                        .buttonStyle(.plainText)
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await session.reloadProfile() }
        }
    }

    private func header(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.app.surfaceRaised)
                .frame(width: 56, height: 56)
                .overlay(Text(profile.displayName.prefix(1)).font(Font.app.title))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(Font.app.title)
                Text("@\(profile.username)").captionStyle()
            }
        }
        .foregroundStyle(Color.app.textPrimary)
    }

    private func row(_ title: String) -> some View {
        HStack {
            Text(title).statLabel().foregroundStyle(Color.app.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.app.textTertiary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var stats: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("0-0-0").font(Font.app.scoreXL).foregroundStyle(Color.app.textPrimary)
                Text("Výhry-prohry-remízy").statLabel()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SÉRIE 0").font(Font.app.stat).foregroundStyle(Color.app.textPrimary)
                Text("nejlepší 0").captionStyle()
            }
        }
    }
}
