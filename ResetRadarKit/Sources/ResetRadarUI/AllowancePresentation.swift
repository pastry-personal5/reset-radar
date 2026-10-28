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
    public static func derive(from sections: [WindowSection], now: Date) -> NextReset? {
        func date(for standard: AccountWindow.StandardWindow) -> Date? {
            guard let section = sections.first(where: { $0.id == .standard(standard) }),
                !section.ambiguous
            else { return nil }
            return section.details?.window.resetsAt
        }
        return derive(fiveHour: date(for: .fiveHour), weekly: date(for: .weekly), now: now)
    }

    public static func derive(fiveHour: Date?, weekly: Date?, now: Date) -> NextReset? {
        [
            (AccountWindow.StandardWindow.fiveHour, fiveHour),
            (.weekly, weekly),
        ].compactMap { standard, date -> NextReset? in
            guard let date, date > now else { return nil }
            return NextReset(date: date, window: standard)
        }.min { left, right in
            if left.date == right.date { return left.window == .fiveHour }
            return left.date < right.date
        }
    }
}
