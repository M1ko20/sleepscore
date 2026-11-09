import Foundation

/// Odkazy na zásady a podmínky (web v `site/`, GitHub Pages). Česky, jinak anglicky.
enum Legal {
    private static let base = "https://m1ko20.github.io/sleepscore/"
    private static var prefix: String {
        Locale.current.language.languageCode?.identifier == "cs" ? "" : "en/"
    }
    static var privacyURL: URL { URL(string: base + prefix + "privacy.html")! }
    static var termsURL: URL { URL(string: base + prefix + "terms.html")! }

    /// První zaškrtávátko: věk + podmínky a zásady (markdown s odkazy pro `Text`).
    static var termsConsentMarkdown: String {
        "Je mi 18 let a souhlasím s [Podmínkami](\(termsURL)) a [Zásadami ochrany soukromí](\(privacyURL)). Nevhodný obsah ani obtěžování netolerujeme."
    }

    /// Druhé zaškrtávátko: výslovný souhlas se zdravotními údaji (čl. 9 odst. 2 písm. a GDPR).
    static let healthConsent =
        "Výslovně souhlasím, aby Bedrival zpracovával můj spánek a tep z Apple Health a ukazoval je mým přátelům. Souhlas můžu kdykoliv odvolat."
}

/// Stav souhlasu s aktuální verzí podmínek (`my_terms_status`, `accept_terms`).
struct TermsStatus: Decodable, Sendable {
    let version: String
    let accepted: Bool
}
