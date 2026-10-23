/// A storage failure. `io` carries an errno-style number and never a path, so an error cannot
/// leak where the owner keeps their data.
public enum StorageError: Error, Equatable, Sendable {
    /// Undecodable or invalid content. The file was moved aside, or left untouched when a
    /// migration rejected it.
    case corrupt
    /// An unknown mandatory schema version. The file is left untouched.
    case incompatible(foundVersion: Int)
    case tooLarge
    case lockTimeout
    // swiftlint:disable:next identifier_name
    case io(code: Int)
}
