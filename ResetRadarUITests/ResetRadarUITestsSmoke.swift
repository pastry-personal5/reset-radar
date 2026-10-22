import XCTest

final class ResetRadarUITestsSmoke: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Reset Radar"].waitForExistence(timeout: 10))
    }
}
