import Foundation
import Testing

@testable import ResetRadarStorage

struct StorageLocationsTests {
    private let root = URL(filePath: "/tmp/rr-locations-test", directoryHint: .isDirectory)

    @Test func debugAndReleaseNeverShareAFile() throws {
        let release = StorageLocations(root: root, flavor: .release)
        let debug = StorageLocations(root: root, flavor: .debug)
        #expect(release.directory != debug.directory)
        #expect(try release.file("reader.json") != debug.file("reader.json"))
        #expect(debug.directory.lastPathComponent == "Debug")
        #expect(debug.directory.deletingLastPathComponent() == release.directory)
    }

    @Test(arguments: ["../escape", "a/b", "..", ".", "", "/abs"])
    func rejectsTraversalNames(_ name: String) {
        let locations = StorageLocations(root: root, flavor: .release)
        #expect(throws: StorageError.io(code: Int(EINVAL))) { try locations.file(name) }
    }

    @Test func fileLivesDirectlyInDirectory() throws {
        let locations = StorageLocations(root: root, flavor: .debug)
        let file = try locations.file("publisher.json")
        #expect(file.deletingLastPathComponent().path == locations.directory.path)
    }

    @Test func rootNeedNotExistYet() throws {
        let directory = TemporaryDirectory()
        let locations = StorageLocations(root: directory.url, flavor: .debug)
        #expect(!FileManager.default.fileExists(atPath: locations.directory.path))
        try AtomicFileWriter().write(Data("x".utf8), to: locations.file("a.json"))
        #expect(FileManager.default.fileExists(atPath: locations.directory.path))
    }

    #if os(macOS)
        @Test func macApplicationSupportSeparatesFlavors() {
            let release = StorageLocations.macApplicationSupport(flavor: .release)
            let debug = StorageLocations.macApplicationSupport(flavor: .debug)
            #expect(release.directory.lastPathComponent == "ResetRadar")
            #expect(debug.directory.lastPathComponent == "ResetRadar.dev")
        }
    #endif
}
