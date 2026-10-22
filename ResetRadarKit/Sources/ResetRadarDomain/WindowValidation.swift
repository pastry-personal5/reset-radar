import Foundation

public enum WindowValidation {
    /// Validates each window independently. Invalid windows are dropped with a redacted
    /// diagnostic, windows of an unknown product are ignored with a diagnostic, and a duplicate
    /// `WindowID` keeps the first. The offending values never reach a diagnostic.
    public static func validate(_ windows: [RawWindow], now: Date) -> (
        valid: [AllowanceWindow], diagnostics: [DiagnosticEvent]
    ) {
        var valid: [AllowanceWindow] = []
        var seen: Set<WindowID> = []
        var diagnostics: [DiagnosticEvent] = []
        for raw in windows {
            do {
                let window = try AllowanceWindow(validating: raw)
                if seen.insert(window.id).inserted {
                    valid.append(window)
                } else {
                    diagnostics.append(.duplicateWindow(product: window.product, at: now))
                }
            } catch {
                diagnostics.append(
                    error == .unknownProduct
                        ? .unknownProduct(at: now)
                        : .invalidWindow(
                            error.category, product: ProductID(rawValue: raw.product), at: now))
            }
        }
        return (valid, diagnostics)
    }
}
