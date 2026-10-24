import Darwin
import Foundation
import ResetRadarProviderAdapters

// Composition root for the Claude Code status-line helper. All behavior lives in ProviderAdapters.

private func ownerHomeDirectory() -> URL {
    if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}

private let home = ownerHomeDirectory()
private let configuration = StatusLineHelperConfiguration(
    rootDirectory: home.appending(path: "Library/Application Support/ResetRadar"),
    homeDirectory: home, environment: ProcessInfo.processInfo.environment,
    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
private let cancellation = StatusLineHelperCancellation()

signal(SIGPIPE, SIG_IGN)
private var cancellationSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT, SIGHUP] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler {
        cancellation.cancel()
        exit(128 + number)
    }
    source.resume()
    cancellationSources.append(source)
}

exit(
    StatusLineHelperMain.run(
        arguments: CommandLine.arguments, standardInput: STDIN_FILENO,
        standardOutput: FileHandle.standardOutput, standardError: FileHandle.standardError,
        configuration: configuration, cancellation: cancellation))
