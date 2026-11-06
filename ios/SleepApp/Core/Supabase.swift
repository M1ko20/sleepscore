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
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
