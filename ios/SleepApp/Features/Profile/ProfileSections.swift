import SwiftUI

/// Hlavička profilu: avatar, jméno, přezdívka.
struct ProfileHeader: View {
    let profile: ProfileLite

    var body: some View {
        HStack(spacing: 12) {
            Avatar(profile: profile, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                Text("@\(profile.username)").captionStyle()
            }
        }
    }
}

/// Bilance, série, průměr, vitrína duší, odznaky. Sdílené mým profilem i profilem přítele.
struct ProfileStatsSections: View {
    let summary: ProfileSummary
    let catalog: [AchievementInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            recordAndStreak
            average
            if let insights = summary.insights {
                InsightsSection(insights: insights, nights: summary.nights90 ?? 0)
            }
            SoulShowcase(souls: summary.souls, total: summary.soulCount)
            BadgeGrid(catalog: catalog, counts: summary.badgeCounts)
        }
    }

    private var recordAndStreak: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.mma.fullText)
                    .font(Font.app.scoreXL)
                    .foregroundStyle(Color.app.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Výhry-prohry-remízy").statLabel()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bilance \(summary.mma.wins) výher, \(summary.mma.losses) proher, \(summary.mma.draws) remíz")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SÉRIE \(summary.streak?.current ?? 0)")
                    .font(Font.app.stat).foregroundStyle(Color.app.textPrimary)
                Text("nejlepší \(summary.streak?.best ?? 0)").captionStyle()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var average: some View {
        HStack(spacing: 10) {
            Text("Průměr 30 dní").statLabel()
            Spacer()
            if let a = summary.avg30 {
                Text("\(Int(a.score.value.rounded()))")
                    .font(Font.app.stat).foregroundStyle(Color.app.textPrimary)
                Text("·").foregroundStyle(Color.app.textTertiary)
                Text(Fmt.duration(minutes: a.sleepMin))
                    .font(Font.app.stat).foregroundStyle(Color.app.textPrimary)
            } else {
                Text("zatím žádné noci").captionStyle()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SectionTitle: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 12) {
            Divider().overlay(Color.app.hairline)
            HStack {
                Text(title).statLabel()
                Spacer()
                Text(value).font(Font.app.label.monospacedDigit()).foregroundStyle(Color.app.textSecondary)
            }
        }
    }
}

/// Zjištění z tagů (jen můj profil): jedna věta na tag, nejsilnější nahoře.
struct InsightsSection: View {
    let insights: [TagInsight]
    let nights: Int

    static let minNights = 14

    private var lines: [(TagInsight, String)] {
        insights.sorted { InsightCopy.strength($0) > InsightCopy.strength($1) }
            .compactMap { i in InsightCopy.sentence(i).map { (i, $0) } }
            .prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Zjištění", value: "90 dní")
            if nights < Self.minNights {
                Text("Ukážou se po \(Self.minNights) nocích s tagy. Zatím máš \(nights).").captionStyle()
            } else if lines.isEmpty {
                Text("Zatím nic průkazného. Přidávej tagy ke kartám.").captionStyle()
            } else {
                ForEach(lines, id: \.0.id) { insight, text in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(insight.label) · \(nightsText(insight.nWith)) s tagem").captionStyle()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func nightsText(_ n: Int) -> String {
        switch n {
        case 1: "1 noc"
        case 2...4: "\(n) noci"
        default: "\(n) nocí"
        }
    }
}

/// Vitrína duší: 4 sloupce, desaturovaný avatar poraženého, datum, ×N.
struct SoulShowcase: View {
    let souls: [ProfileSummary.Soul]
    let total: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Vitrína duší", value: "\(total)")
            if souls.isEmpty {
                Text("Prázdno. Vyhraj výzvu a první duše je tvoje.").captionStyle()
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(souls) { soul in
                        VStack(spacing: 6) {
                            Avatar(profile: soul.loser, size: 52)
                                .grayscale(1)
                                .opacity(0.75)
                                .overlay(alignment: .bottomTrailing) {
                                    if soul.count > 1 {
                                        Text("×\(soul.count)")
                                            .font(Font.app.label.monospacedDigit())
                                            .foregroundStyle(Color.app.accentInk)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.app.accent, in: Capsule())
                                            .offset(x: 6, y: 2)
                                    }
                                }
                            Text(soul.loser.displayName.split(separator: " ").first.map(String.init) ?? soul.loser.displayName)
                                .font(Font.app.caption).foregroundStyle(Color.app.textPrimary).lineLimit(1)
                            Text(shortDate(soul.lastDate)).font(Font.app.label).foregroundStyle(Color.app.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Duše: \(soul.loser.displayName), \(soul.count)×")
                    }
                }
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = ISODay.date(iso) else { return iso }
        return d.formatted(.dateTime.day().month(.defaultDigits).locale(Locale(identifier: "cs_CZ")))
    }
}

/// Odznaky: šestiúhelníky, získané žlutě s ×N, nezískané šedě. Klepnutí = podmínka.
struct BadgeGrid: View {
    let catalog: [AchievementInfo]
    let counts: [String: Int]

    @State private var selected: AchievementInfo?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Odznaky", value: "\(counts.count)/\(catalog.count)")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(sorted, id: \.code) { a in
                    let n = counts[a.code] ?? 0
                    Button { selected = (selected?.code == a.code) ? nil : a } label: {
                        BadgeHex(symbol: BadgeGlyph.symbol(a.code), earned: n > 0, count: n,
                                 selected: selected?.code == a.code)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(a.name)\(n > 0 ? ", získáno \(n)×" : ", nezískáno")")
                    .accessibilityHint(a.description)
                }
            }
            if let s = selected {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.name).font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                        if let n = counts[s.code], n > 0 { Text("×\(n)").captionStyle() }
                    }
                    Text(s.description).captionStyle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }

    /// Získané první (v pořadí katalogu), pak ty, co se dají honit.
    private var sorted: [AchievementInfo] {
        catalog.filter { counts[$0.code] != nil } + catalog.filter { counts[$0.code] == nil }
    }
}

struct BadgeHex: View {
    let symbol: String
    let earned: Bool
    let count: Int
    var selected = false

    var body: some View {
        ZStack {
            Image(systemName: "hexagon")
                .font(.system(size: 50, weight: .ultraLight))
                .foregroundStyle(earned ? Color.app.accent : Color.app.hairline)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(earned ? Color.app.textPrimary : Color.app.textTertiary)
        }
        .frame(width: 54, height: 54)
        .background(selected ? Color.app.surfaceRaised : .clear, in: Circle())
        .overlay(alignment: .bottomTrailing) {
            if count > 1 {
                Text("×\(count)")
                    .font(Font.app.label.monospacedDigit())
                    .foregroundStyle(Color.app.textPrimary)
                    .offset(x: 2, y: 2)
            }
        }
    }
}
