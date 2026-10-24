import Foundation
import ResetRadarProviderAdapters
import Testing

@Suite("Codex executable validation")
struct CodexExecutableValidationTests {
    @Test("native executable preserves invocation path and canonicalizes only identity")
    func nativeAndSymlink() throws {
        try withDirectory { directory in
            let target = try executable(
                named: "codex-target", data: Data([0xCF, 0xFA]), in: directory)
            let link = directory.appending(path: "codex-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let result = try CodexExecutableValidator().validate(
                invocationPath: link.path, pathEnvironment: "/usr/bin:/bin")
            #expect(result.invocationPath == link.path)
            #expect(result.executable.canonicalPath == target.path)
            #expect(result.node == nil)
        }
    }

    @Test("env-node launcher binds the first node from the exact PATH")
    func environmentNode() throws {
        try withDirectory { directory in
            let first = directory.appending(path: "first", directoryHint: .isDirectory)
            let second = directory.appending(path: "second", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
            let firstNode = try executable(named: "node", data: Data([0xCF]), in: first)
            let secondNode = try executable(named: "node", data: Data([0xCE]), in: second)
            let codex = try executable(
                named: "codex", data: Data("#!/usr/bin/env node\nsynthetic".utf8), in: directory)
            let validator = CodexExecutableValidator()

            let firstResult = try validator.validate(
                invocationPath: codex.path,
                pathEnvironment: "\(first.path):\(second.path)")
            let secondResult = try validator.validate(
                invocationPath: codex.path,
                pathEnvironment: "\(second.path):\(first.path)")
            #expect(firstResult.node?.canonicalPath == firstNode.path)
            #expect(secondResult.node?.canonicalPath == secondNode.path)
            #expect(firstResult != secondResult)
            #expect(throws: CodexExecutableValidationError.changed) {
                try validator.revalidate(
                    firstResult, pathEnvironment: "\(second.path):\(first.path)")
            }
        }
    }

    @Test("unsafe PATH components and a missing node fail closed")
    func pathAndNodeFailures() throws {
        try withDirectory { directory in
            let codex = try executable(
                named: "codex", data: Data("#!/usr/bin/env node\n".utf8), in: directory)
            for path in ["", ":/usr/bin", "/usr/bin:", "/usr/bin:relative", ".:/usr/bin"] {
                #expect(throws: CodexExecutableValidationError.invalidPath) {
                    try CodexExecutableValidator().validate(
                        invocationPath: codex.path, pathEnvironment: path)
                }
            }
            #expect(throws: CodexExecutableValidationError.missingNode) {
                try CodexExecutableValidator().validate(
                    invocationPath: codex.path, pathEnvironment: directory.path)
            }
        }
    }

    @Test("unsafe file mode, unsupported shebang, and oversized shebang are rejected")
    func unsafeLaunchers() throws {
        try withDirectory { directory in
            let writable = try executable(named: "writable", data: Data([0xCF]), in: directory)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o722], ofItemAtPath: writable.path)
            #expect(throws: CodexExecutableValidationError.unsafePermissions) {
                try CodexExecutableValidator().validate(
                    invocationPath: writable.path, pathEnvironment: "/usr/bin")
            }

            let shell = try executable(
                named: "shell", data: Data("#!/bin/sh\n".utf8), in: directory)
            #expect(throws: CodexExecutableValidationError.unsupportedLauncher) {
                try CodexExecutableValidator().validate(
                    invocationPath: shell.path, pathEnvironment: "/usr/bin")
            }
            let oversized = try executable(
                named: "oversized",
                data: Data(("#!" + String(repeating: "x", count: 4_096) + "\n").utf8),
                in: directory)
            #expect(throws: CodexExecutableValidationError.unsupportedLauncher) {
                try CodexExecutableValidator().validate(
                    invocationPath: oversized.path, pathEnvironment: "/usr/bin")
            }
        }
    }

    @Test("a launcher larger than the shebang bound is accepted when its first line is short")
    func largeNpmLauncher() throws {
        try withDirectory { directory in
            let node = try executable(named: "node", data: Data([0xCF]), in: directory)
            let script = Data(
                ("#!/usr/bin/env node\n" + String(repeating: "//", count: 8_192)).utf8)
            let launcher = try executable(named: "codex", data: script, in: directory)
            let validated = try CodexExecutableValidator().validate(
                invocationPath: launcher.path,
                pathEnvironment: node.deletingLastPathComponent().path)
            #expect(validated.node != nil)
        }
    }

    @Test("replacement or modification invalidates a confirmed identity")
    func replacement() throws {
        try withDirectory { directory in
            let codex = try executable(named: "codex", data: Data([0xCF]), in: directory)
            let validator = CodexExecutableValidator()
            let original = try validator.validate(
                invocationPath: codex.path, pathEnvironment: "/usr/bin")
            try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: codex)
            #expect(throws: CodexExecutableValidationError.changed) {
                try validator.revalidate(original, pathEnvironment: "/usr/bin")
            }
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-executable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func executable(named name: String, data: Data, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
