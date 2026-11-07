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
        _ = try await db.from("posts").update(NullableRow(["title": title, "body": body])).eq("id", value: id).execute().data
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

    // MARK: Výzvy

    /// Výzvy, kterých se účastním (pozvaný, přijatý). Zrušené a odmítnuté ne.
    nonisolated static func myChallenges(userID: UUID) async throws -> [Challenge] {
        try await decode(db.from("challenges")
            .select(Challenge.select + ",mine:challenge_participants!inner(user_id,status)")
            .eq("mine.user_id", value: userID)
            .neq("mine.status", value: "declined")
            .neq("status", value: "cancelled")
            .order("created_at", ascending: false)
            .execute().data)
    }

    nonisolated static func challenge(id: UUID) async throws -> Challenge? {
        let list: [Challenge] = try await decode(db.from("challenges").select(Challenge.select)
            .eq("id", value: id).limit(1).execute().data)
        return list.first
    }

    nonisolated static func openDebts() async throws -> [Debt] {
        try await decode(db.from("debts").select(Debt.select)
            .is("settled_at", value: nil).order("created_at", ascending: false).execute().data)
    }

    nonisolated static func friends(of userID: UUID) async throws -> [ProfileLite] {
        struct Row: Decodable { let a: ProfileLite; let b: ProfileLite }
        let rows: [Row] = try await decode(db.from("friendships")
            .select("a:profiles!friendships_user_a_fkey(id,username,display_name,avatar_path,timezone),b:profiles!friendships_user_b_fkey(id,username,display_name,avatar_path,timezone)")
            .eq("status", value: "accepted")
            .execute().data)
        return rows.map { $0.a.id == userID ? $0.b : $0.a }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    nonisolated static func createChallenge(type: ChallengeType, opponents: [UUID], days: Int,
                                            stake: String?, target: Int?) async throws -> UUID {
        struct Params: Encodable {
            let p_type: String
            let p_opponents: [UUID]
            let p_duration_days: Int
            let p_stake: String?
            let p_target_score: Int?
        }
        return try await decode(db.rpc("create_challenge", params: Params(
            p_type: type.rawValue, p_opponents: opponents, p_duration_days: days,
            p_stake: stake, p_target_score: target
        )).execute().data)
    }

    nonisolated static func respondChallenge(_ id: UUID, accept: Bool) async throws {
        struct Params: Encodable { let p_challenge: UUID; let p_accept: Bool }
        _ = try await db.rpc("respond_challenge", params: Params(p_challenge: id, p_accept: accept)).execute().data
    }

    nonisolated static func startChallenge(_ id: UUID) async throws {
        _ = try await db.rpc("start_challenge", params: ["p_challenge": id]).execute().data
    }

    nonisolated static func cancelChallenge(_ id: UUID) async throws {
        _ = try await db.rpc("cancel_challenge", params: ["p_challenge": id]).execute().data
    }

    nonisolated static func settleDebt(_ id: UUID) async throws {
        _ = try await db.rpc("settle_debt", params: ["p_debt": id]).execute().data
    }

    /// Karty výsledků výzev do feedu.
    nonisolated static func challengeResultPosts(limit: Int = 20) async throws -> [ChallengeResultPost] {
        try await decode(db.from("posts")
            .select("id,created_at,challenge:challenges(\(Challenge.select))")
            .eq("kind", value: "challenge_result")
            .order("created_at", ascending: false).limit(limit)
            .execute().data)
    }

    // MARK: Profil a přátelé

    nonisolated static func profileSummary(_ userID: UUID) async throws -> ProfileSummary {
        try await decode(db.rpc("profile_summary", params: ["p_user": userID]).execute().data)
    }

    /// Všechna moje přátelství včetně čekajících žádostí (RLS vrací jen moje řádky).
    nonisolated static func friendships(me: UUID) async throws -> [FriendshipEntry] {
        struct Row: Decodable {
            let status: FriendshipStatus
            let requested_by: UUID
            let a: ProfileLite
            let b: ProfileLite
        }
        let rows: [Row] = try await decode(db.from("friendships")
            .select("status,requested_by,a:profiles!friendships_user_a_fkey(id,username,display_name,avatar_path,timezone),b:profiles!friendships_user_b_fkey(id,username,display_name,avatar_path,timezone)")
            .execute().data)
        return rows.map { r in
            FriendshipEntry(other: r.a.id == me ? r.b : r.a, status: r.status, incoming: r.requested_by != me)
        }
        .sorted { $0.other.displayName.localizedCompare($1.other.displayName) == .orderedAscending }
    }

    /// Hledání podle začátku přezdívky (bez mě).
    nonisolated static func searchProfiles(_ query: String, me: UUID) async throws -> [ProfileLite] {
        let q = query.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        guard q.count >= 2 else { return [] }
        return try await decode(db.from("profiles")
            .select("id,username,display_name,avatar_path,timezone")
            .ilike("username", pattern: q.replacingOccurrences(of: "_", with: "\\_") + "%")
            .neq("id", value: me)
            .is("banned_at", value: nil)
            .order("username").limit(20)
            .execute().data)
    }

    nonisolated static func sendFriendRequest(_ user: UUID) async throws {
        try await db.rpc("send_friend_request", params: ["p_user": user]).execute()
    }

    nonisolated static func respondFriendRequest(_ user: UUID, accept: Bool) async throws {
        struct Params: Encodable { let p_user: UUID; let p_accept: Bool }
        try await db.rpc("respond_friend_request", params: Params(p_user: user, p_accept: accept)).execute()
    }

    nonisolated static func removeFriend(_ user: UUID) async throws {
        try await db.rpc("remove_friend", params: ["p_user": user]).execute()
    }

    // MARK: Moderace

    /// Nahlášení obsahu. `block` = rovnou zablokovat autora (jedním callem).
    nonisolated static func report(_ kind: ReportTarget, id: UUID, reason: ReportReason,
                                   note: String?, block: Bool) async throws {
        struct Params: Encodable {
            let p_kind: String
            let p_target: UUID
            let p_reason: String
            let p_note: String?
            let p_block: Bool
        }
        _ = try await db.rpc("report_content", params: Params(
            p_kind: kind.rawValue, p_target: id, p_reason: reason.rawValue, p_note: note, p_block: block
        )).execute().data
    }

    nonisolated static func blockUser(_ user: UUID) async throws {
        try await db.rpc("block_user", params: ["p_user": user]).execute()
    }

    nonisolated static func unblockUser(_ user: UUID) async throws {
        try await db.rpc("unblock_user", params: ["p_user": user]).execute()
    }

    /// Koho jsem zablokoval (RLS vrací jen moje bloky).
    nonisolated static func blockedUsers() async throws -> [ProfileLite] {
        struct Row: Decodable { let blocked: ProfileLite }
        let rows: [Row] = try await decode(db.from("blocks")
            .select("blocked:profiles!blocks_blocked_id_fkey(id,username,display_name,avatar_path,timezone)")
            .order("created_at", ascending: false)
            .execute().data)
        return rows.map(\.blocked)
    }

    nonisolated static func updateDisplayName(_ name: String, me: UUID) async throws {
        try await db.from("profiles").update(["display_name": name]).eq("id", value: me).execute()
    }

    /// nil = minulý celý týden (po–ne).
    nonisolated static func weeklyRecap(weekStart: String? = nil) async throws -> WeeklyRecap {
        struct Params: Encodable { let p_week_start: String? }
        if let weekStart {
            return try await decode(db.rpc("weekly_recap", params: Params(p_week_start: weekStart)).execute().data)
        }
        return try await decode(db.rpc("weekly_recap").execute().data)
    }

    /// nil = v lednu uplynulý rok, jinak letošní.
    nonisolated static func sleepWrapped(year: Int? = nil) async throws -> SleepWrapped {
        struct Params: Encodable { let p_year: Int }
        if let year { return try await decode(db.rpc("sleep_wrapped", params: Params(p_year: year)).execute().data) }
        return try await decode(db.rpc("sleep_wrapped").execute().data)
    }

    // MARK: Notifikace

    /// Zvoneček: posledních 50 (starší než 30 dní maže pg_cron).
    nonisolated static func notifications(limit: Int = 50) async throws -> [AppNotification] {
        try await decode(db.from("notifications").select(AppNotification.select)
            .order("created_at", ascending: false).limit(limit).execute().data)
    }

    /// Počet nepřečtených – jen hlavička s počtem, bez dat. Volá se s feedem.
    nonisolated static func unreadNotificationCount() async throws -> Int {
        try await db.from("notifications").select("id", head: true, count: .exact)
            .is("read_at", value: nil).execute().count ?? 0
    }

    nonisolated static func markNotificationsRead() async throws {
        _ = try await db.rpc("mark_notifications_read").execute().data
    }

    /// Nastavení pushů (úplné, s výchozími hodnotami).
    nonisolated static func notificationPrefs() async throws -> NotificationPrefs {
        try await decode(db.rpc("my_notification_prefs").execute().data)
    }

    /// Uloží změněné klíče (`{"reactions": false}`), vrací úplné nastavení.
    nonisolated static func setNotificationPrefs(_ changes: [String: Bool]) async throws -> NotificationPrefs {
        struct Params: Encodable { let p_prefs: [String: Bool] }
        return try await decode(db.rpc("set_notification_prefs", params: Params(p_prefs: changes)).execute().data)
    }

    // MARK: GDPR

    /// Všechna moje data jako JSON (export_my_data).
    nonisolated static func exportMyData() async throws -> Data {
        try await db.rpc("export_my_data").execute().data
    }

    /// Smaže moje soubory ve Storage (přímo v SQL to Supabase nedovolí) a pak účet i data.
    nonisolated static func deleteMyAccount(me: UUID) async throws {
        let folder = me.uuidString.lowercased()
        for bucket in [Bucket.avatars, .nightPhotos] {
            let store = db.storage.from(bucket.rawValue)
            while true {
                let files = try await store.list(path: folder, options: SearchOptions(limit: 100))
                let paths = files.map { "\(folder)/\($0.name)" }
                if paths.isEmpty { break }
                _ = try await store.remove(paths: paths)
                if files.count < 100 { break }
            }
        }
        // Účet přes Apple: Edge Function nejdřív zneplatní Apple token (App Review 5.1.1(v)),
        // pak zavolá delete_my_account. Ostatní účty (e-mail v dev buildu) rovnou RPC – o call míň.
        if isAppleAccount {
            try await db.functions.invoke("delete-account", options: FunctionInvokeOptions(method: .post))
        } else {
            try await db.rpc("delete_my_account").execute()
        }
    }

    /// Přihlášen přes Sign in with Apple (z lokální session, bez callu).
    nonisolated static var isAppleAccount: Bool {
        guard let user = db.auth.currentUser else { return false }
        if user.identities?.contains(where: { $0.provider == "apple" }) == true { return true }
        return user.appMetadata["provider"]?.stringValue == "apple"
    }

    /// Po přihlášení přes Apple: pošle jednorázový authorization code serveru, ten ho vymění
    /// za refresh token a uloží (kvůli zneplatnění při smazání účtu). Chyba nevadí – nic nebrání.
    nonisolated static func storeAppleAuthorizationCode(_ code: String) async {
        do {
            try await db.functions.invoke(
                "apple-token", options: FunctionInvokeOptions(body: ["authorization_code": code]))
        } catch {
            log.error("apple-token failed: \(String(describing: error))")
        }
    }

    // MARK: Fotky

    /// Nahraje JPEG pod `<me>/<uuid>.jpg` (cesta je unikátní → cache podle cesty je navždy platná).
    nonisolated static func uploadImage(_ data: Data, bucket: Bucket, me: UUID) async throws -> String {
        let path = "\(me.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await db.storage.from(bucket.rawValue).upload(
            path, data: data, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false))
        return path
    }

    nonisolated static func removeImage(_ path: String, bucket: Bucket) async {
        do { _ = try await db.storage.from(bucket.rawValue).remove(paths: [path]) }
        catch { log.error("remove image failed: \(String(describing: error))") }
    }

    nonisolated static func setAvatarPath(_ path: String?, me: UUID) async throws {
        try await db.from("profiles").update(NullableRow(["avatar_path": path])).eq("id", value: me).execute()
    }

    nonisolated static func setPostPhoto(_ path: String?, postID: UUID) async throws {
        try await db.from("posts").update(NullableRow(["photo_path": path])).eq("id", value: postID).execute()
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
    case let t where t.contains("need at least 3 accepted"): return "Potřebuješ aspoň 3 přijaté (včetně tebe)."
    case let t where t.contains("is not a friend"): return "Vyzvat jde jen kamarády."
    case let t where t.contains("group challenge needs"): return "Skupinová výzva potřebuje aspoň 2 pozvané."
    case let t where t.contains("duration_days"): return "Výzva musí mít aspoň 7 dní."
    case let t where t.contains("no pending invitation"): return "Pozvánka už neplatí."
    case let t where t.contains("you blocked this user"): return "Nejdřív zruš blokování."
    case let t where t.contains("too many reports"): return "Na dnešek stačí. Zkus to zítra."
    case let t where t.contains("content not found"): return "Tohle už neexistuje."
    case let t where t.contains("profile hidden pending review"):
        return "Jméno a fotku po nahlášení zatím měnit nejde. Projdeme to do 24 h."
    case let t where t.contains("not allowed"): return "Tohle nejde."
    default: return "Nepovedlo se. \(text)"
    }
}

/// Řádek pro UPDATE, kde nil = SQL null. Synteticky generované Encodable by nil vynechalo
/// → smazaný název nebo odebraná fotka by se na serveru nikdy nevymazaly.
struct NullableRow: Encodable, Sendable {
    let fields: [String: String?]
    init(_ fields: [String: String?]) { self.fields = fields }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (k, v) in fields {
            if let v { try c.encode(v, forKey: Key(stringValue: k)) } else { try c.encodeNil(forKey: Key(stringValue: k)) }
        }
    }
}
