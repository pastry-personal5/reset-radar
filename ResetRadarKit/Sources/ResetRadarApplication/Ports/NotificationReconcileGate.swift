/// Serializes reset-notification reconciliation across the iOS app and widget extension.
public protocol NotificationReconcileGate: Sendable {
    /// `nil` while another live claim holds the gate; a claim past its expiry is reclaimable.
    func claim() async -> GateClaim?
    func release(_ claim: GateClaim) async
}
