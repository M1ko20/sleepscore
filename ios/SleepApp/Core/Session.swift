import Foundation
import Observation
import Supabase

/// Stav přihlášení a vlastního profilu.
@MainActor
@Observable
final class Session {
    enum State: Equatable {
        case loading
        case signedOut
        /// Přihlášen, ale bez profilu (ještě neuplatnil pozvánku).
        case needsProfile(userID: UUID)
        case ready(Profile)
    }

    private(set) var state: State = .loading
    private var listenTask: Task<Void, Never>?

    func start() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await (event, session) in Backend.client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .signedOut, .userDeleted:
                    await self.update(for: session)
                default:
                    break
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Backend.client.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        try? await Backend.client.auth.signOut()
    }

    func reloadProfile() async {
        let session = try? await Backend.client.auth.session
        await update(for: session)
    }

    private func update(for session: Supabase.Session?) async {
        guard let session, !session.isExpired else {
            state = .signedOut
            return
        }
        let userID = session.user.id
        do {
            let data = try await Self.fetchProfileData(userID: userID)
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            state = profiles.first.map(State.ready) ?? .needsProfile(userID: userID)
        } catch {
            // Bez sítě nechceme uživatele odhlásit – zkusí se znovu při dalším spuštění.
            state = .needsProfile(userID: userID)
        }
    }

    /// Mimo MainActor – PostgrestResponse není Sendable.
    nonisolated private static func fetchProfileData(userID: UUID) async throws -> Data {
        try await Backend.client
            .from("profiles")
            .select("id, username, display_name, avatar_path, timezone, invites_available")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .data
    }
}
