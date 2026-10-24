import Foundation

public enum ComposeRecordError: Error, Equatable, Sendable {
    case incompatible
    case unsafeLocation
    case unavailable
}

/// `statusline-compose.json`: only the resolved executable path, never a shell string.
public struct ComposeRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let fileName = "statusline-compose.json"

    public let executablePath: String

    public init?(executablePath: String) {
        guard executablePath.hasPrefix("/"), !executablePath.contains("\0"),
            executablePath.utf8.count <= 4_096
        else { return nil }
        self.executablePath = executablePath
    }
}

private struct WireCompose: Codable {
    let schemaVersion: Int
    let executablePath: String

    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, executablePath }

    init(_ record: ComposeRecord) {
        schemaVersion = ComposeRecord.currentSchemaVersion
        executablePath = record.executablePath
    }

    init(from decoder: any Decoder) throws {
        let present = Set(
            try decoder.container(keyedBy: AnyCodingKey.self).allKeys.map(\.stringValue))
        guard present == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw ComposeRecordError.incompatible
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        executablePath = try container.decode(String.self, forKey: .executablePath)
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Owner-only persistence of the compose record inside the Reset Radar support directory.
public struct ComposeRecordStore: Sendable {
    private let files: OwnerOnlyConfigurationFiles

    public init(rootDirectory: URL) {
        files = OwnerOnlyConfigurationFiles(
            directoryURL: rootDirectory, maximumBytes: StatusLineLimits.maximumRecordBytes,
            lockTimeout: StatusLineLimits.lockTimeout)
    }

    /// nil when no executable is composed.
    public func load() throws -> ComposeRecord? {
        let data: Data
        do {
            data = try files.read(named: ComposeRecord.fileName)
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            return nil
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        }
        do {
            try JSONStructuralPreflight.validate(data)
            let wire = try JSONDecoder().decode(WireCompose.self, from: data)
            guard wire.schemaVersion == ComposeRecord.currentSchemaVersion,
                let record = ComposeRecord(executablePath: wire.executablePath)
            else { throw ComposeRecordError.incompatible }
            return record
        } catch {
            throw ComposeRecordError.incompatible
        }
    }

    public func save(_ record: ComposeRecord) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try files.withLock {
                try files.write(
                    try encoder.encode(WireCompose(record)), named: ComposeRecord.fileName)
            }
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        } catch {
            throw ComposeRecordError.unavailable
        }
    }

    public func remove() throws {
        do {
            try files.withLock {
                do {
                    try files.remove(named: ComposeRecord.fileName)
                } catch ProviderAccountCatalogStoreError.accountNotFound {
                    return
                }
            }
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: ProviderAccountCatalogStoreError) -> ComposeRecordError {
        switch error {
        case .unsafeLocation: .unsafeLocation
        case .incompatibleConfiguration: .incompatible
        default: .unavailable
        }
    }
}
