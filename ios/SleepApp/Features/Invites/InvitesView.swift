import SwiftUI

/// Pozvánky: zbývající počet, vytvoření kódu, nepoužité kódy se sdílením.
struct InvitesView: View {
    @Environment(Session.self) private var session
    @State private var invites: [Invite] = []
    @State private var busy = false
    @State private var error: String?

    private var remaining: Int { session.profile?.invitesAvailable ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(remaining)").font(Font.app.scoreXL).foregroundStyle(Color.app.textPrimary)
                    Text(remaining == 1 ? "Zbývá pozvánka" : "Zbývá pozvánek").statLabel()
                }

                if !invites.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Nepoužité kódy").statLabel().padding(.bottom, 8)
                        ForEach(invites) { invite in
                            HStack {
                                Text(invite.code)
                                    .font(.system(size: 22, weight: .bold).monospaced())
                                    .foregroundStyle(Color.app.textPrimary)
                                    .textSelection(.enabled)
                                Spacer()
                                ShareLink(item: Self.shareText(invite.code)) {
                                    Image(systemName: "square.and.arrow.up")
                                        .fontWeight(.medium)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Sdílet kód \(invite.code)")
                            }
                            Divider().overlay(Color.app.hairline)
                        }
                    }
                }

                if let error {
                    Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.screenPadding)
        }
        .safeAreaInset(edge: .bottom) {
            Button(busy ? "Vytvářím…" : "Vytvořit kód", action: create)
                .buttonStyle(.primary)
                .disabled(remaining == 0 || busy)
                .padding(Metrics.screenPadding)
                .background(Color.app.bg)
        }
        .background(Color.app.bg)
        .navigationTitle("Pozvánky")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    static func shareText(_ code: String) -> String {
        "Pojď se měřit ve spaní. Kód: \(code)"
    }

    private func load() async {
        guard let id = session.profile?.id else { return }
        invites = (try? await API.myOpenInvites(userID: id)) ?? invites
    }

    private func create() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                _ = try await API.createInvite()
                await session.reloadProfile()
                await load()
            } catch {
                self.error = serverMessage(error)
            }
        }
    }
}
