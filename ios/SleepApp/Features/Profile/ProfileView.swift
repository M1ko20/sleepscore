import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    stats
                    Divider().overlay(Color.app.hairline)
                    Button("Odhlásit") { Task { await session.signOut() } }
                        .buttonStyle(.plainText)
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var header: some View {
        switch session.state {
        case .ready(let profile):
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
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Bez profilu").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                Text("Účet nemá profil. Založí se uplatněním pozvánky.").captionStyle()
            }
        }
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
