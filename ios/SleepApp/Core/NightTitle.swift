import Foundation

/// Automatický název karty, když si ho autor nenapíše (#15). Jen pro zobrazení, do DB se neukládá –
/// karta se publikuje vždycky a autor ho kdykoliv přepíše vlastním.
/// Výběr podle noci, varianta deterministicky podle id karty (ať se název mezi spuštěními nemění).
/// Texty bez rodu (nevíme, jestli spal, nebo spala).
enum NightTitle {
    static func template(for night: Night, postID: UUID, timezone: String?) -> String {
        let pool: [String]
        let tz = timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Prague")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let bedHour = cal.component(.hour, from: night.sleepStart)
        let total = night.totalSleepMin
        let deepShare = total > 0 ? Double(night.deepMin) / Double(total) : 0
        let score = night.score ?? 0

        if score >= 92 {
            pool = ["Dokonalá noc", "Tohle se povedlo", "Noc jak z katalogu"]
        } else if total < 300 {
            pool = ["Krátká noc", "Na půl plynu", "Dneska jede kafe"]
        } else if total > 570 {
            pool = ["Zimní spánek", "Ještě pět minut", "Peřina vyhrála"]
        } else if (1...5).contains(bedHour) {
            pool = ["Dlouhý večer", "Do postele až po půlnoci", "Pozdní příchod"]
        } else if night.wakeCount >= 5 || night.awakeMin >= 45 {
            pool = ["Noc na etapy", "Rozházená noc", "S přestávkami"]
        } else if deepShare >= 0.22 {
            pool = ["Hluboko pod hladinou", "Ponor do hloubky", "Deep na maximum"]
        } else if score > 0 && score < 55 {
            pool = ["Nic moc", "Zítra líp", "Na tuhle se zapomene"]
        } else {
            pool = ["Solidní noc", "Noc jako noc", "Bez dramatu"]
        }
        let seed = withUnsafeBytes(of: postID.uuid) { $0.reduce(0) { $0 &+ Int($1) } }
        return pool[seed % pool.count]
    }
}

extension FeedPost {
    /// Název na kartě: vlastní, jinak automatický.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return NightTitle.template(for: night, postID: id, timezone: author.timezone)
    }
}
