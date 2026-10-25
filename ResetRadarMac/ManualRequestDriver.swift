import ResetRadarApplication

actor ManualRequestDriver {
    static let pollInterval = Duration.seconds(15)

    typealias Poll = @Sendable () async -> [PendingRefreshRequest]
    typealias Handle = @Sendable ([PendingRefreshRequest]) async -> HandleOutcome

    private let poll: Poll
    private let handle: Handle
    private let interval: Duration
    private var loop: Task<Void, Never>?
    private var ready = false
    private var hasReaders = false
    private var sleeping = false
    private var inFlight = false

    init(
        interval: Duration = pollInterval, poll: @escaping Poll, handle: @escaping Handle
    ) {
        self.interval = interval
        self.poll = poll
        self.handle = handle
    }

    func update(ready: Bool, hasReaders: Bool, sleeping: Bool) {
        self.ready = ready
        self.hasReaders = hasReaders
        self.sleeping = sleeping
        reconcileLoop()
    }

    func wake() async {
        sleeping = false
        reconcileLoop()
        await tick()
    }

    func tick() async {
        guard ready, hasReaders, !sleeping, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        let requests = await poll()
        guard !requests.isEmpty else { return }
        _ = await handle(requests)
    }

    func stop() {
        ready = false
        loop?.cancel()
        loop = nil
    }

    private func reconcileLoop() {
        guard ready, hasReaders, !sleeping else {
            loop?.cancel()
            loop = nil
            return
        }
        guard loop == nil else { return }
        loop = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }
}
