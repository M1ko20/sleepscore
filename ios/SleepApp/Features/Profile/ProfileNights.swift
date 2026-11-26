import SwiftUI

/// Noci v profilu (můj i přítele): měsíc jako mřížka se skóre, pod ní seznam nocí toho měsíce.
/// Jeden call na měsíc (RPC `user_night_posts`), načtené měsíce drží v paměti.
struct NightsSection: View {
    let userID: UUID

    @Environment(FeedStore.self) private var feed

    /// První den zobrazeného měsíce.
    @State private var month = NightsSection.monthStart(.now)
    @State private var cache: [String: [FeedPost]] = [:]
    @State private var failed = false
    @State private var showAll = false
    private static let collapsed = 5

    private var key: String { ISODay.string(month) }
    private var nights: [FeedPost]? { cache[key] }
    private var isCurrentMonth: Bool { month >= Self.monthStart(.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let nights {
                MonthGrid(month: month, nights: nights)
                if nights.isEmpty {
                    Text("Žádné noci.").captionStyle()
                } else {
                    // Celý měsíc by odtlačil stádo a odznaky – nejdřív jen posledních pár nocí.
                    let shown = showAll ? nights : Array(nights.prefix(Self.collapsed))
                    VStack(spacing: 0) {
                        ForEach(shown) { post in
                            NavigationLink(value: post.id) { NightRow(post: post) }
                                .buttonStyle(.plain)
                            if post.id != shown.last?.id {
                                Divider().overlay(Color.app.hairline)
                            }
                        }
                    }
                    if nights.count > Self.collapsed {
                        Button(showAll ? "Méně" : "Celý měsíc (\(nights.count))") {
                            withAnimation(.snappy) { showAll.toggle() }
                        }
                        .buttonStyle(.plainText)
                    }
                }
            } else if failed {
                Button("Noci se nenačetly. Zkusit znovu") { Task { await load() } }
                    .font(Font.app.caption)
                    .tint(Color.app.textSecondary)
            } else {
                ProgressView().tint(Color.app.textSecondary).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: key) { await load() }
        .onChange(of: key) { showAll = false }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Divider().overlay(Color.app.hairline)
            HStack(spacing: 4) {
                Text("Noci").statLabel()
                Spacer()
                Button { shift(-1) } label: { chevron("chevron.left") }
                    .accessibilityLabel("Předchozí měsíc")
                Text(Self.monthTitle(month))
                    .font(Font.app.label.monospacedDigit())
                    .foregroundStyle(Color.app.textSecondary)
                Button { shift(1) } label: { chevron("chevron.right") }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Další měsíc")
            }
            .tint(Color.app.textPrimary)
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func shift(_ months: Int) {
        guard let m = Calendar.iso.date(byAdding: .month, value: months, to: month) else { return }
        month = min(m, Self.monthStart(.now))
    }

    /// Aktuální měsíc se načte znovu při každém zobrazení (mezitím mohla přibýt noc), starší jen jednou.
    private func load() async {
        let k = key
        guard cache[k] == nil || isCurrentMonth, let end = Calendar.iso.date(byAdding: DateComponents(month: 1, day: -1), to: month) else { return }
        failed = false
        do {
            let list = try await API.userNights(userID, from: k, to: ISODay.string(end))
            feed.adopt(list)
            cache[k] = list.sorted { $0.night.nightDate > $1.night.nightDate }
        } catch {
            log.error("profile nights failed: \(String(describing: error))")
            failed = cache[k] == nil
        }
    }

    static func monthStart(_ d: Date) -> Date {
        Calendar.iso.dateInterval(of: .month, for: d)?.start ?? d
    }

    /// „listopad 2026“
    static func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = Calendar.iso.timeZone
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }
}

/// Mřížka měsíce (týden od pondělí). Den s nocí = skóre a proklik na detail, nejlepší noc obrysem `accent`.
private struct MonthGrid: View {
    let month: Date
    let nights: [FeedPost]

    private static let weekdays = ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let byDate = Dictionary(nights.map { ($0.night.nightDate, $0) }, uniquingKeysWith: { a, _ in a })
        let best = nights.compactMap(\.night.score).max()
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.weekdays, id: \.self) { Text($0).statLabel().frame(maxWidth: .infinity) }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    let iso = ISODay.string(day)
                    if let post = byDate[iso] {
                        NavigationLink(value: post.id) {
                            cell(day: day, score: post.night.score, best: best != nil && post.night.score == best)
                        }
                        .buttonStyle(.plain)
                    } else {
                        cell(day: day, score: nil, best: false)
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    /// Dny měsíce, zepředu doplněné `nil` na pondělí.
    private var days: [Date?] {
        let cal = Calendar.iso
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) + 5) % 7   // po = 0 … ne = 6
        let list = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + list
    }

    private func cell(day: Date, score: Int?, best: Bool) -> some View {
        let n = Calendar.iso.component(.day, from: day)
        return VStack(spacing: 0) {
            Text("\(n)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.app.textTertiary)
            Text(score.map(String.init) ?? "·")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(score == nil ? Color.app.textTertiary : Color.app.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(score == nil ? Color.clear : Color.app.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if best { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.app.accent, lineWidth: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\(n). skóre \($0)" } ?? "\(n). bez noci")
    }
}

/// Řádek noci: datum a název, vpravo mini hypnogram, délka a skóre.
private struct NightRow: View {
    let post: FeedPost

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.nightStamp(post.night.nightDate))
                    .font(Font.app.body.weight(.semibold))
                    .foregroundStyle(Color.app.textPrimary)
                Text(post.displayTitle).captionStyle().lineLimit(1)
            }
            Spacer(minLength: 8)
            MiniHypnogram(segments: post.night.segments, start: post.night.sleepStart, end: post.night.sleepEnd)
                .frame(width: 56)
            Text(Fmt.duration(minutes: post.night.totalSleepMin))
                .font(Font.app.caption.monospacedDigit())
                .foregroundStyle(Color.app.textSecondary)
                .frame(width: 56, alignment: .trailing)
            Text(post.night.score.map(String.init) ?? "–")
                .font(Font.app.stat)
                .foregroundStyle(Color.app.textPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
