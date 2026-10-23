import Foundation

/// File protection for the platform: owner-only on macOS, and data that stays readable after
/// the first unlock on iOS and watchOS, so Lock Screen widgets and background refresh can read.
public enum ProtectionPolicy: Sendable, Equatable {
    public enum Platform: Sendable, Equatable {
        case macOS
        case iOS
        case watchOS
    }

    case ownerOnly
    case untilFirstUserAuthentication

    public static func policy(for platform: Platform) -> ProtectionPolicy {
        switch platform {
        case .macOS: .ownerOnly
        case .iOS, .watchOS: .untilFirstUserAuthentication
        }
    }

    public static func forCurrentPlatform() -> ProtectionPolicy {
        #if os(macOS)
            policy(for: .macOS)
        #elseif os(watchOS)
            policy(for: .watchOS)
        #else
            policy(for: .iOS)
        #endif
    }

    public var fileAttributes: [FileAttributeKey: Any] {
        switch self {
        case .ownerOnly: [.posixPermissions: 0o600]
        case .untilFirstUserAuthentication:
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        }
    }

    public var directoryAttributes: [FileAttributeKey: Any] {
        switch self {
        case .ownerOnly: [.posixPermissions: 0o700]
        case .untilFirstUserAuthentication:
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        }
    }
}
