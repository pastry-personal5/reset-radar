import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// The iOS reader bundle: snapshot and reader state in one file, replaced whole, so a process
/// killed mid-write sees the old bundle or the new one, never a mix.
public final class FileReaderStore: ReaderStore {
    private let file: TransactionalFile<ReaderState>

    public init(locations: StorageLocations, writer: AtomicFileWriter = AtomicFileWriter()) {
        file = TransactionalFile(
            locations: locations, name: "reader", writer: writer, persistDefault: true,
            makeDefault: { ReaderState(installationID: Self.newInstallationID()) })
    }

    public func load() async throws -> ReaderState {
        try await file.load()
    }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout ReaderState) throws -> T
    ) async throws -> T {
        try await file.transact(body)
    }

    private static func newInstallationID() -> InstallationID {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<InstallationID.byteCount).map { _ in
            UInt8.random(in: 0...255, using: &generator)
        }
        // The length is fixed, so construction cannot fail.
        return InstallationID(data: Data(bytes))!
    }
}
