import Foundation

enum ChallengeType: String, Codable, Sendable, CaseIterable {
    case duel
    case freeForAll = "free_for_all"
    case teamGoal = "team_goal"

    var label: String {
        switch self {
        case .duel: "Souboj"
        case .freeForAll: "Všichni proti všem"
        case .teamGoal: "Společný cíl"
        }
    }
}

enum ChallengeStatus: String, Codable, Sendable { case pending, active, finished, cancelled }
enum ParticipantStatus: String, Codable, Sendable { case invited, accepted, declined }
enum ChallengeResult: String, Codable, Sendable { case win, loss, draw }

/// numeric z Postgresu může přijít jako číslo i jako text.
struct FlexDouble: Decodable, Hashable, Sendable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else { value = Double(try c.decode(String.self)) ?? 0 }
    }
}

struct Participant: Decodable, Hashable, Sendable, Identifiable {
    let userID: UUID
    let status: ParticipantStatus
    let finalAvg: Double?
    let daysWon: Int?
    let result: ChallengeResult?
    let profile: ProfileLite
    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case status, result, profile
        case userID = "user_id"
        case finalAvg = "final_avg"
        case daysWon = "days_won"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        status = try c.decode(ParticipantStatus.self, forKey: .status)
        finalAvg = try c.decodeIfPresent(FlexDouble.self, forKey: .finalAvg)?.value
        daysWon = try c.decodeIfPresent(Int.self, forKey: .daysWon)
        result = try c.decodeIfPresent(ChallengeResult.self, forKey: .result)
        profile = try c.decode(ProfileLite.self, forKey: .profile)
    }
}

struct DayScore: Decodable, Hashable, Sendable {
    let userID: UUID
    let day: String
    let score: Int

    enum CodingKeys: String, CodingKey {
        case day, score
        case userID = "user_id"
    }
}

struct Challenge: Decodable, Hashable, Sendable, Identifiable {
    let id: UUID
    let type: ChallengeType
    let creatorID: UUID?   // null, když zakladatel smazal účet
    let stake: String?
    let durationDays: Int
    let targetScore: Int?
    let startDate: String?
    let endDate: String?
    let status: ChallengeStatus
    let createdAt: Date
    let participants: [Participant]
    let scores: [DayScore]

    static let select = """
    id,type,creator_id,stake,duration_days,target_score,start_date,end_date,status,created_at,\
    participants:challenge_participants(user_id,status,final_avg,days_won,result,\
    profile:profiles(id,username,display_name,avatar_path,timezone)),\
    scores:challenge_day_scores(user_id,day,score)
    """

    enum CodingKeys: String, CodingKey {
        case id, type, stake, status, participants, scores
        case creatorID = "creator_id"
        case durationDays = "duration_days"
        case targetScore = "target_score"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ChallengeType.self, forKey: .type)
        creatorID = try c.decodeIfPresent(UUID.self, forKey: .creatorID)
        stake = try c.decodeIfPresent(String.self, forKey: .stake)
        durationDays = try c.decode(Int.self, forKey: .durationDays)
        targetScore = try c.decodeIfPresent(Int.self, forKey: .targetScore)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        status = try c.decode(ChallengeStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        participants = try c.decodeIfPresent([Participant].self, forKey: .participants) ?? []
        scores = try c.decodeIfPresent([DayScore].self, forKey: .scores) ?? []
    }

    // MARK: Odvozené

    var creator: Participant? { participants.first { $0.userID == creatorID } }
    var accepted: [Participant] { participants.filter { $0.status == .accepted } }
    func me(_ id: UUID?) -> Participant? { participants.first { $0.userID == id } }

    /// Všechny dny výzvy (ISO), prázdné u čekající.
    var days: [String] {
        guard let s = startDate.flatMap(ISODay.date), let e = endDate.flatMap(ISODay.date) else { return [] }
        var out: [String] = []
        var d = s
        while d <= e { out.append(ISODay.string(d)); d = Calendar.iso.date(byAdding: .day, value: 1, to: d)! }
        return out
    }

    /// Skóre hráče v den: nalezené, 0 za uplynulý den bez noci, nil = ještě nehraný den.
    func score(_ user: UUID, on day: String, today: String = ISODay.today) -> Int? {
        if let s = scores.first(where: { $0.userID == user && $0.day == day }) { return s.score }
        if status == .finished { return 0 }
        return day < today ? 0 : nil
    }

    /// Dny, které už se počítají (uplynulé, nebo dnešní s nocí).
    func playedDays(today: String = ISODay.today) -> [String] {
        days.filter { d in d < today || status == .finished || scores.contains { $0.day == d } }
    }

    /// Průměr hráče: po uzavření finální, jinak průběžný (chybějící uplynulý den = 0).
    func average(_ user: UUID) -> Double? {
        if status == .finished, let f = me(user)?.finalAvg { return f }
        let vals = playedDays().compactMap { score(user, on: $0) }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    func daysWon(_ user: UUID) -> Int {
        if status == .finished, let w = me(user)?.daysWon { return w }
        return playedDays().filter { winner(of: $0) == user }.count
    }

    /// Den vyhrává jen jasně nejvyšší skóre.
    func winner(of day: String) -> UUID? {
        let vals = accepted.compactMap { p in score(p.userID, on: day).map { (p.userID, $0) } }
        guard let top = vals.map(\.1).max(), top > 0 else { return nil }
        let leaders = vals.filter { $0.1 == top }
        return leaders.count == 1 ? leaders[0].0 : nil
    }

    /// Pořadí podle průměru (sestupně).
    var standings: [Participant] {
        accepted.sorted { (average($0.userID) ?? -1) > (average($1.userID) ?? -1) }
    }

    var teamAverage: Double? {
        let vals = accepted.flatMap { p in playedDays().compactMap { score(p.userID, on: $0) } }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    /// „den 4/7“
    var dayProgress: String? {
        guard status == .active, let s = startDate.flatMap(ISODay.date) else { return nil }
        let n = (Calendar.iso.dateComponents([.day], from: s, to: ISODay.date(ISODay.today)!).day ?? 0) + 1
        return n < 1 ? "začíná zítra" : "den \(min(n, durationDays))/\(durationDays)"
    }

    /// „končí v neděli ve 14:00“ (čas zakladatele)
    var endsText: String? {
        guard let e = endDate.flatMap(ISODay.date) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEE d. M."
        return "končí \(f.string(from: e)) ve 14:00"
    }
}

struct Debt: Decodable, Hashable, Sendable, Identifiable {
    let id: UUID
    let stake: String
    let settledAt: Date?
    let debtor: ProfileLite
    let creditor: ProfileLite

    static let select = """
    id,stake,settled_at,\
    debtor:profiles!debts_debtor_id_fkey(id,username,display_name,avatar_path,timezone),\
    creditor:profiles!debts_creditor_id_fkey(id,username,display_name,avatar_path,timezone)
    """

    enum CodingKeys: String, CodingKey {
        case id, stake, debtor, creditor
        case settledAt = "settled_at"
    }
}

/// Práce s „yyyy-MM-dd“ (night_date, start_date…).
enum ISODay {
    static func date(_ s: String) -> Date? { formatter.date(from: s) }
    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static var today: String { string(.now) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .iso
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Calendar {
    static let iso: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2   // týden od pondělí (recap, ISO týdny)
        return c
    }()
}

extension Fmt {
    /// 81.43 → „81,4“
    static func avg(_ v: Double?) -> String {
        guard let v else { return "–" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.roundingMode = .halfUp   // 87,25 → 87,3 (výchozí je bankéřské)
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// „2 dny“, „5 dní“, „1 den“
    static func days(_ n: Int) -> String {
        switch n {
        case 1: "1 den"
        case 2...4: "\(n) dny"
        default: "\(n) dní"
        }
    }
}
