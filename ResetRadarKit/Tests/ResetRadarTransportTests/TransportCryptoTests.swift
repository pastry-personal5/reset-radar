import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarTransport
import Testing

private let publisher = PublisherID(data: Data(repeating: 0x23, count: 32))!
private let reader = ReaderID(data: Data(repeating: 0x45, count: 16))!
private let key = SecretValue(Data(repeating: 0x67, count: 32))
private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func fixture(_ name: String) throws -> [String: String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Protocol/\(name).json")
    return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
}

@Test func generatorUsesIndependentSecretBytesAndSHA256() throws {
    let generator = CryptoSecretGenerator()
    let first = try generator.randomBytes(count: 32)
    let second = try generator.randomBytes(count: 32)
    #expect(first.reveal().count == 32)
    #expect(first != second)
    #expect((0...1).contains(generator.randomUnit()))
    #expect(
        generator.digest(of: SecretValue(Data("abc".utf8))).map {
            String(format: "%02x", $0)
        }.joined() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(!String(reflecting: first).contains(first.reveal().base64EncodedString()))
}

@Test func accountScopeIsStableAndFirstUseIsSerialized() async throws {
    let store = FakeSecretStore()
    let scoper = HMACAccountScoper(secrets: store, generator: FakeSecretGenerator())
    async let first = scoper.scope(forAccountIdentifier: "synthetic-account-one")
    async let second = scoper.scope(forAccountIdentifier: "synthetic-account-one")
    let (firstScope, secondScope) = try await (first, second)
    #expect(firstScope == secondScope)
    #expect(store.readCount == 1)
    #expect(store.names == [.accountScopeKey])
    let different = try await scoper.scope(forAccountIdentifier: "synthetic-account-two")
    #expect(different != firstScope)
}

@Test func accountScopeMatchesIndependentHMACVector() async throws {
    let store = FakeSecretStore()
    store.seed(.accountScopeKey, key)
    let scoper = HMACAccountScoper(secrets: store)
    let scope = try await scoper.scope(forAccountIdentifier: "synthetic-account-one")
    #expect(scope.hex == "6c300a9b95193752811f7825fce5cb63")
    #expect(store.readCount == 1)
}

@Test func accountScopeRejectsNon256BitPersistedKey() async {
    let store = FakeSecretStore()
    store.seed(.accountScopeKey, SecretValue(Data(repeating: 0x67, count: 31)))
    let scoper = HMACAccountScoper(secrets: store)
    await #expect(throws: HMACAccountScoperError.invalidKeyLength) {
        try await scoper.scope(forAccountIdentifier: "synthetic-account-one")
    }
}

@Test func originGuardRequiresCanonicalWorkersOrigin() {
    #expect(OriginGuard.accepts(URL(string: "https://reset.example.workers.dev")!))
    for origin in [
        "http://reset.example.workers.dev", "https://Reset.example.workers.dev",
        "https://reset.example.workers.dev/", "https://reset.example.workers.dev:443",
        "https://reset.example.workers.dev/v1", "https://reset.example.workers.dev?x=1",
        "https://reset.example.workers.dev#fragment",
        "https://person@reset.example.workers.dev",
        "https://reset.example.workers.dev.evil.test",
        "https://reset.example.workers.dev.",
    ] {
        #expect(!OriginGuard.accepts(URL(string: origin)!))
    }
}

@Test func pairingRoundTripAndDeadlineBounds() throws {
    let codec = JSONPairingCodec()
    func package(expiresAt: Date) -> PairingPackage {
        PairingPackage(
            relayEndpoint: URL(string: "https://reset.example.workers.dev")!, readerID: reader,
            readToken: Data(repeating: 0x89, count: 32), contentKey: key.reveal(),
            publisherID: publisher, keyVersion: 1, minimumSequence: 7,
            registrationExpiresAt: expiresAt)
    }
    let encoded = try codec.encode(package(expiresAt: now.addingTimeInterval(300)))
    #expect(try codec.decode(encoded, now: now).readerID == reader)
    #expect(codec.confirmationCode(for: encoded).split(separator: "-").count == 4)
    let lowerBoundary = try codec.encode(package(expiresAt: now.addingTimeInterval(-30)))
    let upperBoundary = try codec.encode(package(expiresAt: now.addingTimeInterval(330)))
    #expect(try codec.decode(lowerBoundary, now: now).readerID == reader)
    #expect(try codec.decode(upperBoundary, now: now).readerID == reader)
    #expect(throws: PairingCodecError.expired) {
        try codec.decode(codec.encode(package(expiresAt: now.addingTimeInterval(-31))), now: now)
    }
    #expect(throws: PairingCodecError.implausibleDeadline) {
        try codec.decode(codec.encode(package(expiresAt: now.addingTimeInterval(331))), now: now)
    }
    #expect(throws: PairingCodecError.malformed) { try codec.decode(encoded + "=", now: now) }
}

@Test func envelopeAuthenticatesHeaderAndRejectsSequenceOverflow() throws {
    let cipher = AESGCMEnvelopeCipher(nonceSource: { Data(repeating: 0xAB, count: 12) })
    let snapshot = try UsageSnapshot(
        publisherID: publisher, generatedAt: now, heartbeatSeconds: 60, sources: [], windows: [])
    let header = EnvelopeHeader(
        protocolVersion: 1, envelopeVersion: 1, publisherID: publisher, sequence: 7,
        keyVersion: 1)
    let sealed = try cipher.seal(snapshot, header: header, key: key)
    let opened = try cipher.open(sealed.encoded, key: key)
    #expect(opened.header == header)
    #expect(opened.snapshot == snapshot)
    #expect(throws: EnvelopeCipherError.authenticationFailed) {
        try cipher.open(sealed.encoded, key: SecretValue(Data(repeating: 0x77, count: 32)))
    }
    let changed = String(data: sealed.encoded, encoding: .utf8)!
        .replacingOccurrences(of: "\"sequence\":7", with: "\"sequence\":8")
    #expect(throws: EnvelopeCipherError.authenticationFailed) {
        try cipher.open(Data(changed.utf8), key: key)
    }
    let overflow = EnvelopeHeader(
        protocolVersion: 1, envelopeVersion: 1, publisherID: publisher,
        sequence: 9_007_199_254_740_992, keyVersion: 1)
    #expect(throws: EnvelopeCipherError.malformed) {
        try cipher.seal(snapshot, header: overflow, key: key)
    }
}

@Test func goldenEnvelopeMatchesSharedFixtureBytes() throws {
    let golden = try fixture("envelope")
    let header = EnvelopeHeader(
        protocolVersion: 1, envelopeVersion: 1, publisherID: publisher, sequence: 7,
        keyVersion: 1)
    let snapshot = try UsageSnapshot(
        publisherID: publisher, generatedAt: now, heartbeatSeconds: 60, sources: [], windows: [])
    #expect(
        String(data: try WireCoding.encoder().encode(header), encoding: .utf8)
            == golden["headerJSON"])
    #expect(
        String(data: try WireCoding.encoder().encode(snapshot), encoding: .utf8)
            == golden["plaintextJSON"])
    let cipher = AESGCMEnvelopeCipher(nonceSource: { Data(repeating: 0xAB, count: 12) })
    let sealed = try cipher.seal(snapshot, header: header, key: key)
    #expect(String(data: sealed.encoded, encoding: .utf8) == golden["outerJSON"])
    #expect(try cipher.open(Data(golden["outerJSON"]!.utf8), key: key).snapshot == snapshot)
    let digest = SHA256.hash(data: sealed.encoded).map { String(format: "%02x", $0) }.joined()
    #expect("\"\(digest)\"" == golden["etag"])
}

@Test func goldenPairingMatchesSharedFixtureBytes() throws {
    let golden = try fixture("pairing")
    let codec = JSONPairingCodec()
    let package = try codec.decode(golden["encoded"]!, now: now)
    #expect(
        String(data: try WireCoding.encoder().encode(package), encoding: .utf8)
            == golden["packageJSON"])
    #expect(try codec.encode(package) == golden["encoded"])
    #expect(codec.confirmationCode(for: golden["encoded"]!) == golden["confirmationCode"])
}

@Test func pairingRejectsUnsupportedAndNoncanonicalWireBytes() throws {
    let golden = try fixture("pairing")
    let codec = JSONPairingCodec()
    let packageJSON = golden["packageJSON"]!
    let unsupported = packageJSON.replacingOccurrences(
        of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
    func encoded(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    #expect(throws: PairingCodecError.unsupportedVersion) {
        try codec.decode(encoded(unsupported), now: now)
    }
    let extraField = packageJSON.replacingOccurrences(
        of: "{", with: "{\"extra\":1,",
        range: packageJSON.startIndex..<packageJSON.index(after: packageJSON.startIndex))
    #expect(throws: PairingCodecError.malformed) {
        try codec.decode(encoded(extraField), now: now)
    }
    let whitespace = packageJSON.replacingOccurrences(of: ",", with: ", ")
    #expect(throws: PairingCodecError.malformed) {
        try codec.decode(encoded(whitespace), now: now)
    }
    let invalidReader = packageJSON.replacingOccurrences(
        of: String(repeating: "45", count: 16), with: String(repeating: "gg", count: 16))
    #expect(throws: PairingCodecError.invalidIdentifier) {
        try codec.decode(encoded(invalidReader), now: now)
    }
}

@Test func pairingEncoderChecksEndpointLengthsAndSafeSequence() {
    let codec = JSONPairingCodec()
    func package(
        endpoint: String, keyCount: Int, tokenCount: Int, sequence: UInt64
    ) -> PairingPackage {
        PairingPackage(
            relayEndpoint: URL(string: endpoint)!, readerID: reader,
            readToken: Data(repeating: 0x89, count: tokenCount),
            contentKey: Data(repeating: 0x67, count: keyCount),
            publisherID: publisher, keyVersion: 1, minimumSequence: sequence,
            registrationExpiresAt: now.addingTimeInterval(300))
    }
    #expect(throws: PairingCodecError.endpointNotAllowed) {
        try codec.encode(
            package(
                endpoint: "https://reset.example.workers.dev/", keyCount: 32,
                tokenCount: 32, sequence: 7))
    }
    #expect(throws: PairingCodecError.invalidKeyLength) {
        try codec.encode(
            package(
                endpoint: "https://reset.example.workers.dev", keyCount: 31,
                tokenCount: 32, sequence: 7))
    }
    #expect(throws: PairingCodecError.invalidTokenLength) {
        try codec.encode(
            package(
                endpoint: "https://reset.example.workers.dev", keyCount: 32,
                tokenCount: 31, sequence: 7))
    }
    #expect(throws: PairingCodecError.unsupportedVersion) {
        try codec.encode(
            package(
                endpoint: "https://reset.example.workers.dev", keyCount: 32,
                tokenCount: 32, sequence: 9_007_199_254_740_992))
    }
}

@Test func pairingConfirmationChangesWithEveryPackageField() throws {
    let golden = try fixture("pairing")
    let json = golden["packageJSON"]!
    let changes: [(String, String)] = [
        ("reset.example", "other.example"),
        (String(repeating: "45", count: 16), String(repeating: "46", count: 16)),
        (
            Data(repeating: 0x89, count: 32).base64EncodedString(),
            Data(repeating: 0x88, count: 32).base64EncodedString()
        ),
        (
            key.reveal().base64EncodedString(),
            Data(repeating: 0x66, count: 32).base64EncodedString()
        ),
        (publisher.hex, String(repeating: "24", count: 32)),
        ("\"keyVersion\":1", "\"keyVersion\":2"),
        ("\"minimumSequence\":7", "\"minimumSequence\":8"),
        ("22:18:20.000Z", "22:17:20.000Z"),
        ("\"schemaVersion\":1", "\"schemaVersion\":2"),
    ]
    let codec = JSONPairingCodec()
    for (old, new) in changes {
        #expect(json.contains(old))
        let changed = json.replacingOccurrences(of: old, with: new)
        let encoded = Data(changed.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(codec.confirmationCode(for: encoded) != golden["confirmationCode"])
    }
}

@Test func envelopeRejectsUnknownDuplicateAndUnsupportedOuterFields() throws {
    let golden = try fixture("envelope")
    let cipher = AESGCMEnvelopeCipher()
    let outer = golden["outerJSON"]!
    let unknown = outer.replacingOccurrences(
        of: "{", with: "{\"extra\":1,",
        range: outer.startIndex..<outer.index(after: outer.startIndex))
    #expect(throws: EnvelopeCipherError.malformed) {
        try cipher.open(Data(unknown.utf8), key: key)
    }
    let duplicate = outer.replacingOccurrences(
        of: "{", with: "{\"keyVersion\":1,",
        range: outer.startIndex..<outer.index(after: outer.startIndex))
    #expect(throws: EnvelopeCipherError.malformed) {
        try cipher.open(Data(duplicate.utf8), key: key)
    }
    let unsupported = outer.replacingOccurrences(
        of: "\"envelopeVersion\":1", with: "\"envelopeVersion\":2")
    #expect(throws: EnvelopeCipherError.unsupportedVersion) {
        try cipher.open(Data(unsupported.utf8), key: key)
    }
    let ciphertext = outer.replacingOccurrences(
        of: "\"ciphertext\":\"", with: "\"ciphertext\":\"A")
    #expect(throws: EnvelopeCipherError.authenticationFailed) {
        try cipher.open(Data(ciphertext.utf8), key: key)
    }
    let tag = outer.replacingOccurrences(of: "\"tag\":\"", with: "\"tag\":\"A")
    #expect(throws: EnvelopeCipherError.malformed) {
        try cipher.open(Data(tag.utf8), key: key)
    }
}

@Test func maximumSafeSequenceSealsAndOpens() throws {
    let snapshot = try UsageSnapshot(
        publisherID: publisher, generatedAt: now, heartbeatSeconds: 60,
        sources: [], windows: [])
    let header = EnvelopeHeader(
        protocolVersion: 1, envelopeVersion: 1, publisherID: publisher,
        sequence: AESGCMEnvelopeCipher.maximumSequence, keyVersion: 1)
    let cipher = AESGCMEnvelopeCipher(nonceSource: { Data(repeating: 0xAD, count: 12) })
    let envelope = try cipher.seal(snapshot, header: header, key: key)
    #expect(
        try cipher.open(envelope.encoded, key: key).header.sequence
            == AESGCMEnvelopeCipher.maximumSequence)
}
