import Darwin
import Foundation

@testable import ResetRadarProviderAdapters

let sentinelSessionID = "SENTINEL-session-id-7f3a"
let sentinelPrompt = "SENTINEL-prompt-text"

/// A synthetic status-line payload. `rateLimits` and `cost` are raw JSON fragments.
func statusPayload(
    version: String = "2.1.0", sessionID: String = sentinelSessionID,
    cost: String? = "{\"total_api_duration_ms\":1000}",
    rateLimits: String? =
        "{\"five_hour\":{\"used_percentage\":12.5,\"resets_at\":1900000000}}",
    extra: String = ""
) -> Data {
    var members = ["\"session_id\":\(jsonString(sessionID))", "\"version\":\(jsonString(version))"]
    if let cost { members.append("\"cost\":\(cost)") }
    if let rateLimits { members.append("\"rate_limits\":\(rateLimits)") }
    if !extra.isEmpty { members.append(extra) }
    return Data("{\(members.joined(separator: ","))}".utf8)
}

func jsonString(_ text: String) -> String { "\"\(text)\"" }

func windowJSON(_ percent: String, resetsAt: String? = "1900000000") -> String {
    var members = ["\"used_percentage\":\(percent)"]
    if let resetsAt { members.append("\"resets_at\":\(resetsAt)") }
    return "{\(members.joined(separator: ","))}"
}

func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let root = URL(filePath: "/private/tmp").appending(
        path: "reset-radar-claude-tests-\(UUID().uuidString)")
    var status = mkdir(root.path, 0o700)
    precondition(status == 0)
    defer {
        _ = try? FileManager.default.removeItem(at: root)
        status = 0
    }
    return try body(root)
}

func withAsyncTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let root = URL(filePath: "/private/tmp").appending(
        path: "reset-radar-claude-tests-\(UUID().uuidString)")
    precondition(mkdir(root.path, 0o700) == 0)
    defer { _ = try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

func decoded(_ data: Data) throws -> DecodedStatusLine {
    try StatusLineDecoder.decode(data)
}

/// A fixture "home" under the per-user temporary directory, whose ancestors satisfy the trust
/// rule (the shared /private/tmp is world-writable and would not).
func withAsyncTrustedHome<T>(_ body: (URL) async throws -> T) async throws -> T {
    let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    let home = base.appending(path: "reset-radar-home-\(UUID().uuidString)")
    precondition(mkdir(home.path, 0o700) == 0)
    defer { _ = try? FileManager.default.removeItem(at: home) }
    return try await body(home)
}

func withTrustedHome<T>(_ body: (URL) throws -> T) throws -> T {
    let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    let home = base.appending(path: "reset-radar-home-\(UUID().uuidString)")
    precondition(mkdir(home.path, 0o700) == 0)
    defer { _ = try? FileManager.default.removeItem(at: home) }
    return try body(home)
}

@discardableResult
func writeExecutable(_ script: String, at url: URL, mode: mode_t = 0o700) throws -> URL {
    try Data(script.utf8).write(to: url)
    precondition(chmod(url.path, mode) == 0)
    return url
}

func openFile(_ url: URL) -> FileHandle {
    FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    // swiftlint:disable:next force_try
    return try! FileHandle(forWritingTo: url)
}

func utf8String(_ bytes: some Sequence<UInt8>) -> String {
    String(bytes: bytes, encoding: .utf8) ?? ""
}

/// A settings document whose `statusLine` is a command object; `extra` is raw JSON members
/// appended inside that object (with a leading comma).
func settingsJSON(command: String, extra: String = "") -> String {
    "{\"statusLine\":{\"type\":\"command\",\"command\":\(JSONTokens.string(command))\(extra)}}"
}
