import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .boolean(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public enum JSONRPCProtocolError: Error, Equatable, Sendable {
    case invalidEnvelope
    case requestIDExhausted
}

public struct JSONRPCIDSequence: Sendable {
    public static let maximum: Int64 = 9_007_199_254_740_991
    private var nextValue: Int64

    public init(startingAt: Int64 = 1) {
        self.nextValue = startingAt
    }

    public mutating func next() throws(JSONRPCProtocolError) -> Int64 {
        guard (1...Self.maximum).contains(nextValue) else { throw .requestIDExhausted }
        let value = nextValue
        nextValue = value == Self.maximum ? Self.maximum + Int64(1) : value + Int64(1)
        return value
    }
}

public enum JSONRPCDecodedMessage: Equatable, Sendable {
    case response(id: Int64, result: JSONValue)
    case error(id: Int64, code: Int64)
    case rateLimitsUpdated
    case ignoredNotification
}

public enum JSONRPCMessageDecoder {
    public static func decode(_ data: Data) throws -> JSONRPCDecodedMessage {
        try JSONStructuralPreflight.validate(data)
        let object: [String: JSONValue]
        do {
            object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            throw JSONRPCProtocolError.invalidEnvelope
        }
        guard object["jsonrpc"] == .string("2.0") else {
            throw JSONRPCProtocolError.invalidEnvelope
        }
        if let method = object["method"] {
            return try decodeNotification(object, method: method)
        }
        return try decodeResponse(object)
    }

    private static func decodeNotification(
        _ object: [String: JSONValue], method: JSONValue
    ) throws -> JSONRPCDecodedMessage {
        guard object["id"] == nil, object["result"] == nil, object["error"] == nil,
            case .string(let methodName) = method
        else { throw JSONRPCProtocolError.invalidEnvelope }
        return methodName == "account/rateLimits/updated"
            ? .rateLimitsUpdated : .ignoredNotification
    }

    private static func decodeResponse(
        _ object: [String: JSONValue]
    ) throws -> JSONRPCDecodedMessage {
        guard case .integer(let id) = object["id"], (1...JSONRPCIDSequence.maximum).contains(id)
        else { throw JSONRPCProtocolError.invalidEnvelope }
        let result = object["result"]
        let error = object["error"]
        guard (result == nil) != (error == nil) else { throw JSONRPCProtocolError.invalidEnvelope }
        if let result { return .response(id: id, result: result) }
        guard case .object(let errorObject) = error,
            case .integer(let code) = errorObject["code"]
        else { throw JSONRPCProtocolError.invalidEnvelope }
        return .error(id: id, code: code)
    }
}

public enum JSONRPCMethod: String, Sendable {
    case initialize
    case accountRead = "account/read"
    case accountRateLimitsRead = "account/rateLimits/read"
}

public enum JSONRPCMessageEncoder {
    public static func request(id: Int64, method: JSONRPCMethod, params: JSONValue) throws -> Data {
        guard (1...JSONRPCIDSequence.maximum).contains(id) else {
            throw JSONRPCProtocolError.invalidEnvelope
        }
        return try encode([
            "jsonrpc": .string("2.0"), "id": .integer(id),
            "method": .string(method.rawValue), "params": params,
        ])
    }

    public static func initialized() throws -> Data {
        try encode(["jsonrpc": .string("2.0"), "method": .string("initialized")])
    }

    private static func encode(_ object: [String: JSONValue]) throws -> Data {
        var data = try JSONEncoder().encode(object)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
