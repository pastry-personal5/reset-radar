import Foundation

public enum AccountAliasError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case unsafeScalar
    case noVisibleContent
}

/// A Mac-authored account alias that preserves its exact accepted Unicode spelling.
public struct AccountAlias: Codable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 32
    public let value: String

    public init(validating value: String) throws(AccountAliasError) {
        guard !value.isEmpty else { throw .empty }
        guard value.utf8.count <= Self.maximumUTF8Bytes else { throw .tooLong }
        var hasVisibleContent = false
        for scalar in value.unicodeScalars {
            if scalar.value == 0x20 { continue }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
                .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation, .mathSymbol,
                .currencySymbol, .modifierSymbol, .otherSymbol:
                hasVisibleContent = true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                break
            default:
                throw .unsafeScalar
            }
        }
        guard hasVisibleContent else { throw .noVisibleContent }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid account alias")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct AccountMetadata: Codable, Hashable, Sendable {
    public let id: AccountID
    public let product: ProductID
    public let number: Int
    public let alias: AccountAlias?

    public var defaultDisplayLabel: String { "Account #\(number)" }
    public var effectiveDisplayLabel: String { alias?.value ?? defaultDisplayLabel }

    public init(id: AccountID, product: ProductID, number: Int, alias: AccountAlias? = nil) {
        self.id = id
        self.product = product
        self.number = number
        self.alias = alias
    }

    public func replacingAlias(_ alias: AccountAlias?) -> AccountMetadata {
        AccountMetadata(id: id, product: product, number: number, alias: alias)
    }
}

public enum AccountCatalogError: Error, Equatable, Sendable {
    case duplicateID
    case duplicateNumber
    case duplicateDisplayLabel
    case invalidNumber
    /// Retained for binary compatibility. Catalog validation no longer emits this case.
    case tooManyCodexAccounts
    case tooManyClaudeCodeAccounts
}

/// The complete bounded account catalog carried by a schema-2 snapshot.
public struct AccountCatalog: Codable, Hashable, Sendable {
    public static let maximumClaudeCodeAccounts = 1
    public let accounts: [AccountMetadata]

    public init(validating accounts: [AccountMetadata]) throws(AccountCatalogError) {
        guard accounts.allSatisfy({ $0.number > 0 }) else { throw .invalidNumber }
        guard Set(accounts.map(\.id)).count == accounts.count else { throw .duplicateID }
        guard Set(accounts.map(\.number)).count == accounts.count else { throw .duplicateNumber }
        guard Set(accounts.map { Array($0.effectiveDisplayLabel.utf8) }).count == accounts.count
        else {
            throw .duplicateDisplayLabel
        }
        guard
            accounts.count(where: { $0.product == .claudeCode })
                <= Self.maximumClaudeCodeAccounts
        else {
            throw .tooManyClaudeCodeAccounts
        }
        self.accounts = accounts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let accounts = try container.decode([AccountMetadata].self)
        do {
            try self.init(validating: accounts)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid account catalog")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(accounts)
    }

    public var smallestUnusedNumber: Int {
        let used = Set(accounts.map(\.number))
        return (1...).first(where: { !used.contains($0) }) ?? 1
    }

    public func account(id: AccountID) -> AccountMetadata? {
        accounts.first { $0.id == id }
    }
}

public enum ReaderProfileNameError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case unsafeScalar
    case noVisibleContent
}

/// A reader-authored, visible Unicode device label. Duplicate labels are valid; Reader ID is
/// the identity.
public struct ReaderProfileName: Codable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 64
    public let value: String

    public init(validating value: String) throws(ReaderProfileNameError) {
        guard !value.isEmpty else { throw .empty }
        guard value.utf8.count <= Self.maximumUTF8Bytes else { throw .tooLong }
        var hasVisibleContent = false
        for scalar in value.unicodeScalars {
            if scalar.value == 0x20 { continue }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
                .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation, .mathSymbol,
                .currencySymbol, .modifierSymbol, .otherSymbol:
                hasVisibleContent = true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                break
            default:
                throw .unsafeScalar
            }
        }
        guard hasVisibleContent else { throw .noVisibleContent }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid reader profile name")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public enum ReaderDeviceClass: String, Codable, Sendable, CaseIterable {
    case phone
    case tablet
}

public enum ReaderNamingMode: String, Codable, Sendable {
    case automatic
    case custom
}

public struct ReaderProfile: Codable, Sendable, Equatable {
    public let profileVersion: Int
    public let displayName: ReaderProfileName
    public let deviceClass: ReaderDeviceClass

    public init(displayName: ReaderProfileName, deviceClass: ReaderDeviceClass) {
        profileVersion = 1
        self.displayName = displayName
        self.deviceClass = deviceClass
    }
}

public struct ReaderProfileHeader: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let profileVersion: Int
    public let publisherID: PublisherID
    public let readerID: ReaderID
    public let keyVersion: Int
    public let revision: UInt64

    public init(
        publisherID: PublisherID, readerID: ReaderID, keyVersion: Int, revision: UInt64
    ) {
        protocolVersion = 2
        profileVersion = 1
        self.publisherID = publisherID
        self.readerID = readerID
        self.keyVersion = keyVersion
        self.revision = revision
    }
}

/// Opaque at the relay: the two user-readable fields exist only inside the ciphertext.
public struct ReaderProfileEnvelope: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let profileVersion: Int
    public let publisherID: PublisherID
    public let readerID: ReaderID
    public let keyVersion: Int
    public let revision: UInt64
    public let nonce: String
    public let ciphertext: String
    public let tag: String

    public var header: ReaderProfileHeader {
        ReaderProfileHeader(
            publisherID: publisherID, readerID: readerID, keyVersion: keyVersion,
            revision: revision)
    }

    public init(
        header: ReaderProfileHeader, nonce: String, ciphertext: String, tag: String
    ) {
        protocolVersion = header.protocolVersion
        profileVersion = header.profileVersion
        publisherID = header.publisherID
        readerID = header.readerID
        keyVersion = header.keyVersion
        revision = header.revision
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}
