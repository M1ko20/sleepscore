import Foundation
import Observation

@MainActor
@Observable
final class ChallengeStore {
    private(set) var challenges: [Challenge] = []
    private(set) var debts: [Debt] = []
    private(set) var friends: [ProfileLite] = []
    private(set) var loaded = false
    private(set) var error: String?

    /// Uzavřená výzva, jejíž výsledek jsem ještě neviděl (jednorázová obrazovka).
    var unseenResult: Challenge?

    private static let seenKey = "seenChallengeResults"
    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.seenKey) }
    }

    func load(me: UUID) async {
        do {
            async let c = API.myChallenges(userID: me)
            async let d = API.openDebts()
            async let f = API.friends(of: me)
            (challenges, debts, friends) = try await (c, d, f)
            error = nil
            pickUnseenResult(me: me)
        } catch {
            log.error("challenges load failed: \(String(describing: error))")
            self.error = "Výzvy se nenačetly."
        }
        loaded = true
    }

    func challenge(_ id: UUID) -> Challenge? { challenges.first { $0.id == id } }

    // MARK: Sekce seznamu

    func waitingForMe(_ me: UUID) -> [Challenge] {
        challenges.filter { $0.status == .pending && $0.me(me)?.status == .invited }
    }

    /// Moje čekající výzvy (čekám na soupeře / na start skupiny).
    func pendingMine(_ me: UUID) -> [Challenge] {
        challenges.filter { $0.status == .pending && $0.me(me)?.status == .accepted }
    }

    var running: [Challenge] { challenges.filter { $0.status == .active } }
    var finished: [Challenge] { challenges.filter { $0.status == .finished } }

    // MARK: Akce

    func respond(_ id: UUID, accept: Bool, me: UUID) async throws {
        try await API.respondChallenge(id, accept: accept)
        await load(me: me)
    }

    func start(_ id: UUID, me: UUID) async throws {
        try await API.startChallenge(id)
        await load(me: me)
    }

    func cancel(_ id: UUID, me: UUID) async throws {
        try await API.cancelChallenge(id)
        await load(me: me)
    }

    func create(type: ChallengeType, opponents: [UUID], days: Int, stake: String?, target: Int?, me: UUID) async throws {
        _ = try await API.createChallenge(type: type, opponents: opponents, days: days, stake: stake, target: target)
        await load(me: me)
    }

    func settle(_ debt: Debt, me: UUID) async throws {
        try await API.settleDebt(debt.id)
        debts.removeAll { $0.id == debt.id }
    }

    func markSeen(_ id: UUID) {
        seen.insert(id.uuidString)
        if unseenResult?.id == id { unseenResult = nil }
    }

    private func pickUnseenResult(me: UUID) {
        guard unseenResult == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugNoResult") { return }
        #endif
        let seen = self.seen
        // Výsledky starší než týden už neukazujeme (nový telefon, reinstalace).
        let weekAgo = ISODay.string(Calendar.iso.date(byAdding: .day, value: -7, to: .now)!)
        unseenResult = finished.first { c in
            !seen.contains(c.id.uuidString) && c.me(me)?.status == .accepted && (c.endDate ?? "") >= weekAgo
        }
    }
}
