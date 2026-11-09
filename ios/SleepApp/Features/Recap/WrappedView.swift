import SwiftUI

/// Sleep Wrapped: rok po slidech (jedno velké číslo + jedna suchá věta), na konci shrnutí ke sdílení.
struct WrappedView: View {
    let wrapped: SleepWrapped

    @Environment(FeedStore.self) private var feed
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var shareImage: Image?

    private var slides: [WrappedSlide] { WrappedSlide.all(wrapped, achievementNames: feed.achievementNames) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.app.bg.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { i, slide in
                    slideView(slide).tag(i)
                }
                summary.tag(slides.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            progress
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.app.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 20)
            .padding(.trailing, 8)
            .accessibilityLabel("Zavřít")
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-debugWrappedPage"), i + 1 < args.count, let n = Int(args[i + 1]) { page = n }
            #endif
            renderShareImage()
        }
    }

    /// Proužky nahoře jako u stories.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0...slides.count, id: \.self) { i in
                Capsule()
                    .fill(i <= page ? Color.app.accent : Color.app.hairline)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .padding(.trailing, 44)
        .accessibilityHidden(true)
    }

    private func slideView(_ s: WrappedSlide) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(s.label).statLabel()
            Text(s.value)
                .font(Font.app.scoreXL)
                .foregroundStyle(Color.app.textPrimary)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
            Text(s.line)
                .font(Font.app.title)
                .foregroundStyle(Color.app.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { page += 1 } }
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        VStack(spacing: 24) {
            Spacer()
            WrappedSummary(wrapped: wrapped)
            Spacer()
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview("Můj rok ve spaní", image: shareImage)) {
                    Text("Sdílet").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
            }
            Button("Zavřít") { dismiss() }.buttonStyle(.plainText)
        }
        .padding(24)
    }

    private func renderShareImage() {
        let card = WrappedSummary(wrapped: wrapped, branded: true)
            .padding(28)
            .frame(width: 390)
            .background(Color.app.bg)
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: card)
        r.scale = 3
        if let ui = r.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// Shrnutí roku – poslední slide a obrázek ke sdílení.
struct WrappedSummary: View {
    let wrapped: SleepWrapped
    var branded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Můj rok \(String(wrapped.year))").statLabel()
            Text(Fmt.avg(wrapped.avgScore?.value))
                .font(Font.app.scoreXL).foregroundStyle(Color.app.textPrimary)
            Text("Průměrné skóre").statLabel().padding(.top, -20)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 18) {
                GridRow {
                    StatBlock(value: "\(wrapped.nights)", label: "Nocí")
                    StatBlock(value: "\(wrapped.totalSleepMin / 60) h", label: "Spánku")
                }
                GridRow {
                    StatBlock(value: wrapped.record.fullText, label: "Výzvy")
                    StatBlock(value: "\(wrapped.souls)", label: "Oveček")
                }
                GridRow {
                    StatBlock(value: "\(wrapped.bestStreak ?? 0)", label: "Nejdelší série")
                    StatBlock(value: "\(wrapped.achievements)", label: "Odznaků")
                }
            }

            if branded {
                Text("Bedrival").font(Font.app.label).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Color.app.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Jeden slide: popisek, velká hodnota, věta. Slidy bez dat se vynechají.
struct WrappedSlide {
    let label: String
    let value: String
    let line: String

    static func all(_ w: SleepWrapped, achievementNames: [String: String]) -> [WrappedSlide] {
        var out: [WrappedSlide] = []
        let year = String(w.year)

        out.append(.init(label: "Tvůj rok \(year)", value: "\(w.nights)",
                         line: "nocí s hodinkami. Dohromady \(w.totalSleepMin / 60) hodin spánku, z toho \(w.deepMin / 60) v deepu."))

        if let avg = w.avgScore?.value {
            let best = w.bestNight.map { "Nejlepší noc \(day($0.date)): \($0.score)." } ?? ""
            out.append(.init(label: "Průměrné skóre", value: Fmt.avg(avg), line: best))
        }

        if let m = w.bestMonth {
            out.append(.init(label: "Nejlepší měsíc", value: monthName(m.month),
                             line: "Průměr \(Fmt.avg(m.avg.value)). Tenkrát to šlo."))
        }

        if let onset = w.avgOnset?.value {
            let streak = (w.bestStreak ?? 0) > 0 ? "Nejdelší série: \(w.bestStreak!) nocí v kuse." : "Série zatím žádná."
            out.append(.init(label: "Usínáš v průměru v", value: clock(onset), line: streak))
        }

        if let top = w.topTags.first {
            let rest = w.topTags.dropFirst().map { "\($0.label.lowercased()) (\($0.count)×)" }
            let line = rest.isEmpty ? "\(top.count)× za rok." : "\(top.count)×. Pak \(rest.joined(separator: " a "))."
            out.append(.init(label: "Nejčastější tag", value: top.label, line: line))
        }

        if w.challenges > 0 {
            var parts = ["\(w.challenges) \(w.challenges == 1 ? "výzva" : (2...4).contains(w.challenges) ? "výzvy" : "výzev"), \(w.souls) \(w.souls == 1 ? "ovečka" : (2...4).contains(w.souls) ? "ovečky" : "oveček")."]
            if let v = w.victim { parts.append("Oblíbená oběť: \(v.profile.displayName) (\(v.count)×).") }
            if let n = w.nemesis { parts.append("Nemesis: \(n.profile.displayName) (\(n.count)×).") }
            out.append(.init(label: "Výzvy", value: w.record.fullText, line: parts.joined(separator: " ")))
        }

        if w.achievements > 0 {
            let top = w.topAchievement.map { "Nejčastěji \(achievementNames[$0.code] ?? $0.code) (\($0.count)×)." } ?? ""
            out.append(.init(label: "Odznaky", value: "\(w.achievements)", line: top))
        }

        if w.reactions > 0 || w.comments > 0 {
            let r = w.topReaction.map { "Nejčastější reakce: \($0.label.lowercased())." } ?? ""
            out.append(.init(label: "Reakce od kamarádů", value: "\(w.reactions)",
                             line: [r, "\(w.comments) komentářů."].filter { !$0.isEmpty }.joined(separator: " ")))
        }
        return out
    }

    private static func day(_ iso: String) -> String {
        ISODay.date(iso).map {
            $0.formatted(Date.FormatStyle().day().month(.defaultDigits).locale(Locale(identifier: "cs_CZ")))
        } ?? iso
    }

    /// 1 → „leden“ (1. pád).
    private static func monthName(_ m: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        let names = f.standaloneMonthSymbols ?? []
        return (1...names.count).contains(m) ? names[m - 1] : "\(m)."
    }

    /// Minuty od poledne → „23:16“.
    private static func clock(_ fromNoon: Double) -> String {
        let total = (Int(fromNoon.rounded()) + 12 * 60) % (24 * 60)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Karta ve feedu (prosinec a leden).
struct WrappedCard: View {
    let year: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep Wrapped").statLabel()
                    Text("Tvůj rok \(String(year)) ve spánku").font(Font.app.title).foregroundStyle(Color.app.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.app.accent)
            }
            .cardStyle(highlighted: true)
        }
        .buttonStyle(.plain)
    }
}
