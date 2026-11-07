import Foundation

/// Řádek ze `notifications`. Text skládá databáze (`notification_text`) – stejný pro zvoneček i push.
struct AppNotification: Decodable, Identifiable, Sendable {
    static let select = "id,kind,created_at,read_at,post_id,challenge_id,payload,"
        + "text:notification_text,"
        + "actor:profiles!notifications_actor_id_fkey(id,username,display_name,avatar_path,timezone)"

    struct Payload: Decodable, Sendable {
        let weekStart: String?
        enum CodingKeys: String, CodingKey { case weekStart = "week_start" }
    }

    let id: UUID
    let kind: String
    let createdAt: Date
    let readAt: Date?
    let postID: UUID?
    let challengeID: UUID?
    let payload: Payload?
    let text: String
    let actor: ProfileLite?

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, text, actor
        case createdAt = "created_at"
        case readAt = "read_at"
        case postID = "post_id"
        case challengeID = "challenge_id"
    }

    enum Target {
        case post(UUID)
        case challenge(UUID)
        case profile(ProfileLite)
        case recap(weekStart: String)
        case none
    }

    /// Kam vede klepnutí.
    var target: Target {
        switch kind {
        case "weekly_recap":
            if let w = payload?.weekStart { return .recap(weekStart: w) }
        case "friend_request", "friend_accepted":
            if let actor { return .profile(actor) }
        default:
            if let postID { return .post(postID) }
            if let challengeID { return .challenge(challengeID) }
            if let actor { return .profile(actor) }
        }
        return .none
    }

    /// Glyf pro notifikace bez člověka (appka sama).
    var systemImage: String {
        switch kind {
        case "night_ready": "moon.zzz"
        case "achievement": "hexagon"
        case "weekly_recap": "chart.bar"
        default: "flag.2.crossed"
        }
    }
}

/// Odkaz na výzvu v navigaci feedu (UUID už vede na detail karty).
struct ChallengeLink: Hashable {
    let id: UUID
}
