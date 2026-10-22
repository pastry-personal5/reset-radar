import Foundation
import ResetRadarTestSupport
import ResetRadarTransport
import Testing

@Test func moduleIsLinked() {
    #expect(ResetRadarTransportModule.name == "ResetRadarTransport")
}

/// Reads `Fixtures/Protocol` by source path because package resources cannot live outside the
/// target directory; the same files are read by the relay tests.
@Test func sharedProtocolFixtureIsReadable() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Protocol/scaffold.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let marker = (object as? [String: Any])?["marker"] as? String
    #expect(marker == "reset-radar-scaffold")
}
