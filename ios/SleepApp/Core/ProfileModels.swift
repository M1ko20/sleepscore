import Foundation

/// Výhry-prohry-remízy.
struct Record: Decodable, Hashable, Sendable {
    let wins: Int
    let losses: Int
    let draws: Int

    static let zero = Record(wins: 0, losses: 0, draws: 0)

    /// „12-3-1“, remízy jen když nějaké jsou („7-3“).
    var text: String { draws > 0 ? "\(wins)-\(losses)-\(draws)" : "\(wins)-\(losses)" }
    var fullText: String { "\(wins)-\(losses)-\(draws)" }
    var isEmpty: Bool { wins + losses + draws == 0 }
}

enum FriendshipStatus: String, Decodable, Sendable {
    case pending, accepted
}

/// Výstup RPC `profile_summary` – celý profil jedním callem.
struct ProfileSummary: Decodable, Sendable {
    struct Streak: Decodable, Sendable { let current: Int; let best: Int }
    struct Average: Decodable, Sendable {
        let score: FlexDouble
        let sleepMin: Int
        let nights: Int
        enum CodingKeys: String, CodingKey { case score, nights; case sleepMin = "sleep_min" }
    }
    struct Soul: Decodable, Sendable, Identifiable {
        let loser: ProfileLite
        let count: Int
        let lastDate: String
        var id: UUID { loser.id }
        enum CodingKeys: String, CodingKey { case loser, count; case lastDate = "last_date" }
    }
    struct Badge: Decodable, Sendable { let code: String; let count: Int }
    struct Friendship: Decodable, Sendable {
        let status: FriendshipStatus
        let requestedBy: UUID
        enum CodingKeys: String, CodingKey { case status; case requestedBy = "requested_by" }
    }

    enum CodingKeys: String, CodingKey {
        case profile, mma, streak, avg30, souls, achievements, h2h, friendship, insights
        case nights90 = "nights_90"
    }

    let profile: ProfileLite
    let mma: Record
    let streak: Streak?
    let avg30: Average?
    let souls: [Soul]
    let achievements: [Badge]
    let h2h: Record?
    let friendship: Friendship?
    /// Jen na vlastním profilu (jinak nil).
    let insights: [TagInsight]?
    let nights90: Int?

    var soulCount: Int { souls.reduce(0) { $0 + $1.count } }
    var badgeCounts: [String: Int] { Dictionary(uniqueKeysWithValues: achievements.map { ($0.code, $0.count) }) }
}

/// Řádek přátelství z pohledu přihlášeného uživatele.
struct FriendshipEntry: Identifiable, Hashable, Sendable {
    let other: ProfileLite
    let status: FriendshipStatus
    /// true = žádost poslal ten druhý (čeká na mě).
    let incoming: Bool
    var id: UUID { other.id }
}

/// SF Symbol pro odznak (než budou vlastní glyfy).
enum BadgeGlyph {
    static func symbol(_ code: String) -> String {
        switch code {
        case "coma": "bed.double.fill"
        case "zombie": "figure.walk"
        case "night_shift": "moon.haze"
        case "didnt_move": "pause"
        case "deep_diver": "arrow.down.to.line"
        case "perfect_night": "star"
        case "either_or": "arrow.left.arrow.right"
        case "swiss_watch": "clock"
        case "double_life": "theatermasks"
        case "streak_7": "7.circle"
        case "streak_30": "30.circle"
        case "streak_100": "flame"
        case "despite_it": "bolt"
        case "beer_won": "mug"
        case "first_soul": "person.crop.circle"
        case "collector": "square.grid.2x2"
        case "undefeated": "shield"
        case "revenge": "arrow.uturn.backward"
        case "by_a_hair": "scissors"
        case "forgot_watch": "applewatch.slash"
        case "stolen_hour": "clock.arrow.circlepath"
        case "new_year_survivor": "sparkles"
        default: "hexagon"
        }
    }
}

extension Profile {
    var lite: ProfileLite {
        ProfileLite(id: id, username: username, displayName: displayName, avatarPath: avatarPath, timezone: timezone)
    }
}

/// Noci s tagem vs. bez něj (90 dní). Větu skládá `InsightCopy`.
struct TagInsight: Decodable, Sendable, Identifiable {
    let tag: String
    let label: String
    let nWith: Int
    let nWithout: Int
    let scoreWith: FlexDouble?
    let scoreWithout: FlexDouble?
    let deepWith: FlexDouble?
    let deepWithout: FlexDouble?
    let onsetWith: FlexDouble?
    let onsetWithout: FlexDouble?
    let sleepWith: FlexDouble?
    let sleepWithout: FlexDouble?
    var id: String { tag }

    enum CodingKeys: String, CodingKey {
        case tag, label
        case nWith = "n_with", nWithout = "n_without"
        case scoreWith = "score_with", scoreWithout = "score_without"
        case deepWith = "deep_with", deepWithout = "deep_without"
        case onsetWith = "onset_with", onsetWithout = "onset_without"
        case sleepWith = "sleep_with", sleepWithout = "sleep_without"
    }
}

/// Výstup RPC `weekly_recap`.
struct WeeklyRecap: Decodable, Sendable {
    struct Night: Decodable, Sendable { let date: String; let score: Int }
    struct Streak: Decodable, Sendable { let current: Int; let best: Int }

    let weekStart: String
    let weekEnd: String
    let nights: Int
    let avgScore: FlexDouble?
    let avgSleepMin: Int?
    let prevAvgScore: FlexDouble?
    let best: Night?
    let worst: Night?
    let streak: Streak?
    let achievements: Int

    enum CodingKeys: String, CodingKey {
        case nights, best, worst, streak, achievements
        case weekStart = "week_start", weekEnd = "week_end"
        case avgScore = "avg_score", avgSleepMin = "avg_sleep_min", prevAvgScore = "prev_avg_score"
    }

    /// „26. 10. – 1. 11.“
    var rangeText: String {
        guard let a = ISODay.date(weekStart), let b = ISODay.date(weekEnd) else { return weekStart }
        let f = Date.FormatStyle().day().month(.defaultDigits).locale(Locale(identifier: "cs_CZ"))
        return "\(a.formatted(f)) – \(b.formatted(f))"
    }
}

/// Výstup RPC `sleep_wrapped` – rok jedním callem.
struct SleepWrapped: Decodable, Sendable, Identifiable {
    var id: Int { year }
    struct Night: Decodable, Sendable { let date: String; let score: Int }
    struct Month: Decodable, Sendable { let month: Int; let avg: FlexDouble }
    struct TagCount: Decodable, Sendable { let tag: String; let label: String; let count: Int }
    struct Person: Decodable, Sendable { let profile: ProfileLite; let count: Int }
    struct Badge: Decodable, Sendable { let code: String; let count: Int }

    let year: Int
    let nights: Int
    let totalSleepMin: Int
    let deepMin: Int
    let avgScore: FlexDouble?
    let avgOnset: FlexDouble?
    let bestNight: Night?
    let bestMonth: Month?
    let bestStreak: Int?
    let topTags: [TagCount]
    let record: Record
    let challenges: Int
    let souls: Int
    let victim: Person?
    let nemesis: Person?
    let achievements: Int
    let topAchievement: Badge?
    let reactions: Int
    let topReaction: ReactionKind?
    let comments: Int

    enum CodingKeys: String, CodingKey {
        case year, nights, record, challenges, souls, victim, nemesis, achievements, reactions, comments
        case totalSleepMin = "total_sleep_min", deepMin = "deep_min", avgScore = "avg_score", avgOnset = "avg_onset"
        case bestNight = "best_night", bestMonth = "best_month", bestStreak = "best_streak", topTags = "top_tags"
        case topAchievement = "top_achievement", topReaction = "top_reaction"
    }
}

enum WrappedWindow {
    /// Prosinec = letošní rok, leden = uplynulý. Jinak nil (Wrapped se nenabízí).
    static var year: Int? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugWrapped") {
            return Calendar.iso.component(.year, from: .now)
        }
        #endif
        let c = Calendar.iso.dateComponents([.year, .month], from: .now)
        switch c.month {
        case 12: return c.year
        case 1: return c.year.map { $0 - 1 }
        default: return nil
        }
    }
}
