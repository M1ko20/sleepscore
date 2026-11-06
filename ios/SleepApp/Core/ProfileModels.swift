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

    let profile: ProfileLite
    let mma: Record
    let streak: Streak?
    let avg30: Average?
    let souls: [Soul]
    let achievements: [Badge]
    let h2h: Record?
    let friendship: Friendship?

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
