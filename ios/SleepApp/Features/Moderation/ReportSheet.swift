import SwiftUI

/// Co se hlásí (`report_target` v DB).
enum ReportTarget: String, Sendable {
    case post, comment, profile, challenge

    var title: String {
        switch self {
        case .post: "Nahlásit kartu"
        case .comment: "Nahlásit komentář"
        case .profile: "Nahlásit profil"
        case .challenge: "Nahlásit sázku"
        }
    }
}

/// Důvod hlášení (pevný seznam, kontroluje i DB).
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case harassment, hate, sexual, spam, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: "Urážky nebo obtěžování"
        case .hate: "Nenávist nebo vyhrožování"
        case .sexual: "Sexuální nebo nechutný obsah"
        case .spam: "Spam nebo podvod"
        case .other: "Něco jiného"
        }
    }
}

/// Co se hlásí a kdo za tím stojí (autor se dá rovnou zablokovat).
struct ReportRequest: Identifiable, Hashable {
    let kind: ReportTarget
    let targetID: UUID
    let author: ProfileLite?

    var id: String { "\(kind.rawValue)-\(targetID)" }
}

/// Nahlášení: důvod → poznámka → (zablokovat autora) → Odeslat.
/// Po odeslání se obsah volajícímu skryje (RLS), `onDone(blocked)` uklidí lokální stav.
struct ReportSheet: View {
    let request: ReportRequest
    var onDone: (_ blocked: Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var block = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if sent { done } else { form }
            }
            .padding(Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.app.bg)
            .navigationTitle(request.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !sent {
                        Button("Zrušit") { dismiss() }.tint(Color.app.textPrimary).disabled(sending)
                    }
                }
            }
        }
        .presentationBackground(Color.app.bg)
        .interactiveDismissDisabled(sending)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proč").statLabel().padding(.bottom, 4)
                    ForEach(ReportReason.allCases) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r.label).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                                Spacer()
                                Image(systemName: reason == r ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(reason == r ? Color.app.accent : Color.app.textTertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == r ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Poznámka").statLabel()
                    TextField("", text: $note,
                              prompt: Text("Nepovinné").foregroundStyle(Color.app.textTertiary),
                              axis: .vertical)
                        .lineLimit(2...5)
                        .font(Font.app.body)
                        .foregroundStyle(Color.app.textPrimary)
                        .padding(14)
                        .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                }

                if let author = request.author {
                    Toggle(isOn: $block) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zablokovat @\(author.username)")
                                .font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                            Text("Zmizíte si z feedu, nepůjde komentovat, žádat o přátelství ani vyzývat.")
                                .captionStyle()
                        }
                    }
                    .tint(Color.app.accent)
                }

                Text("Hlášení čteme my, ne autor. Ozveme se do 24 hodin a obsah, který porušuje pravidla, smažeme.")
                    .captionStyle()

                if let error { Text(error).captionStyle() }

                Button(sending ? "Posílám…" : "Odeslat", action: send)
                    .buttonStyle(.primary)
                    .disabled(reason == nil || sending)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Díky. Mrkneme na to.").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
            Text(block
                 ? "Do 24 hodin. Obsah už nevidíš a blokování @\(request.author?.username ?? "") platí hned."
                 : "Do 24 hodin. Obsah už nevidíš.")
                .captionStyle()
            Spacer()
            Button("Hotovo") { dismiss() }.buttonStyle(.secondary)
        }
    }

    private func send() {
        guard let reason else { return }
        sending = true
        error = nil
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await API.report(request.kind, id: request.targetID, reason: reason,
                                     note: text.isEmpty ? nil : String(text.prefix(500)),
                                     block: block && request.author != nil)
                sent = true
                onDone(block && request.author != nil)
            } catch {
                self.error = serverMessage(error)
            }
            sending = false
        }
    }
}

/// Potvrzení blokování (stejný text všude).
struct BlockConfirmation: ViewModifier {
    @Binding var target: ProfileLite?
    var onBlocked: (ProfileLite) -> Void

    @Environment(Session.self) private var session
    @Environment(FriendsStore.self) private var friends
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Zablokovat @\(target?.username ?? "")?",
                isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
                titleVisibility: .visible,
                presenting: target
            ) { p in
                Button("Zablokovat", role: .destructive) { block(p) }
                Button("Zrušit", role: .cancel) {}
            } message: { _ in
                Text("Zrušíte si přátelství, zmizíte si z feedu a nepůjde komentovat, žádat o přátelství ani vyzývat. Běžící výzvy doběhnou. O blokování se nedozví.")
            }
            .alert("Nepovedlo se", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    private func block(_ p: ProfileLite) {
        guard let me = session.profile?.id else { return }
        Task {
            do {
                try await friends.block(p.id, me: me)
                onBlocked(p)
            } catch {
                self.error = serverMessage(error)
            }
        }
    }
}

extension View {
    /// Zobrazí potvrzení, když `target` není nil; po zablokování zavolá `onBlocked`.
    func blockConfirmation(_ target: Binding<ProfileLite?>, onBlocked: @escaping (ProfileLite) -> Void) -> some View {
        modifier(BlockConfirmation(target: target, onBlocked: onBlocked))
    }
}
