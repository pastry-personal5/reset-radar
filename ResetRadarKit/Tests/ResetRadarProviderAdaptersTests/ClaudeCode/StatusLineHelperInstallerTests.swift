import Darwin
import Foundation
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code helper installer")
struct StatusLineHelperInstallerTests {
    private func embedded(_ home: URL, version: String? = nil) throws -> URL {
        let version = version ?? StatusLineHelperVersion.current
        return try writeExecutable(
            "#!/bin/sh\nprintf '\(version)\\n'\n", at: home.appending(path: "embedded"))
    }

    @Test func installsAtomicallyRefreshesAndVerifiesTheVersion() throws {
        try withTrustedHome { home in
            let root = home.appending(path: "ResetRadar")
            let installer = StatusLineHelperInstaller(
                embeddedHelper: try embedded(home), rootDirectory: root)
            #expect(try installer.state() == .missing)
            try installer.install()
            #expect(try installer.state() == .current)
            var metadata = Darwin.stat()
            #expect(lstat(installer.installedURL.path, &metadata) == 0)
            #expect(metadata.st_mode & 0o7777 == 0o700)
            #expect(installer.installedURL.lastPathComponent == "reset-radar-statusline")
            // A stale copy is detected without executing it, then refreshed.
            try Data("#!/bin/sh\nprintf stale\n".utf8).write(to: installer.installedURL)
            #expect(try installer.state() == .mismatch)
            try installer.install()
            #expect(try installer.state() == .current)
            let leftovers = try FileManager.default.contentsOfDirectory(
                atPath: installer.binDirectoryURL.path)
            #expect(leftovers == ["reset-radar-statusline"])
        }
    }

    @Test func aWrongBakedVersionIsReported() throws {
        try withTrustedHome { home in
            let installer = StatusLineHelperInstaller(
                embeddedHelper: try embedded(home, version: "99"),
                rootDirectory: home.appending(path: "ResetRadar"))
            #expect(throws: StatusLineHelperInstallerError.versionMismatch) {
                try installer.install()
            }
        }
    }

    @Test func refusesSymlinkedUnsafeAndInvalidLocations() throws {
        try withTrustedHome { home in
            let source = try embedded(home)
            let root = home.appending(path: "ResetRadar")
            let installer = StatusLineHelperInstaller(embeddedHelper: source, rootDirectory: root)
            try installer.install()
            let victim = home.appending(path: "victim")
            try Data("keep".utf8).write(to: victim)
            try FileManager.default.removeItem(at: installer.installedURL)
            try FileManager.default.createSymbolicLink(
                at: installer.installedURL, withDestinationURL: victim)
            #expect(throws: StatusLineHelperInstallerError.unsafeLocation) {
                _ = try installer.state()
            }
            #expect(throws: StatusLineHelperInstallerError.unsafeLocation) {
                try installer.install()
            }
            #expect(try Data(contentsOf: victim) == Data("keep".utf8))
            try FileManager.default.removeItem(at: installer.installedURL)
            #expect(chmod(installer.binDirectoryURL.path, 0o770) == 0)
            #expect(throws: StatusLineHelperInstallerError.unsafeLocation) {
                try installer.install()
            }
            let missing = StatusLineHelperInstaller(
                embeddedHelper: home.appending(path: "nope"), rootDirectory: root)
            #expect(throws: StatusLineHelperInstallerError.invalidSource) { try missing.install() }
        }
    }
}
