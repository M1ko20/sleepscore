import SwiftUI

/// Týden v číslech: průměr (a změna proti minulému), nejlepší a nejhorší noc, série, výzvy.
/// Sdílí se jako obrázek (ImageRenderer) – žádný odkaz ven, data zůstávají v appce.
struct RecapView: View {
    let recap: WeeklyRecap

    @Environment(Session.self) private var session
    @Environment(ChallengeStore.self) private var challenges
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    private var me: UUID? { session.profile?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                RecapContent(recap: recap, lines: challengeLines)
                    .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .safeAreaInset(edge: .bottom) {
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("Můj týden ve spaní", image: shareImage)) {
                        Text("Sdílet").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .padding(Metrics.screenPadding)
                    .background(Color.app.bg)
                }
            }
            .navigationTitle("Tvůj týden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }.tint(Color.app.textPrimary)
                }
            }
            .task { renderShareImage() }
        }
        .presentationBackground(Color.app.bg)
    }

    /// Výzvy, které v tom týdnu běžely (nebo skončily): „Ty vs Jakub · 87,3 : 85,1“.
    private var challengeLines: [String] {
        guard let me else { return [] }
        return challenges.challenges
            .filter { c in
                guard c.status == .active || c.status == .finished,
                      let start = c.startDate, let end = c.endDate else { return false }
                return start <= recap.weekEnd && end >= recap.weekStart
            }
            .prefix(4)
            .map { c in
                let result: String? = switch c.status == .finished ? c.me(me)?.result : nil {
                case .win: "výhra"
                case .loss: "prohra"
                case .draw: "remíza"
                case nil: nil
                }
                return [ChallengeCopy.title(c, me: me), result, ChallengeCopy.score(c, me: me)]
                    .compactMap { $0 }.joined(separator: " · ")
            }
    }

    private func renderShareImage() {
        let card = RecapContent(recap: recap, lines: challengeLines, branded: true)
            .padding(24)
            .frame(width: 390)
            .background(Color.app.bg)
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: card)
        r.scale = 3
        if let ui = r.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// Obsah recapu – stejný na obrazovce i v obrázku ke sdílení.
struct RecapContent: View {
    let recap: WeeklyRecap
    let lines: [String]
    var branded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Týden \(recap.rangeText)").statLabel()

            if recap.nights == 0 {
                Text("Žádná noc. Hodinky zůstaly v šuplíku?").font(Font.app.title)
                    .foregroundStyle(Color.app.textPrimary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.avg(recap.avgScore?.value))
                        .font(Font.app.scoreXL).foregroundStyle(Color.app.textPrimary)
                    HStack(spacing: 8) {
                        Text("Průměrné skóre").statLabel()
                        if let delta {
                            Text(delta).font(Font.app.caption.monospacedDigit()).foregroundStyle(Color.app.textSecondary)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 28) {
                    StatBlock(value: "\(recap.nights)/7", label: "Nocí")
                    StatBlock(value: Fmt.duration(minutes: recap.avgSleepMin ?? 0), label: "Průměrně")
                    StatBlock(value: "\(recap.streak?.current ?? 0)", label: "Série")
                }

                VStack(spacing: 0) {
                    if let b = recap.best { nightRow("Nejlepší noc", b) }
                    if let w = recap.worst, recap.nights > 1 { nightRow("Nejhorší noc", w) }
                    if recap.achievements > 0 { row("Nové odznaky", value: "+\(recap.achievements)") }
                }
            }

            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Výzvy").statLabel()
                    ForEach(lines, id: \.self) {
                        Text($0).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                    }
                }
            }

            if branded {
                Text("Bedrival").font(Font.app.label).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Color.app.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// „+2,4 proti minulému“
    private var delta: String? {
        guard let now = recap.avgScore?.value, let prev = recap.prevAvgScore?.value else { return nil }
        let d = now - prev
        guard abs(d) >= 0.05 else { return "stejně jako minule" }
        return "\(d > 0 ? "+" : "−")\(Fmt.avg(abs(d))) proti minulému"
    }

    private func nightRow(_ title: String, _ n: WeeklyRecap.Night) -> some View {
        let day = ISODay.date(n.date).map {
            $0.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.defaultDigits)
                .locale(Locale(identifier: "cs_CZ")))
        } ?? n.date
        return row(title, detail: day, value: "\(n.score)")
    }

    private func row(_ title: String, detail: String? = nil, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).statLabel()
            Spacer()
            if let detail { Text(detail).captionStyle() }
            Text(value).font(Font.app.stat).foregroundStyle(Color.app.textPrimary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
    }
}

/// Karta ve feedu po–st: „Tvůj týden“ + hlavní čísla. Klepnutí = recap, křížek = skrýt do dalšího týdne.
struct RecapCard: View {
    let recap: WeeklyRecap
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tvůj týden · \(recap.rangeText)").statLabel()
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.app.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skrýt")
                }
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    StatBlock(value: Fmt.avg(recap.avgScore?.value), label: "Průměr", font: Font.app.scoreL)
                    StatBlock(value: "\(recap.nights)/7", label: "Nocí")
                    if let b = recap.best { StatBlock(value: "\(b.score)", label: "Nejlepší") }
                }
                HStack {
                    Text("Celý týden").font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.accent)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.app.accent)
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
