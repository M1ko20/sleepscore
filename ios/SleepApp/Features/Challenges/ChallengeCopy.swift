import Foundation

/// Suché věty k výzvám (design.md → Tón textů).
enum ChallengeCopy {
    static func name(_ p: ProfileLite, me: UUID?) -> String { p.id == me ? "Ty" : p.displayName }

    /// Titulek řádku: „Ty vs Jakub“ / „Partička (4)“
    static func title(_ c: Challenge, me: UUID?) -> String {
        switch c.type {
        case .duel:
            let names = c.participants.sorted { a, _ in a.userID == me }.map { name($0.profile, me: me) }
            return names.joined(separator: " vs ")
        case .freeForAll: return "Všichni proti všem (\(c.accepted.count))"
        case .teamGoal: return "Společný cíl \(c.targetScore ?? 0) (\(c.accepted.count))"
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
            guard let w = winners.first, winners.count == 1 else { return "Remíza. Nikdo nic nebere." }
            let wn = name(w.profile, me: me)
            let souls = losers.count == 1 ? "ovečku" : (2...4).contains(losers.count) ? "\(losers.count) ovečky" : "\(losers.count) oveček"
            var line = w.userID == me ? "Bereš \(souls)." : "\(wn) bere \(souls)."
            if let stake = c.stake { line += " Sázka: \(stake)." }
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
