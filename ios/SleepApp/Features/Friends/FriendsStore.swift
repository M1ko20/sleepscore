import Foundation
import Observation

/// Moje přátelství a žádosti (profil, seznam přátel, odznak na záložce).
@MainActor
@Observable
final class FriendsStore {
    private(set) var entries: [FriendshipEntry] = []
    private(set) var loaded = false
    private(set) var error: String?

    var friends: [ProfileLite] { entries.filter { $0.status == .accepted }.map(\.other) }
    var incoming: [ProfileLite] { entries.filter { $0.status == .pending && $0.incoming }.map(\.other) }
    var outgoing: [ProfileLite] { entries.filter { $0.status == .pending && !$0.incoming }.map(\.other) }

    /// Koho jsem zablokoval.
    private(set) var blocked: [ProfileLite] = []

    func entry(_ id: UUID) -> FriendshipEntry? { entries.first { $0.id == id } }
    func isBlocked(_ id: UUID) -> Bool { blocked.contains { $0.id == id } }

    func load(me: UUID) async {
        do {
            async let blockedReq = API.blockedUsers()
            entries = try await API.friendships(me: me)
            blocked = (try? await blockedReq) ?? blocked
            error = nil
        } catch {
            log.error("friends load failed: \(String(describing: error))")
            self.error = "Přátelé se nenačetli."
        }
        loaded = true
    }

    func send(_ user: UUID, me: UUID) async throws {
        try await API.sendFriendRequest(user)
        await load(me: me)
    }

    func respond(_ user: UUID, accept: Bool, me: UUID) async throws {
        try await API.respondFriendRequest(user, accept: accept)
        await load(me: me)
    }

    func remove(_ user: UUID, me: UUID) async throws {
        try await API.removeFriend(user)
        await load(me: me)
    }

    /// Blok zruší i přátelství (server) → znovu načíst.
    func block(_ user: UUID, me: UUID) async throws {
        try await API.blockUser(user)
        await load(me: me)
    }

    func unblock(_ user: UUID, me: UUID) async throws {
        try await API.unblockUser(user)
        await load(me: me)
    }

    /// Po hlášení s blokem (blok udělal server v report_content).
    func markBlocked(_ user: ProfileLite, me: UUID) async {
        if !isBlocked(user.id) { blocked.insert(user, at: 0) }
        await load(me: me)
    }
}
