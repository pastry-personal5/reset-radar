import Foundation
import Testing

@testable import ResetRadarDomain

// DiagnosticEvent has no initializer, factory, or stored property of type String; that absence
// is a compile-time property of the type and is not tested here.
@Suite struct DiagnosticEventTests {
    static let events: [DiagnosticEvent] = [
        .invalidWindow(.invalidPercentage, product: .codex, at: at(0)),
        .unknownProduct(at: at(0)),
        .duplicateWindow(accountID: claudeAccountID, product: .claudeCode, at: at(0)),
        .ambiguousAccountWindow(codexWeekly, product: .codex, at: at(0)),
        .invalidHeartbeat(at: at(0)),
        .unsupportedSchema(found: 9, supported: 1...1, at: at(0)),
        .publicationStopped(httpStatusClass: 4, lastSequence: 7, at: at(0)),
        .envelopeTooLarge(sequence: 8, at: at(0)),
        .secretsUnavailable(at: at(0)),
        .relayFailure(status: .quotaLimited, httpStatusClass: 5, at: at(0)),
    ]

    @Test func roundTrips() throws {
        let data = try WireCoding.encoder().encode(Self.events)
        #expect(try WireCoding.decoder().decode([DiagnosticEvent].self, from: data) == Self.events)
    }

    @Test func encodedValuesAreEnumsNumbersAndDates() throws {
        let allowed = Set(
            DiagnosticEvent.Category.allCases.map(\.rawValue) + ProductID.allCases.map(\.rawValue)
                + TransportStatus.allCases.map(\.rawValue) + [
                    codexAccountID.hex,
                    claudeAccountID.hex,
                    try wire([at(0)])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]\"")),
                ])
        for event in Self.events {
            let object = try #require(
                JSONSerialization.jsonObject(with: WireCoding.encoder().encode(event))
                    as? [String: Any])
            for (key, value) in object {
                if let text = value as? String { #expect(allowed.contains(text), "\(key)=\(text)") }
            }
        }
    }
}

@Suite struct NewDiagnosticFactoryTests {
    @Test func factoriesCarryOnlyEnumsNumbersAndDates() {
        let stopped = DiagnosticEvent.publicationStopped(
            httpStatusClass: 4, lastSequence: 9, at: at(0))
        #expect(stopped.category == .publicationStopped)
        #expect(stopped.httpStatusClass == 4 && stopped.lastSequence == 9)
        let large = DiagnosticEvent.envelopeTooLarge(sequence: 3, at: at(1))
        #expect(large.category == .envelopeTooLarge && large.lastSequence == 3)
        #expect(
            DiagnosticEvent.secretsUnavailable(at: at(2)).transportStatus == .secretsUnavailable)
        let failure = DiagnosticEvent.relayFailure(
            status: .offline, httpStatusClass: nil, at: at(3))
        #expect(failure.category == .relayFailure && failure.transportStatus == .offline)
    }
}
