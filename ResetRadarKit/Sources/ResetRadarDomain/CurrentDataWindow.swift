import Foundation

public enum CurrentDataWindow {
    /// Candidate constants until source calibration confirms them; the one place to edit.
    public static func seconds(for product: ProductID) -> TimeInterval {
        switch product {
        case .codex: 900
        case .claudeCode: 3_600
        }
    }
}
