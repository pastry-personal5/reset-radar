import Foundation
import Testing

@testable import ResetRadarDomain

// DiagnosticEvent has no initializer, factory, or stored property of type String; that absence
// is a compile-time property of the type and is not tested here.
@Suite struct DiagnosticEventTests {
    static let events: [DiagnosticEvent] = [
        .invalidWindow(.invalidPercentage, product: .codex, at: at(0)),
        .unknownProduct(at: at(0)),
        .duplicateWindow(product: .claudeCode, at: at(0)),
        .ambiguousHomeSlot(.codexWeekly, at: at(0)),
        .invalidHeartbeat(at: at(0)),
        .unsupportedSchema(found: 9, supported: 1...1, at: at(0)),
    ]

    @Test func roundTrips() throws {
        let data = try WireCoding.encoder().encode(Self.events)
        #expect(try WireCoding.decoder().decode([DiagnosticEvent].self, from: data) == Self.events)
    }

    @Test func encodedValuesAreEnumsNumbersAndDates() throws {
        let allowed = Set(
            DiagnosticEvent.Category.allCases.map(\.rawValue) + ProductID.allCases.map(\.rawValue)
                + HomeSlot.allCases.map(\.rawValue) + [
                    try wire([at(0)])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]\""))
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
