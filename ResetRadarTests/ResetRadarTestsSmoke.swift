import XCTest

final class ResetRadarTestsSmoke: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle(for: Self.self).bundleIdentifier)
    }
}
