/// How a collected snapshot differs from the previous one; ordered by urgency.
public enum ChangeClass: Int, Sendable, Comparable, CaseIterable {
    /// Nothing differs.
    case none
    /// Only `observedAt` advanced.
    case observationOnly
    /// A percentage or reset instant changed.
    case material
    /// Source state, the window set, report state, or account scope changed.
    case transition

    public static func < (lhs: ChangeClass, rhs: ChangeClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
