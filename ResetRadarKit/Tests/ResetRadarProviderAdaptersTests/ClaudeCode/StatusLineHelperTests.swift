import Darwin
import Foundation
import Testing

@testable import ResetRadarProviderAdapters

private struct HelperResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

private struct HelperRig {
    let home: URL
    let root: URL
    var configuration: StatusLineHelperConfiguration {
        StatusLineHelperConfiguration(
            rootDirectory: root, homeDirectory: home,
            environment: ["PATH": "/usr/bin:/bin", "HELPER_TEST": "yes"], workingDirectory: home)
    }

    init(_ home: URL) throws {
        self.home = home
        root = home.appending(path: "ResetRadar")
        #expect(mkdir(root.path, 0o700) == 0)
    }

    func compose(_ executable: URL) throws {
        try ComposeRecordStore(rootDirectory: root).save(
            ComposeRecord(executablePath: executable.path)!)
    }

    func run(
        input: Data, chunk: Int = 1_000_000, clock: TimeInterval = 5_000
    ) throws -> HelperResult {
        let inPipe = Pipe()
        let outURL = home.appending(path: "out-\(UUID().uuidString)")
        let errURL = home.appending(path: "err-\(UUID().uuidString)")
        let out = openFile(outURL)
        let err = openFile(errURL)
        let writer = Thread {
            var offset = 0
            let descriptor = inPipe.fileHandleForWriting.fileDescriptor
            while offset < input.count {
                let end = min(offset + chunk, input.count)
                let slice = input[offset..<end]
                slice.withUnsafeBytes { raw in
                    _ = Darwin.write(descriptor, raw.baseAddress, raw.count)
                }
                offset = end
            }
            try? inPipe.fileHandleForWriting.close()
        }
        writer.start()
        let status = StatusLineHelperMain.run(
            arguments: ["helper"], standardInput: inPipe.fileHandleForReading.fileDescriptor,
            standardOutput: out, standardError: err, configuration: configuration,
            clock: { Date(timeIntervalSince1970: clock) })
        try out.close()
        try err.close()
        return HelperResult(
            status: status, stdout: try Data(contentsOf: outURL),
            stderr: try Data(contentsOf: errURL))
    }

    func record() throws -> SessionRecord? {
        try SessionRecordFile(rootDirectory: root).read(
            key: SessionKey(sessionID: sentinelSessionID))
    }
}

private let echoChild = "#!/bin/sh\ncat\nprintf 'child-err' >&2\nexit 7\n"

@Suite("Claude Code status-line helper")
struct StatusLineHelperTests {
    @Test func withoutACommandItRecordsPrintsNothingAndSucceeds() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            let result = try rig.run(input: statusPayload())
            #expect(result.status == 0)
            #expect(result.stdout.isEmpty && result.stderr.isEmpty)
            #expect(try rig.record()?.windows.count == 1)
        }
    }

    @Test func aRecordingFailureIsQuietButNonzeroWithoutACommand() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            for input in [
                Data("not json".utf8), statusPayload(cost: "{\"total_api_duration_ms\":-1}"),
            ] {
                let result = try rig.run(input: input)
                #expect(result.status == 1)
                #expect(result.stdout.isEmpty && result.stderr.isEmpty)
            }
            let big = statusPayload(
                extra: "\"pad\":\"\(String(repeating: "a", count: 1_100_000))\"")
            #expect(try rig.run(input: big, chunk: 4_096).status == 1)
            #expect(try rig.record() == nil)
        }
    }

    @Test func aComposedChildGetsIdenticalBytesAndKeepsItsOutputAndStatus() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            try rig.compose(try writeExecutable(echoChild, at: home.appending(path: "line")))
            let payload = statusPayload(extra: "\"note\":\"split \\u00e9 across chunks\"")
            for chunk in [1, 2, 7, 64, 4_096] {
                let result = try rig.run(input: payload, chunk: chunk)
                #expect(result.stdout == payload, "chunk \(chunk)")
                #expect(utf8String(result.stderr) == "child-err")
                #expect(result.status == 7)
            }
            #expect(try rig.record() != nil)
        }
    }

    @Test func overBoundInputStillReachesTheChildButCreatesNoRecord() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            try rig.compose(
                try writeExecutable("#!/bin/sh\ncat\n", at: home.appending(path: "line")))
            let big = statusPayload(
                extra:
                    "\"pad\":\"" + String(repeating: "b", count: StatusLineLimits.maximumInputBytes)
                    + "\""
            )
            #expect(big.count > StatusLineLimits.maximumInputBytes)
            let result = try rig.run(input: big, chunk: 8_192)
            #expect(result.stdout == big)
            #expect(result.status == 0)
            #expect(try rig.record() == nil)
        }
    }

    @Test func aChildThatWritesBeforeReadingAndClosesEarlyCannotDeadlockTheHelper() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            // Emits 1 MiB on stdout and stderr, never reads stdin, exits 3.
            let script = """
                #!/bin/sh
                head -c 1048576 /dev/zero | tr '\\0' 'o'
                head -c 1048576 /dev/zero | tr '\\0' 'e' >&2
                exit 3
                """
            try rig.compose(try writeExecutable(script, at: home.appending(path: "chatty")))
            let big = statusPayload(extra: "\"pad\":\"\(String(repeating: "c", count: 900_000))\"")
            let result = try rig.run(input: big, chunk: 16_384)
            #expect(result.status == 3)
            #expect(result.stdout.count == 1_048_576)
            #expect(result.stderr.count == 1_048_576)
            #expect(try rig.record() != nil)
        }
    }

    @Test func aRecordingFailureNeverChangesAComposedCommandsBehavior() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            try rig.compose(
                try writeExecutable("#!/bin/sh\ncat\nexit 0\n", at: home.appending(path: "line")))
            let result = try rig.run(input: Data("{\"not\":\"a status line\"}".utf8))
            #expect(result.stdout == Data("{\"not\":\"a status line\"}".utf8))
            #expect(result.status == 0)
            #expect(result.stderr.isEmpty)
        }
    }

    @Test func untrustedMissingOrCorruptCompositionIsQuietAndNonzeroBeforeAnyLaunch() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            let marker = home.appending(path: "ran")
            let line = try writeExecutable(
                "#!/bin/sh\ntouch '\(marker.path)'\n", at: home.appending(path: "line"))
            try rig.compose(line)
            // Group-writable, replaced by a symlink to elsewhere, deleted, and a corrupt record.
            #expect(chmod(line.path, 0o770) == 0)
            var result = try rig.run(input: statusPayload())
            #expect(result.status == 1 && result.stdout.isEmpty && result.stderr.isEmpty)
            #expect(chmod(line.path, 0o700) == 0)
            try FileManager.default.removeItem(at: line)
            result = try rig.run(input: statusPayload())
            #expect(result.status == 1)
            let outside = URL(filePath: "/usr/bin/true")
            try FileManager.default.createSymbolicLink(at: line, withDestinationURL: outside)
            result = try rig.run(input: statusPayload())
            #expect(result.status == 1)
            try Data("{\"schemaVersion\":1,\"executablePath\":\"/x\",\"extra\":1}".utf8).write(
                to: rig.root.appending(path: ComposeRecord.fileName))
            result = try rig.run(input: statusPayload())
            #expect(result.status == 1 && result.stdout.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test func pathsWithSpacesAreLaunchedDirectlyWithoutAShell() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            let directory = home.appending(path: "my scripts")
            #expect(mkdir(directory.path, 0o700) == 0)
            let line = try writeExecutable(
                "#!/bin/sh\nprintf \"%s|%s\" \"$#\" \"$HELPER_TEST\"\n",
                at: directory.appending(path: "status line"))
            try rig.compose(line)
            let result = try rig.run(input: statusPayload())
            #expect(utf8String(result.stdout) == "0|yes")
        }
    }

    @Test func terminationReapsOnlyTheChildAndPrintsNothing() async throws {
        try await withAsyncTrustedHome { home in
            let validator = ExecutableIdentityValidator(homeDirectory: home)
            let pidFile = home.appending(path: "pid")
            let script = "#!/bin/sh\necho $$ > '\(pidFile.path)'\nexec sleep 30\n"
            let line = try writeExecutable(script, at: home.appending(path: "slow"))
            let out = openFile(home.appending(path: "o"))
            let err = openFile(home.appending(path: "e"))
            let runner = try ComposedCommandRunner(
                executablePath: line.path, validator: validator, environment: [:],
                workingDirectory: nil, standardOutput: out, standardError: err)
            for _ in 0..<200 where !FileManager.default.fileExists(atPath: pidFile.path) {
                try await Task.sleep(for: .milliseconds(10))
            }
            let pid = pid_t(
                try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines))!
            runner.terminate()
            // After terminate returns the child is reaped: signalling it fails.
            #expect(kill(pid, 0) == -1)
            #expect(runner.write(Data("x".utf8)) == false)
            #expect(runner.waitForExit() == 128 + SIGTERM)
        }
    }

    @Test func versionFlagPrintsOnlyThePublicVersion() throws {
        try withTrustedHome { home in
            let rig = try HelperRig(home)
            let out = openFile(home.appending(path: "o"))
            let status = StatusLineHelperMain.run(
                arguments: ["helper", "--version"], standardInput: -1, standardOutput: out,
                standardError: out, configuration: rig.configuration)
            try out.close()
            #expect(status == 0)
            #expect(
                try String(contentsOf: home.appending(path: "o"), encoding: .utf8)
                    == StatusLineHelperVersion.current + "\n")
        }
    }
}

@Suite("Claude Code executable trust")
struct ExecutableIdentityTests {
    @Test func acceptsAnOwnerOnlyExecutableInsideHomeAndBindsItsIdentity() throws {
        try withTrustedHome { home in
            let line = try writeExecutable("#!/bin/sh\necho hi\n", at: home.appending(path: "line"))
            let validator = ExecutableIdentityValidator(homeDirectory: home)
            let first = try validator.identity(of: line.path)
            #expect(first.canonicalPath == ExecutableIdentityValidator.resolve(line.path))
            #expect(try validator.revalidate(first) == first)
            try Data("#!/bin/sh\necho changed\n".utf8).write(to: line)
            #expect(throws: ExecutableTrustError.changed) { try validator.revalidate(first) }
            // A legitimate upgrade is still accepted at runtime.
            #expect(throws: Never.self) { try validator.validatePath(line.path) }
        }
    }

    @Test func refusesEveryUntrustedShape() throws {
        try withTrustedHome { home in
            let validator = ExecutableIdentityValidator(homeDirectory: home)
            let line = try writeExecutable("#!/bin/sh\n", at: home.appending(path: "line"))
            #expect(chmod(line.path, 0o702) == 0)
            #expect(throws: ExecutableTrustError.untrusted) {
                try validator.validatePath(line.path)
            }
            #expect(chmod(line.path, 0o770) == 0)
            #expect(throws: ExecutableTrustError.untrusted) {
                try validator.validatePath(line.path)
            }
            #expect(chmod(line.path, 0o600) == 0)
            #expect(throws: ExecutableTrustError.notExecutable) {
                try validator.validatePath(line.path)
            }
            #expect(chmod(line.path, 0o700) == 0)
            // Outside home, root-owned system executables, directories, relative and missing paths.
            #expect(throws: ExecutableTrustError.untrusted) {
                try validator.validatePath("/usr/bin/true")
            }
            #expect(mkdir(home.appending(path: "dir").path, 0o700) == 0)
            #expect(throws: ExecutableTrustError.notRegularFile) {
                try validator.validatePath(home.appending(path: "dir").path)
            }
            #expect(throws: ExecutableTrustError.invalidPath) {
                try validator.validatePath("relative/line")
            }
            #expect(throws: ExecutableTrustError.unavailable) {
                try validator.validatePath(home.path + "/missing")
            }
            // A symlink inside home that resolves outside it is refused by containment.
            let link = home.appending(path: "link")
            try FileManager.default.createSymbolicLink(
                at: link, withDestinationURL: URL(filePath: "/usr/bin/true"))
            #expect(throws: ExecutableTrustError.untrusted) {
                try validator.validatePath(link.path)
            }
            // A group-writable ancestor inside home fails the ancestor rule.
            let wide = home.appending(path: "wide")
            #expect(mkdir(wide.path, 0o700) == 0)
            let nested = try writeExecutable("#!/bin/sh\n", at: wide.appending(path: "line"))
            #expect(chmod(wide.path, 0o770) == 0)
            #expect(throws: ExecutableTrustError.untrusted) {
                try validator.validatePath(nested.path)
            }
            #expect(chmod(wide.path, 0o700) == 0)
            #expect(throws: Never.self) { try validator.validatePath(nested.path) }
        }
    }

    @Test func theDigestBoundIsExact() throws {
        try withTrustedHome { home in
            let line = try writeExecutable(
                String(repeating: "x", count: 10), at: home.appending(path: "line"))
            #expect(throws: Never.self) {
                try ExecutableIdentityValidator(homeDirectory: home, maximumDigestBytes: 10)
                    .identity(of: line.path)
            }
            #expect(throws: ExecutableTrustError.tooLarge) {
                try ExecutableIdentityValidator(homeDirectory: home, maximumDigestBytes: 9)
                    .identity(of: line.path)
            }
        }
    }
}
