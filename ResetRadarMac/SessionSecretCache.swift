import ResetRadarApplication

enum SecretAvailability: Sendable, Equatable {
    case available
    case secretsUnavailable
}

actor SessionSecretCache: SecretStore {
    private let store: any SecretStore
    private var values: [SecretName: SecretValue] = [:]
    private(set) var availability: SecretAvailability = .available

    init(store: any SecretStore) {
        self.store = store
    }

    func read(_ name: SecretName) async throws(SecretStoreError) -> SecretValue {
        if let value = values[name] { return value }
        do {
            let value = try await store.read(name)
            values[name] = value
            availability = .available
            return value
        } catch .interactionRequired {
            availability = .secretsUnavailable
            throw .interactionRequired
        } catch {
            throw error
        }
    }

    func write(_ name: SecretName, value: SecretValue) async throws(SecretStoreError) {
        values[name] = nil
        try await store.write(name, value: value)
        availability = .available
    }

    func delete(_ name: SecretName) async throws(SecretStoreError) {
        values[name] = nil
        try await store.delete(name)
    }

    func invalidateCache() async {
        values.removeAll()
        availability = .available
        await store.invalidateCache()
    }
}

actor SecretRetryDriver {
    typealias Retry = @Sendable () async -> Void

    private let interval: Duration
    private let retry: Retry
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(60), retry: @escaping Retry) {
        self.interval = interval
        self.retry = retry
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await retry()
            }
        }
    }

    func loginSessionBecameActive() async { await retry() }

    func stop() {
        task?.cancel()
        task = nil
    }
}
