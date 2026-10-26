import XCTest

final class ReaderHomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// One launch covers the toolbar and then the unpaired Home, which the toolbar steps leave
    /// unchanged.
    @MainActor
    func testTheMainToolbarHasFiveDestinationsAndHomeBeforePairingShowsOnlyThePairMacBanner() {
        let app = launchReader("notPaired")
        let names = ["Home", "Benefits", "Community", "Insight", "All"]
        let items = names.map { app.tab($0) }
        XCTAssertTrue(items.allSatisfy(\.exists))
        let positions = items.map(\.frame.midX)
        XCTAssertEqual(positions, positions.sorted())
        for name in ["Benefits", "Community", "Insight"] {
            app.tab(name).tap()
            XCTAssertTrue(
                app.staticTexts["This destination has no content yet."].appears(timeout: 5)
            )
        }
        app.openSettings()

        app.tab("Home").tap()
        XCTAssertTrue(app.element("setupBanner").appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["Pair Mac"].exists)
        XCTAssertFalse(app.element("accountRow.1").exists)
        app.element("setupBanner.action").tap()
        XCTAssertTrue(app.navigationBars["Pairing & Sync"].appears(timeout: 5))
        // The simulator has no data scanner, so scanning reports itself unavailable and the
        // manual paste below stays usable.
        app.buttons["Scan Pairing QR Code"].tap()
        let message = app.element("pairing.message")
        XCTAssertTrue(message.appears(timeout: 5))
        XCTAssertEqual(
            message.label, "Camera scanning is unavailable. Paste the Pairing Package instead.")
        let field = app.element("pairing.package")
        field.tap()
        field.typeText("not-a-package")
        app.element("pairing.review").tap()
        XCTAssertTrue(
            app.staticTexts["This is not a valid Reset Radar Pairing Package."]
                .appears(timeout: 5))
        XCTAssertFalse(app.element("pairing.confirmationCode").exists)
    }

    @MainActor
    func testConfirmingPairingAndWaitingForMacDataAreDistinctEmptyStates() {
        let confirming = launchReader("confirmingPairing")
        XCTAssertTrue(confirming.staticTexts["Confirming Pairing"].appears(timeout: 10))
        XCTAssertFalse(confirming.element("accountRow.1").exists)
        confirming.terminate()
        let waiting = launchReader("waitingForMacData")
        XCTAssertTrue(waiting.staticTexts["Waiting for Mac Data"].appears(timeout: 10))
        XCTAssertFalse(waiting.staticTexts["Confirming Pairing"].exists)
        XCTAssertFalse(waiting.element("accountRow.1").exists)
    }

    /// One launch covers the paired Home rows, then Account Details, then Home Refresh. Refresh
    /// runs last because it publishes a new snapshot.
    @MainActor
    func testPairedRowsUseNaturalOrderOpenEveryValidWindowAndRefreshReportsEachAccount() throws {
        let app = launchReader("paired")
        let second = app.element("accountRow.2")
        let personal = app.element("accountRow.3")
        let work = app.element("accountRow.1")
        XCTAssertTrue(work.appears(timeout: 10))
        XCTAssertLessThan(second.frame.minY, personal.frame.minY)
        XCTAssertLessThan(personal.frame.minY, work.frame.minY)
        XCTAssertFalse(app.element("setupBanner").exists)

        XCTAssertEqual(
            app.element("ring.1.fiveHour").label, "Work, Codex, Five-hour, 42% used, Current")
        let unavailable = app.element("ring.2.fiveHour").label
        XCTAssertEqual(
            unavailable, "Account #2, Codex, Five-hour, No percentage available, Unavailable")
        XCTAssertFalse(unavailable.contains("0%"))
        XCTAssertTrue(app.element("ring.3.weekly").label.hasSuffix("Waiting for Update"))
        XCTAssertTrue(app.element("ring.3.fiveHour").label.contains("33.5% used"))
        XCTAssertEqual(app.element("accountDetails.1").label, "Account Details")
        try assertRowReadingOrder(app, number: 1, alias: "Work")

        XCTAssertTrue(app.element("accountDetails.1").appears(timeout: 10))
        app.element("accountDetails.1").tap()
        XCTAssertTrue(app.navigationBars["Work"].appears(timeout: 5))
        XCTAssertTrue(app.element("windowDetails.Five-hour").exists)
        XCTAssertTrue(app.element("windowDetails.Weekly").exists)
        let additional = app.element("windowDetails.Code review")
        app.reveal(additional)
        XCTAssertTrue(additional.exists)
        let acquired = app.element("provenance.source")
        app.reveal(acquired)
        XCTAssertTrue(
            acquired.label.contains("Codex app-server")
                || (acquired.value as? String) == "Codex app-server")

        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.element("ring.3.weekly").tap()
        XCTAssertTrue(app.navigationBars["personal"].appears(timeout: 5))
        let weekly = app.element("windowDetails.Weekly")
        XCTAssertTrue(weekly.appears(timeout: 5))
        XCTAssertTrue(weekly.isSelected)
        XCTAssertTrue(weekly.label.contains("Waiting for Update"))

        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.element("accountRow.1").appears(timeout: 10))
        app.element("homeRefresh").tap()
        let workRefresh = app.element("refreshLine.1")
        XCTAssertTrue(
            workRefresh.appears(timeout: 5)
                && waitForLabel(workRefresh, "The Collector Mac read this account."))
        XCTAssertEqual(
            app.element("refreshLine.2").label,
            "The Collector Mac could not read Codex for this account.")
        XCTAssertTrue(app.element("refreshLine.3").label.hasPrefix("Relay read completed"))
    }

    @MainActor
    func testASyncProblemKeepsTheCommittedRowsVisible() {
        let app = launchReader("syncProblem")
        XCTAssertTrue(app.staticTexts["Sync Problem"].appears(timeout: 10))
        XCTAssertTrue(app.element("accountRow.1").exists)
        XCTAssertTrue(app.element("ring.1.fiveHour").label.contains("42% used"))
    }

    @MainActor
    func testLargeAccessibilityTextKeepsTheToolbarAndRowControls() throws {
        let app = launchReader(
            "paired",
            arguments: [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ])
        XCTAssertTrue(app.element("accountRow.2").appears(timeout: 10))
        // At accessibility sizes the iPad's adaptive tab bar may scroll items out of view; the
        // default-size toolbar test covers all five there.
        let names = isPad ? ["Home"] : ["Home", "Benefits", "Community", "Insight", "All"]
        for name in names {
            XCTAssertTrue(app.tab(name).exists, name)
        }
        XCTAssertTrue(app.element("ring.2.fiveHour").exists)
        XCTAssertTrue(app.element("accountDetails.2").isHittable)
        // The accessibility layout stacks the rings below the alias without reordering them.
        try assertRowReadingOrder(app, number: 2, alias: "Account #2")
    }

    @MainActor
    func testIPadKeepsTheListBesideDetailsAndRestoresItsSelection() throws {
        try XCTSkipUnless(isPad, "The split Home and its selection are iPad behavior.")
        let app = launchReader("paired")
        XCTAssertTrue(app.navigationBars["Account #2"].appears(timeout: 10))
        app.element("accountDetails.1").tap()
        XCTAssertTrue(app.navigationBars["Work"].appears(timeout: 5))
        app.terminate()
        let relaunched = launchReader("paired", arguments: ["-ResetRadarKeepSelection"])
        XCTAssertTrue(relaunched.navigationBars["Work"].appears(timeout: 10))

        let empty = launchReader("notPaired")
        XCTAssertTrue(
            empty.staticTexts[
                "Scan or paste a Pairing Package from Reset Radar on your Collector Mac."
            ].firstMatch.appears(timeout: 10))
        XCTAssertFalse(empty.navigationBars["Work"].exists)
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        waitUntil(timeout: 25) { element.exists && element.label == label }
    }
}
