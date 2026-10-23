import Foundation
import Testing

@testable import ResetRadarTransport

private func streamedBytes(count: Int) -> AsyncStream<UInt8> {
    AsyncStream { continuation in
        for _ in 0..<count { continuation.yield(0x41) }
        continuation.finish()
    }
}

@Test func readerEnforcesBothResponseCapsOnDeliveredBytes() async throws {
    let small = try await BoundedBodyReader.read(
        streamedBytes(count: 4_096), maximumBytes: 4_096)
    #expect(small.count == 4_096)
    do {
        _ = try await BoundedBodyReader.read(
            streamedBytes(count: 4_097), maximumBytes: 4_096)
        Issue.record("Expected a 4 KiB body rejection")
    } catch BodyLimitError.tooLarge {
    } catch {
        Issue.record("Unexpected body read error")
    }
    let snapshot = try await BoundedBodyReader.read(
        streamedBytes(count: 65_536), maximumBytes: 65_536)
    #expect(snapshot.count == 65_536)
    do {
        _ = try await BoundedBodyReader.read(
            streamedBytes(count: 65_537), maximumBytes: 65_536)
        Issue.record("Expected a 64 KiB body rejection")
    } catch BodyLimitError.tooLarge {
    } catch {
        Issue.record("Unexpected body read error")
    }
}
