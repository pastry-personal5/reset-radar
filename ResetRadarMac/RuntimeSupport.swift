import Foundation
import ResetRadarApplication

struct SystemAppClock: AppClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

enum PublishingMode: Sendable, Equatable {
    case live
    case synthetic

    static func selected(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        arguments.contains("--synthetic") ? .synthetic : .live
    }
}

enum RuntimeRefreshReason: Sendable {
    case foreground
    case wake
    case manual
}

protocol ResetNotificationHook: Sendable {
    func snapshotDidCommit() async
}

struct NoOpResetNotificationHook: ResetNotificationHook {
    func snapshotDidCommit() async {}
}
