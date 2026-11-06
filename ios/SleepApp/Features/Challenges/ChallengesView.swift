import SwiftUI

struct ChallengesView: View {
    @Environment(Session.self) private var session
    @Environment(ChallengeStore.self) private var store
    @State private var creating = false
    @State private var actionError: String?
    @State private var busy: UUID?
    @State private var path: [UUID] = []

    private var me: UUID? { session.profile?.id }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let me { sections(me) }
                    if let actionError { Text(actionError).font(Font.app.caption).foregroundStyle(Color.app.textPrimary) }
                }
                .padding(Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Výzvy")
            .navigationDestination(for: UUID.self) { ChallengeDetailView(challengeID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: {
                        Image(systemName: "plus").fontWeight(.medium).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Nová výzva")
                }
            }
            .refreshable { if let me { await store.load(me: me) } }
            .task {
                if let me, !store.loaded { await store.load(me: me) }
                #if DEBUG
                // `-debugOpenChallenge active|finished|pending|free_for_all|team_goal` otevře detail.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-debugOpenChallenge"), i + 1 < args.count, path.isEmpty,
                   let c = store.challenges.first(where: { $0.status.rawValue == args[i + 1] || $0.type.rawValue == args[i + 1] }) {
                    path = [c.id]
                }
                #endif
            }
            .sheet(isPresented: $creating) { NewChallengeFlow() }
        }
    }

    @ViewBuilder private func sections(_ me: UUID) -> some View {
        let waiting = store.waitingForMe(me)
        let pending = store.pendingMine(me)
        let empty = store.loaded && store.challenges.isEmpty && store.debts.isEmpty

        if empty {
            VStack(spacing: 16) {
                Text("Žádná výzva. Někoho vyzvi.").captionStyle()
                Button("Nová výzva") { creating = true }.buttonStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        }
        if let error = store.error { Text(error).captionStyle() }

        if !waiting.isEmpty {
            section("Čeká na tebe") {
                ForEach(waiting) { c in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink(value: c.id) {
                            Text(ChallengeCopy.invite(c, me: me))
                                .font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            Button("Přijmout") { respond(c, true, me) }.buttonStyle(.primary)
                            Button("Odmítnout") { respond(c, false, me) }.buttonStyle(.secondary)
                        }
                        .disabled(busy == c.id)
                    }
                    .cardStyle(highlighted: true)
                }
            }
        }

        if !store.running.isEmpty || !pending.isEmpty {
            section("Běží") {
                ForEach(store.running) { c in row(c, me: me) }
                ForEach(pending) { c in row(c, me: me) }
            }
        }

        if !store.debts.isEmpty {
            section("Dluhy") {
                ForEach(store.debts) { d in debtRow(d, me: me) }
            }
        }

        if !store.finished.isEmpty {
            section("Hotové") {
                ForEach(store.finished) { c in row(c, me: me) }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).statLabel().padding(.bottom, 8)
            content()
        }
    }

    private func row(_ c: Challenge, me: UUID) -> some View {
        NavigationLink(value: c.id) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChallengeCopy.title(c, me: me))
                        .font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(c, me: me)).captionStyle()
                }
                Spacer(minLength: 12)
                Text(scoreText(c, me: me))
                    .font(Font.app.stat)
                    .foregroundStyle(c.me(me)?.result == .win ? Color.app.accent : Color.app.textPrimary)
            }
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ c: Challenge, me: UUID) -> String {
        switch c.status {
        case .pending:
            if c.type == .duel { return "čeká na soupeře" }
            return "přijalo \(c.accepted.count) z \(c.participants.count)"
        case .active:
            return [c.dayProgress, c.stake].compactMap { $0 }.joined(separator: " · ")
        case .finished:
            let end = c.endDate.flatMap(ISODay.date).map { d -> String in
                let f = DateFormatter(); f.locale = Locale(identifier: "cs_CZ"); f.dateFormat = "d. M."; return f.string(from: d)
            } ?? ""
            let r: String = switch c.me(me)?.result {
            case .win: "výhra"
            case .loss: "prohra"
            case .draw: "remíza"
            case nil: ""
            }
            return [r, end].filter { !$0.isEmpty }.joined(separator: " · ")
        case .cancelled:
            return "zrušeno"
        }
    }

    private func scoreText(_ c: Challenge, me: UUID) -> String {
        guard c.status != .pending else { return "" }
        switch c.type {
        case .duel:
            let mine = c.average(me)
            let other = c.accepted.first { $0.userID != me }.flatMap { c.average($0.userID) }
            return "\(Fmt.avg(mine)) : \(Fmt.avg(other))"
        case .freeForAll:
            guard let i = c.standings.firstIndex(where: { $0.userID == me }) else { return "" }
            return "\(i + 1). místo"
        case .teamGoal:
            return "\(Fmt.avg(c.teamAverage)) / \(c.targetScore ?? 0)"
        }
    }

    private func debtRow(_ d: Debt, me: UUID) -> some View {
        let iOwe = d.debtor.id == me
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(iOwe ? "Dlužíš: \(d.creditor.displayName)" : "\(d.debtor.displayName) ti dluží")
                    .font(Font.app.body.weight(.semibold)).foregroundStyle(Color.app.textPrimary)
                Text(d.stake).captionStyle()
            }
            Spacer()
            if iOwe {
                Button("Splaceno") {
                    Task {
                        do { try await store.settle(d, me: me) } catch { actionError = serverMessage(error) }
                    }
                }
                .font(Font.app.caption.weight(.semibold))
                .foregroundStyle(Color.app.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.app.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
            }
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
    }

    private func respond(_ c: Challenge, _ accept: Bool, _ me: UUID) {
        busy = c.id
        actionError = nil
        Task {
            defer { busy = nil }
            do { try await store.respond(c.id, accept: accept, me: me) } catch { actionError = serverMessage(error) }
        }
    }
}
