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

/// Bilance, série, průměr, stádo, odznaky. Sdílené mým profilem i profilem přítele.
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
                Text("Jen orientační srovnání tvých nocí, ne lékařská rada.").captionStyle()
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

/// Stádo: 4 sloupce, desaturovaný avatar poraženého, datum, ×N.
struct SoulShowcase: View {
    let souls: [ProfileSummary.Soul]
    let total: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Stádo", value: "\(total)")
            if souls.isEmpty {
                Text("Zatím ani jedna ovečka. Vyhraj výzvu a první je tvoje.").captionStyle()
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
                        .accessibilityLabel("Ovečka: \(soul.loser.displayName), \(soul.count)×")
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

/// Odznaky: jen získané (žlutě s ×N). Klepnutí = podmínka pod mřížkou a posun k ní.
struct BadgeGrid: View {
    let catalog: [AchievementInfo]
    let counts: [String: Int]

    @State private var selected: AchievementInfo?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private static let detailID = "badgeDetail"

    var body: some View {
        // Reader uvnitř ScrollView profilu – scrollTo posouvá ten nadřazený.
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Odznaky", value: "\(earned.count)/\(catalog.count)")
                if earned.isEmpty {
                    Text("Zatím žádný. První přijde dřív, než čekáš.").captionStyle()
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(earned, id: \.code) { a in
                        let n = counts[a.code] ?? 0
                        Button { selected = (selected?.code == a.code) ? nil : a } label: {
                            BadgeHex(symbol: BadgeGlyph.symbol(a.code), earned: true, count: n,
                                     selected: selected?.code == a.code)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(a.name), získáno \(n)×")
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
                    .id(Self.detailID)
                }
            }
            .onChange(of: selected?.code) { _, code in
                guard code != nil else { return }
                // Až po vložení karty do layoutu, jinak scrollTo nemá kam.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.snappy) { proxy.scrollTo(Self.detailID, anchor: .bottom) }
                }
            }
        }
    }

    /// Jen získané, v pořadí katalogu.
    private var earned: [AchievementInfo] {
        catalog.filter { (counts[$0.code] ?? 0) > 0 }
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
