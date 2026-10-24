import Foundation
import ResetRadarApplication

public final class CodexProcessRPCSession: CodexRPCSession, @unchecked Sendable {
    public let notifications: AsyncStream<JSONRPCNotification>

    private let process: ChildProcessSession
    private let client: JSONRPCClient

    fileprivate init(process: ChildProcessSession, client: JSONRPCClient) {
        self.process = process
        self.client = client
        notifications = client.notifications
    }

    public func initialize(params: JSONValue) async throws -> JSONValue {
        try await client.initialize(params: params)
    }

    public func accountStatus() async throws -> JSONValue {
        try await client.accountStatus()
    }

    public func rateLimits() async throws -> JSONValue {
        try await client.rateLimits()
    }

    public func stop() async {
        await client.stop()
        await process.stop()
    }
}

public struct CodexProcessRPCSessionFactory: CodexRPCSessionFactory, Sendable {
    private let configuration: CodexProcessLaunchConfiguration
    private let host: ChildProcessHost
    private let clock: any AppClock

    public init(
        configuration: CodexProcessLaunchConfiguration, host: ChildProcessHost,
        clock: any AppClock
    ) {
        self.configuration = configuration
        self.host = host
        self.clock = clock
    }

    public func makeSession(generation: UInt64) async throws -> any CodexRPCSession {
        let process: ChildProcessSession
        do {
            process = try host.launch(configuration)
        } catch ChildProcessHostError.executableUnavailable {
            throw CodexSourceFailure.notInstalled
        } catch ChildProcessHostError.unsafeLaunchConfiguration {
            throw CodexSourceFailure.permissionDenied
        } catch {
            throw CodexSourceFailure.processExited
        }
        let client = JSONRPCClient(
            transport: process, clock: clock, generation: generation, timeout: .seconds(10))
        return CodexProcessRPCSession(process: process, client: client)
    }
}
