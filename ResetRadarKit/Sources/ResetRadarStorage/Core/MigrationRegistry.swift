import Foundation

/// Schema migrations, one version at a time. `steps[v]` turns a version `v` payload into a
/// version `v + 1` payload.
public struct MigrationRegistry: Sendable {
    public typealias Step = @Sendable (Data) throws -> Data

    private let steps: [Int: Step]

    public init(steps: [Int: Step] = [:]) {
        self.steps = steps
    }

    /// Runs every step from `start` up to `end`. A missing step is `incompatible`; a throwing step
    /// is `corrupt`. Nothing is written here, so a failure leaves the stored file as it was.
    public func migrate(_ payload: Data, from start: Int, to end: Int) throws -> Data {
        guard start <= end else { throw StorageError.incompatible(foundVersion: start) }
        var current = payload
        for version in start..<end {
            guard let step = steps[version] else {
                throw StorageError.incompatible(foundVersion: start)
            }
            do {
                current = try step(current)
            } catch {
                throw StorageError.corrupt
            }
        }
        return current
    }
}
