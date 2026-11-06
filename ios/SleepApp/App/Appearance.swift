import UIKit
import SwiftUI

/// UIKit vzhled tab baru a navigace, aby seděl s tokeny.
enum Appearance {
    static func configure() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.app.bg)
        tab.shadowColor = UIColor(Color.app.hairline)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Color.app.textTertiary)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Color.app.textTertiary)]
        item.selected.iconColor = UIColor(Color.app.textPrimary)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.app.textPrimary)]
        // Odznak = žlutá (jediná akcentní barva), ne systémová červená.
        for state in [item.normal, item.selected] {
            state.badgeBackgroundColor = UIColor(Color.app.accent)
            state.badgeTextAttributes = [.foregroundColor: UIColor(Color.app.accentInk)]
        }
        tab.stackedLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.app.bg)
        nav.shadowColor = .clear
        let text = UIColor(Color.app.textPrimary)
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
