import ActivityKit
import ResetRadarApplication
import ResetRadarDomain
import SwiftUI
import WidgetKit

import struct ResetRadarScheduling.ResetActivityAttributes

@main
struct ResetRadarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AllowanceWidget()
        StandardAllowanceWidget()
        if #available(iOS 16.1, *) {
            ResetLiveActivity()
        }
    }
}
@available(iOS 16.1, *)
private struct ResetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ResetActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.accountLabel).font(.headline)
                Text("\(product(context.state.product)) · \(window(context.state.window))")
                    .font(.caption)
                Text(percentage(context.state) + "% used").font(.title3.weight(.semibold))
                countdown(context.state.resetsAt)
                    .monospacedDigit()
                if isStale(context.state, systemStale: context.isStale) {
                    Text("Stale").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .activityBackgroundTint(.black.opacity(0.15))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.accountLabel).lineLimit(1)
                        countdown(context.state.resetsAt).monospacedDigit()
                        if isStale(context.state, systemStale: context.isStale) {
                            Text("Stale").font(.caption2)
                        }
                    }
                }
            } compactLeading: {
                if isStale(context.state, systemStale: context.isStale) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityLabel("Stale")
                } else {
                    Text(percentage(context.state) + "%")
                }
            } compactTrailing: {
                countdown(context.state.resetsAt).monospacedDigit()
            } minimal: {
                if isStale(context.state, systemStale: context.isStale) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityLabel("Stale")
                } else {
                    Text(percentage(context.state) + "%")
                }
            }
        }
    }

    private func percentage(_ state: ResetActivityAttributes.ContentState) -> String {
        state.usedPercent.formatted(
            .number.precision(.fractionLength(state.fractionDigits ?? 0)))
    }

    private func product(_ value: ProductID) -> String {
        value == .codex ? "Codex" : "Claude Code"
    }

    private func window(_ value: WindowDisplayDescriptor) -> String {
        switch value {
        case .standard(.fiveHour): "Five-hour"
        case .standard(.weekly): "Weekly"
        case .additional(let label?, _): label
        case .additional(nil, let minutes?): "\(minutes)-minute window"
        case .additional: "Additional window"
        }
    }

    private func isStale(
        _ state: ResetActivityAttributes.ContentState, systemStale: Bool
    ) -> Bool {
        systemStale || state.sourceState != .reporting
    }

    @ViewBuilder
    private func countdown(_ resetsAt: Date) -> some View {
        if resetsAt > .now {
            Text(timerInterval: Date.now...resetsAt, countsDown: true)
        } else {
            Text("0:00")
        }
    }
}
