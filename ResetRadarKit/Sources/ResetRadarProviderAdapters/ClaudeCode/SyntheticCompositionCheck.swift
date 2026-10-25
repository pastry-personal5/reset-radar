import Darwin
import Foundation

public enum SyntheticCompositionError: Error, Equatable, Sendable {
    case notTrusted
    case launchFailed
    case timedOut
    case outputTooLarge
    case mismatch
    case unavailable
}

/// Runs the original executable alone and through the complete helper path on one synthetic
/// payload, in an isolated temporary Reset Radar root that never touches the production session
/// directory, compose record, or restore store. Both runs get the same bounded environment,
/// working directory, and input.
public struct SyntheticCompositionCheck: Sendable {
    private let validator: ExecutableIdentityValidator
    private let homeDirectory: URL
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let outputLimit: Int

    public init(
        validator: ExecutableIdentityValidator, homeDirectory: URL, environment: [String: String],
        timeout: TimeInterval = StatusLineLimits.syntheticCommandTimeout,
        outputLimit: Int = StatusLineLimits.syntheticOutputBytes
    ) {
        self.validator = validator
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    static let payload = Data(
        ("{\"session_id\":\"reset-radar-synthetic\",\"version\":\"0.0.0\","
            + "\"cost\":{\"total_api_duration_ms\":1},"
            + "\"rate_limits\":{\"five_hour\":{\"used_percentage\":1,\"resets_at\":4102444800}}}")
            .utf8)

    private struct Outcome: Equatable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
    }

    public func verify(
        executablePath: String, originalBashScript: Bool = false
    ) throws(SyntheticCompositionError) {
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-synthetic-\(UUID().uuidString)")
        guard mkdir(scratch.path, 0o700) == 0 else { throw .unavailable }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appending(path: "ResetRadar")
        guard mkdir(root.path, 0o700) == 0,
            let record = ComposeRecord(executablePath: executablePath),
            (try? ComposeRecordStore(rootDirectory: root).save(record)) != nil
        else { throw .unavailable }

        let alone = try runAlone(
            executablePath, scratch: scratch, originalBashScript: originalBashScript)
        let composed = try runComposed(root: root, scratch: scratch)
        guard alone == composed else { throw .mismatch }
    }

    private func runAlone(
        _ path: String, scratch: URL, originalBashScript: Bool
    ) throws(SyntheticCompositionError) -> Outcome {
        let out = scratch.appending(path: "alone.out")
        let err = scratch.appending(path: "alone.err")
        guard let outHandle = Self.create(out), let errHandle = Self.create(err) else {
            throw .unavailable
        }
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }
        let runner: ComposedCommandRunner
        do {
            runner = try ComposedCommandRunner(
                executablePath: path, validator: validator, environment: environment,
                workingDirectory: scratch, standardOutput: outHandle, standardError: errHandle,
                syntheticBashInvocation: originalBashScript)
        } catch ComposedCommandError.notTrusted {
            throw .notTrusted
        } catch {
            throw .launchFailed
        }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            timedOut.set()
            runner.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        _ = runner.write(Self.payload)
        runner.closeStandardInput()
        let status = runner.waitForExit()
        watchdog.cancel()
        guard !timedOut.value else { throw .timedOut }
        return try outcome(status: status, out: out, err: err)
    }

    private func runComposed(root: URL, scratch: URL) throws(SyntheticCompositionError) -> Outcome {
        let out = scratch.appending(path: "composed.out")
        let err = scratch.appending(path: "composed.err")
        guard let outHandle = Self.create(out), let errHandle = Self.create(err) else {
            throw .unavailable
        }
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw .unavailable }
        let writer = descriptors[1]
        Thread.detachNewThread {
            Self.payload.withUnsafeBytes { raw in
                _ = Darwin.write(writer, raw.baseAddress, raw.count)
            }
            close(writer)
        }
        let cancellation = StatusLineHelperCancellation()
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            timedOut.set()
            cancellation.cancel()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let status = StatusLineHelperMain.run(
            arguments: ["synthetic"], standardInput: descriptors[0], standardOutput: outHandle,
            standardError: errHandle,
            configuration: StatusLineHelperConfiguration(
                rootDirectory: root, homeDirectory: homeDirectory, environment: environment,
                workingDirectory: scratch),
            cancellation: cancellation)
        watchdog.cancel()
        close(descriptors[0])
        guard !timedOut.value else { throw .timedOut }
        return try outcome(status: status, out: out, err: err)
    }

    private func outcome(
        status: Int32, out: URL, err: URL
    ) throws(SyntheticCompositionError) -> Outcome {
        guard let outData = try? Data(contentsOf: out), let errData = try? Data(contentsOf: err)
        else { throw .unavailable }
        guard outData.count <= outputLimit, errData.count <= outputLimit else {
            throw .outputTooLarge
        }
        return Outcome(status: status, standardOutput: outData, standardError: errData)
    }

    private static func create(_ url: URL) -> FileHandle? {
        guard
            FileManager.default.createFile(
                atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { return nil }
        return try? FileHandle(forWritingTo: url)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        func set() { lock.withLock { raised = true } }
        var value: Bool { lock.withLock { raised } }
    }
}
