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
    case tooManyCodexAccounts
    case tooManyClaudeCodeAccounts
}

/// The complete bounded account catalog carried by a schema-2 snapshot.
public struct AccountCatalog: Codable, Hashable, Sendable {
    public static let maximumCodexAccounts = 2
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
        guard accounts.count(where: { $0.product == .codex }) <= Self.maximumCodexAccounts else {
            throw .tooManyCodexAccounts
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
