import ResetRadarDomain
import SwiftUI

/// The Allowance Ring: fills from 0% toward 100% used, shows no value when unavailable or
/// waiting, and gives every state a symbol as well as color.
public struct AllowanceRing: View {
    let display: AllowanceDisplay
    let caption: String?
    let diameter: CGFloat
    let emphasized: Bool

    public init(
        display: AllowanceDisplay, caption: String? = nil, diameter: CGFloat = 62,
        emphasized: Bool = false
    ) {
        self.display = display
        self.caption = caption
        self.diameter = diameter
        self.emphasized = emphasized
    }

    public var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.24), lineWidth: lineWidth)
                if let fill = display.fill {
                    Circle()
                        .trim(from: 0, to: fill)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(display.percentText ?? "—")
                        .font(.system(size: diameter * 0.23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if display.state != .current {
                        Image(systemName: display.symbolName)
                            .font(.system(size: diameter * 0.16, weight: .semibold))
                    }
                }
                .foregroundStyle(tint)
                .padding(lineWidth)
            }
            .frame(width: diameter, height: diameter)
            .overlay {
                if emphasized {
                    Circle().stroke(Color.accentColor, lineWidth: 2).padding(-5)
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var lineWidth: CGFloat { max(4, diameter * 0.09) }

    private var tint: Color {
        switch display.state {
        case .current: .accentColor
        case .stale: .orange
        case .resetAwaitingRefresh, .unavailable: .secondary
        }
    }
}

/// Text and a symbol for one state, so color never carries it alone.
public struct StateBadge: View {
    let text: String
    let symbolName: String

    public init(text: String, symbolName: String) {
        self.text = text
        self.symbolName = symbolName
    }

    public init(display: AllowanceDisplay) {
        self.init(text: display.statusText, symbolName: display.symbolName)
    }

    public var body: some View {
        Label(text, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
