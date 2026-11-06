import Foundation
import Supabase

/// Jediný klient Supabase. URL a publishable klíč jdou z Info.plist (← Config/Secrets.xcconfig).
enum Backend {
    static let client: SupabaseClient = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String, let url = URL(string: urlString),
              let key = info["SupabaseKey"] as? String, !key.isEmpty, !urlString.contains("$(")
        else {
            fatalError("Chybí SUPABASE_URL / SUPABASE_KEY – zkopíruj ios/Config/Secrets.example.xcconfig na Secrets.xcconfig.")
        }
        // Ephemeral: nepamatuje si Alt-Svc → nezkouší HTTP/3. QUIC přes UDP v simulátoru (VPN na Macu)
        // padal s "Network is down" a požadavek visel do timeoutu. Session SDK drží v Keychainu, ne tady.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return SupabaseClient(
            supabaseURL: url, supabaseKey: key,
            options: SupabaseClientOptions(
                // Uloženou session vydat hned (i prošlou) – obnova tokenu nesmí blokovat start appky.
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: config))
            )
        )
    }()
}
