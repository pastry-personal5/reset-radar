import XCTest

final class ResetRadarMacTestsSmoke: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle(for: Self.self).bundleIdentifier)
    }
}
