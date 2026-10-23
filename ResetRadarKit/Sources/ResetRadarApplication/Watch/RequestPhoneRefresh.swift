/// Asks the iPhone to ingest and reply; the reply is an ordinary payload.
public actor RequestPhoneRefresh {
    private let phone: any PhoneLink
    private let commit: CommitWatchPayload

    public init(phone: any PhoneLink, commit: CommitWatchPayload) {
        self.phone = phone
        self.commit = commit
    }

    /// An unreachable iPhone is not an error.
    public func request() async {
        guard let reply = await phone.requestRefresh() else { return }
        _ = await commit.commit(reply)
    }
}
