import XCTest

/// Datum noci ve feedu, noci v profilu, kdo jak reagoval, skupinové výzvy podle jmen.
/// Demo účet pro review: `TEST_RUNNER_UITEST_LOGIN=…bedrival-review…`, screenshoty do `TEST_RUNNER_UITEST_SHOTS`.
final class NightDatesTests: XCTestCase {
    func testNightDatesTour() throws {
        guard let login = ProcessInfo.processInfo.environment["UITEST_LOGIN"], !login.isEmpty else {
            throw XCTSkip("Chybí UITEST_LOGIN")
        }
        let app = XCUIApplication.launchApp()
        let dont = app.buttons.matching(NSPredicate(format: "label IN {\"Don’t Allow\", \"Don't Allow\", \"Nepovolit\"}")).firstMatch
        if dont.waitForExistence(timeout: 20) {
            dont.tap()
            let ok = app.buttons["OK"]
            if ok.waitForExistence(timeout: 5) { ok.tap() }
        }
        app.navigationBars["Feed"].waitFor(30)
        pause(5)
        shot(app, "1-feed")

        // Detail cizí karty: reagovat → seznam reakcí → reakci zase smazat (demo účet zůstane, jak byl)
        // karta noci kamarádky z demo účtu (karta se otevírá klepnutím, není to Button)
        app.staticTexts["Bára"].firstMatch.waitFor().tap(); pause(3)
        let pick = app.buttons["Spal jak dřevo"]
        if !pick.exists { app.swipeUp() }
        pick.waitFor().tap(); pause(3)
        let r = app.buttons["reactions"]
        if !r.exists { app.swipeUp() }
        shot(app, "2-detail")
        r.waitFor().tap(); pause(3)
        shot(app, "3-reactions")
        XCTAssertTrue(app.staticTexts["Ty"].exists, "v seznamu reakcí chybím já")
        app.swipeDown(velocity: .fast); pause(1.5)
        pick.waitFor().tap(); pause(2)   // zrušit
        XCTAssertFalse(app.buttons["reactions"].exists, "reakce se nesmazala")
        app.navigationBars.buttons.firstMatch.tap(); pause(2)

        let tabs = app.tabBars.buttons
        tabs.element(boundBy: 1).tap(); pause(4)
        shot(app, "4-challenges")

        tabs.element(boundBy: tabs.count - 1).tap(); pause(4)
        app.swipeUp(velocity: .slow); pause(2)
        shot(app, "5-profile-nights")
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Celý měsíc'")).firstMatch
        if all.waitForExistence(timeout: 3) { all.tap(); pause(1); app.swipeUp(); pause(1); shot(app, "5b-all") }
        app.buttons["Předchozí měsíc"].waitFor().tap(); pause(3)
        shot(app, "6-profile-prev-month")
        app.buttons["Další měsíc"].tap(); pause(2)
        // klepnutí na noc v seznamu → detail
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'dnes' OR label CONTAINS 'včera' OR label CONTAINS '. 11.'")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap(); pause(3)
            shot(app, "7-profile-night-detail")
            app.navigationBars.buttons.firstMatch.tap(); pause(2)
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["UITEST_SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
