import Foundation

enum BodyLimitError: Error {
    case tooLarge
}

enum BoundedBodyReader {
    static func read<Bytes: AsyncSequence>(
        _ bytes: Bytes, maximumBytes: Int
    ) async throws -> Data where Bytes.Element == UInt8 {
        var result = Data()
        for try await byte in bytes {
            guard result.count < maximumBytes else { throw BodyLimitError.tooLarge }
            result.append(byte)
        }
        return result
    }
}
