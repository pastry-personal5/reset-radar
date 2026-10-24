import Foundation
import ResetRadarApplication

public enum ClaudeCodeInstallationStatus: Equatable, Sendable {
    case ready
    /// Setup has not run, was restored, or its records are unusable.
    case notConfigured
    /// The stable helper copy is missing or differs from the embedded helper.
    case helperUnavailable
}

/// Reports whether the status line is installed. The source never inspects settings itself.
public protocol ClaudeCodeInstallationProbing: Sendable {
    func status() async -> ClaudeCodeInstallationStatus
}

public struct ConfiguratorInstallationProbe: ClaudeCodeInstallationProbing {
    private let configurator: ClaudeCodeConfigurator
    private let installer: StatusLineHelperInstaller

    public init(configurator: ClaudeCodeConfigurator, installer: StatusLineHelperInstaller) {
        self.configurator = configurator
        self.installer = installer
    }

    public func status() async -> ClaudeCodeInstallationStatus {
        guard (try? installer.state()) == .current else { return .helperUnavailable }
        return await configurator.inspect(accountID: nil) == .configured
            ? .ready : .notConfigured
    }
}
