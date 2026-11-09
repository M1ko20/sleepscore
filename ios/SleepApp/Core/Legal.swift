import Foundation

/// Odkazy na zásady a podmínky (web v `site/`, GitHub Pages). Česky, jinak anglicky.
enum Legal {
    private static let base = "https://m1ko20.github.io/sleepscore/"
    private static var prefix: String {
        Locale.current.language.languageCode?.identifier == "cs" ? "" : "en/"
    }
    static var privacyURL: URL { URL(string: base + prefix + "privacy.html")! }
    static var termsURL: URL { URL(string: base + prefix + "terms.html")! }

    /// „Pokračováním souhlasíš s Podmínkami a Zásadami…“ s klikacími odkazy (markdown pro `Text`).
    static var consentMarkdown: String {
        "Pokračováním souhlasíš s [Podmínkami](\(termsURL)) a [Zásadami ochrany soukromí](\(privacyURL)). Nevhodný obsah ani obtěžování netolerujeme."
    }
}

/// Stav souhlasu s aktuální verzí podmínek (`my_terms_status`, `accept_terms`).
struct TermsStatus: Decodable, Sendable {
    let version: String
    let accepted: Bool
}
