import ResetRadarApplication
import ResetRadarUI
import SwiftUI
import VisionKit

/// Pairing & Sync: the reader relationship, Pair Mac by QR scan or owner-initiated paste,
/// activation and cleanup recovery, honest Watch Erasure Status on iPhone, and Forget Mac.
struct PairingSyncView: View {
    @ObservedObject var environment: ReaderEnvironment
    @State private var packageText = ""
    @State private var scanning = false
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: PairingSyncText.status(environment.pairing))
                    .accessibilityIdentifier("pairing.status")
                if environment.pairing?.state == .paired {
                    LabeledContent(
                        "Sync", value: ReaderVocabulary.transport(environment.details.transport))
                }
            }
            if PairingSyncText.acceptsPairingPackage(environment.pairing) {
                pairMac
            }
            if environment.pairing?.state == .awaitingActivation {
                Section {
                    Text(
                        "Pairing is saved on this device. Reset Radar retries the relay "
                            + "confirmation whenever it opens; usage stays hidden until then.")
                    Button("Retry Confirmation") { Task { await environment.retryActivation() } }
                }
            }
            if environment.pairing?.cleanupPending == true {
                Section {
                    Text(
                        "Forget Mac did not finish removing this device’s pairing secrets. Old "
                            + "usage stays hidden and a new pairing waits until cleanup finishes.")
                    Button("Retry Cleanup") { Task { await environment.retryCleanup() } }
                        .accessibilityIdentifier("pairing.retryCleanup")
                } header: {
                    Text("Local Cleanup Pending")
                }
            }
            if environment.hasWatchStage, let erase = environment.pairing?.watchErase {
                Section("Apple Watch") {
                    Text(PairingSyncText.watchErasure(erase))
                        .accessibilityIdentifier("pairing.watchErasure")
                }
            }
            messages
            if PairingSyncText.offersForgetMac(environment.pairing) {
                Section {
                    Button("Forget Mac", role: .destructive) { confirmForget = true }
                        .accessibilityIdentifier("pairing.forgetMac")
                } footer: {
                    Text(
                        "Forget Mac erases this device’s pairing and cached usage. It does not "
                            + "revoke this reader on the Collector Mac; revoke it there.")
                }
            }
        }
        .navigationTitle("Pairing & Sync")
        .confirmationDialog(
            "Forget the Collector Mac?", isPresented: $confirmForget, titleVisibility: .visible
        ) {
            Button("Forget Mac", role: .destructive) { Task { await environment.forget() } }
        } message: {
            Text(
                environment.hasWatchStage
                    ? "This device’s pairing and cached usage are erased. A paired Watch may keep "
                        + "its cache until it reconnects."
                    : "This device’s pairing and cached usage are erased.")
        }
        .sheet(isPresented: $scanning) {
            PairingScannerView(
                onCode: { code in
                    scanning = false
                    environment.previewPairing(code)
                },
                onUnavailable: {
                    scanning = false
                    environment.reportCameraUnavailable()
                })
        }
        .onDisappear {
            packageText = ""
            if case .confirm = environment.pairingStep { environment.cancelPairing() }
        }
    }

    @ViewBuilder private var pairMac: some View {
        Section {
            switch environment.pairingStep {
            case .entry:
                Button("Scan Pairing QR Code", systemImage: "qrcode.viewfinder") { startScan() }
                TextField("Paste Pairing Package", text: $packageText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .lineLimit(3)
                    .accessibilityIdentifier("pairing.package")
                Button("Review Pairing Package") {
                    let text = packageText
                    packageText = ""
                    environment.previewPairing(text)
                }
                .disabled(packageText.isEmpty)
                .accessibilityIdentifier("pairing.review")
            case .confirm(let code):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pairing Confirmation Code").font(.subheadline)
                    Text(code)
                        .font(.title2.monospaced().weight(.semibold))
                        .accessibilityIdentifier("pairing.confirmationCode")
                    Text("Confirm only if the Collector Mac shows exactly this code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Confirm Pairing") { Task { await environment.confirmPairing() } }
                    .accessibilityIdentifier("pairing.confirm")
                Button("Cancel", role: .cancel) { environment.cancelPairing() }
            case .saving:
                ProgressView("Saving and confirming…")
            }
        } header: {
            Text("Pair Mac")
        } footer: {
            Text(
                "Scan the QR code or paste the Pairing Package shown in the Collector Mac’s Relay "
                    + "& Pairing settings. It carries Reset Radar secrets, never provider "
                    + "credentials.")
        }
    }

    @ViewBuilder private var messages: some View {
        if let message = environment.pairingMessage {
            Section { Text(message).accessibilityIdentifier("pairing.message") }
        }
        if let message = environment.forgetMessage {
            Section { Text(message).accessibilityIdentifier("pairing.forgetMessage") }
        }
    }

    /// Camera access is requested only here, by the scanner itself; paste stays available.
    private func startScan() {
        if DataScannerViewController.isSupported {
            scanning = true
        } else {
            environment.reportCameraUnavailable()
        }
    }
}
