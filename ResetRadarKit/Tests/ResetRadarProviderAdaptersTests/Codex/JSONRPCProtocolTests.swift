import Foundation
import ResetRadarProviderAdapters
import Testing

@Suite("Codex JSON-RPC protocol")
struct JSONRPCProtocolTests {
    @Test("request IDs are positive, monotonic, and stop at the JavaScript-safe maximum")
    func requestIDs() throws {
        var ordinary = JSONRPCIDSequence()
        #expect(try ordinary.next() == 1)
        #expect(try ordinary.next() == 2)

        var ending = JSONRPCIDSequence(startingAt: JSONRPCIDSequence.maximum)
        #expect(try ending.next() == JSONRPCIDSequence.maximum)
        #expect(throws: JSONRPCProtocolError.requestIDExhausted) { try ending.next() }
    }

    @Test("decodes one valid result or error and routes only the allowlisted notification")
    func validMessages() throws {
        #expect(
            try decode("{\"id\":1,\"result\":{\"platformFamily\":\"unix\"}}")
                == .response(id: 1, result: .object(["platformFamily": .string("unix")])))
        #expect(
            try decode("{\"id\":2,\"error\":{\"code\":-32603}}")
                == .error(id: 2, code: -32603))
        #expect(
            try decode("{\"method\":\"account/rateLimits/updated\",\"params\":{}}")
                == .rateLimitsUpdated)
        #expect(
            try decode("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}")
                == .response(id: 1, result: .object(["ok": .boolean(true)])))
        #expect(
            try decode(
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"ignored\"}}"
            )
                == .error(id: 2, code: -32603))
        #expect(
            try decode(
                "{\"jsonrpc\":\"2.0\",\"method\":\"account/rateLimits/updated\",\"params\":{}}")
                == .rateLimitsUpdated)
        #expect(
            try decode("{\"jsonrpc\":\"2.0\",\"method\":\"future/notification\",\"params\":{}}")
                == .ignoredNotification)
    }

    @Test("rejects mixed envelopes, server requests, invalid versions, and unsafe IDs")
    func invalidMessages() {
        for message in [
            "{\"jsonrpc\":\"1.0\",\"id\":1,\"result\":{}}",
            "{\"jsonrpc\":null,\"id\":1,\"result\":{}}",
            "{\"id\":1,\"result\":{},\"error\":{\"code\":-1}}",
            "{\"id\":1,\"method\":\"server/request\",\"params\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{},\"error\":{\"code\":-1}}",
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/request\",\"params\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":9007199254740992,\"result\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"result\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":1}",
        ] {
            #expect(throws: JSONRPCProtocolError.invalidEnvelope) { try decode(message) }
        }
    }

    @Test("duplicate keys fail before semantic decoding")
    func duplicateKeys() {
        #expect(throws: JSONPreflightError.duplicateObjectKey) {
            try decode("{\"jsonrpc\":\"2.0\",\"id\":1,\"id\":2,\"result\":{}}")
        }
    }

    @Test("encodes only allowlisted requests and initialized notification with a newline")
    func encoding() throws {
        let request = try JSONRPCMessageEncoder.request(
            id: 4, method: .accountRead,
            params: .object(["refreshToken": .boolean(false)]))
        #expect(request.last == UInt8(ascii: "\n"))
        let decoded = try JSONSerialization.jsonObject(with: request.dropLast()) as? [String: Any]
        #expect(decoded?["method"] as? String == "account/read")
        #expect((decoded?["params"] as? [String: Any])?["refreshToken"] as? Bool == false)

        let initialized = try JSONRPCMessageEncoder.initialized()
        #expect(initialized.last == UInt8(ascii: "\n"))
        #expect(String(bytes: initialized, encoding: .utf8)?.contains("initialized") == true)
    }

    private func decode(_ string: String) throws -> JSONRPCDecodedMessage {
        try JSONRPCMessageDecoder.decode(Data(string.utf8))
    }
}
