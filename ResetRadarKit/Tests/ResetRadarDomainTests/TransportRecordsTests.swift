import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct TransportRecordsTests {
    func payload(cleared: Bool = false, snapshot: UsageSnapshot? = nil) throws -> WatchPayload {
        try WatchPayload(
            installationID: installation, deliveryRevision: 3, snapshot: snapshot,
            relaySequence: snapshot == nil ? nil : 9,
            transportStatus: .current, lastRelayContactAt: at(1), lastCommitAt: at(2),
            cleared: cleared)
    }

    func json<T: Encodable>(_ value: T) throws -> String {
        try wire(value)
    }

    @Test func watchPayloadGoldenAndRoundTrip() throws {
        let value = try payload()
        let text = try json(value)
        #expect(
            text
                == "{\"cleared\":false,\"deliveryRevision\":3,"
                + "\"installationID\":\"\(String(repeating: "0c", count: 16))\",\"lastCommitAt\":"
                + "\"2026-05-09T06:13:22.000Z\","
                + "\"lastRelayContactAt\":\"2026-05-09T06:13:21.000Z\",\"schemaVersion\":1,"
                + "\"transportStatus\":\"current\"}"
        )
        #expect(try WireCoding.decoder().decode(WatchPayload.self, from: Data(text.utf8)) == value)
        let full = try payload(snapshot: snapshot(windows: [window()]))
        #expect(
            try WireCoding.decoder().decode(
                WatchPayload.self, from: WireCoding.encoder().encode(full)) == full)
    }

    @Test func clearedPayloadWithSnapshotIsRejected() throws {
        #expect(throws: WatchPayloadError.clearedPayloadHasSnapshot) {
            try payload(cleared: true, snapshot: snapshot(windows: []))
        }
        let cleared = try payload(cleared: true)
        var text = try json(cleared)
        text = text.replacingOccurrences(
            of: "\"cleared\":true",
            with: "\"cleared\":true,\"snapshot\":\(try json(snapshot(windows: [])))")
        #expect(throws: WatchPayloadError.clearedPayloadHasSnapshot) {
            try WireCoding.decoder().decode(WatchPayload.self, from: Data(text.utf8))
        }
    }

    @Test func unknownTransportStatusDecodesToIncompatible() throws {
        let text = try json(payload()).replacingOccurrences(of: "\"current\"", with: "\"brandNew\"")
        let decoded = try WireCoding.decoder().decode(WatchPayload.self, from: Data(text.utf8))
        #expect(decoded.transportStatus == .incompatible)
    }

    @Test func unsupportedSchemaIsRejected() throws {
        let text = try json(payload()).replacingOccurrences(
            of: "\"schemaVersion\":1", with: "\"schemaVersion\":7")
        #expect(throws: SchemaError.unsupported(found: 7, supported: 1...1)) {
            try WireCoding.decoder().decode(WatchPayload.self, from: Data(text.utf8))
        }
    }

    @Test func eraseReceiptCarriesNoUsageOrSecret() throws {
        let receipt = WatchEraseReceipt(installationID: installation, deliveryRevision: 4)
        let object = try #require(
            JSONSerialization.jsonObject(with: WireCoding.encoder().encode(receipt))
                as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "installationID", "deliveryRevision"])
        #expect(
            try WireCoding.decoder().decode(
                WatchEraseReceipt.self, from: WireCoding.encoder().encode(receipt)) == receipt)
        let bad = try json(receipt).replacingOccurrences(
            of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        #expect(throws: SchemaError.self) {
            try WireCoding.decoder().decode(WatchEraseReceipt.self, from: Data(bad.utf8))
        }
    }

    @Test func pairingPackageRoundTripRedactsAndRejectsSchema() throws {
        let package = PairingPackage(
            relayEndpoint: URL(string: "https://relay.example.workers.dev")!, readerID: readerA,
            readToken: bytes(32, 1), contentKey: bytes(32, 2), publisherID: publisher,
            keyVersion: 1,
            minimumSequence: 5, registrationExpiresAt: at(300))
        let data = try WireCoding.encoder().encode(package)
        #expect(try WireCoding.decoder().decode(PairingPackage.self, from: data) == package)
        #expect(!package.description.contains("AQEB"))
        let bad = text(data).replacingOccurrences(
            of: "\"schemaVersion\":1", with: "\"schemaVersion\":3")
        #expect(throws: SchemaError.self) {
            try WireCoding.decoder().decode(PairingPackage.self, from: Data(bad.utf8))
        }
    }

    @Test func envelopeHeaderGoldenAndRoundTrip() throws {
        let header = EnvelopeHeader(
            protocolVersion: 1, envelopeVersion: 1, publisherID: publisher, sequence: 12,
            keyVersion: 1)
        let text = try json(header)
        #expect(
            text
                == "{\"envelopeVersion\":1,\"keyVersion\":1,\"protocolVersion\":1,"
                + "\"publisherID\":\"\(String(repeating: "01", count: 32))\",\"sequence\":12}"
        )
        #expect(
            try WireCoding.decoder().decode(EnvelopeHeader.self, from: Data(text.utf8)) == header)
    }

    @Test func transportStatusHasNineStableValues() {
        #expect(TransportStatus.allCases.count == 9)
        #expect(TransportStatus.secretsUnavailable.rawValue == "secretsUnavailable")
    }
}
