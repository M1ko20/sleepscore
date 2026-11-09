import XCTest

/// Prázdné stavy (#28, App Store 2.1): účet bez nocí, přátel a výzev → screenshoty hlavních obrazovek.
/// Účet zakládá jen na chvíli service klíč (qa-empty@…), pak se maže.
/// `TEST_RUNNER_UITEST_LOGIN=qa-empty@sleepscore.test:<heslo>`, volitelně `TEST_RUNNER_UITEST_SHOTS=<složka>` (PNG i mimo xcresult).
final class EmptyStateTests: XCTestCase {
    private var app: XCUIApplication!

    func testEmptyAccount() throws {
        guard let login = ProcessInfo.processInfo.environment["UITEST_LOGIN"], login.hasPrefix("qa-empty@") else {
            throw XCTSkip("Chybí UITEST_LOGIN pro prázdný účet")
        }
        app = XCUIApplication.launchApp()
        let dont = app.buttons.matching(NSPredicate(format: "label IN {\"Don’t Allow\", \"Don't Allow\", \"Nepovolit\"}")).firstMatch
        if dont.waitForExistence(timeout: 15) {
            dont.tap()
            if app.buttons["OK"].waitForExistence(timeout: 5) { app.buttons["OK"].tap() }
        }
        app.navigationBars["Feed"].waitFor(30)
        pause(4)
        shot("01-feed")
        app.navigationBars["Feed"].buttons.element(boundBy: 0).tap(); pause(3)
        shot("01b-notifications")
        app.navigationBars.buttons.element(boundBy: 0).tap(); pause(2)

        let tabs = app.tabBars.buttons
        tabs.element(boundBy: 1).tap(); pause(4)
        shot("02-challenges")
        // Nová výzva bez přátel
        let plus = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add' OR label CONTAINS[c] 'nová' OR identifier == 'newChallenge'")).firstMatch
        if plus.exists { plus.tap(); pause(3); shot("03-new-challenge"); app.swipeDown(velocity: .fast); pause(2) }

        tabs.element(boundBy: tabs.count - 1).tap(); pause(4)
        shot("04-profile")
        app.swipeUp(); pause(1.5)
        shot("05-profile-scrolled")
        app.swipeUp(); pause(1.5)
        shot("06-profile-bottom")
        for (label, name) in [("Minulý týden v číslech", "07-recap"), ("Přátelé (0)", "08-friends"), ("Pozvánky · zbývá 3", "09-invites")] {
            let row = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            guard row.waitForExistence(timeout: 3) else { continue }
            row.tap(); pause(4)
            shot(name)
            if app.navigationBars.buttons.count > 0, app.navigationBars.firstMatch.buttons.firstMatch.label != "Nastavení" {
                app.navigationBars.firstMatch.buttons.firstMatch.tap()
            }
            app.swipeDown(velocity: .fast); pause(2)
        }
    }

    private func shot(_ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["UITEST_SHOTS"] {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
