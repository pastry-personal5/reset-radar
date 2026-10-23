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
    #endif
}
