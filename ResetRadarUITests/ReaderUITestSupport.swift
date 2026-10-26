import XCTest

/// Launches the Development app in one synthetic reader scenario; nothing leaves the simulator.
@MainActor
func launchReader(_ scenario: String, arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ResetRadarSyntheticScenario", scenario] + arguments
    app.launch()
    return app
}

@MainActor
var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

/// Polls `condition` every 0.1 s until it holds or `timeout` passes. XCTest's own waits check only
/// about once a second, which added a second to every wait even when the screen was ready.
@MainActor
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date.now.addingTimeInterval(timeout)
    while !condition() {
        guard Date.now < deadline else { return false }
        RunLoop.current.run(until: .now.addingTimeInterval(0.1))
    }
    return true
}

extension XCUIElement {
    /// `waitForExistence(timeout:)` without its one-second polling interval.
    func appears(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { exists }
    }
}

extension XCUIApplication {
    /// A Main Toolbar item, whether the system shows a tab bar or the iPad's adaptive tab bar.
    func tab(_ name: String) -> XCUIElement {
        let tabBarButton = tabBars.buttons[name]
        let button = buttons.matching(identifier: name).firstMatch
        // The iPad's adaptive tab bar has no tab bar element, so wait for either form at once.
        if waitUntil(timeout: 2, { tabBarButton.exists || button.exists }) {
            return tabBarButton.exists ? tabBarButton : button
        }
        return descendants(matching: .any).matching(NSPredicate(format: "label == %@", name))
            .firstMatch
    }

    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func openSettings() {
        tab("All").tap()
        buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(navigationBars["Settings"].appears(timeout: 5))
    }

    func openPairingAndSync() {
        openSettings()
        element("settings.pairingSync").tap()
        XCTAssertTrue(navigationBars["Pairing & Sync"].appears(timeout: 5))
    }

    /// Scrolls the current list until `element` is hittable.
    func reveal(_ element: XCUIElement, attempts: Int = 6) {
        for _ in 0..<attempts where !element.isHittable {
            swipeUp()
        }
    }
}
