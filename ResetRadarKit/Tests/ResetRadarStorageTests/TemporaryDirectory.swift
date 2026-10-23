import Foundation

/// A unique directory removed when the test finishes.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(
                path: "reset-radar-storage-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func posixMode(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path(percentEncoded: false))
    return (attributes[.posixPermissions] as? Int) ?? -1
}
