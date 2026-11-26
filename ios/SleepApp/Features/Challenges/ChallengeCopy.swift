import Foundation

/// Suché věty k výzvám (design.md → Tón textů).
enum ChallengeCopy {
    static func name(_ p: ProfileLite, me: UUID?) -> String { p.id == me ? "Ty" : p.displayName }

    /// Titulek: „Ty vs Jakub“ / skupina jménama „Ty, Jakub, Bára“ (typ je v `kind`).
    /// Dlouhý seznam utne `lineLimit(1)` třemi tečkami; `maxNames` ho zkrátí už tady (recap).
    static func title(_ c: Challenge, me: UUID?, maxNames: Int? = nil) -> String {
        switch c.type {
        case .duel:
            var names = c.participants.sorted { a, _ in a.userID == me }.map { name($0.profile, me: me) }
            if names.count == 1 { names.append("smazaný účet") }
            return names.joined(separator: " vs ")
        case .freeForAll, .teamGoal:
            // Než výzva začne, i pozvaní (kdo odmítl, už ne); pak jen kdo hraje.
            let started = c.status == .active || c.status == .finished
            let players = c.participants.filter { started ? $0.status == .accepted : $0.status != .declined }
            let names = players.sorted { a, _ in a.userID == me }.map { name($0.profile, me: me) }
            if let maxNames, names.count > maxNames {
                return names.prefix(maxNames).joined(separator: ", ") + "…"
            }
            return names.joined(separator: ", ")
        }
    }

    /// Typ skupinové výzvy do podtitulku: „všichni proti všem“, „společný cíl 75“. U souboje nil.
    static func kind(_ c: Challenge) -> String? {
        switch c.type {
        case .duel: nil
        case .freeForAll: "všichni proti všem"
        case .teamGoal: "společný cíl \(c.targetScore ?? 0)"
        }
    }

    /// Pozvánka: „Jakub Novotny: souboj, 7 dní, večeře.“ (bez rodu – nevíme, kdo je kdo)
    static func invite(_ c: Challenge, me: UUID?) -> String {
        let who = c.creator?.profile.displayName ?? "Někdo"
        let kind = switch c.type {
        case .duel: "souboj"
        case .freeForAll: "všichni proti všem"
        case .teamGoal: "společný cíl \(c.targetScore ?? 0)"
        }
        var s = "\(who): \(kind), \(Fmt.days(c.durationDays))"
        if let stake = c.stake { s += ", \(stake)" }
        return s + "."
    }

    /// Jedna věta výsledku do feedu.
    static func resultLine(_ c: Challenge, me: UUID?) -> String {
        let winners = c.accepted.filter { $0.result == .win }
        let losers = c.accepted.filter { $0.result == .loss }
        switch c.type {
        case .teamGoal:
            let avg = Fmt.avg(c.teamAverage)
            return winners.isEmpty ? "Cíl \(c.targetScore ?? 0) nesplněn. Průměr \(avg)." : "Cíl \(c.targetScore ?? 0) splněn. Průměr \(avg)."
        case .duel, .freeForAll:
            if c.forfeit {
                return c.type == .freeForAll ? "Ostatní smazali účet. Výhra kontumačně." : "Soupeř smazal účet. Výhra kontumačně."
            }
            guard let w = winners.first, winners.count == 1 else { return "Remíza. Nikdo nic nebere." }
            let wn = name(w.profile, me: me)
            let souls = losers.count == 1 ? "ovečku" : (2...4).contains(losers.count) ? "\(losers.count) ovečky" : "\(losers.count) oveček"
            var line = w.userID == me ? "Bereš \(souls)." : "\(wn) bere \(souls)."
            if let stake = c.stake { line += " Hraje se o: \(stake)." }
            return line
        }
    }

    /// Skóre do řádku: „87,3 : 88,2“, „3. místo“, „89,8 / 85“.
    static func score(_ c: Challenge, me: UUID) -> String {
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
}
