import Foundation
import Supabase

/// Volání RPC a dotazy. Vše nonisolated – odpovědi Supabase SDK nejsou Sendable.
enum API {
    private static var db: SupabaseClient { Backend.client }

    nonisolated static func checkInvite(_ code: String) async throws -> Bool {
        try await decode(db.rpc("check_invite", params: ["p_code": code]).execute().data)
    }

    nonisolated static func usernameAvailable(_ username: String) async throws -> Bool {
        try await decode(db.rpc("username_available", params: ["p_username": username]).execute().data)
    }

    nonisolated static func redeemInvite(code: String, username: String, displayName: String) async throws -> Profile {
        try await decode(db.rpc("redeem_invite", params: [
            "p_code": code, "p_username": username, "p_display_name": displayName,
        ]).execute().data)
    }

    nonisolated static func createInvite() async throws -> String {
        try await decode(db.rpc("create_invite").execute().data)
    }

    nonisolated static func myOpenInvites(userID: UUID) async throws -> [Invite] {
        try await decode(db.from("invites")
            .select("code, created_at")
            .eq("inviter_id", value: userID)
            .is("redeemed_by", value: nil)
            .order("created_at", ascending: false)
            .execute().data)
    }

    nonisolated static func profile(id: UUID) async throws -> Profile? {
        let list: [Profile] = try await decode(db.from("profiles")
            .select(Profile.columns)
            .eq("id", value: id)
            .limit(1)
            .execute().data)
        return list.first
    }

    nonisolated private static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: s)
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Čitelná hláška z chyby serveru (raise exception v RPC).
func serverMessage(_ error: Error) -> String {
    let text = (error as? PostgrestError)?.message ?? error.localizedDescription
    switch text {
    case let t where t.contains("invalid or used invite"): return "Kód neplatí nebo už ho někdo použil."
    case let t where t.contains("profiles_username_key"): return "Přezdívka je zabraná."
    case let t where t.contains("profile already exists"): return "Profil už máš."
    case let t where t.contains("no invites available"): return "Došly ti pozvánky."
    default: return "Nepovedlo se. \(text)"
    }
}
