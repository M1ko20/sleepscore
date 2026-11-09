import XCTest

/// Průchod demo účtem pro App Review (#18): feed, výzvy, profil → screenshoty v xcresult.
/// `TEST_RUNNER_UITEST_LOGIN=adam.mikolas64+bedrival-review@gmail.com:<heslo z ~/.bedrival/review_state.json>`
final class ReviewAccountTests: XCTestCase {
    func testReviewAccountTour() throws {
        guard let login = ProcessInfo.processInfo.environment["UITEST_LOGIN"], !login.isEmpty, login.contains("bedrival-review") else {
            throw XCTSkip("Chybí UITEST_LOGIN")
        }
        let app = XCUIApplication.launchApp()

        // Dialog Zdraví (jen poprvé) – recenzent ho uvidí taky, tady ho odmítneme.
        let dont = app.buttons.matching(NSPredicate(format: "label IN {\"Don’t Allow\", \"Don't Allow\", \"Nepovolit\"}")).firstMatch
        if dont.waitForExistence(timeout: 20) {
            dont.tap()
            let okButton = app.buttons["OK"]   // „You can turn on health data categories later…“
            if okButton.waitForExistence(timeout: 5) { okButton.tap() }
        }

        app.navigationBars["Feed"].waitFor(30)
        pause(5)
        attach(app, "1-feed")

        // Detail první karty noci
        let card = app.scrollViews.firstMatch.buttons.element(boundBy: 0)
        if card.waitForExistence(timeout: 5) {
            card.tap(); pause(4)
            attach(app, "2-night")
            app.navigationBars.buttons.firstMatch.tap(); pause(2)
        }

        let tabs = app.tabBars.buttons
        XCTAssertGreaterThanOrEqual(tabs.count, 3)
        tabs.element(boundBy: 1).tap(); pause(4)
        attach(app, "3-challenges")
        let challenge = app.scrollViews.firstMatch.buttons.element(boundBy: 0)
        if challenge.waitForExistence(timeout: 5) {
            challenge.tap(); pause(4)
            attach(app, "4-challenge")
            app.navigationBars.buttons.firstMatch.tap(); pause(2)
        }
        tabs.element(boundBy: tabs.count - 1).tap(); pause(4)
        attach(app, "5-profile")
        app.swipeUp(); pause(1.5)
        attach(app, "6-profile-scrolled")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["UITEST_SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
