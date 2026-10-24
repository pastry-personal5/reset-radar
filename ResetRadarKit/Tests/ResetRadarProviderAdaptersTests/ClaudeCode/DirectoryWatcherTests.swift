import Darwin
import Foundation
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code real directory watcher")
struct DirectoryWatcherTests {
    private func nextEvent(
        _ session: any DirectoryWatchSession, within seconds: Double = 5
    ) async -> DirectoryWatchEvent? {
        await withTaskGroup(of: DirectoryWatchEvent?.self) { group in
            group.addTask {
                var iterator = session.events.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test func atomicRecordReplacementIsSeenAtTheDirectoryLevel() async throws {
        try await withAsyncTemporaryDirectory { root in
            let file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
            try file.prepare()
            let session = try DispatchDirectoryWatchFactory().watch(directory: file.directoryURL)
            defer { session.cancel() }
            try store(sessionRecord("a", windows: [sessionWindow(observed: 1)]), in: file)
            #expect(await nextEvent(session) == .changed)
            // A replacement of an existing record still produces a directory event.
            try store(
                sessionRecord("a", windows: [sessionWindow(percent: 50, observed: 2)]), in: file)
            #expect(await nextEvent(session) == .changed)
        }
    }

    @Test func aRenamedRootInvalidatesTheWatchAndCancelFinishesTheStream() async throws {
        try await withAsyncTemporaryDirectory { root in
            let file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
            try file.prepare()
            let session = try DispatchDirectoryWatchFactory().watch(directory: file.directoryURL)
            #expect(
                rename(file.directoryURL.path, root.appending(path: "moved").path) == 0)
            var sawInvalidation = false
            var attempts = 0
            while !sawInvalidation, attempts < 5 {
                attempts += 1
                sawInvalidation = await nextEvent(session, within: 2) == .rootInvalidated
            }
            #expect(sawInvalidation)
            session.cancel()
            var iterator = session.events.makeAsyncIterator()
            while await iterator.next() != nil {}
        }
    }

    @Test func missingAndSymlinkedDirectoriesAreRefused() throws {
        try withTemporaryDirectory { root in
            #expect(throws: DirectoryWatchError.unavailable) {
                try DispatchDirectoryWatchFactory().watch(directory: root.appending(path: "none"))
            }
            let real = root.appending(path: "real")
            #expect(mkdir(real.path, 0o700) == 0)
            let link = root.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            #expect(throws: DirectoryWatchError.self) {
                try DispatchDirectoryWatchFactory().watch(directory: link)
            }
        }
    }
}
