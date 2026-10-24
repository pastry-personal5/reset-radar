import Foundation
import ResetRadarProviderAdapters
import Testing

@Suite("Bounded Codex RPC input")
struct BoundedRPCFrameTests {
    @Test("splits LF and CRLF frames at every byte boundary")
    func framingBoundaries() throws {
        let input = Data("{\"a\":1}\r\n\n[true]\n".utf8)
        for split in 0...input.count {
            var reader = BoundedRPCFrame(maximumPayloadBytes: 16)
            var frames = try reader.consume(input.prefix(split))
            frames += try reader.consume(input.dropFirst(split))
            try reader.finish()
            #expect(frames == [Data("{\"a\":1}".utf8), Data("[true]".utf8)])
        }
    }

    @Test("counts payload bytes without LF or an immediately preceding CR")
    func exactFrameBound() throws {
        var lineFeedReader = BoundedRPCFrame(maximumPayloadBytes: 3)
        #expect(try lineFeedReader.consume(Data("abc\n".utf8)) == [Data("abc".utf8)])

        var crlf = BoundedRPCFrame(maximumPayloadBytes: 3)
        #expect(try crlf.consume(Data("abc\r".utf8)).isEmpty)
        #expect(try crlf.consume(Data("\n".utf8)) == [Data("abc".utf8)])

        var standaloneCR = BoundedRPCFrame(maximumPayloadBytes: 3)
        _ = try standaloneCR.consume(Data("abc\r".utf8))
        #expect(throws: RPCFrameError.payloadTooLarge) {
            try standaloneCR.consume(Data("x".utf8))
        }
    }

    @Test("rejects delivered and unterminated oversized payloads before decode")
    func rejectsOversized() throws {
        var delivered = BoundedRPCFrame(maximumPayloadBytes: 3)
        #expect(throws: RPCFrameError.payloadTooLarge) {
            try delivered.consume(Data("abcd\n".utf8))
        }
        var unterminated = BoundedRPCFrame(maximumPayloadBytes: 3)
        #expect(throws: RPCFrameError.payloadTooLarge) {
            try unterminated.consume(Data("abcd".utf8))
        }
        var eof = BoundedRPCFrame(maximumPayloadBytes: 3)
        _ = try eof.consume(Data("abc".utf8))
        #expect(throws: RPCFrameError.unterminatedPayload) { try eof.finish() }
    }

    @Test("preflight rejects malformed input, duplicate decoded keys, and excessive nesting")
    func rejectsStructure() throws {
        #expect(throws: JSONPreflightError.malformed) {
            try JSONStructuralPreflight.validate(Data([0xff]))
        }
        #expect(throws: JSONPreflightError.malformed) {
            try JSONStructuralPreflight.validate(Data("{\"a\":}".utf8))
        }
        #expect(throws: JSONPreflightError.duplicateObjectKey) {
            try JSONStructuralPreflight.validate(Data("{\"a\":1,\"\\u0061\":2}".utf8))
        }
        #expect(throws: JSONPreflightError.nestingTooDeep) {
            try JSONStructuralPreflight.validate(
                Data("[[[0]]]".utf8), maximumNestingDepth: 2)
        }
    }

    @Test("preflight measures decoded UTF-8 for keys and values")
    func decodedStringBytes() throws {
        try JSONStructuralPreflight.validate(
            Data("{\"é\":\"\\u00e9\"}".utf8), maximumStringBytes: 2)
        #expect(throws: JSONPreflightError.stringTooLarge) {
            try JSONStructuralPreflight.validate(
                Data("{\"é\":true}".utf8), maximumStringBytes: 1)
        }
        #expect(throws: JSONPreflightError.stringTooLarge) {
            try JSONStructuralPreflight.validate(
                Data("{\"a\":\"\\ud83d\\ude00\"}".utf8), maximumStringBytes: 3)
        }
    }
}
