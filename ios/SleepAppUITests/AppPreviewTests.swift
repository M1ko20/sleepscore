import XCTest

/// Záběry pro App Store video (app preview) na demo účtu z `promo_seed.py`.
/// Nahrává `simctl io recordVideo` zvenku, střih podle značek `PROMO_MARK <scéna> <start|end> <epoch>`
/// (viz tools/promo/README.md). Mění jen reakci hrdiny na jedné kartě.
final class AppPreviewTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func mark(_ scene: String, _ edge: String) {
        print("PROMO_MARK \(scene) \(edge) \(Date().timeIntervalSince1970)")
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoResult", "-debugNoPushPrompt"] + args
        return app
    }

    private func slowSwipe(_ app: XCUIApplication, _ n: Int, velocity: XCUIGestureVelocity = 250, gap: Double = 1.0) {
        for _ in 0..<n { app.windows.firstMatch.swipeUp(velocity: velocity); pause(gap) }
    }

    func testFeed() {
        let app = launch(["-debugTab", "0"])
        mark("feed", "start")
        app.launch()
        pause(5)
        slowSwipe(app, 2, velocity: 400)
        pause(0.5)
        mark("feed", "end")
        app.terminate()
    }

    func testReact() {
        let app = launch(["-debugTab", "0"])
        app.launch()
        pause(4)
        mark("react", "start")
        let card = app.staticTexts["Klára"].firstMatch.waitFor()
        card.press(forDuration: 0.6)
        pause(1.2)
        app.buttons["Král spánku"].firstMatch.waitFor().tap()
        pause(1.5)
        card.tap()
        pause(2.5)
        slowSwipe(app, 2, velocity: 300, gap: 1.2)
        pause(1)
        mark("react", "end")
        app.terminate()
    }

    func testDuel() {
        let app = launch(["-debugTab", "1"])
        app.launch()
        pause(4)
        mark("duel", "start")
        pause(1)
        app.staticTexts["Ty vs Ondra"].firstMatch.waitFor().tap()
        pause(3)
        slowSwipe(app, 1, velocity: 300, gap: 1.5)
        mark("duel", "end")
        app.terminate()
    }

    func testProfile() {
        let app = launch(["-debugTab", "2"])
        app.launch()
        pause(4)
        mark("profile", "start")
        pause(1.5)
        slowSwipe(app, 4, velocity: 300, gap: 1.3)
        mark("profile", "end")
        app.terminate()
    }

    func testRecapWrapped() {
        let app = launch(["-debugRecap", "-debugRecapOpen"])
        app.launch()
        pause(4)
        mark("recap", "start")
        pause(2.5)
        slowSwipe(app, 1, velocity: 300, gap: 1.5)
        mark("recap", "end")
        app.terminate()

        let w = launch(["-debugWrapped", "-debugWrappedOpen"])
        w.launch()
        pause(6)
        mark("wrapped", "start")
        for _ in 0..<7 {
            pause(1.8)
            w.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        pause(1.5)
        mark("wrapped", "end")
        w.terminate()
    }
}
