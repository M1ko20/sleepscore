import XCTest

/// Issue #13: zvoneček, nahlášení, blokování – proklikané v simulátoru proti produkci.
/// Data připraví `supabase/tests/ui_seed.py` (A = UI Anna, B = UI Bára, C = UI Cyril).
/// Env pro test runner (přes `TEST_RUNNER_…`): `UITEST_LOGIN` (A), `UITEST_LOGIN_B`, `UITEST_TAG`.
/// Testy jdou po sobě (abecedně) a navazují: A přijme souboj → B vidí notifikaci → A hlásí →
/// A blokuje B → B je zablokovaný.
final class Issue13Tests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var tag: String { env["UITEST_TAG"] ?? "" }
    private var loginA: String { env["UITEST_LOGIN"] ?? "" }
    private var loginB: String { env["UITEST_LOGIN_B"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !DEBUG
        throw XCTSkip("Issue13Tests potřebují Debug build (-debugLogin).")
        #endif
        if loginA.isEmpty || tag.isEmpty { throw XCTSkip("Chybí UITEST_LOGIN / UITEST_TAG (ui_seed.py).") }
    }

    // MARK: 1. Zvoneček a proklik (A)

    func test1_bellAndNotificationLinks() {
        let app = launch(as: loginA)
        // počet nepřečtených: komentář, sloučené reakce, pozvánka do souboje
        let bell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upozornění'")).firstMatch.waitFor(30)
        waitLabel(bell, contains: "nových")
        shot(app, "01 feed – zvoneček s počtem nepřečtených (\(bell.label))")
        XCTAssertEqual(bell.label, "Upozornění, 3 nových")
        bell.tap()

        app.navigationBars["Upozornění"].waitFor()
        let comment = row(app, "chrápals").waitFor()
        let reaction = row(app, "a 1 další reagují na tvoji noc").waitFor()
        let invite = row(app, "tě vyzývá").waitFor()
        XCTAssertTrue(row(app, "UI Bára je tu přes tvoji pozvánku").exists)
        XCTAssertTrue(app.descendants(matching: .any)["Nové"].exists, "tečka u nových chybí")
        shot(app, "02 upozornění – výpis, sloučené reakce")
        _ = reaction

        // proklik na kartu (komentář)
        comment.tap()
        app.staticTexts["Bára byla u toho, chrápals"].waitFor()
        shot(app, "03 proklik z notifikace → karta s komentářem")
        back(app)

        // proklik na výzvu → přijmout souboj
        invite.tap()
        let accept = app.buttons["Přijmout"].waitFor()
        shot(app, "04 proklik z notifikace → pozvánka do souboje")
        accept.tap()
        XCTAssertTrue(app.buttons["Přijmout"].waitForNonExistence(timeout: 15), "souboj se nepřijal")
        pause(1)
        shot(app, "05 souboj přijatý")
        back(app)

        // proklik na profil
        row(app, "UI Bára je tu přes tvoji pozvánku").tap()
        app.navigationBars["@ui_b_\(tag)"].waitFor()
        shot(app, "06 proklik z notifikace → profil")
        back(app)
        back(app)
        let bellAfter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upozornění'")).firstMatch.waitFor()
        XCTAssertEqual(bellAfter.label, "Upozornění", "po otevření má zvoneček být bez počtu")
        shot(app, "07 feed – zvoneček po přečtení")

        // výzva založená uživatelem, který smazal účet (creator_id = null)
        app.tabBars.buttons["Výzvy"].tap()
        let group = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Všichni proti všem'")).firstMatch.waitFor()
        shot(app, "08 výzvy – skupinová po smazaném zakladateli + přijatý souboj")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Bára'")).firstMatch.exists)
        group.tap()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'poslední peče buchty'")).firstMatch.waitFor()
        XCTAssertFalse(app.staticTexts["Výzva už není k dispozici."].exists)
        shot(app, "09 detail výzvy se smazaným zakladatelem")
    }

    // MARK: 2. Souboj: notifikace u druhé strany (B)

    func test2_challengeAcceptedNotificationForB() throws {
        if loginB.isEmpty { throw XCTSkip("Chybí UITEST_LOGIN_B") }
        let app = launch(as: loginB)
        let bell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upozornění'")).firstMatch.waitFor(30)
        bell.tap()
        app.navigationBars["Upozornění"].waitFor()
        let accepted = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Anna' AND label CONTAINS 'přijímá'"))
            .firstMatch.waitFor()
        shot(app, "10 B: upozornění – Anna přijala souboj")
        accepted.tap()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prohraná peče štrúdl'")).firstMatch.waitFor()
        shot(app, "11 B: proklik na souboj")
    }

    // MARK: 3. Nahlášení komentáře, karty a profilu (A)

    func test3_reports() {
        let app = launch(as: loginA)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upozornění'")).firstMatch.waitFor(30).tap()

        // komentář: dlouhý stisk → Nahlásit
        row(app, "chrápals").waitFor().tap()
        let comment = app.staticTexts["Bára byla u toho, chrápals"].waitFor()
        comment.press(forDuration: 1.2)
        app.buttons["Nahlásit"].waitFor().tap()
        app.navigationBars["Nahlásit komentář"].waitFor()
        app.buttons["Spam nebo podvod"].tap()
        shot(app, "12 nahlášení komentáře – formulář")
        app.buttons["Odeslat"].tap()
        app.staticTexts["Díky. Mrkneme na to."].waitFor()
        shot(app, "13 nahlášení komentáře – odesláno")
        app.buttons["Hotovo"].tap()
        XCTAssertTrue(app.staticTexts["Bára byla u toho, chrápals"].waitForNonExistence(timeout: 10),
                      "nahlášený komentář nezmizel")
        shot(app, "14 karta po nahlášení komentáře")
        back(app)
        back(app)

        // karta: ⋯ → Nahlásit kartu
        let cyrilCard = findInFeed(app, "UI Cyril")
        cyrilCard.tap()
        tapMore(app)
        app.buttons["Nahlásit kartu"].waitFor().tap()
        app.navigationBars["Nahlásit kartu"].waitFor()
        app.buttons["Něco jiného"].tap()
        app.buttons["Odeslat"].tap()
        app.staticTexts["Díky. Mrkneme na to."].waitFor()
        app.buttons["Hotovo"].tap()
        app.navigationBars["Feed"].waitFor()
        pause(1)
        shot(app, "15 feed po nahlášení karty Cyrila")
        app.swipeDown() // refresh – karta nesmí přijít zpátky
        pause(3)
        XCTAssertFalse(feedContains(app, "UI Cyril"), "nahlášená karta je pořád ve feedu")

        // profil: ⋯ → Nahlásit profil + Zablokovat v jednom kroku
        openFriend(app, "UI Cyril")
        tapMore(app)
        app.buttons["Nahlásit profil"].waitFor().tap()
        app.navigationBars["Nahlásit profil"].waitFor()
        app.buttons["Urážky nebo obtěžování"].tap()
        let toggle = app.switches.firstMatch.waitFor()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "přepínač Zablokovat se nezapnul")
        shot(app, "16 nahlášení profilu se zablokováním")
        app.buttons["Odeslat"].tap()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'blokování @ui_c_'")).firstMatch.waitFor()
        shot(app, "17 nahlášení profilu – odesláno, blok platí")
        app.buttons["Hotovo"].tap()
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Zablokováno.'")).firstMatch.waitFor()
        shot(app, "18 profil Cyrila – Zablokováno")
        back(app)

        // sekce Zablokovaní → Zrušit blok
        app.staticTexts["Zablokovaní"].waitFor()
        shot(app, "19 přátelé – sekce Zablokovaní (Cyril)")
        app.buttons["Zrušit blok"].tap()
        XCTAssertTrue(app.staticTexts["Zablokovaní"].waitForNonExistence(timeout: 10), "odblokování ze seznamu nefunguje")
        shot(app, "20 přátelé po zrušení bloku")
    }

    // MARK: 4. Blok a odblok z profilu (A blokuje B)

    func test4_blockFromProfile() {
        let app = launch(as: loginA)
        openFriend(app, "UI Bára")
        tapMore(app)
        app.buttons["Zablokovat"].waitFor().tap()
        confirm(app, "Zablokovat")
        let blocked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Zablokováno.'")).firstMatch.waitFor()
        shot(app, "21 profil Báry – Zablokováno")

        // odblok z profilu
        app.buttons["Zrušit blokování"].firstMatch.tap()
        XCTAssertTrue(blocked.waitForNonExistence(timeout: 10), "odblokování z profilu nefunguje")
        app.buttons["Přidat do přátel"].waitFor()
        shot(app, "22 profil Báry po odblokování (přátelství zrušené blokem)")

        // znovu zablokovat (pro test 5) a zkontrolovat sekci Zablokovaní
        tapMore(app)
        app.buttons["Zablokovat"].waitFor().tap()
        confirm(app, "Zablokovat")
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Zablokováno.'")).firstMatch.waitFor()
        back(app)
        app.staticTexts["Zablokovaní"].waitFor()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Bára'")).firstMatch.exists)
        shot(app, "23 přátelé – Bára v Zablokovaných")
        app.tabBars.buttons["Feed"].tap()
        pause(2)
        XCTAssertFalse(feedContains(app, "UI Bára"), "karty zablokované Báry jsou pořád ve feedu")
    }

    // MARK: 5. Zablokovaný (B)

    func test5_blockedUserView() throws {
        if loginB.isEmpty { throw XCTSkip("Chybí UITEST_LOGIN_B") }
        let app = launch(as: loginB)
        // karta Cyrila: komentář a reakce od Anny (blokuje B) nejsou vidět, Cyrilův ano
        let card = findInFeed(app, "UI Cyril")
        XCTAssertFalse(feedContains(app, "UI Anna"), "B vidí karty Anny")
        card.tap()
        app.staticTexts["Cyril sám sobě"].waitFor()
        XCTAssertFalse(app.staticTexts["Anna tu byla"].exists, "B vidí komentář Anny")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES 'Král spánku [0-9]+'")).firstMatch.exists, "B vidí reakci Anny")
        shot(app, "24 B: karta Cyrila bez komentáře a reakce Anny")
        back(app)

        // žádost o přátelství Anně → „Tohle nejde.“
        app.tabBars.buttons["Profil"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Přátelé'")).firstMatch.waitFor().tap()
        let search = app.textFields["Hledat přezdívku"].waitFor()
        search.tap()
        search.typeText("ui_a_\(tag)")
        let add = app.buttons["Přidat"].waitFor()
        shot(app, "25 B: hledání Anny")
        add.tap()
        app.staticTexts["Tohle nejde."].waitFor()
        shot(app, "26 B: žádost Anně → Tohle nejde.")
    }

    // MARK: Pomůcky

    private func launch(as login: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoResult", "-debugLogin", login]
        app.launch()
        dismissHealthSheet(app)
        return app
    }

    /// První start na čistém simulátoru: HealthKit sheet → screenshot a „Nepovolit“.
    private func dismissHealthSheet(_ app: XCUIApplication) {
        let dont = app.buttons.matching(NSPredicate(format: "label IN {\"Don’t Allow\", \"Don't Allow\", \"Nepovolit\"}")).firstMatch
        // Dialog přijde až po přihlášení a načtení profilu (MainTabView) → nejdřív počkat na záložky.
        _ = app.tabBars.buttons["Feed"].waitForExistence(timeout: 40)
        if dont.waitForExistence(timeout: 8) {
            pause(1)
            shot(app, "00 Debug build – HealthKit dialog (čtení i zápis)")
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "00 Debug HealthKit dialog – strom"
            dump.lifetime = .keepAlways
            add(dump)
            dont.tap()
            // „You can turn on health data categories later…“ → OK
            let ok = app.alerts.buttons["OK"]
            if ok.waitForExistence(timeout: 5) { ok.tap() }
            pause(1)
        }
    }

    /// ⋯ v liště: SwiftUI Menu v toolbaru neumí „scroll to visible“ → klepnout na souřadnici.
    private func tapMore(_ app: XCUIApplication) {
        let more = app.navigationBars.buttons["Další možnosti"].firstMatch.waitFor()
        pause(0.5)
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func row(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(0.8)
    }

    private func confirm(_ app: XCUIApplication, _ title: String) {
        for q in [app.sheets, app.alerts] {
            let b = q.buttons[title]
            if b.waitForExistence(timeout: 3) { b.tap(); return }
        }
        // iOS 18: confirmationDialog bez kontejneru sheet → poslední tlačítko s titulkem
        let all = app.buttons.matching(identifier: title)
        all.element(boundBy: all.count - 1).tap()
    }

    private func openFriend(_ app: XCUIApplication, _ name: String) {
        app.tabBars.buttons["Profil"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Přátelé'")).firstMatch.waitFor().tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.waitFor().tap()
        app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH '@'")).firstMatch.waitFor()
    }

    private func feedContains(_ app: XCUIApplication, _ text: String) -> Bool {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).count > 0
    }

    /// Najde kartu ve feedu (LazyVStack → posouvat).
    private func findInFeed(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        app.tabBars.buttons["Feed"].tap()
        let el = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        _ = el.waitForExistence(timeout: 15)
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(el.exists, "ve feedu chybí \(text)", file: file, line: line)
        return el
    }

    private func waitLabel(_ el: XCUIElement, contains text: String, timeout: TimeInterval = 20) {
        let exp = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: el)
        wait(for: [exp], timeout: timeout)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

/// Release build (#8): HealthKit dialog žádá jen o čtení. Přihlášení přes formulář (v Release
/// není `-debugLogin`). Spouští se `xcodebuild test -configuration Release` na čistém simulátoru.
final class ReleaseHealthTests: XCTestCase {
    func testReleaseAsksOnlyForRead() throws {
        #if DEBUG
        throw XCTSkip("Jen pro Release build.")
        #else
        let login = ProcessInfo.processInfo.environment["UITEST_LOGIN"] ?? ""
        let parts = login.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw XCTSkip("Chybí UITEST_LOGIN") }
        let app = XCUIApplication()
        app.launch()
        // Uvítání → přihlášení (podle WelcomeFlow)
        let email = app.textFields["E-mail"]
        if !email.waitForExistence(timeout: 10) {
            let a = XCTAttachment(string: app.debugDescription); a.name = "welcome tree"; a.lifetime = .keepAlways; add(a)
            for title in ["Už mám účet"] where app.buttons[title].exists {
                app.buttons[title].tap(); break
            }
        }
        // LoginView: e-mail je pod Sign in with Apple (#18).
        let toggle = app.buttons["toggleEmailLogin"]
        if !email.exists, toggle.waitForExistence(timeout: 5) { toggle.tap() }
        email.waitFor()
        email.tap(); email.typeText(parts[0])
        let pw = app.secureTextFields["Heslo"]
        pw.tap(); pw.typeText(parts[1])
        app.buttons["Přihlásit"].tap()

        let dont = app.buttons.matching(NSPredicate(format: "label IN {\"Don’t Allow\", \"Don't Allow\", \"Nepovolit\"}")).firstMatch
        XCTAssertTrue(dont.waitForExistence(timeout: 40), "HealthKit dialog se neukázal")
        pause(1.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "R1 Release build – HealthKit dialog"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = app.debugDescription
        let dump = XCTAttachment(string: tree); dump.name = "R1 Release HealthKit dialog – strom"; dump.lifetime = .keepAlways
        add(dump)
        XCTAssertFalse(tree.localizedCaseInsensitiveContains("to write"), "Release žádá o zápis")
        // „access and update your Health data“ píše iOS i u čistě čtecí žádosti – rozhoduje sekce „to write“.
        XCTAssertTrue(tree.localizedCaseInsensitiveContains("to read"), "chybí sekce čtení")
        dont.tap()
        #endif
    }
}
