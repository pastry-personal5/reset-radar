#if os(macOS)
    import Foundation
    import ResetRadarTransport
    import Testing

    @MainActor private final class FakePairingPasteboard: PairingPasteboard {
        private(set) var changeCount = 0
        private(set) var value: String?

        func readString() -> String? { value }

        func writeString(_ value: String) -> Int {
            changeCount += 1
            self.value = value
            return changeCount
        }

        func clear() {
            changeCount += 1
            value = nil
        }
    }

    @MainActor @Test func clipboardClearsOnlyTheUnchangedPackageAcrossRelaunch() {
        let pasteboard = FakePairingPasteboard()
        let firstHelper = PairingClipboardHelper(pasteboard: pasteboard)
        let lease = firstHelper.copy(
            "synthetic-encoded-package", expiresAt: Date(timeIntervalSince1970: 1_700_000_300))
        #expect(lease.digest.count == 32)
        #expect(pasteboard.value == "synthetic-encoded-package")

        let relaunchedHelper = PairingClipboardHelper(pasteboard: pasteboard)
        #expect(relaunchedHelper.clearIfUnchanged(lease))
        #expect(pasteboard.value == nil)

        let nextLease = relaunchedHelper.copy(
            "another-synthetic-package", expiresAt: Date(timeIntervalSince1970: 1_700_000_600))
        _ = pasteboard.writeString("a different app's value")
        #expect(!relaunchedHelper.clearIfUnchanged(nextLease))
        #expect(pasteboard.value == "a different app's value")
    }
#endif
