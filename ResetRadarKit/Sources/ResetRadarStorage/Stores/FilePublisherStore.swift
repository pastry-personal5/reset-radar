import Foundation
import ResetRadarApplication

/// The Mac's relay metadata. `nextSequence` is on disk before it returns, so a crash or retry can
/// skip a number but never reuse one.
public final class FilePublisherStore: PublisherStore {
    private let file: TransactionalFile<PublisherState>

    public init(locations: StorageLocations, writer: AtomicFileWriter = AtomicFileWriter()) {
        file = TransactionalFile(
            locations: locations, name: "publisher", writer: writer,
            validate: { state in
                // The relay cannot have accepted a number this Mac never allocated.
                guard state.sequence >= state.lastPublishedSequence else {
                    throw StorageError.corrupt
                }
            },
            validateTransition: { previous, next in
                // A fresh publisher may start at zero after relay destruction or setup.
                // Within one publisher, neither allocated nor accepted numbers can retreat.
                if let publisherID = previous.publisherID, next.publisherID == publisherID {
                    guard next.sequence >= previous.sequence,
                        next.lastPublishedSequence >= previous.lastPublishedSequence
                    else { throw StorageError.corrupt }
                }
            },
            makeDefault: { PublisherState() })
    }

    public func load() async throws -> PublisherState {
        try await file.load()
    }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout PublisherState) throws -> T
    ) async throws -> T {
        try await file.transact(body)
    }

    public func nextSequence() async throws -> UInt64 {
        try await file.transact { state in
            guard state.sequence < UInt64.max else {
                throw StorageError.io(code: Int(EOVERFLOW))
            }
            state.sequence += 1
            return state.sequence
        }
    }
}
