import Foundation

public enum CurrentDataWindow {
    /// Codex is calibration-confirmed; Claude Code stays a candidate until its calibration.
    /// The one place to edit.
    public static func seconds(for product: ProductID) -> TimeInterval {
        switch product {
        case .codex: 900
        case .claudeCode: 3_600
        }
    }
}
