import Foundation
import ResetRadarDomain
import SwiftUI

/// A Mac Home cell resolved by account and default duration, never by snapshot array position.
struct MacAllowanceDisplay: Equatable {
    let state: PresentationState
    let usedPercent: Double?
    let fractionDigits: Int?

    static func resolve(
        account: AccountMetadata, window: AccountWindow.StandardWindow,
        snapshot: UsageSnapshot?, now: Date
    ) -> Self {
        guard let snapshot else { return unavailable }
        let accountWindow = AccountWindow(accountID: account.id, window: window)
        let (resolution, _) = AccountWindowResolver.resolve(
            accountWindow, in: snapshot, now: now)
        guard case .window(let value) = resolution else { return unavailable }
        let state = PresentationPolicy.derive(
            window: value, source: snapshot.source(for: account.id), now: now
        ).state
        switch state {
        case .current, .stale:
            return Self(
                state: state, usedPercent: value.observation?.usedPercent,
                fractionDigits: value.observation?.fractionDigits)
        case .resetAwaitingRefresh, .unavailable:
            return Self(state: state, usedPercent: nil, fractionDigits: nil)
        }
    }

    var percentageText: String? {
        guard let usedPercent else { return nil }
        let value: String
        if let fractionDigits {
            value = usedPercent.formatted(.number.precision(.fractionLength(fractionDigits)))
        } else {
            value = usedPercent.formatted(.number.precision(.fractionLength(0...2)))
        }
        return "\(value)%"
    }

    var statusText: String {
        switch state {
        case .current: "Current"
        case .stale: "Stale"
        case .resetAwaitingRefresh: "Waiting for Update"
        case .unavailable: "Unavailable"
        }
    }

    private static let unavailable = Self(
        state: .unavailable, usedPercent: nil, fractionDigits: nil)
}

struct MacAllowanceRing: View {
    let account: AccountMetadata
    let window: AccountWindow.StandardWindow
    let snapshot: UsageSnapshot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let display = MacAllowanceDisplay.resolve(
                account: account, window: window, snapshot: snapshot, now: timeline.date)
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.24), lineWidth: 5)
                    if let usedPercent = display.usedPercent {
                        Circle()
                            .trim(from: 0, to: CGFloat(usedPercent / 100))
                            .stroke(
                                ringColor(for: display.state),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 1) {
                        Text(display.percentageText ?? "—")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                        if let symbol = statusSymbol(for: display.state) {
                            Image(systemName: symbol)
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(ringColor(for: display.state))
                }
                .frame(width: 62, height: 62)
                Text(window == .fiveHour ? "5h" : "Weekly")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: display))
        }
    }

    private func ringColor(for state: PresentationState) -> Color {
        switch state {
        case .current: .accentColor
        case .stale: .orange
        case .resetAwaitingRefresh, .unavailable: .secondary
        }
    }

    private func statusSymbol(for state: PresentationState) -> String? {
        switch state {
        case .current: nil
        case .stale: "exclamationmark.circle.fill"
        case .resetAwaitingRefresh: "clock"
        case .unavailable: "questionmark.circle"
        }
    }

    private func accessibilityLabel(for display: MacAllowanceDisplay) -> String {
        let product = account.product == .codex ? "Codex" : "Claude Code"
        let name = window == .fiveHour ? "Five-hour" : "Weekly"
        let reading = display.percentageText.map { "\($0) used" } ?? "No percentage available"
        let identity = "\(account.effectiveDisplayLabel), \(product), \(name)"
        return "\(identity), \(reading), \(display.statusText)"
    }
}
