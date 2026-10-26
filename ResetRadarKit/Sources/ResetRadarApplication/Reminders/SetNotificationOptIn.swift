import ResetRadarDomain

/// Records the per-device reminder choice. The first enable asks for authorization once.
public actor SetNotificationOptIn {
    private let preferences: any PreferenceStore
    private let scheduler: any NotificationScheduler
    private let reconcile: ReconcileResetNotifications?

    public init(
        preferences: any PreferenceStore, scheduler: any NotificationScheduler,
        reconcile: ReconcileResetNotifications?
    ) {
        self.preferences = preferences
        self.scheduler = scheduler
        self.reconcile = reconcile
    }

    public func set(_ accountWindow: AccountWindow, enabled: Bool) async -> OptInOutcome {
        await set(.standard(accountWindow), enabled: enabled)
    }

    public func set(_ selection: WindowSelection, enabled: Bool) async -> OptInOutcome {
        await preferences.setNotificationOptIn(selection, enabled: enabled)
        guard enabled else {
            await scheduler.cancel(selection: selection)
            return .disabled
        }
        var authorization = await scheduler.authorization()
        if authorization == .notDetermined {
            authorization = await scheduler.requestAuthorization()
        }
        // Reconcile every terminal state: a later denial also removes an older pending request.
        _ = await reconcile?.run(onIOS: true)
        switch authorization {
        case .authorized: return .enabled
        case .provisional: return .provisional
        case .denied: return .denied
        case .failed, .unknown, .notDetermined: return .unavailable
        }
    }
}
