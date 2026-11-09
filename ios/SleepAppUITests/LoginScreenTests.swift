import XCTest

/// Přihlašovací obrazovka (#18, #19): Sign in with Apple + viditelný e-mail, žádné testovací texty.
/// Potřebuje odhlášenou appku (čerstvá instalace).
final class LoginScreenTests: XCTestCase {
    func testLoginScreen() throws {
        let app = XCUIApplication()
        app.launch()
        let haveAccount = app.buttons["Už mám účet"]
        guard haveAccount.waitForExistence(timeout: 15) else { throw XCTSkip("Appka není odhlášená.") }
        haveAccount.tap()

        app.buttons["signInWithApple"].waitFor()
        XCTAssertFalse(app.textFields["E-mail"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'testovací'")).firstMatch.exists)
        attach(app, "login-apple")

        app.buttons["toggleEmailLogin"].tap()
        app.textFields["E-mail"].waitFor()
        XCTAssertTrue(app.secureTextFields["Heslo"].exists)
        XCTAssertFalse(app.buttons["signInWithApple"].exists)
        attach(app, "login-email")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
