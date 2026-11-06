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

    func entry(_ id: UUID) -> FriendshipEntry? { entries.first { $0.id == id } }

    func load(me: UUID) async {
        do {
            entries = try await API.friendships(me: me)
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
}
