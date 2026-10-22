import XCTest

final class ResetRadarWatchTestsSmoke: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle(for: Self.self).bundleIdentifier)
    }
}
