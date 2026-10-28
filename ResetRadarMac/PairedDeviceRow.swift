import AppKit
import ResetRadarApplication
import SwiftUI

struct PairedDeviceRow: View {
    let entry: RosterEntry
    let revoke: () -> Void
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName).font(.body.weight(.medium))
                Text(entry.shortID).font(.caption.monospaced()).foregroundStyle(.secondary)
                Label(statusText, systemImage: symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                if let date = entry.date, let label = entry.dateLabel {
                    Text("\(label) \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if case .missingOnRelay = entry.status {
                    Text("This reader was removed from the relay elsewhere.")
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
        .accessibilityElement(children: .contain)
        .confirmationDialog("Revoke \(displayName)?", isPresented: $confirming) {
            Button("Revoke", role: .destructive, action: revoke)
        } message: {
            Text("Reader \(entry.shortID) will no longer receive updates.")
        }
    }

    private var displayName: String {
        if case .pending = entry.status { return "Awaiting iPhone or iPad" }
        return entry.name ?? "iPhone or iPad"
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
        case .activated: Color(nsColor: .systemGreen)
        case .pending: Color(nsColor: .systemOrange)
        case .missingOnRelay: Color(nsColor: .systemRed)
        case .unknownOnThisMac: Color(nsColor: .secondaryLabelColor)
        }
    }
}
