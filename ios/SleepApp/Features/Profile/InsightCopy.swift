import Foundation

/// Z čísel `TagInsight` složí jednu suchou větu: „S alkoholem máš o 17 % méně deep a usínáš o 32 minut později.“
/// Bere nejvýš dva nejsilnější rozdíly nad prahem; když žádný není, insight se neukáže.
enum InsightCopy {
    /// Prahy: rozdíl menší než tohle je šum (málo nocí, malé efekty).
    private static let deepMin = 0.10, onsetMin = 15.0, sleepMin = 20.0, scoreMin = 3.0

    static func sentence(_ i: TagInsight) -> String? {
        var parts: [(strength: Double, text: String)] = []

        if let w = i.deepWith?.value, let wo = i.deepWithout?.value, wo > 0 {
            let rel = w / wo - 1
            if abs(rel) >= deepMin {
                parts.append((abs(rel) / deepMin, "máš o \(Int((abs(rel) * 100).rounded()))\u{00A0}% \(rel < 0 ? "méně" : "víc") deep"))
            }
        }
        if let w = i.onsetWith?.value, let wo = i.onsetWithout?.value {
            let d = w - wo
            if abs(d) >= onsetMin {
                parts.append((abs(d) / onsetMin, "usínáš o \(minutes(abs(d))) \(d > 0 ? "později" : "dřív")"))
            }
        }
        if let w = i.sleepWith?.value, let wo = i.sleepWithout?.value {
            let d = w - wo
            if abs(d) >= sleepMin {
                parts.append((abs(d) / sleepMin, "spíš o \(minutes(abs(d))) \(d < 0 ? "míň" : "déle")"))
            }
        }
        if let w = i.scoreWith?.value, let wo = i.scoreWithout?.value {
            let d = w - wo
            if abs(d) >= scoreMin {
                parts.append((abs(d) / scoreMin, "máš skóre o \(points(abs(d))) \(d < 0 ? "nižší" : "vyšší")"))
            }
        }
        let top = parts.sorted { $0.strength > $1.strength }.prefix(2).map(\.text)
        guard !top.isEmpty else { return nil }
        return "\(prefix(i)) \(top.joined(separator: " a "))."
    }

    /// Síla nejsilnějšího rozdílu – na řazení zjištění.
    static func strength(_ i: TagInsight) -> Double {
        var best = 0.0
        if let w = i.deepWith?.value, let wo = i.deepWithout?.value, wo > 0 { best = max(best, abs(w / wo - 1) / deepMin) }
        if let w = i.onsetWith?.value, let wo = i.onsetWithout?.value { best = max(best, abs(w - wo) / onsetMin) }
        if let w = i.sleepWith?.value, let wo = i.sleepWithout?.value { best = max(best, abs(w - wo) / sleepMin) }
        if let w = i.scoreWith?.value, let wo = i.scoreWithout?.value { best = max(best, abs(w - wo) / scoreMin) }
        return best
    }

    private static func prefix(_ i: TagInsight) -> String {
        switch i.tag {
        case "alcohol": "S alkoholem"
        case "sick": "V nemoci"
        case "phone_in_bed": "S telefonem v posteli"
        case "studying": "Po učení"
        case "workout": "Po tréninku"
        case "no_phone": "Bez telefonu"
        case "reading": "Když před spaním čteš,"
        case "sauna": "Po sauně"
        default: "S tagem \(i.label)"
        }
    }

    private static func minutes(_ m: Double) -> String {
        let n = Int(m.rounded())
        if n >= 60 { return Fmt.duration(minutes: n) }
        return "\(n) min"
    }

    private static func points(_ p: Double) -> String {
        let n = Int(p.rounded())
        switch n {
        case 1: return "1 bod"
        case 2...4: return "\(n) body"
        default: return "\(n) bodů"
        }
    }
}
