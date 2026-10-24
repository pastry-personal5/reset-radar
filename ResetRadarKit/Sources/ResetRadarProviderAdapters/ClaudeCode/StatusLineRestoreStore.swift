import Foundation

public enum StatusLineRestoreError: Error, Equatable, Sendable {
    case incompatible
    case unsafeLocation
    case unavailable
}

/// The only prior-state copy Reset Radar keeps: an absence marker or the safely parsed prior
/// command, the exact values it installed, and transaction metadata. No sibling field and no
/// settings document is ever stored here.
public struct StatusLineRestoreRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let fileName = "claude-statusline-restore.json"

    public enum Prior: Equatable, Sendable {
        case absent
        case command(String)
    }

    public enum State: String, Equatable, Sendable {
        case pending
        case installed
    }

    public let prior: Prior
    public let installedCommand: String
    public let transactionID: UUID
    public let createdAt: Date
    public var state: State

    public init(
        prior: Prior, installedCommand: String, transactionID: UUID, createdAt: Date,
        state: State
    ) {
        self.prior = prior
        self.installedCommand = installedCommand
        self.transactionID = transactionID
        self.createdAt = createdAt
        self.state = state
    }
}

private struct WireRestore: Codable {
    let schemaVersion: Int
    let priorKind: String
    let priorCommand: String?
    let installedType: String
    let installedCommand: String
    let transactionID: String
    let createdAtMs: Int64
    let state: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, priorKind, priorCommand, installedType, installedCommand
        case transactionID, createdAtMs, state
    }

    init(_ record: StatusLineRestoreRecord) {
        schemaVersion = StatusLineRestoreRecord.currentSchemaVersion
        switch record.prior {
        case .absent:
            priorKind = "absent"
            priorCommand = nil
        case .command(let command):
            priorKind = "command"
            priorCommand = command
        }
        installedType = "command"
        installedCommand = record.installedCommand
        transactionID = record.transactionID.uuidString
        createdAtMs = Int64((record.createdAt.timeIntervalSince1970 * 1_000).rounded())
        state = record.state.rawValue
    }

    init(from decoder: any Decoder) throws {
        let present = Set(
            try decoder.container(keyedBy: AnyCodingKey.self).allKeys.map(\.stringValue))
        let all = Set(CodingKeys.allCases.map(\.rawValue))
        guard present.isSubset(of: all), all.subtracting(["priorCommand"]).isSubset(of: present)
        else { throw StatusLineRestoreError.incompatible }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        priorKind = try container.decode(String.self, forKey: .priorKind)
        priorCommand = try container.decodeIfPresent(String.self, forKey: .priorCommand)
        installedType = try container.decode(String.self, forKey: .installedType)
        installedCommand = try container.decode(String.self, forKey: .installedCommand)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        createdAtMs = try container.decode(Int64.self, forKey: .createdAtMs)
        state = try container.decode(String.self, forKey: .state)
    }

    var record: StatusLineRestoreRecord? {
        guard schemaVersion == StatusLineRestoreRecord.currentSchemaVersion,
            installedType == "command", !installedCommand.isEmpty,
            let id = UUID(uuidString: transactionID), createdAtMs >= 0,
            let state = StatusLineRestoreRecord.State(rawValue: state)
        else { return nil }
        let prior: StatusLineRestoreRecord.Prior
        switch (priorKind, priorCommand) {
        case ("absent", nil): prior = .absent
        case ("command", let command?) where !command.isEmpty: prior = .command(command)
        default: return nil
        }
        return StatusLineRestoreRecord(
            prior: prior, installedCommand: installedCommand, transactionID: id,
            createdAt: Date(timeIntervalSince1970: Double(createdAtMs) / 1_000), state: state)
    }
}

/// Owner-only persistence for the status-line restore record.
public struct StatusLineRestoreStore: Sendable {
    private let files: OwnerOnlyConfigurationFiles

    public init(directory: URL) {
        files = OwnerOnlyConfigurationFiles(
            directoryURL: directory, maximumBytes: StatusLineLimits.maximumRecordBytes,
            lockTimeout: StatusLineLimits.lockTimeout)
    }

    public func load() throws -> StatusLineRestoreRecord? {
        let data: Data
        do {
            data = try files.read(named: StatusLineRestoreRecord.fileName)
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            return nil
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        }
        do {
            try JSONStructuralPreflight.validate(data)
            guard let record = try JSONDecoder().decode(WireRestore.self, from: data).record
            else { throw StatusLineRestoreError.incompatible }
            return record
        } catch {
            throw StatusLineRestoreError.incompatible
        }
    }

    public func save(_ record: StatusLineRestoreRecord) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try files.withLock {
                try files.write(
                    try encoder.encode(WireRestore(record)),
                    named: StatusLineRestoreRecord.fileName)
            }
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        } catch {
            throw StatusLineRestoreError.unavailable
        }
    }

    public func remove() throws {
        do {
            try files.withLock {
                do {
                    try files.remove(named: StatusLineRestoreRecord.fileName)
                } catch ProviderAccountCatalogStoreError.accountNotFound {
                    return
                }
            }
        } catch let error as ProviderAccountCatalogStoreError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: ProviderAccountCatalogStoreError) -> StatusLineRestoreError {
        switch error {
        case .unsafeLocation: .unsafeLocation
        case .incompatibleConfiguration: .incompatible
        default: .unavailable
        }
    }
}
