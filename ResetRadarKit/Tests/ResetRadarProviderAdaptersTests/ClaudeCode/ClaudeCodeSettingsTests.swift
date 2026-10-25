import Darwin
import Foundation
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code existing-command parser")
struct ExistingStatusLineParserTests {
    private let home = URL(filePath: "/Users/owner")

    @Test func acceptsExactlyOneExecutablePath() throws {
        let cases: [(String, String)] = [
            ("/Users/owner/bin/line", "/Users/owner/bin/line"),
            ("~/bin/line", "/Users/owner/bin/line"),
            ("\"/Users/owner/My Scripts/status line\"", "/Users/owner/My Scripts/status line"),
            ("'/Users/owner/My Scripts/line'", "/Users/owner/My Scripts/line"),
        ]
        for (command, expected) in cases {
            #expect(try ExistingStatusLineParser.parse(command, homeDirectory: home) == expected)
        }
    }

    @Test func refusesEveryOtherShape() {
        let refused = [
            "", "line", "./line", "bin/line", "/bin/line --flag", "/bin/line arg",
            "FOO=1 /bin/line", "/bin/line;ls", "/bin/line && ls", "/bin/line | cat",
            "/bin/line > out", "/bin/line < in", "$HOME/bin/line", "/bin/$X", "/bin/`x`",
            "/bin/line\\ x", "\"~/bin/line\"", "'~/bin/line'", "~", "~/", "~user/bin/line",
            "\"/bin/line\" extra", "\"/bin/line", "/bin/line\"", "\"/bin/$X\"", "\"/bin/a\\\"b\"",
            "/bin/line\n", "/bin/line\u{0}", "/bin/../line", "/bin//line", "/bin/./line", "/",
            "\"\"", "/bin/line/", "/bin/line *", "/tmp/a=b", "TOKEN=abc123 /bin/line",
            "bash -c 'curl x'", "/bin/line #c",
        ]
        for command in refused {
            #expect(throws: ExistingStatusLineParseError.unsupported, "\(command)") {
                try ExistingStatusLineParser.parse(command, homeDirectory: home)
            }
        }
        #expect(throws: ExistingStatusLineParseError.unsupported) {
            try ExistingStatusLineParser.parse(
                "/" + String(repeating: "a", count: 4_100), homeDirectory: home)
        }
    }
}

@Suite("Claude Code settings editor")
struct ClaudeCodeSettingsEditorTests {
    private let helper =
        "\"/Users/o/Library/Application Support/ResetRadar/bin/reset-radar-statusline\""

    private func snap(_ text: String) throws -> ClaudeSettingsSnapshot {
        try ClaudeCodeSettingsEditor.snapshot(of: Data(text.utf8))
    }

    @Test func classifiesStatusLineShapes() throws {
        #expect(try snap("{}").statusLine == .absent)
        #expect(try snap("{\"a\":1}").statusLine == .absent)
        #expect(
            try snap("{\"statusLine\":{\"type\":\"command\",\"command\":\"/x\"}}").statusLine
                == .command("/x"))
        for unsupported in [
            "{\"statusLine\":null}", "{\"statusLine\":\"/x\"}", "{\"statusLine\":{}}",
            "{\"statusLine\":{\"type\":\"other\",\"command\":\"/x\"}}",
            "{\"statusLine\":{\"type\":\"command\"}}",
            "{\"statusLine\":{\"type\":\"command\",\"command\":5}}",
            "{\"statusLine\":[1]}",
        ] {
            #expect(try snap(unsupported).statusLine == .unsupported, "\(unsupported)")
        }
    }

    @Test func rejectsMalformedDuplicateDeepAndOversizedSettings() {
        let bad = [
            "", "[]", "{", "{\"a\":1,\"a\":2}", "{\"x\":{\"b\":1,\"b\":2}}",
            "{\"statusLine\":{\"type\":\"command\",\"type\":\"command\"}}",
            "{\"d\":" + String(repeating: "[", count: 40) + String(repeating: "]", count: 40) + "}",
        ]
        for text in bad {
            #expect(throws: ClaudeSettingsError.malformed, "\(text.prefix(20))") { try snap(text) }
        }
        // A long unrelated string is fine; the byte ceiling is the bound.
        #expect(throws: Never.self) {
            try snap("{\"a\":\"\(String(repeating: "x", count: 50_000))\"}")
        }
    }

    @Test func replacingTheCommandPreservesEveryOtherByte() throws {
        let original = """
            {\r\n  "big": 123456789012345678901234567890.5e+10,\n  "env": {"K": "v", "n": [1, 2,3]},
              "statusLine" : { "padding": 2,\t"type":"command" ,
                "command" :   "/Users/o/bin/line",  "refreshInterval": 5, "x": {"y": 1} },
              "after":true }\n
            """
        let snapshot = try snap(original)
        let edited = try ClaudeCodeSettingsEditor.replacingCommand(in: snapshot, with: helper)
        var expected = original
        expected = expected.replacingOccurrences(
            of: "\"/Users/o/bin/line\"", with: JSONTokens.string(helper))
        #expect(utf8String(edited) == expected)
        #expect(try snap(utf8String(edited)).statusLine == .command(helper))
    }

    @Test func insertionKeepsEverythingAndRemovalRestoresTheBytes() throws {
        for original in [
            "{}", "{\n}", "{\"a\": 1}", "{\"a\": 1,\n  \"b\": {\"c\": [1]}\n}\n",
            "  {  \"k\":\"v\"  }  ",
        ] {
            let snapshot = try snap(original)
            let inserted = try ClaudeCodeSettingsEditor.inserting(
                statusLineCommand: helper, into: snapshot)
            let after = try snap(utf8String(inserted))
            #expect(after.statusLine == .command(helper))
            let removed = try #require(
                ClaudeCodeSettingsEditor.removingMinimalStatusLine(in: after, command: helper))
            #expect(try snap(utf8String(removed)).statusLine == .absent)
            if original != "{\n}" && original != "  {  \"k\":\"v\"  }  " {
                #expect(utf8String(removed) == original)
            }
        }
        let missing = try ClaudeCodeSettingsEditor.inserting(
            statusLineCommand: helper,
            into: ClaudeSettingsSnapshot(
                exists: false, revision: "absent", statusLine: .absent, bytes: Data()))
        #expect(try snap(utf8String(missing)).statusLine == .command(helper))
    }

    @Test func removalRefusesAnythingButTheExactMinimalObject() throws {
        let extra = try snap(
            settingsJSON(command: helper, extra: ",\"padding\":1")
        )
        #expect(
            ClaudeCodeSettingsEditor.removingMinimalStatusLine(in: extra, command: helper) == nil)
        let other = try snap("{\"statusLine\":{\"type\":\"command\",\"command\":\"/other\"}}")
        #expect(
            ClaudeCodeSettingsEditor.removingMinimalStatusLine(in: other, command: helper) == nil)
    }

    @Test func conditionalReplacementDetectsExternalEditsAndKeepsModes() throws {
        try withTrustedHome { home in
            let claude = home.appending(path: ".claude")
            #expect(mkdir(claude.path, 0o700) == 0)
            let settings = claude.appending(path: "settings.json")
            let text = "{\"a\": 1}\n"
            try Data(text.utf8).write(to: settings)
            #expect(chmod(settings.path, 0o640) == 0)
            let editor = ClaudeCodeSettingsEditor(
                settingsURL: settings,
                transactionDirectory: home.appending(path: "ResetRadar/claude-setup"))
            #expect(mkdir(home.appending(path: "ResetRadar").path, 0o700) == 0)
            let snapshot = try editor.read()
            let edited = try ClaudeCodeSettingsEditor.inserting(
                statusLineCommand: helper, into: snapshot)
            // An external edit between inspection and replacement is a conflict, nothing written.
            try Data("{\"a\": 2}\n".utf8).write(to: settings)
            #expect(throws: ClaudeSettingsError.conflict) {
                try editor.replace(expecting: snapshot, with: edited)
            }
            #expect(try Data(contentsOf: settings) == Data("{\"a\": 2}\n".utf8))
            let fresh = try editor.read()
            try editor.replace(
                expecting: fresh,
                with: try ClaudeCodeSettingsEditor.inserting(statusLineCommand: helper, into: fresh)
            )
            var metadata = Darwin.stat()
            #expect(lstat(settings.path, &metadata) == 0)
            #expect(metadata.st_mode & 0o7777 == 0o640)
            #expect(try editor.read().statusLine == .command(helper))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: claude.path) == [
                    "settings.json"
                ])
        }
    }

    @Test func postWriteConflictIsDistinctAndLeavesTheReplacementEvidenceInPlace() throws {
        try withTrustedHome { home in
            let claude = home.appending(path: ".claude")
            #expect(mkdir(claude.path, 0o700) == 0)
            #expect(mkdir(home.appending(path: "ResetRadar").path, 0o700) == 0)
            let settings = claude.appending(path: "settings.json")
            try Data("{\"a\":1}".utf8).write(to: settings)
            #expect(chmod(settings.path, 0o600) == 0)
            let editor = ClaudeCodeSettingsEditor(
                settingsURL: settings,
                transactionDirectory: home.appending(path: "ResetRadar/claude-setup"),
                afterReplacement: {
                    try Data("{\"a\":3}".utf8).write(to: settings)
                    guard chmod(settings.path, 0o600) == 0 else {
                        throw ClaudeSettingsError.unavailable
                    }
                })
            let snapshot = try editor.read()
            #expect(throws: ClaudeSettingsError.postWriteConflict) {
                try editor.replace(expecting: snapshot, with: Data("{\"a\":2}".utf8))
            }
            #expect(try String(contentsOf: settings, encoding: .utf8) == "{\"a\":3}")
        }
    }

    @Test func refusesUnsafeFilesAndCreatesAMissingOneOwnerOnly() throws {
        try withTrustedHome { home in
            let claude = home.appending(path: ".claude")
            let settings = claude.appending(path: "settings.json")
            #expect(mkdir(home.appending(path: "ResetRadar").path, 0o700) == 0)
            let editor = ClaudeCodeSettingsEditor(
                settingsURL: settings,
                transactionDirectory: home.appending(path: "ResetRadar/claude-setup"))
            // Missing directory and file read as absent and are created owner-only.
            let absent = try editor.read()
            #expect(!absent.exists)
            try editor.replace(
                expecting: absent,
                with: try ClaudeCodeSettingsEditor.inserting(
                    statusLineCommand: helper, into: absent))
            var metadata = Darwin.stat()
            #expect(lstat(settings.path, &metadata) == 0)
            #expect(metadata.st_mode & 0o7777 == 0o600)
            #expect(lstat(claude.path, &metadata) == 0)
            #expect(metadata.st_mode & 0o7777 == 0o700)
            // Group-writable file, symlink, and oversized file are refused.
            #expect(chmod(settings.path, 0o660) == 0)
            #expect(throws: ClaudeSettingsError.unsafeFile) { try editor.read() }
            #expect(chmod(settings.path, 0o600) == 0)
            let real = claude.appending(path: "real.json")
            try Data("{}".utf8).write(to: real)
            try FileManager.default.removeItem(at: settings)
            try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: real)
            #expect(throws: ClaudeSettingsError.unsafeFile) { try editor.read() }
            try FileManager.default.removeItem(at: settings)
            try Data(repeating: 0x20, count: StatusLineLimits.maximumSettingsBytes + 1).write(
                to: settings)
            #expect(chmod(settings.path, 0o600) == 0)
            #expect(throws: ClaudeSettingsError.tooLarge) { try editor.read() }
            // A group-writable ~/.claude is refused.
            try FileManager.default.removeItem(at: settings)
            #expect(chmod(claude.path, 0o770) == 0)
            #expect(throws: ClaudeSettingsError.unsafeFile) { try editor.read() }
        }
    }
}

@Suite("Claude Code restore store")
struct StatusLineRestoreStoreTests {
    @Test func roundTripsOnlyTheApprovedFieldsAndRejectsOthers() throws {
        try withTrustedHome { home in
            let directory = home.appending(path: "claude-setup")
            #expect(mkdir(directory.path, 0o700) == 0)
            let store = StatusLineRestoreStore(directory: directory)
            #expect(try store.load() == nil)
            let record = StatusLineRestoreRecord(
                prior: .command("/Users/o/bin/line"), installedCommand: "\"/x/helper\"",
                transactionID: UUID(), createdAt: Date(timeIntervalSince1970: 100),
                state: .pending)
            try store.save(record)
            #expect(try store.load() == record)
            let path = directory.appending(path: StatusLineRestoreRecord.fileName)
            var text = try String(contentsOf: path, encoding: .utf8)
            for key in [
                "schemaVersion", "priorKind", "priorCommand", "installedType",
                "installedCommand", "transactionID", "createdAtMs", "state",
            ] { #expect(text.contains("\"\(key)\"")) }
            text = text.replacingOccurrences(of: "\"state\"", with: "\"padding\":1,\"state\"")
            try Data(text.utf8).write(to: path)
            #expect(throws: StatusLineRestoreError.incompatible) { try store.load() }
            try store.save(
                StatusLineRestoreRecord(
                    prior: .absent, installedCommand: "\"/x\"", transactionID: UUID(),
                    createdAt: Date(), state: .installed))
            #expect(try store.load()?.prior == .absent)
            try store.remove()
            try store.remove()
            #expect(try store.load() == nil)
        }
    }
}
