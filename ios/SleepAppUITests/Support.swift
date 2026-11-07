import XCTest

/// Společné pomůcky pro UI testy. Appka běží proti produkčnímu Supabase,
/// přihlášení přes DEBUG argument `-debugLogin email:heslo` (z env `UITEST_LOGIN`).
extension XCUIApplication {
    static func launchApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-debugNoResult"]
        if let login = ProcessInfo.processInfo.environment["UITEST_LOGIN"], !login.isEmpty {
            args += ["-debugLogin", login]
        }
        app.launchArguments = args + extra
        app.launch()
        return app
    }
}

extension XCUIElement {
    @discardableResult
    func waitFor(_ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "Nenalezeno: \(self)", file: file, line: line)
        return self
    }
}

func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
