import Foundation

/// A whole-value file under a cross-process lock. `transact` is the one atomic boundary every
/// transactional store is built on: lock, read, run the closure, write once, unlock.
final class TransactionalFile<State: Codable & Sendable>: Sendable {
    private let file: VersionedCodableFile<State>
    private let lock: ProcessFileLock
    private let makeDefault: @Sendable () -> State
    private let persistDefault: Bool
    private let validateTransition: @Sendable (State, State) throws -> Void

    /// `persistDefault` writes the default value the first time the file is missing, for state
    /// whose default is random and so must not differ between two reads.
    init(
        locations: StorageLocations, name: String, writer: AtomicFileWriter,
        persistDefault: Bool = false,
        validate: @escaping @Sendable (State) throws -> Void = { _ in },
        validateTransition: @escaping @Sendable (State, State) throws -> Void = { _, _ in },
        makeDefault: @escaping @Sendable () -> State
    ) {
        file = VersionedCodableFile(
            url: locations.ownFile("\(name).json"), currentVersion: 1, writer: writer,
            validate: validate)
        lock = ProcessFileLock(lockFile: locations.ownFile("\(name).lock"))
        self.makeDefault = makeDefault
        self.persistDefault = persistDefault
        self.validateTransition = validateTransition
    }

    func load() async throws -> State {
        guard persistDefault else {
            return try await lock.withLock { try file.read() ?? makeDefault() }
        }
        return try await lock.withLock {
            if let existing = try file.read() { return existing }
            let created = makeDefault()
            try file.write(created)
            return created
        }
    }

    func transact<T: Sendable>(_ body: @Sendable (inout State) throws -> T) async throws -> T {
        try await lock.withLock {
            var state = try file.read() ?? makeDefault()
            let previous = state
            let result = try body(&state)
            try validateTransition(previous, state)
            try file.write(state)
            return result
        }
    }
}
