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
