import Foundation
import Testing

@testable import ResetRadarStorage

struct ProtectionPolicyTests {
    @Test func mapsEachPlatform() {
        #expect(ProtectionPolicy.policy(for: .macOS) == .ownerOnly)
        #expect(ProtectionPolicy.policy(for: .iOS) == .untilFirstUserAuthentication)
        #expect(ProtectionPolicy.policy(for: .watchOS) == .untilFirstUserAuthentication)
    }

    @Test func attributesFollowThePolicy() {
        #expect(ProtectionPolicy.ownerOnly.fileAttributes[.posixPermissions] as? Int == 0o600)
        #expect(ProtectionPolicy.ownerOnly.directoryAttributes[.posixPermissions] as? Int == 0o700)
        let protected = ProtectionPolicy.untilFirstUserAuthentication
        #expect(
            protected.fileAttributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication)
        #expect(
            protected.directoryAttributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication)
    }

    #if os(macOS)
        @Test func currentPlatformIsOwnerOnlyAndWritesOwnerOnlyFiles() throws {
            #expect(ProtectionPolicy.forCurrentPlatform() == .ownerOnly)
            let directory = TemporaryDirectory()
            let file = directory.url.appending(path: "nested/value.json")
            try AtomicFileWriter().write(Data("{}".utf8), to: file)
            #expect(try posixMode(of: file) == 0o600)
            #expect(try posixMode(of: file.deletingLastPathComponent()) == 0o700)
        }

        @Test func anExistingDirectoryIsTightenedBeforeWritingOrLocking() async throws {
            let directory = TemporaryDirectory()
            let root = directory.url.appending(path: "existing")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.path(percentEncoded: false))
            let file = root.appending(path: "value.json")
            try AtomicFileWriter().write(Data("{}".utf8), to: file)
            #expect(try posixMode(of: root) == 0o700)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.path(percentEncoded: false))
            let lockFile = root.appending(path: "value.lock")
            try Data().write(to: lockFile)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: lockFile.path(percentEncoded: false))
            let lock = ProcessFileLock(lockFile: lockFile)
            #expect(try await lock.withLock { 1 } == 1)
            #expect(try posixMode(of: root) == 0o700)
            #expect(try posixMode(of: lockFile) == 0o600)
        }
    #endif
}
