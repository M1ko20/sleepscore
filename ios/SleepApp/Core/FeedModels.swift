import Foundation

struct ProfileLite: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarPath: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, username, timezone
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }

    var timeZone: TimeZone { timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
}

enum SleepStage: String, Codable, Sendable, CaseIterable {
    case awake, rem, core, deep, asleep

    /// Řádek v hypnogramu (0 = nahoře).
    var row: Int {
        switch self {
        case .awake: 0
        case .rem: 1
        case .core, .asleep: 2
        case .deep: 3
        }
    }

    var label: String {
        switch self {
        case .awake: "Vzhůru"
        case .rem: "REM"
        case .core, .asleep: "Core"
        case .deep: "Deep"
        }
    }
}

struct Segment: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
    let stage: SleepStage
}

struct HeartRatePoint: Decodable, Hashable, Sendable {
    let t: Date
    let bpm: Double

    /// V DB jako ["ISO", 52].
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(Date.self)
        bpm = try c.decode(Double.self)
    }
}

struct Night: Decodable, Hashable, Sendable, Identifiable {
    let id: UUID
    let nightDate: String
    let sleepStart: Date
    let sleepEnd: Date
    let totalSleepMin: Int
    let awakeMin: Int
    let coreMin: Int
    let deepMin: Int
    let remMin: Int
    let wakeCount: Int
    let hrAvg: Double?
    let score: Int?
    let scoreBreakdown: [String: Double?]?
    var tags: [String]
    let segments: [Segment]
    let achievementCodes: [String]

    enum CodingKeys: String, CodingKey {
        case id, score
        case nightDate = "night_date"
        case sleepStart = "sleep_start"
        case sleepEnd = "sleep_end"
        case totalSleepMin = "total_sleep_min"
        case awakeMin = "awake_min"
        case coreMin = "core_min"
        case deepMin = "deep_min"
        case remMin = "rem_min"
        case wakeCount = "wake_count"
        case hrAvg = "hr_avg"
        case scoreBreakdown = "score_breakdown"
        case nightTags = "night_tags"
        case nightRaw = "night_raw"
        case userAchievements = "user_achievements"
    }

    private struct TagRow: Decodable { let tag: String }
    private struct Raw: Decodable { let segments: [Segment] }
    private struct AchievementRow: Decodable { let code: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nightDate = try c.decode(String.self, forKey: .nightDate)
        sleepStart = try c.decode(Date.self, forKey: .sleepStart)
        sleepEnd = try c.decode(Date.self, forKey: .sleepEnd)
        totalSleepMin = try c.decode(Int.self, forKey: .totalSleepMin)
        awakeMin = try c.decode(Int.self, forKey: .awakeMin)
        coreMin = try c.decode(Int.self, forKey: .coreMin)
        deepMin = try c.decode(Int.self, forKey: .deepMin)
        remMin = try c.decode(Int.self, forKey: .remMin)
        wakeCount = try c.decode(Int.self, forKey: .wakeCount)
        hrAvg = try c.decodeIfPresent(Double.self, forKey: .hrAvg)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        scoreBreakdown = try c.decodeIfPresent([String: Double?].self, forKey: .scoreBreakdown)
        tags = (try c.decodeIfPresent([TagRow].self, forKey: .nightTags) ?? []).map(\.tag)
        segments = (try c.decodeIfPresent(Raw.self, forKey: .nightRaw))?.segments ?? []
        achievementCodes = (try c.decodeIfPresent([AchievementRow].self, forKey: .userAchievements) ?? []).map(\.code)
    }
}

enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case sleeper, zombie, beer, coffee, crown

    /// Zatím SF Symbols, vlastní glyfy později (design.md).
    var symbol: String {
        switch self {
        case .sleeper: "moon.zzz"
        case .zombie: "hand.raised"
        case .beer: "mug"
        case .coffee: "cup.and.saucer"
        case .crown: "crown"
        }
    }

    var label: String {
        switch self {
        case .sleeper: "Spal jak dřevo"
        case .zombie: "Zombie"
        case .beer: "Pivo vyhrálo"
        case .coffee: "Potřebuješ kafe"
        case .crown: "Král spánku"
        }
    }
}

struct Reaction: Codable, Hashable, Sendable {
    let userID: UUID
    let kind: ReactionKind

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case kind
    }
}

struct FeedPost: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var body: String?
    var photoPath: String?
    let createdAt: Date
    let author: ProfileLite
    var night: Night
    var reactions: [Reaction]
    var commentCount: Int
    /// Skryto ostatním po hlášeních (do kontroly). Vidí jen autor.
    let hiddenAt: Date?

    static let select = """
    id,title,body,photo_path,created_at,hidden_at,\
    author:profiles!posts_user_id_fkey(id,username,display_name,avatar_path,timezone),\
    night:nights(id,night_date,sleep_start,sleep_end,total_sleep_min,awake_min,core_min,deep_min,rem_min,\
    wake_count,hr_avg,score,score_breakdown,night_tags(tag),night_raw(segments),user_achievements(code)),\
    reactions(user_id,kind),comments(count)
    """

    enum CodingKeys: String, CodingKey {
        case id, title, body, author, night, reactions, comments
        case photoPath = "photo_path"
        case createdAt = "created_at"
        case hiddenAt = "hidden_at"
    }

    private struct Count: Decodable { let count: Int }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        author = try c.decode(ProfileLite.self, forKey: .author)
        night = try c.decode(Night.self, forKey: .night)
        reactions = try c.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
        commentCount = (try c.decodeIfPresent([Count].self, forKey: .comments))?.first?.count ?? 0
        hiddenAt = try c.decodeIfPresent(Date.self, forKey: .hiddenAt)
    }

    /// Karta bez názvu i tagů = ještě nedoplněná.
    var needsDetails: Bool { (title ?? "").isEmpty && night.tags.isEmpty }
}

struct Comment: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let body: String
    let createdAt: Date
    let author: ProfileLite
    /// Skryto ostatním po hlášeních (do kontroly). Vidí jen autor.
    var hiddenAt: Date? = nil

    static let select = "id,body,created_at,hidden_at,author:profiles(id,username,display_name,avatar_path,timezone)"

    enum CodingKeys: String, CodingKey {
        case id, body, author
        case createdAt = "created_at"
        case hiddenAt = "hidden_at"
    }
}

struct Tag: Decodable, Hashable, Sendable, Identifiable {
    let slug: String
    let label: String
    /// Pomáhá spánku (pravý sloupec výběru), jinak ho kazí.
    var positive: Bool = false
    var id: String { slug }
}

struct AchievementInfo: Decodable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
}

struct UserStats: Decodable, Hashable, Sendable {
    let userID: UUID
    let currentStreak: Int
    let bestStreak: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
    }
}

struct ChallengeResultPost: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let challenge: Challenge

    enum CodingKeys: String, CodingKey {
        case id, challenge
        case createdAt = "created_at"
    }
}

enum FeedItem: Identifiable, Hashable {
    case night(FeedPost)
    case result(ChallengeResultPost)

    var id: UUID {
        switch self {
        case .night(let p): p.id
        case .result(let r): r.id
        }
    }

    var createdAt: Date {
        switch self {
        case .night(let p): p.createdAt
        case .result(let r): r.createdAt
        }
    }
}
