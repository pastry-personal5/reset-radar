import Foundation
import ResetRadarApplication
import ResetRadarDomain
import UserNotifications

/// Framework boundary for Reset Radar's local reset notifications. Only requests carrying the
/// versioned selection user-info field are returned or removed; unrelated app notifications are
/// never inspected as owned state.
public actor SystemNotificationScheduler: NotificationScheduler {
    private let center: UNUserNotificationCenter
    private var requestFailed = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorization() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        let current = NotificationRequestCodec.authorization(settings.authorizationStatus)
        if current != .notDetermined { requestFailed = false }
        return current == .notDetermined && requestFailed ? .failed : current
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            requestFailed = false
            return await authorization()
        } catch {
            requestFailed = true
            return .failed
        }
    }

    public func pending() async -> [ResetRequest] {
        await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(NotificationRequestCodec.identifierPrefix),
                let trigger = request.trigger as? UNCalendarNotificationTrigger,
                !trigger.repeats,
                let fireAt = trigger.nextTriggerDate()
            else { return nil }
            return NotificationRequestCodec.request(
                identifier: request.identifier, userInfo: request.content.userInfo,
                fireAt: fireAt)
        }
    }

    public func ownedPendingIdentifiers() async -> Set<String> {
        Set(
            await center.pendingNotificationRequests().compactMap {
                $0.identifier.hasPrefix(NotificationRequestCodec.identifierPrefix)
                    ? $0.identifier : nil
            })
    }

    public func schedule(_ request: ResetRequest) async throws {
        let content = UNMutableNotificationContent()
        let copy = NotificationRequestCodec.copy(for: request)
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = NotificationRequestCodec.userInfo(for: request)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: NotificationRequestCodec.utcComponents(for: request.fireAt),
            repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: request.identifier, content: content, trigger: trigger))
    }

    public func cancel(accountWindow: AccountWindow) async {
        await cancel(selection: .standard(accountWindow))
    }

    public func cancel(selection: WindowSelection) async {
        await cancel(
            identifier: ResetRequest(selection: selection, fireAt: .distantFuture).identifier)
    }

    public func cancel(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Foreground presentation is limited to this adapter's namespace and full authorization.
/// Provisional requests remain quiet even while Reset Radar is active.
public enum ResetNotificationPresentationPolicy {
    public static func shouldPresent(
        identifier: String, authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        identifier.hasPrefix(NotificationRequestCodec.identifierPrefix)
            && NotificationRequestCodec.authorization(authorizationStatus) == .authorized
    }
}

/// Pure request mapping kept separate from `UNUserNotificationCenter` so identifier ownership,
/// metadata, UTC triggers, authorization, and localized copy can be covered deterministically.
enum NotificationRequestCodec {
    fileprivate static let identifierPrefix = "reset."
    private static let selectionKey = "resetRadar.selection.v1"
    private static let accountKey = "resetRadar.account"
    private static let productKey = "resetRadar.product"
    private static let windowKindKey = "resetRadar.window.kind"
    private static let standardWindowKey = "resetRadar.window.standard"
    private static let windowLabelKey = "resetRadar.window.label"
    private static let durationKey = "resetRadar.window.duration"
    private static let sourceStateKey = "resetRadar.sourceState"
    private static let fractionDigitsKey = "resetRadar.fractionDigits"
    private static let fireAtKey = "resetRadar.fireAt"

    static func authorization(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    static func utcComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    static func userInfo(for request: ResetRequest) -> [AnyHashable: Any] {
        var result: [AnyHashable: Any] = [
            selectionKey: request.selection.versionedID,
            accountKey: request.accountLabel,
            productKey: request.product.rawValue,
            sourceStateKey: request.sourceState.rawValue,
            fireAtKey: request.fireAt.timeIntervalSinceReferenceDate,
        ]
        switch request.window {
        case .standard(let window):
            result[windowKindKey] = "standard"
            result[standardWindowKey] = window.rawValue
        case .additional(let label, let durationMinutes):
            result[windowKindKey] = "additional"
            if let label { result[windowLabelKey] = label }
            if let durationMinutes { result[durationKey] = durationMinutes }
        }
        if let fractionDigits = request.fractionDigits {
            result[fractionDigitsKey] = fractionDigits
        }
        return result
    }

    static func request(
        identifier: String, userInfo: [AnyHashable: Any], fireAt: Date
    ) -> ResetRequest? {
        guard let identity = userInfo[selectionKey] as? String,
            let selection = WindowSelection(versionedID: identity),
            let account = userInfo[accountKey] as? String, !account.isEmpty,
            account.utf8.count <= 32,
            let productRaw = userInfo[productKey] as? String,
            let product = ProductID(rawValue: productRaw),
            let sourceRaw = userInfo[sourceStateKey] as? String,
            let sourceState = SourceState(rawValue: sourceRaw),
            let kind = userInfo[windowKindKey] as? String,
            let recordedFireAt = userInfo[fireAtKey] as? TimeInterval,
            recordedFireAt.isFinite,
            abs(Date(timeIntervalSinceReferenceDate: recordedFireAt).timeIntervalSince(fireAt))
                < 0.001
        else { return nil }
        let window: WindowDisplayDescriptor
        switch kind {
        case "standard":
            guard let raw = userInfo[standardWindowKey] as? String,
                let standard = AccountWindow.StandardWindow(rawValue: raw),
                case .standard(let accountWindow) = selection,
                accountWindow.window == standard
            else { return nil }
            window = .standard(standard)
        case "additional":
            let label = userInfo[windowLabelKey] as? String
            let duration = userInfo[durationKey] as? Int
            guard case .additional(let windowID) = selection, windowID.product == product,
                (label?.utf8.count ?? 0) <= 96, duration.map({ $0 > 0 }) ?? true
            else { return nil }
            window = .additional(label: label, durationMinutes: duration)
        default:
            return nil
        }
        let fractionDigits = userInfo[fractionDigitsKey] as? Int
        guard fractionDigits == nil || (0...1).contains(fractionDigits ?? -1) else { return nil }
        let request = ResetRequest(
            selection: selection, fireAt: Date(timeIntervalSinceReferenceDate: recordedFireAt),
            accountLabel: account, product: product,
            window: window, sourceState: sourceState, fractionDigits: fractionDigits)
        guard request.identifier == identifier else { return nil }
        return request
    }

    static func copy(for request: ResetRequest) -> (title: String, body: String) {
        let product = request.product == .codex ? "Codex" : "Claude Code"
        let window: String
        switch request.window {
        case .standard(.fiveHour): window = "five-hour"
        case .standard(.weekly): window = "weekly"
        case .additional(let label?, _): window = label
        case .additional(nil, let minutes?): window = "\(minutes)-minute"
        case .additional: window = "additional"
        }
        return (
            "Allowance Reset", "\(request.accountLabel)’s \(product) \(window) allowance has reset."
        )
    }
}
