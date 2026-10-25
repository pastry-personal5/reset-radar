import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarTransport
import Testing

private final class LocalRelayURLProtocol: URLProtocol, @unchecked Sendable {
    private typealias Completion = @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    nonisolated(unsafe) static var localPort = 0
    private var relayTask: URLSessionDataTask?

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".workers.dev") == true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let original = request.url,
            var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Self.localPort
        guard let localURL = components.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var forwarded = request
        forwarded.url = localURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        let completion: Completion = { [weak self] data, response, error in
            self?.complete(data: data, response: response, error: error, original: original)
        }
        relayTask = URLSession(configuration: configuration).dataTask(
            with: forwarded, completionHandler: completion)
        relayTask?.resume()
    }

    override func stopLoading() { relayTask?.cancel() }

    private func complete(
        data: Data?, response: URLResponse?, error: (any Error)?, original: URL
    ) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            values[String(describing: entry.key)] = String(describing: entry.value)
        }
        guard
            let rewritten = HTTPURLResponse(
                url: original, statusCode: http.statusCode, httpVersion: "HTTP/1.1",
                headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: rewritten, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct LocalMiniflare {
    let process: Process
    let port: Int

    static func start(writeToken: Data, adminToken: Data) async throws -> Self {
        let port = Int.random(in: 20_000...49_999)
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = repository.appending(path: "relay")
        process.arguments = [
            "npm", "exec", "wrangler", "--", "dev", "--local", "--port", String(port),
            "--inspector-port", String(port + 1),
            "--var", "WRITE_TOKEN_DIGEST:\(digest(writeToken))",
            "--var", "ADMIN_TOKEN_DIGEST:\(digest(adminToken))",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["WRANGLER_LOG_PATH"] =
            FileManager.default.temporaryDirectory
            .appending(path: "reset-radar-wrangler-\(UUID().uuidString).log").path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        guard let base = URL(string: "http://127.0.0.1:\(port)/") else {
            throw URLError(.badURL)
        }
        for _ in 0..<100 {
            guard process.isRunning else { throw CocoaError(.executableLoad) }
            if (try? await URLSession.shared.data(from: base)) != nil {
                return Self(process: process, port: port)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        process.terminate()
        throw URLError(.timedOut)
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@Suite("Synthetic relay integration", .serialized)
struct SyntheticRelayIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    // swiftlint:disable:next function_body_length
    func encryptedSnapshotRoundTripsThroughLocalWorker() async throws {
        let writeBytes = Data(repeating: 0x31, count: 32)
        let adminBytes = Data(repeating: 0x32, count: 32)
        let readBytes = Data(repeating: 0x33, count: 32)
        let contentBytes = Data(repeating: 0x34, count: 32)
        let worker = try await LocalMiniflare.start(
            writeToken: writeBytes, adminToken: adminBytes)
        defer { worker.stop() }
        LocalRelayURLProtocol.localPort = worker.port

        let relay = HTTPRelayGateway(protocolClasses: [LocalRelayURLProtocol.self])
        guard let endpoint = URL(string: "https://synthetic.reset-radar.workers.dev") else {
            throw URLError(.badURL)
        }
        let admin = SecretValue(adminBytes)
        let readerID = ReaderID(data: Data(repeating: 0x41, count: ReaderID.byteCount))!
        let digest = Data(SHA256.hash(data: readBytes))
        guard
            case .value = await relay.registerReader(
                readerID, digest: digest, endpoint: endpoint, adminToken: admin)
        else {
            Issue.record("Local relay did not register the synthetic reader")
            return
        }
        #expect(
            await relay.activateReader(endpoint: endpoint, readToken: SecretValue(readBytes))
                == .accepted(sequence: nil))

        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let publisherStore = FakePublisherStore()
        publisherStore.seed {
            $0.lifecycle = .active
            $0.endpoint = endpoint
            $0.publisherID = snapshot.publisherID
        }
        let secrets = FakeSecretStore()
        secrets.seed(.contentKey, SecretValue(contentBytes))
        secrets.seed(.writeToken, SecretValue(writeBytes))
        let cipher = AESGCMEnvelopeCipher()
        let publishing = PublishSnapshot(
            publisher: publisherStore, secrets: secrets, cipher: cipher, relay: relay,
            diagnostics: FakeDiagnosticsSink(), clock: clock, random: FakeSecretGenerator())
        #expect(
            await publishing.publish(snapshot, change: .transition, trigger: .change)
                == .published(sequence: 1))
        guard
            case .snapshot(let envelope, _, let sequence) = await relay.getSnapshot(
                endpoint: endpoint, readToken: SecretValue(readBytes), etag: nil)
        else {
            Issue.record("Local relay did not return the encrypted snapshot")
            return
        }
        let opened = try cipher.open(envelope, key: SecretValue(contentBytes))
        #expect(sequence == 1)
        #expect(opened.snapshot == snapshot)
    }
}
