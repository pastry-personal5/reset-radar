import ResetRadarApplication
import SwiftUI

struct PairedDeviceRow: View {
    let entry: RosterEntry
    let revoke: () -> Void
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name ?? fallbackName).font(.body.weight(.medium))
                Text(entry.shortID).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(statusText).font(.caption).foregroundStyle(color)
                if let date = entry.date, let label = entry.dateLabel {
                    Text("\(label) \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if entry.profileUnavailable {
                    Label("Profile unavailable", systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Revoke", role: .destructive) { confirming = true }
        }
        .confirmationDialog("Revoke this reader?", isPresented: $confirming) {
            Button("Revoke", role: .destructive, action: revoke)
        }
    }

    private var fallbackName: String {
        if case .pending = entry.status { return "Awaiting iPhone or iPad" }
        return "iPhone or iPad"
    }

    private var statusText: String {
        switch entry.status {
        case .activated: "Active"
        case .pending: "Awaiting"
        case .missingOnRelay: "Missing on relay"
        case .unknownOnThisMac: "Unknown on this Mac"
        }
    }

    private var symbol: String {
        switch entry.status {
        case .activated: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .missingOnRelay: "exclamationmark.triangle.fill"
        case .unknownOnThisMac: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch entry.status {
        case .activated: .green
        case .pending: .orange
        case .missingOnRelay: .red
        case .unknownOnThisMac: .secondary
        }
    }
}
