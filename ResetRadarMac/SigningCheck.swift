import Foundation
import Security

struct RunningSignature: Sendable, Equatable {
    let teamIdentifier: String?
    let isAdHoc: Bool
}

protocol SignatureReading: Sendable {
    func runningSignature() throws -> RunningSignature
}

enum SigningOutcome: Sendable, Equatable {
    case valid(teamIdentifier: String)
    case adHoc
    case missingTeam
    case changedTeam(recorded: String, running: String)
    case unreadable
}

struct SigningCheck: Sendable {
    let reader: any SignatureReading

    func evaluate(recordedTeamIdentifier: String?) -> SigningOutcome {
        guard let signature = try? reader.runningSignature() else { return .unreadable }
        guard !signature.isAdHoc else { return .adHoc }
        guard let running = signature.teamIdentifier, !running.isEmpty else { return .missingTeam }
        if let recordedTeamIdentifier, recordedTeamIdentifier != running {
            return .changedTeam(recorded: recordedTeamIdentifier, running: running)
        }
        return .valid(teamIdentifier: running)
    }
}

struct SystemSignatureReader: SignatureReading {
    enum ReadError: Error { case unavailable(OSStatus) }
    /// `CS_ADHOC` from the public code-signing flags in `<Security/CodeSigning.h>`.
    private static let adHocFlag: UInt32 = 0x0000_0002

    func runningSignature() throws -> RunningSignature {
        var code: SecCode?
        let copyStatus = SecCodeCopySelf([], &code)
        guard copyStatus == errSecSuccess, let code else { throw ReadError.unavailable(copyStatus) }
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw ReadError.unavailable(staticStatus)
        }
        var raw: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &raw)
        guard infoStatus == errSecSuccess, let info = raw as? [String: Any] else {
            throw ReadError.unavailable(infoStatus)
        }
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return RunningSignature(
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: flags & Self.adHocFlag != 0)
    }
}
