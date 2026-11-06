import Foundation
import Supabase

/// Volání RPC a dotazy. Vše nonisolated – odpovědi Supabase SDK nejsou Sendable.
enum API {
    private static var db: SupabaseClient { Backend.client }

    // MARK: Onboarding a pozvánky

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

    // MARK: Feed

    /// Karty nocí (RLS vrátí jen moje a přátel). Výsledky výzev přijdou s výzvami.
    nonisolated static func feed(limit: Int = 30, before: Date? = nil) async throws -> [FeedPost] {
        var q = db.from("posts").select(FeedPost.select).eq("kind", value: "night")
        if let before { q = q.lt("created_at", value: before.ISO8601Format()) }
        return try await decode(q.order("created_at", ascending: false).limit(limit).execute().data)
    }

    nonisolated static func post(id: UUID) async throws -> FeedPost? {
        let list: [FeedPost] = try await decode(db.from("posts").select(FeedPost.select)
            .eq("id", value: id).limit(1).execute().data)
        return list.first
    }

    nonisolated static func tags() async throws -> [Tag] {
        try await decode(db.from("tags").select("slug,label").order("sort").execute().data)
    }

    nonisolated static func achievements() async throws -> [AchievementInfo] {
        try await decode(db.from("achievements").select("code,name,description").order("sort").execute().data)
    }

    nonisolated static func stats(userIDs: [UUID]) async throws -> [UserStats] {
        guard !userIDs.isEmpty else { return [] }
        return try await decode(db.from("user_stats").select("user_id,current_streak,best_streak")
            .in("user_id", values: userIDs.map(\.uuidString)).execute().data)
    }

    nonisolated static func heartRate(nightID: UUID) async throws -> [HeartRatePoint] {
        struct Row: Decodable { let heart_rate: [HeartRatePoint]? }
        let rows: [Row] = try await decode(db.from("night_raw").select("heart_rate")
            .eq("night_id", value: nightID).limit(1).execute().data)
        return rows.first?.heart_rate ?? []
    }

    // MARK: Reakce a komentáře

    /// nil = smazat moji reakci.
    nonisolated static func setReaction(postID: UUID, userID: UUID, kind: ReactionKind?) async throws {
        if let kind {
            struct Row: Encodable { let post_id: UUID; let user_id: UUID; let kind: String }
            _ = try await db.from("reactions")
                .upsert(Row(post_id: postID, user_id: userID, kind: kind.rawValue), onConflict: "post_id,user_id")
                .execute().data
        } else {
            _ = try await db.from("reactions").delete()
                .eq("post_id", value: postID).eq("user_id", value: userID).execute().data
        }
    }

    nonisolated static func comments(postID: UUID) async throws -> [Comment] {
        try await decode(db.from("comments").select(Comment.select)
            .eq("post_id", value: postID).order("created_at").execute().data)
    }

    nonisolated static func addComment(postID: UUID, userID: UUID, body: String) async throws -> Comment {
        struct Row: Encodable { let post_id: UUID; let user_id: UUID; let body: String }
        return try await decode(db.from("comments")
            .insert(Row(post_id: postID, user_id: userID, body: body), returning: .representation)
            .select(Comment.select).single().execute().data)
    }

    nonisolated static func deleteComment(id: UUID) async throws {
        _ = try await db.from("comments").delete().eq("id", value: id).execute().data
    }

    // MARK: Úprava karty

    nonisolated static func updatePost(id: UUID, title: String?, body: String?) async throws {
        struct Row: Encodable { let title: String?; let body: String? }
        _ = try await db.from("posts").update(Row(title: title, body: body)).eq("id", value: id).execute().data
    }

    nonisolated static func setTags(nightID: UUID, add: Set<String>, remove: Set<String>) async throws {
        if !remove.isEmpty {
            _ = try await db.from("night_tags").delete()
                .eq("night_id", value: nightID).in("tag", values: Array(remove)).execute().data
        }
        if !add.isEmpty {
            struct Row: Encodable { let night_id: UUID; let tag: String }
            _ = try await db.from("night_tags")
                .insert(add.map { Row(night_id: nightID, tag: $0) }).execute().data
        }
    }

    // MARK: Dekódování

    nonisolated static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parseTimestamp(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Neznámý formát času: \(s)")
            }
            return date
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Postgres vrací až 6 desetinných míst a „+00:00“, ISO8601DateFormatter zvládne jen 3.
nonisolated func parseTimestamp(_ s: String) -> Date? {
    var text = s
    var fraction = 0.0
    if let dot = text.firstIndex(of: ".") {
        let rest = text[text.index(after: dot)...]
        let digits = rest.prefix { $0.isNumber }
        fraction = Double("0." + digits) ?? 0
        text.removeSubrange(dot..<rest.index(rest.startIndex, offsetBy: digits.count))
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: text).map { $0.addingTimeInterval(fraction) }
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
