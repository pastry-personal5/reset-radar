#if os(iOS)
    @preconcurrency import ActivityKit
    import Foundation
    import ResetRadarApplication
    import ResetRadarDomain

    /// ActivityKit execution boundary. Composition injects it only on iPhone; Application owns
    /// eligibility, content, stale dates, relevance, and every end decision.
    @available(iOS 16.1, *)
    public struct SystemLiveActivityController: LiveActivityController {
        public init() {}

        public func areActivitiesEnabled() async -> Bool {
            ActivityAuthorizationInfo().areActivitiesEnabled
        }

        public func list() async -> [RunningActivity] {
            Activity<ResetActivityAttributes>.activities.map {
                RunningActivity(
                    accountWindow: $0.attributes.accountWindow,
                    windowID: $0.attributes.windowID, startedAt: $0.attributes.startedAt)
            }
        }

        public func start(
            accountWindow: AccountWindow, content: ResetRadarApplication.ActivityContent,
            staleDate: Date
        ) async throws {
            let attributes = ResetActivityAttributes(
                accountWindow: accountWindow, windowID: content.windowID,
                startedAt: content.startedAt)
            _ = try Activity.request(
                attributes: attributes, content: activityContent(content, staleDate: staleDate),
                pushType: nil)
        }

        public func update(
            accountWindow: AccountWindow, content: ResetRadarApplication.ActivityContent,
            staleDate: Date
        ) async {
            guard
                let activity = Activity<ResetActivityAttributes>.activities.first(where: {
                    $0.attributes.accountWindow == accountWindow
                })
            else { return }
            await activity.update(activityContent(content, staleDate: staleDate))
        }

        public func end(accountWindow: AccountWindow) async {
            guard
                let activity = Activity<ResetActivityAttributes>.activities.first(where: {
                    $0.attributes.accountWindow == accountWindow
                })
            else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        private func activityContent(
            _ content: ResetRadarApplication.ActivityContent, staleDate: Date
        ) -> ActivityKit.ActivityContent<ResetActivityAttributes.ContentState> {
            ActivityKit.ActivityContent(
                state: ResetActivityAttributes.ContentState(
                    usedPercent: content.usedPercent, resetsAt: content.resetsAt,
                    observedAt: content.observedAt, accountLabel: content.accountLabel,
                    product: content.product, window: content.window,
                    sourceState: content.sourceState, fractionDigits: content.fractionDigits),
                staleDate: staleDate, relevanceScore: content.relevanceScore)
        }
    }
#endif
