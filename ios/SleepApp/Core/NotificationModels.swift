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
        case "friend_request", "friend_accepted": "person"   // smazaný účet (actor = null)
        default: "flag.2.crossed"
        }
    }
}

/// Odkaz na výzvu v navigaci feedu (UUID už vede na detail karty).
struct ChallengeLink: Hashable {
    let id: UUID
}

/// Nastavení pushů (#11): přepínače po kategoriích (= `notifications.category`) a noční klid.
/// Zvoneček ukazuje vše bez ohledu na nastavení.
struct NotificationPrefs: Decodable, Equatable, Sendable {
    /// Klíče v DB; neznámé nebo chybějící = zapnuto.
    var values: [String: Bool]

    init(values: [String: Bool] = [:]) { self.values = values }

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: Bool].self)
    }

    subscript(key: String) -> Bool {
        get { values[key] ?? true }
        set { values[key] = newValue }
    }

    static let quietHours = "quiet_hours"

    /// Přepínače kategorií v pořadí na obrazovce.
    static let categories: [(key: String, title: String, detail: String)] = [
        ("reactions", "Reakce", "Kdo reaguje na tvoji noc."),
        ("comments", "Komentáře", "U tvých karet a tam, kde píšeš."),
        ("friends", "Přátelé", "Žádosti a nově přijatí."),
        ("challenges", "Výzvy", "Pozvánky, start, předbíhání, konec, výsledky, splacení."),
        ("achievements", "Odznaky", "Nový odznak."),
        ("morning", "Ranní karta", "Noc je tady. Doplň komentář."),
        ("recap", "Týdenní recap", "Pondělí ráno, minulý týden v číslech."),
    ]
}
