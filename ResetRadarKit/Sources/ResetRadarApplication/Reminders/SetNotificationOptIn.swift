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

    public func set(_ slot: HomeSlot, enabled: Bool) async -> OptInOutcome {
        await preferences.setNotificationOptIn(slot, enabled: enabled)
        guard enabled else {
            await scheduler.cancel(slot: slot)
            return .disabled
        }
        var authorization = await scheduler.authorization()
        if authorization == .notDetermined {
            authorization = await scheduler.requestAuthorization()
        }
        // The choice stays recorded when denied, so the UI can show it with a settings route.
        guard authorization == .authorized else { return .denied }
        _ = await reconcile?.run(onIOS: true)
        return .enabled
    }
}
