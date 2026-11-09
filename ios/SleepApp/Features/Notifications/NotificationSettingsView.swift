import SwiftUI
import UIKit
import UserNotifications

/// Nastavení → Notifikace: přepínače kategorií, noční klid, stav povolení v iOS.
/// Platí jen pro pushe – zvoneček ukazuje vše.
struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var prefs: NotificationPrefs?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var system: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                systemSection
                if let prefs {
                    section("Posílat") {
                        ForEach(NotificationPrefs.categories, id: \.key) { c in
                            row(c.title, c.detail, key: c.key, prefs: prefs)
                        }
                    }
                    section("Noční klid") {
                        row("22:00–8:00", "Pushe počkají do rána. Podle časového pásma v profilu.",
                            key: NotificationPrefs.quietHours, prefs: prefs)
                    }
                    if let saveError { Text(saveError).captionStyle() }
                    Text("Platí pro pushe. Ve zvonečku uvidíš všechno.").captionStyle()
                } else if let loadError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loadError).captionStyle()
                        Button("Zkusit znovu") { Task { await load() } }.buttonStyle(.secondary)
                    }
                } else {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius)
                        .fill(Color.app.surface)
                        .frame(height: 320)
                }
            }
            .padding(Metrics.screenPadding)
        }
        .background(Color.app.bg)
        .navigationTitle("Notifikace")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await refreshSystem() }
        .onChange(of: scenePhase) { _, phase in
            // návrat z Nastavení iOS
            if phase == .active { Task { await refreshSystem() } }
        }
    }

    // MARK: Povolení v iOS

    @ViewBuilder
    private var systemSection: some View {
        switch system {
        case .denied:
            VStack(alignment: .leading, spacing: 12) {
                Text("Notifikace má iPhone pro appku vypnuté. Nic z tohohle nepřijde, dokud je nezapneš.")
                    .captionStyle()
                Button("Otevřít Nastavení", action: openSystemSettings).buttonStyle(.secondary)
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 12) {
                Text("Notifikace zatím nejsou povolené.").captionStyle()
                Button("Povolit notifikace") { Task { await requestPermission() } }.buttonStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func refreshSystem() async {
        system = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await Push.shared.start()
        await refreshSystem()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Přepínače

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).statLabel().padding(.bottom, 4)
            content()
        }
    }

    private func row(_ title: String, _ detail: String, key: String, prefs: NotificationPrefs) -> some View {
        Toggle(isOn: Binding(get: { prefs[key] }, set: { set(key, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Font.app.body).foregroundStyle(Color.app.textPrimary)
                Text(detail).captionStyle().fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.app.accent)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.app.hairline).frame(height: 1) }
    }

    private func load() async {
        do {
            prefs = try await API.notificationPrefs()
            loadError = nil
        } catch {
            loadError = "Nastavení se nenačetlo."
        }
    }

    /// Hned přepne (optimisticky), při chybě vrátí zpět.
    private func set(_ key: String, _ on: Bool) {
        guard var next = prefs else { return }
        let before = next
        next[key] = on
        prefs = next
        saveError = nil
        Task {
            do {
                prefs = try await API.setNotificationPrefs([key: on])
            } catch {
                prefs = before
                saveError = "Neuložilo se. Zkus to znovu."
            }
        }
    }
}
