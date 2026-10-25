import ResetRadarApplication

actor RuntimeEventRouter {
    let log: MacRotatingLog
    var sources: SourceRuntime?
    var publication: PublicationDriver?
    var manual: ManualRequestDriver?
    var retry: SecretRetryDriver?

    init(log: MacRotatingLog) { self.log = log }

    func configure(
        sources: SourceRuntime, publication: PublicationDriver, manual: ManualRequestDriver,
        retry: SecretRetryDriver
    ) {
        self.sources = sources
        self.publication = publication
        self.manual = manual
        self.retry = retry
    }

    func workspace(_ event: WorkspaceEvent) async {
        switch event {
        case .woke:
            await log.record(.lifecycle(.wake))
            await manual?.wake()
            await sources?.refresh(.wake)
            await publication?.trigger(.wake)
        case .sessionActive:
            await log.record(.lifecycle(.sessionActive))
            await retry?.loginSessionBecameActive()
        case .foreground:
            await log.record(.lifecycle(.foreground))
            await sources?.refresh(.foreground)
        case .sleeping:
            await log.record(.lifecycle(.sleeping))
            await manual?.setSleeping(true)
        }
    }

    func networkRestored() async {
        await log.record(.lifecycle(.networkRestored))
        await publication?.trigger(.networkRestored)
    }
}
