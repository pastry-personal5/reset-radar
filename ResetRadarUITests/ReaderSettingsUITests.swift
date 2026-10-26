import XCTest

final class ReaderSettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// One launch covers the Settings routes and then Forget Mac from the Pairing & Sync screen
    /// they end on.
    @MainActor
    func testSettingsHasEveryApprovedRouteAndForgetMacNeedsConfirmationThenReturnsHomeToSetup() {
        let app = launchReader("paired")
        app.openSettings()
        XCTAssertTrue(app.staticTexts["Notifications"].exists)
        XCTAssertEqual(app.staticTexts["Live Activities"].exists, !isPad)
        XCTAssertFalse(app.switches.firstMatch.exists)
        for route in ["Privacy & Data", "Diagnostics", "About"] {
            app.buttons[route].tap()
            XCTAssertTrue(app.navigationBars[route].appears(timeout: 5), route)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.element("settings.pairingSync").tap()
        XCTAssertTrue(app.navigationBars["Pairing & Sync"].appears(timeout: 5))
        XCTAssertEqual(
            app.element("pairing.status").label, "Status, Paired with your Collector Mac")
        XCTAssertFalse(app.element("pairing.package").exists)

        app.element("pairing.forgetMac").tap()
        let confirm = app.sheets.buttons["Forget Mac"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.element("pairing.forgetMessage").appears(timeout: 5))
        XCTAssertTrue(app.element("pairing.package").exists)
        app.tab("Home").tap()
        XCTAssertTrue(app.staticTexts["Pair Mac"].appears(timeout: 5))
        XCTAssertFalse(app.element("accountRow.1").exists)
    }

    @MainActor
    func testInterruptedCleanupIsRetryableAndWatchErasureStaysPendingOnIPhone() {
        let app = launchReader("cleanupPending")
        XCTAssertTrue(app.staticTexts["Local Cleanup Pending"].appears(timeout: 10))
        app.openPairingAndSync()
        XCTAssertTrue(app.element("pairing.retryCleanup").exists)
        XCTAssertFalse(app.element("pairing.package").exists)
        let watch = app.element("pairing.watchErasure")
        if isPad {
            XCTAssertFalse(watch.exists)
        } else {
            app.reveal(watch)
            XCTAssertTrue(watch.label.hasPrefix("Watch Erasure Status: pending."))
        }
        app.element("pairing.retryCleanup").tap()
        XCTAssertTrue(
            app.staticTexts[
                "Local Cleanup Pending. Old usage stays hidden; retry cleanup to finish."
            ]
            .appears(timeout: 5))
    }
}
