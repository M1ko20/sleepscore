import Foundation

enum Fmt {
    /// 462 → „7 h 42“
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }

    static func time(_ date: Date, in tz: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = tz
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }

    /// Hlavička karty: dnes → čas, včera → „včera“, jinak „5. 11.“
    static func postStamp(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time(date) }
        if cal.isDateInYesterday(date) { return "včera" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = cal.isDate(date, equalTo: now, toGranularity: .year) ? "d. M." : "d. M. yyyy"
        return f.string(from: date)
    }

    /// night_date „2026-11-06“ → „čtvrtek 6. 11.“
    static func nightDate(_ iso: String) -> String {
        let p = DateFormatter()
        p.dateFormat = "yyyy-MM-dd"
        p.timeZone = .current
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEE d. M."
        return f.string(from: d)
    }
}
