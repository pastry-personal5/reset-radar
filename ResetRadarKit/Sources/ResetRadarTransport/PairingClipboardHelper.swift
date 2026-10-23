#if os(macOS)
    import AppKit
    import CryptoKit
    import Foundation

    @MainActor public protocol PairingPasteboard {
        var changeCount: Int { get }
        func readString() -> String?
        @discardableResult func writeString(_ value: String) -> Int
        func clear()
    }

    @MainActor public struct SystemPairingPasteboard: PairingPasteboard {
        public init() {}
        public var changeCount: Int { NSPasteboard.general.changeCount }
        public func readString() -> String? { NSPasteboard.general.string(forType: .string) }
        public func writeString(_ value: String) -> Int {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            return NSPasteboard.general.changeCount
        }
        public func clear() { NSPasteboard.general.clearContents() }
    }

    /// Persist only this lease after an explicit Copy action; never persist package text.
    public struct PairingClipboardLease: Codable, Sendable, Equatable {
        public let digest: Data
        public let changeCount: Int
        public let expiresAt: Date

        public init(digest: Data, changeCount: Int, expiresAt: Date) {
            self.digest = digest
            self.changeCount = changeCount
            self.expiresAt = expiresAt
        }
    }

    @MainActor public struct PairingClipboardHelper {
        private let pasteboard: any PairingPasteboard

        public init(pasteboard: any PairingPasteboard = SystemPairingPasteboard()) {
            self.pasteboard = pasteboard
        }

        public func copy(_ encodedPackage: String, expiresAt: Date) -> PairingClipboardLease {
            let count = pasteboard.writeString(encodedPackage)
            let digest = Data(SHA256.hash(data: Data(encodedPackage.utf8)))
            return PairingClipboardLease(digest: digest, changeCount: count, expiresAt: expiresAt)
        }

        /// Returns true only when the value written by Reset Radar was actually removed.
        @discardableResult
        public func clearIfUnchanged(_ lease: PairingClipboardLease) -> Bool {
            guard pasteboard.changeCount == lease.changeCount,
                let value = pasteboard.readString(),
                Data(SHA256.hash(data: Data(value.utf8))) == lease.digest
            else { return false }
            pasteboard.clear()
            return true
        }
    }
#endif
