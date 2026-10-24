import Darwin
import Foundation

/// Small descriptor helpers shared by the owner-only file code.
enum POSIXIO {
    /// Writes every byte, retrying short writes; false on any failure.
    static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    enum ReadFailure: Error { case failed, overLimit }

    /// Reads to EOF, failing once more than `limit` bytes arrive.
    static func readAll(from descriptor: Int32, limit: Int) throws(ReadFailure) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw .failed }
            if count == 0 { return data }
            data.append(buffer, count: count)
            guard data.count <= limit else { throw .overLimit }
        }
    }

    /// Creates a new exclusive owner-only temporary file holding `data`, synced, with `mode`.
    static func writeExclusive(
        _ data: Data, to url: URL, mode: mode_t
    ) -> Bool {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
        let finished =
            writeAll(data, to: descriptor) && fchmod(descriptor, mode) == 0
            && fsync(descriptor) == 0
        close(descriptor)
        if !finished { unlink(url.path) }
        return finished
    }
}
