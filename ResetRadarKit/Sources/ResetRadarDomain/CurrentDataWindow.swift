import Foundation

public enum CurrentDataWindow {
    /// Both product windows are confirmed by owner-present source calibration.
    /// The one place to edit.
    public static func seconds(for product: ProductID) -> TimeInterval {
        switch product {
        case .codex: 900
        case .claudeCode: 3_600
        }
    }
}
