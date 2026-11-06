import Foundation

struct Profile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarPath: String?
    var timezone: String
    var invitesAvailable: Int

    enum CodingKeys: String, CodingKey {
        case id, username, timezone
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case invitesAvailable = "invites_available"
    }
}
