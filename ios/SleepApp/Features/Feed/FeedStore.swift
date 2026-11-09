import Foundation
import Observation

/// Data feedu sdílená mezi feedem a detailem (reakce a úpravy se propíšou všude).
@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [FeedPost] = []
    private(set) var results: [ChallengeResultPost] = []
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var tagLabels: [String: String] = [:]
    private(set) var tagCatalog: [Tag] = []
    private(set) var achievementNames: [String: String] = [:]
    private(set) var achievementCatalog: [AchievementInfo] = []
    private(set) var streaks: [UUID: Int] = [:]
    /// Recap minulého týdne – jen po–st a dokud ho neskryju (1 call týdně navíc).
    private(set) var recap: WeeklyRecap?
    /// Nepřečtené notifikace (zvoneček). Načítá se s feedem, žádný polling.
    var unreadNotifications = 0
    /// Starší karty otevřené ze zvonečku (nejsou v načteném feedu).
    private var extraPosts: [FeedPost] = []

    func load() async {
        do {
            async let postsReq = API.feed()
            async let resultsReq = API.challengeResultPosts()
            async let unreadReq = API.unreadNotificationCount()
            try await loadCatalogs()
            posts = try await postsReq
            results = (try? await resultsReq) ?? results
            unreadNotifications = (try? await unreadReq) ?? unreadNotifications
            Push.shared.setBadge(unreadNotifications)
            let authors = Array(Set(posts.map(\.author.id)))
            let stats = try await API.stats(userIDs: authors)
            streaks = Dictionary(uniqueKeysWithValues: stats.map { ($0.userID, $0.currentStreak) })
            error = nil
        } catch {
            log.error("feed load failed: \(String(describing: error))")
            self.error = "Feed se nenačetl."
        }
        loaded = true
    }

    /// Číselníky tagů a achievementů (jednou za běh; volá feed i profil).
    func loadCatalogs() async throws {
        guard tagCatalog.isEmpty else { return }
        async let tagsReq = API.tags()
        async let achReq = API.achievements()
        let (tags, ach) = try await (tagsReq, achReq)
        tagCatalog = tags
        tagLabels = Dictionary(uniqueKeysWithValues: tags.map { ($0.slug, $0.label) })
        achievementNames = Dictionary(uniqueKeysWithValues: ach.map { ($0.code, $0.name) })
        achievementCatalog = ach
    }

    private static let dismissedRecapKey = "dismissedRecapWeek"

    /// Pondělí minulého týdne (podle místního času) – klíč recapu.
    private static var lastWeekStart: String {
        let cal = Calendar.iso
        let thisMonday = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return ISODay.string(cal.date(byAdding: .day, value: -7, to: thisMonday) ?? thisMonday)
    }

    func loadRecap() async {
        #if DEBUG
        // `-debugRecap`: karta kdykoliv, za tenhle týden (ať je na screenshotu co ukázat).
        if ProcessInfo.processInfo.arguments.contains("-debugRecap") {
            let weekStart = ISODay.string(Calendar.iso.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now)
            recap = try? await API.weeklyRecap(weekStart: weekStart)
            return
        }
        #endif
        let weekday = Calendar.iso.component(.weekday, from: .now)   // 2 = pondělí … 4 = středa
        guard (2...4).contains(weekday),
              UserDefaults.standard.string(forKey: Self.dismissedRecapKey) != Self.lastWeekStart,
              recap == nil else { return }
        if let r = try? await API.weeklyRecap(), r.nights > 0 { recap = r }
    }

    func dismissRecap() {
        if let r = recap { UserDefaults.standard.set(r.weekStart, forKey: Self.dismissedRecapKey) }
        recap = nil
    }

    func post(_ id: UUID) -> FeedPost? { posts.first { $0.id == id } ?? extraPosts.first { $0.id == id } }

    /// Karta mimo načtený feed (proklik ze zvonečku) – dotáhne ji jedním dotazem.
    func ensurePost(_ id: UUID) async {
        guard post(id) == nil, let p = try? await API.post(id: id) else { return }
        extraPosts.append(p)
    }

    /// Úprava karty ve feedu i mezi staršími kartami.
    private func mutate(_ id: UUID, _ change: (inout FeedPost) -> Void) {
        if let i = posts.firstIndex(where: { $0.id == id }) { change(&posts[i]) }
        if let i = extraPosts.firstIndex(where: { $0.id == id }) { change(&extraPosts[i]) }
    }

    /// Moje dnešní karta nahoru, pak karty nocí a výsledky výzev od nejnovější.
    func items(me: UUID?) -> [FeedItem] {
        var nights = posts
        var head: [FeedItem] = []
        if let me, let i = nights.firstIndex(where: { $0.author.id == me && Calendar.current.isDateInToday($0.createdAt) }) {
            head = [.night(nights.remove(at: i))]
        }
        let rest = (nights.map(FeedItem.night) + results.map(FeedItem.result)).sorted { $0.createdAt > $1.createdAt }
        return head + rest
    }

    var isEmpty: Bool { posts.isEmpty && results.isEmpty }

    /// Série se ukazuje jen na nejnovější kartě autora a od 3 nocí.
    func streakBadge(for post: FeedPost) -> Int? {
        guard let s = streaks[post.author.id], s >= 3,
              posts.first(where: { $0.author.id == post.author.id })?.id == post.id else { return nil }
        return s
    }

    func react(_ postID: UUID, me: UUID, kind: ReactionKind?) async {
        guard let before = post(postID)?.reactions else { return }
        mutate(postID) { p in
            p.reactions.removeAll { $0.userID == me }
            if let kind { p.reactions.append(Reaction(userID: me, kind: kind)) }
        }
        do {
            try await API.setReaction(postID: postID, userID: me, kind: kind)
        } catch {
            mutate(postID) { $0.reactions = before }
        }
    }

    func applyEdit(postID: UUID, title: String?, body: String?, tags: [String], photoPath: String?) {
        mutate(postID) { p in
            p.photoPath = photoPath
            p.title = title
            p.body = body
            p.night.tags = tags
        }
    }

    /// Nahlášená karta zmizí hned (server ji volajícímu už nevrátí).
    func removePost(_ id: UUID) {
        posts.removeAll { $0.id == id }
    }

    /// Po zablokování: karty i reakce blokovaného pryč bez dalšího callu.
    func removeAuthor(_ userID: UUID) {
        posts.removeAll { $0.author.id == userID }
        for i in posts.indices { posts[i].reactions.removeAll { $0.userID == userID } }
    }

    func setCommentCount(postID: UUID, _ count: Int) {
        mutate(postID) { $0.commentCount = count }
    }

    func tagLine(_ tags: [String]) -> String {
        let order = Dictionary(uniqueKeysWithValues: tagCatalog.enumerated().map { ($1.slug, $0) })
        return tags.sorted { (order[$0] ?? 99) < (order[$1] ?? 99) }
            .map { tagLabels[$0] ?? $0 }
            .joined(separator: " · ")
    }
}
