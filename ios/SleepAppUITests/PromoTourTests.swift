import XCTest

/// Průchod appkou pro promo video. Jen prohlíží, nic nemění.
/// Běží na přihlášeném účtu v simulátoru; video nahrává `simctl io recordVideo` zvenku
/// a střih se řídí značkami `PROMO_MARK <scéna> <start|end> <epoch>` ve výstupu testu.
final class PromoTourTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func mark(_ scene: String, _ edge: String) {
        print("PROMO_MARK \(scene) \(edge) \(Date().timeIntervalSince1970)")
    }

    private func scene(_ name: String, args: [String], noResult: Bool = true, settle: Double = 4,
                       _ body: (XCUIApplication) -> Void) {
        let app = XCUIApplication()
        app.launchArguments = (noResult ? ["-debugNoResult"] : []) + args
        app.launch()
        pause(settle)               // data z produkce
        mark(name, "start")
        body(app)
        mark(name, "end")
        app.terminate()
    }

    private func slowScroll(_ app: XCUIApplication, ups: Int, downs: Int = 0) {
        let w = app.windows.firstMatch
        for _ in 0..<ups { w.swipeUp(velocity: 300); pause(1.2) }
        for _ in 0..<downs { w.swipeDown(velocity: 300); pause(1.0) }
    }

    func testPromoTour() {
        // 1. Feed: karty přátel a výsledky výzev
        scene("feed", args: ["-debugTab", "0"]) { app in
            pause(2.5)
            slowScroll(app, ups: 4)
            pause(1)
        }
        // 2. Detail noci: hypnogram, fáze, komentáře
        scene("night", args: ["-debugOpen", "1"]) { app in
            pause(2.5)
            slowScroll(app, ups: 3)
            pause(1)
        }
        // Výsledek výzvy a Nastavení → Notifikace se pod XCUITestem nevykreslí (appka zůstane
        // na pozadí), nahrávají se zvlášť přes `simctl launch` – viz tools/promo/README.md.
        // 4. Výzvy: seznam
        scene("challenges", args: ["-debugTab", "1"]) { app in
            pause(2.5)
            slowScroll(app, ups: 2)
            pause(1)
        }
        // 5. Detail výzvy
        scene("challenge", args: ["-debugTab", "1", "-debugOpenChallenge", "finished"]) { app in
            pause(2.5)
            slowScroll(app, ups: 2)
            pause(1)
        }
        // 6. Profil: MMA bilance, série, stádo, odznaky
        scene("profile", args: ["-debugTab", "2"]) { app in
            pause(2.5)
            slowScroll(app, ups: 4)
            pause(1)
        }
        // 7. Týdenní recap
        scene("recap", args: ["-debugRecap", "-debugRecapOpen"], settle: 5) { app in
            pause(3)
            slowScroll(app, ups: 1)
            pause(1.5)
        }
        // 8. Sleep Wrapped (stories)
        scene("wrapped", args: ["-debugWrapped", "-debugWrappedOpen"], settle: 6) { app in
            pause(2.5)
            for _ in 0..<6 {
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
                pause(2.5)
            }
        }
    }
}
