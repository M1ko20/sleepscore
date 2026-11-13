import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Kam vede klepnutí na push (`link` v payloadu z `claim_push_batch`).
enum PushLink: Equatable {
    case post(UUID)
    case challenge(UUID)
    case profile(ProfileLite)
    case recap(weekStart: String)
    case notifications

    init?(userInfo: [AnyHashable: Any]) {
        guard let link = userInfo["link"] as? [String: Any], let t = link["t"] as? String else { return nil }
        switch t {
        case "post":
            guard let id = (link["id"] as? String).flatMap(UUID.init) else { return nil }
            self = .post(id)
        case "challenge":
            guard let id = (link["id"] as? String).flatMap(UUID.init) else { return nil }
            self = .challenge(id)
        case "profile":
            guard let obj = link["profile"],
                  let data = try? JSONSerialization.data(withJSONObject: obj),
                  let p = try? JSONDecoder().decode(ProfileLite.self, from: data) else { return nil }
            self = .profile(p)
        case "recap":
            guard let w = link["week_start"] as? String else { return nil }
            self = .recap(weekStart: w)
        default:
            self = .notifications
        }
    }
}

/// Push notifikace (#10): povolení, device token na server, proklik, badge.
/// Odesílá server (pg_cron → Edge Function `send-push` → APNs).
@MainActor @Observable
final class Push {
    static let shared = Push()

    /// Proklik čekající na zpracování (feed ho otevře a vynuluje).
    var pendingLink: PushLink?

    private let registeredKey = "pushTokenRegistered"   // "<user>|<token>" – ať se při každém startu nevolá server
    private var token: String?

    /// Debug build = vývojový APNs (sandbox), TestFlight / App Store = produkční.
    private var apnsEnv: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Systémové povolení (nil = ještě nezjištěno). Feed podle něj ukáže kartu s nabídkou.
    private(set) var status: UNAuthorizationStatus?
    /// „Teď ne“ na kartě ve feedu – už ji neukazovat (v Nastavení → Notifikace jde povolit kdykoliv).
    private let askDismissedKey = "pushAskDismissed"
    var askDismissed: Bool {
        get { access(keyPath: \.askDismissed); return UserDefaults.standard.bool(forKey: askDismissedKey) }
        set { withMutation(keyPath: \.askDismissed) { UserDefaults.standard.set(newValue, forKey: askDismissedKey) } }
    }

    /// Ukázat ve feedu nabídku notifikací? Až v kontextu (je co sledovat), ne hned po startu – Apple 4.5.4 / HIG.
    var shouldOfferPermission: Bool {
        status == .notDetermined && !askDismissed && !Self.skipPrompt
    }

    /// Po vstupu do appky a při návratu do popředí: zjistí stav a když je povoleno, registruje u APNs.
    /// Na povolení se sám neptá – to dělá až `requestPermission()` z karty ve feedu nebo z Nastavení.
    func start() async {
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        status = s
        if s == .authorized || s == .provisional || s == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Systémový dialog (iOS ho ukáže jen jednou, pak jen Nastavení iOS).
    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await start()
    }

    /// Z AppDelegate. Bez Apple Developer Programu (simulátor bez týmu) sem nic nepřijde.
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        Task {
            guard let user = try? await Backend.client.auth.session.user.id else { return }
            let key = "\(user.uuidString)|\(hex)|\(apnsEnv)"
            if UserDefaults.standard.string(forKey: registeredKey) == key { return }
            do {
                try await API.registerPushToken(hex, env: apnsEnv)
                UserDefaults.standard.set(key, forKey: registeredKey)
            } catch {
                log.error("push token register failed: \(String(describing: error))")
            }
        }
    }

    /// Odhlášení: token pryč ze serveru (jinak by pushe chodily dál), dokud je session platná.
    func unregister() async {
        UserDefaults.standard.removeObject(forKey: registeredKey)
        setBadge(0)
        guard let token else { return }
        try? await API.unregisterPushToken(token)
        UIApplication.shared.unregisterForRemoteNotifications()
        self.token = nil
    }

    func setBadge(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
    }

    private static var skipPrompt: Bool {
        #if DEBUG
        // UI testy: systémový dialog by zakryl appku.
        return ProcessInfo.processInfo.arguments.contains("-debugNoPushPrompt")
        #else
        return false
        #endif
    }
}

/// Callbacky UIKit: device token a klepnutí na notifikaci.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // HealthKit background delivery: observer hned při startu (i na pozadí), ne až s UI.
        MainActor.assumeIsolated {
            if HealthSync.shouldResumeObserving { HealthSync.shared.startObserving() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { Push.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("APNs register failed: \(String(describing: error))")
    }

    /// Push při otevřené appce: ukázat banner (zvoneček se obnoví s feedem).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let link = PushLink(userInfo: response.notification.request.content.userInfo) ?? .notifications
        await MainActor.run { Push.shared.pendingLink = link }
    }
}
