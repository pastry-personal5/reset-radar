import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// Product-aware display formatting for provider-reported Percentage Used values.
public enum PercentageUsedFormatter {
    public static func text(
        _ usedPercent: Double, product: ProductID?, fractionDigits: Int?
    ) -> String {
        let displayed = product == .claudeCode ? floor(usedPercent) : usedPercent
        let digits = product == .claudeCode ? 0 : fractionDigits
        let value =
            if let digits {
                displayed.formatted(.number.precision(.fractionLength(digits)))
            } else {
                displayed.formatted(.number.precision(.fractionLength(0...2)))
            }
        return "\(value)%"
    }
}

/// The next unambiguous, future reset among an account's standard five-hour and weekly windows.
public struct NextReset: Equatable, Sendable {
    public let date: Date
    public let window: AccountWindow.StandardWindow

    public init(date: Date, window: AccountWindow.StandardWindow) {
        self.date = date
        self.window = window
    }

    public var label: String {
        switch window {
        case .fiveHour: "5h Reset"
        case .weekly: "Weekly Reset"
        }
    }
}

public enum NextResetDerivation {
    /// A window above this Percentage Used blocks usage until its own reset.
    static let blockedAbove = 99.0

    public static func derive(from sections: [WindowSection], now: Date) -> NextReset? {
        func window(for standard: AccountWindow.StandardWindow) -> AllowanceWindow? {
            guard let section = sections.first(where: { $0.id == .standard(standard) }),
                !section.ambiguous
            else { return nil }
            return section.details?.window
        }
        return derive(fiveHour: window(for: .fiveHour), weekly: window(for: .weekly), now: now)
    }

    /// The reset that actually restores usage: the latest reset among blocked windows, else the
    /// earliest known future reset. Equal times use the five-hour limit.
    public static func derive(
        fiveHour: AllowanceWindow?, weekly: AllowanceWindow?, now: Date
    ) -> NextReset? {
        let known = [
            (AccountWindow.StandardWindow.fiveHour, fiveHour),
            (.weekly, weekly),
        ].compactMap { standard, window -> (NextReset, blocked: Bool)? in
            guard let date = window?.resetsAt, date > now else { return nil }
            let blocked = (window?.observation?.usedPercent ?? 0) > blockedAbove
            return (NextReset(date: date, window: standard), blocked)
        }
        let blocked = known.filter(\.blocked).map(\.0)
        if !blocked.isEmpty {
            return blocked.max {
                $0.date < $1.date || ($0.date == $1.date && $0.window != .fiveHour)
            }
        }
        return known.map(\.0).min {
            $0.date < $1.date || ($0.date == $1.date && $0.window == .fiveHour)
        }
    }
}
