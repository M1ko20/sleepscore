import SwiftUI

/// Soukromí (GDPR): co ukládáme, stažení dat, smazání účtu.
struct PrivacyView: View {
    @Environment(Session.self) private var session

    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var exportError: String?
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("Co ukládáme") {
                    bullet("Spánek z Apple Health: úseky fází a tep během spánku. Jen ze zařízení, ruční záznamy ne.")
                    bullet("Co sám napíšeš a nahraješ: názvy, komentáře, tagy, reakce, fotky, profilovku.")
                    bullet("Výzvy, dluhy, odznaky, přátele a pozvánky.")
                    bullet("Data leží v EU (Supabase, Frankfurt). Noci, karty a fotky vidí jen tvoji přátelé, přezdívku, jméno a profilovku ostatní členové (kvůli hledání). Nikdy nic neprodáváme ani nepoužíváme na reklamu.")
                }

                section("Apple Health") {
                    Text("Přístup ke Zdraví vypneš v Nastavení iPhonu → Zdraví → Přístup k datům a zařízení → Sleepscore. Už nahrané noci tím nezmizí – na to je smazání účtu.")
                        .captionStyle()
                }

                section("Dokumenty") {
                    Link(destination: Legal.privacyURL) { linkRow("Zásady ochrany soukromí") }
                    Link(destination: Legal.termsURL) { linkRow("Podmínky použití") }
                }

                section("Tvoje data") {
                    Text("Všechno, co o tobě máme, v jednom souboru (JSON).").captionStyle()
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Text("Uložit nebo poslat soubor").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.secondary)
                    } else {
                        Button(exporting ? "Připravuju…" : "Stáhnout moje data", action: export)
                            .buttonStyle(.secondary)
                            .disabled(exporting)
                    }
                    if let exportError { Text(exportError).captionStyle() }
                }

                section("Smazání účtu") {
                    Text("Smaže profil, všechny noci, karty, fotky, komentáře, reakce, přátelství, dluhy a odznaky. Nejde vrátit. Kamarádům zůstanou jejich výsledky ve výzvách.")
                        .captionStyle()
                    Button("Smazat účet") { showDelete = true }
                        .buttonStyle(DestructiveTextStyle())
                }
            }
            .padding(Metrics.screenPadding)
        }
        .background(Color.app.bg)
        .navigationTitle("Soukromí")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).statLabel()
            content()
        }
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Color.app.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·").foregroundStyle(Color.app.textTertiary)
            Text(text).font(Font.app.caption).foregroundStyle(Color.app.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func export() {
        exporting = true
        exportError = nil
        Task {
            defer { exporting = false }
            do {
                let data = try await API.exportMyData()
                let name = "sleepscore-\(session.profile?.username ?? "data")-\(ISODay.today).json"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                exportURL = url
            } catch {
                exportError = serverMessage(error)
            }
        }
    }
}

/// Potvrzení smazání: napsat svoji přezdívku (žádné omylem klepnuté tlačítko).
private struct DeleteAccountSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var deleting = false
    @State private var error: String?

    private var username: String { session.profile?.username ?? "" }
    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces).lowercased() == username && !username.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Smazat účet @\(username)?").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                Text("Všechno zmizí hned a natrvalo. Pro potvrzení napiš svoji přezdívku.").captionStyle()
                TextField(username, text: $typed)
                    .textFieldStyle(AppTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let error { Text(error).captionStyle() }
                Spacer()
                Button(deleting ? "Mažu…" : "Smazat natrvalo", action: delete)
                    .buttonStyle(DestructiveFilledStyle())
                    .disabled(!matches || deleting)
            }
            .padding(Metrics.screenPadding)
            .background(Color.app.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }.tint(Color.app.textPrimary).disabled(deleting)
                }
            }
        }
        .presentationBackground(Color.app.bg)
        .interactiveDismissDisabled(deleting)
    }

    private func delete() {
        guard matches, let me = session.profile?.id else { return }
        deleting = true
        Task {
            do {
                try await API.deleteMyAccount(me: me)
                await session.signOut()
            } catch {
                self.error = serverMessage(error)
                deleting = false
            }
        }
    }
}

/// Textové tlačítko v barvě `destructive`.
private struct DestructiveTextStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.app.body.weight(.semibold))
            .foregroundStyle(Color.app.destructive)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: 44)
    }
}

/// Plné tlačítko pro nevratnou akci (jediné místo, kde je `destructive` výplň).
private struct DestructiveFilledStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.app.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .background(Color.app.destructive.opacity(isEnabled ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
