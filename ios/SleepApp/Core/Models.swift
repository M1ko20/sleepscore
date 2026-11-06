import Foundation

struct Profile: Codable, Identifiable, Equatable, Sendable {
    static let columns = "id, username, display_name, avatar_path, timezone, invites_available, invited_by"

    let id: UUID
    var username: String
    var displayName: String
    var avatarPath: String?
    var timezone: String
    var invitesAvailable: Int
    var invitedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, username, timezone
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case invitesAvailable = "invites_available"
        case invitedBy = "invited_by"
    }
}

struct Invite: Codable, Identifiable, Sendable {
    let code: String
    let createdAt: Date
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code
        case createdAt = "created_at"
    }
}

enum InviteCode {
    static let length = 8
    /// Stejná abeceda jako create_invite (bez 0/O, 1/I/L).
    static let alphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func sanitize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }
}
