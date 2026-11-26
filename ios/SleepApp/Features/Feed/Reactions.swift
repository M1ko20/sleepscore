import SwiftUI

/// Souhrn reakcí na kartě: ikona + počet, max. 3, zbytek „+N“.
struct ReactionSummary: View {
    let reactions: [Reaction]
    let me: UUID?

    var body: some View {
        let groups = Dictionary(grouping: reactions, by: \.kind)
            .map { (kind: $0.key, count: $0.value.count, mine: $0.value.contains { $0.userID == me }) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.rawValue < $1.kind.rawValue }
        HStack(spacing: 12) {
            ForEach(groups.prefix(3), id: \.kind) { g in
                HStack(spacing: 4) {
                    Image(systemName: g.kind.symbol).font(.system(size: 14, weight: .medium))
                    Text("\(g.count)").font(Font.app.caption.monospacedDigit())
                }
                .foregroundStyle(g.mine ? Color.app.accent : Color.app.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(g.kind.label) \(g.count)")
            }
            if groups.count > 3 {
                Text("+\(groups.dropFirst(3).reduce(0) { $0 + $1.count })").captionStyle()
            }
        }
    }
}

/// Kdo jak reagoval: avatar, jméno, reakce. Počty a moje reakce bere z karty (platí hned),
/// jména dotáhne jedním dotazem při otevření.
struct ReactionsSheet: View {
    let postID: UUID
    let reactions: [Reaction]
    let me: UUID?

    @Environment(FriendsStore.self) private var friends
    @State private var people: [ReactionPerson]?
    @State private var failed = false

    /// Pořadí: moje první, pak podle seznamu ze serveru (od nejnovější); jen reakce, co na kartě pořád jsou.
    private var rows: [ReactionPerson] {
        let kinds = Dictionary(reactions.map { ($0.userID, $0.kind) }, uniquingKeysWith: { a, _ in a })
        return (people ?? [])
            .filter { kinds[$0.profile.id] != nil && !friends.isBlocked($0.profile.id) }
            .map { ReactionPerson(kind: kinds[$0.profile.id]!, profile: $0.profile) }
            .sorted { ($0.profile.id == me ? 0 : 1) < ($1.profile.id == me ? 0 : 1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if people != nil {
                        ForEach(rows) { r in
                            HStack(spacing: 10) {
                                Avatar(profile: r.profile)
                                Text(r.profile.id == me ? "Ty" : r.profile.displayName)
                                    .font(Font.app.body.weight(.semibold))
                                    .foregroundStyle(Color.app.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(r.kind.label).captionStyle()
                                Image(systemName: r.kind.symbol)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(r.profile.id == me ? Color.app.accent : Color.app.textPrimary)
                                    .frame(width: 24)
                            }
                            .frame(minHeight: 52)
                            .accessibilityElement(children: .combine)
                            Divider().overlay(Color.app.hairline)
                        }
                    } else if failed {
                        Text("Reakce se nenačetly.").captionStyle().padding(.top, 20)
                    } else {
                        ProgressView().tint(Color.app.textSecondary).frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Reakce · \(reactions.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            do { people = try await API.reactionPeople(postID: postID) }
            catch {
                log.error("reactions load failed: \(String(describing: error))")
                failed = true
            }
        }
    }
}

/// Lišta s 5 reakcemi. Moje = žlutá, opětovné klepnutí reakci zruší.
struct ReactionPicker: View {
    let current: ReactionKind?
    var onPick: (ReactionKind?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReactionKind.allCases, id: \.self) { kind in
                Button {
                    onPick(kind == current ? nil : kind)
                } label: {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(kind == current ? Color.app.accent : Color.app.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.label)
                .accessibilityAddTraits(kind == current ? .isSelected : [])
            }
        }
        .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
        .sensoryFeedback(.selection, trigger: current)
    }
}
