import Foundation

/// Where one process keeps its files. Composition roots pass the root (the App Group container
/// on iOS and watchOS); storage resolves nothing from entitlements.
public struct StorageLocations: Sendable, Equatable {
    public enum Flavor: Sendable, Equatable {
        case release
        case debug
    }

    public let directory: URL

    /// A debug build appends `Debug`, so a development build never reads or migrates the
    /// installed app's data.
    public init(root: URL, flavor: Flavor) {
        switch flavor {
        case .release: directory = root
        case .debug: directory = root.appending(path: "Debug", directoryHint: .isDirectory)
        }
    }

    /// A file directly inside `directory`. A name with a separator or a dot component is
    /// rejected.
    public func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0")
        else {
            throw StorageError.io(code: Int(EINVAL))
        }
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    /// A file the module itself names, so there is no caller-supplied name to validate.
    func ownFile(_ name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    #if os(macOS)
        public static func macApplicationSupport(flavor: Flavor) -> StorageLocations {
            StorageLocations(
                root: URL.applicationSupportDirectory.appending(
                    path: "ResetRadar", directoryHint: .isDirectory),
                flavor: flavor)
        }
    #endif
}
