import SwiftUI

/// Detail výzvy (design.md → Detail výzvy).
struct ChallengeDetailView: View {
    let challengeID: UUID

    @Environment(Session.self) private var session
    @Environment(ChallengeStore.self) private var store
    @State private var error: String?
    @State private var busy = false
    @State private var rematch: ProfileLite?
    @State private var reporting: ReportRequest?

    private var me: UUID? { session.profile?.id }

    var body: some View {
        Group {
            if let c = store.challenge(challengeID) {
                content(c)
            } else {
                Text("Výzva už není k dispozici.").captionStyle()
            }
        }
        .background(Color.app.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $rematch) { NewChallengeFlow(prefill: $0) }
        .sheet(item: $reporting) { ReportSheet(request: $0) }
        .toolbar {
            if let c = store.challenge(challengeID), let stake = c.stake, !stake.isEmpty, c.creatorID != me {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nahlásit text výzvy") {
                            reporting = ReportRequest(kind: .challenge, targetID: c.id, author: c.creator?.profile)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(Color.app.textPrimary)
                    .accessibilityLabel("Další možnosti")
                }
            }
        }
        .task {
            // proklik ze zvonečku na výzvu, kterou seznam ještě nezná
            if store.challenge(challengeID) == nil, let me { await store.load(me: me) }
        }
    }

    private func content(_ c: Challenge) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text([c.type.label, Fmt.days(c.durationDays), c.dayProgress].compactMap { $0 }.joined(separator: " · "))
                        .statLabel()
                }
                poster(c)
                if c.status != .pending { grid(c) }
                info(c)
                actions(c)
                if let error { Text(error).font(Font.app.caption).foregroundStyle(Color.app.textPrimary) }
            }
            .padding(Metrics.screenPadding)
        }
    }

    // MARK: Plakát

    @ViewBuilder private func poster(_ c: Challenge) -> some View {
        switch c.type {
        case .duel:
            let players = c.participants.sorted { a, _ in a.userID == me }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(players.enumerated()), id: \.element.id) { i, p in
                    if i > 0 {
                        Text(":").font(Font.app.scoreL).foregroundStyle(Color.app.textTertiary)
                            .padding(.horizontal, 8).padding(.top, 22)
                    }
                    playerColumn(c, p, leading: i == 0)
                }
            }
        case .freeForAll:
            VStack(spacing: 0) {
                ForEach(Array(c.standings.enumerated()), id: \.element.id) { i, p in
                    standingRow(c, p, place: i + 1)
                }
                ForEach(c.participants.filter { $0.status != .accepted }) { p in
                    HStack {
                        Text(ChallengeCopy.name(p.profile, me: me)).foregroundStyle(Color.app.textSecondary)
                        Spacer()
                        Text(p.status == .invited ? "čeká" : "odmítnuto").captionStyle()
                    }
                    .font(Font.app.body)
                    .frame(minHeight: 44)
                }
            }
        case .teamGoal:
            teamBar(c)
        }
    }

    private func playerColumn(_ c: Challenge, _ p: Participant, leading: Bool) -> some View {
        let avg = c.average(p.userID)
        let lead = c.standings.first?.userID == p.userID && c.status != .pending
        return VStack(alignment: leading ? .leading : .trailing, spacing: 4) {
            Text(ChallengeCopy.name(p.profile, me: me).uppercased())
                .font(Font.app.label).tracking(0.6)
                .foregroundStyle(Color.app.textSecondary)
            Text(c.status == .pending ? "–" : Fmt.avg(avg))
                .font(Font.app.scoreXL)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(lead ? Color.app.textPrimary : Color.app.textSecondary)
            if c.status == .pending {
                Text(p.status == .invited ? "čeká" : "přijato").captionStyle()
            } else {
                Text("vyhrané \(Fmt.days(c.daysWon(p.userID)))").captionStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private func standingRow(_ c: Challenge, _ p: Participant, place: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(place).").font(Font.app.stat).foregroundStyle(Color.app.textTertiary).frame(width: 32, alignment: .leading)
            Avatar(profile: p.profile)
            Text(ChallengeCopy.name(p.profile, me: me)).font(Font.app.body.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
            Spacer()
            Text(Fmt.avg(c.average(p.userID))).font(Font.app.stat)
                .foregroundStyle(place == 1 ? Color.app.textPrimary : Color.app.textSecondary)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
    }

    private func teamBar(_ c: Challenge) -> some View {
        let avg = c.teamAverage ?? 0
        let target = Double(c.targetScore ?? 100)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.avg(c.teamAverage)).font(Font.app.scoreXL).foregroundStyle(Color.app.textPrimary)
                Text("/ \(Int(target))").font(Font.app.stat).foregroundStyle(Color.app.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.app.surfaceRaised)
                    Capsule().fill(avg >= target ? Color.app.accent : Color.app.textPrimary)
                        .frame(width: geo.size.width * min(1, avg / 100))
                    Rectangle().fill(Color.app.textSecondary).frame(width: 1.5, height: 14)
                        .offset(x: geo.size.width * target / 100)
                }
            }
            .frame(height: 6)
            Text("Průměr skupiny proti cíli").statLabel()
        }
    }

    // MARK: Mřížka dní

    private func grid(_ c: Challenge) -> some View {
        let days = c.days
        let players = c.type == .duel ? c.accepted.sorted { a, _ in a.userID == me } : c.standings
        let today = ISODay.today
        return VStack(alignment: .leading, spacing: 8) {
            Text("Dny").statLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .center, horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Color.clear.frame(width: 64, height: 1)
                        ForEach(days, id: \.self) { d in
                            Text(dayLabel(d)).font(Font.app.label).monospacedDigit()
                                .foregroundStyle(d == today ? Color.app.textPrimary : Color.app.textTertiary)
                                .frame(width: 36)
                        }
                    }
                    ForEach(players) { p in
                        GridRow {
                            Text(ChallengeCopy.name(p.profile, me: me))
                                .font(Font.app.caption.weight(.semibold))
                                .foregroundStyle(Color.app.textPrimary)
                                .lineLimit(1)
                                .frame(width: 64, alignment: .leading)
                            ForEach(days, id: \.self) { d in
                                cell(c, p.userID, d)
                            }
                        }
                    }
                }
            }
            if c.status == .active, missingPast(c) {
                Text("Chybějící noc je zatím 0. Dá se dohrát, dokud výzva běží.").captionStyle()
            }
        }
    }

    private func cell(_ c: Challenge, _ user: UUID, _ day: String) -> some View {
        let s = c.score(user, on: day)
        let missing = s == 0 && !c.scores.contains { $0.userID == user && $0.day == day }
        let won = c.type != .teamGoal && c.winner(of: day) == user   // společný cíl: hrají spolu
        return Text(s.map(String.init) ?? "·")
            .font(Font.app.caption.monospacedDigit().weight(won ? .bold : .regular))
            .foregroundStyle(s == nil || missing ? Color.app.textTertiary : won ? Color.app.textPrimary : Color.app.textSecondary)
            .frame(width: 36, height: 32)
            .background(won ? Color.app.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func missingPast(_ c: Challenge) -> Bool {
        let today = ISODay.today
        return c.accepted.contains { p in c.days.contains { d in d < today && !c.scores.contains { $0.userID == p.userID && $0.day == d } } }
    }

    private func dayLabel(_ iso: String) -> String {
        guard let d = ISODay.date(iso) else { return iso }
        let f = DateFormatter(); f.locale = Locale(identifier: "cs_CZ"); f.dateFormat = "d."
        return f.string(from: d)
    }

    // MARK: Info a akce

    private func info(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow("Hraje se o", c.stake ?? "jen o čest")
            if c.type == .teamGoal { infoRow("Cíl", "průměr \(c.targetScore ?? 0)") }
            switch c.status {
            case .pending: infoRow("Start", c.type == .duel ? "den po přijetí" : "spustí zakladatel")
            case .active: if let e = c.endsText { infoRow("Konec", e) }
            case .finished: infoRow("Výsledek", ChallengeCopy.resultLine(c, me: me))
            case .cancelled: infoRow("Stav", "zrušeno")
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).statLabel().frame(width: 80, alignment: .leading)
            Text(value).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
    }

    @ViewBuilder private func actions(_ c: Challenge) -> some View {
        if let me {
            let mine = c.me(me)
            if c.status == .pending, mine?.status == .invited {
                VStack(spacing: 8) {
                    Button("Přijmout") { run { try await store.respond(c.id, accept: true, me: me) } }.buttonStyle(.primary)
                    Button("Odmítnout") { run { try await store.respond(c.id, accept: false, me: me) } }.buttonStyle(.secondary)
                }
                .disabled(busy)
            } else if c.status == .pending, c.creatorID == me {
                VStack(spacing: 8) {
                    if c.type != .duel {
                        Button("Spustit od zítřka") { run { try await store.start(c.id, me: me) } }
                            .buttonStyle(.primary)
                            .disabled(c.accepted.count < 3 || busy)
                        if c.accepted.count < 3 {
                            Text("Spustit jde od 3 přijatých (včetně tebe).").captionStyle()
                        }
                    }
                    Button("Zrušit výzvu") { run { try await store.cancel(c.id, me: me) } }
                        .buttonStyle(.plainText)
                        .disabled(busy)
                }
            } else if c.status == .finished, c.type == .duel, mine?.result == .loss,
                      let opp = c.accepted.first(where: { $0.userID != me }) {
                Button("Odplata") { rematch = opp.profile }.buttonStyle(.primary)
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { self.error = serverMessage(error) }
        }
    }
}
