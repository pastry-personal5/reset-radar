# P1-M6: Storage sequencing

Status: Planned

Order of work, interfaces, and tests for [P1-M6](milestone-06-storage-overview.md). Behavior is defined in [Storage](../architecture/storage.md); this file adds only the file layout, signatures, and test cases that file leaves open. Each task is test-first: write the named tests, watch them fail, implement, run the module's tests. It assumes the recommended answer to each overview question.

## Constraints

- Sources in `ResetRadarKit/Sources/ResetRadarStorage/` (`Core/` and `Stores/`), tests in `ResetRadarKit/Tests/ResetRadarStorageTests/`; Swift Testing only, Swift 6 strict concurrency. Tests use a unique temporary directory per test and remove it afterward.
- Storage imports Domain, Application, Foundation, and OSLog only. The tests may also import `ResetRadarTestSupport` for `FakeAppClock`.
- Stores are `Sendable` final classes or actors that hold a `StorageLocations` and a `ProcessFileLock`; no store reads `Date()` (the gate takes an `AppClock`).
- Encode and decode every file with `WireCoding.encoder()` and `WireCoding.decoder()` from Domain, so dates match the wire form.
- Throw `StorageError`; no `try?` that hides a failure. Files hold no secret, token, key, digest, or ciphertext.
- Iterate with `swift test --package-path ResetRadarKit --filter ResetRadarStorageTests`; run the complete gate once per checkpoint.

## Commits

One conventional commit per checkpoint (A after Task 2, B after Task 5, close-out after Task 6), each made only after the complete gate passes at that point.

## Setup

Branch `feat/p1-m6-storage` from `main`, set P1-M6 to `Active` in [phase-1.md](phase-1.md), add `ResetRadarDomain` and `ResetRadarApplication` to the `ResetRadarStorageTests` dependencies in `ResetRadarKit/Package.swift` (Q4), and run the baseline gate.

## Task 1: Locations, atomic writer, protection, and lock

Files: `Core/StorageError.swift`, `Core/StorageLocations.swift`, `Core/ProtectionPolicy.swift`, `Core/AtomicFileWriter.swift`, `Core/ProcessFileLock.swift`; tests `StorageLocationsTests`, `ProtectionPolicyTests`, `AtomicFileWriterTests`, `ProcessFileLockTests`.

Produces:

- `enum StorageError: Error, Equatable { corrupt, incompatible(foundVersion: Int), tooLarge, lockTimeout, io(code: Int) }`; `io` carries an errno-style number, never a path.
- `struct StorageLocations: Sendable { enum Flavor { case release, debug }; init(root: URL, flavor: Flavor); var directory: URL; func file(_ name: String) -> URL; static func macApplicationSupport(flavor: Flavor) -> StorageLocations }`. `.debug` appends `Debug` to `root`.
- `enum ProtectionPolicy { case ownerOnly, untilFirstUserAuthentication; static func forCurrentPlatform() -> ProtectionPolicy }` with `fileAttributes` and `directoryAttributes` (macOS: `0600`/`0700`; iOS and watchOS: `FileProtectionType.completeUntilFirstUserAuthentication`).
- `struct AtomicFileWriter: Sendable { init(protection: ProtectionPolicy); func write(_ data: Data, to url: URL) throws }` writing a temporary file in the same directory, `fsync`ing it, applying the policy, then `rename`.
- `final class ProcessFileLock: Sendable { init(lockFile: URL, timeout: Duration = .seconds(5)); func withLock<T: Sendable>(_ body: @Sendable () throws -> T) async throws -> T }` using `open` plus `flock(LOCK_EX | LOCK_NB)` polled every 10 ms (Q2) and releasing on every exit path.

Tests:

- **Locations:** `.debug` and `.release` roots for the same base never equal or contain one another; a path-traversal name in `file(_:)` is rejected.
- **Protection:** `forCurrentPlatform()` is `ownerOnly` on macOS; the mapping function for each of the three platforms is covered through an injected platform value; a written file has mode `0600` and its directory `0700`.
- **Atomic writer:** an injected failure between the temporary write and the rename leaves the previous bytes readable and no partial target; a leftover temporary file from a prior crash does not block the next write.
- **Lock:** two `ProcessFileLock` values over the same file serialize (the second body starts only after the first returns, via an ordered event log); a held lock times out as `lockTimeout`; the lock releases when the body throws; cancelling the waiting task stops polling. Spike (Q3): confirm whether `/usr/bin/lockf` takes `flock(2)`; if so add a child-process contention test, otherwise record in the changelog that cross-process evidence is descriptor-level.

## Task 2: Versioned files and migration

Files: `Core/VersionedCodableFile.swift`, `Core/MigrationRegistry.swift`; tests `VersionedCodableFileTests`, `MigrationRegistryTests`.

Consumes: Task 1 types. Produces:

- `struct VersionedCodableFile<Value: Codable & Sendable>: Sendable { init(url: URL, currentVersion: Int, registry: MigrationRegistry, writer: AtomicFileWriter, maxBytes: Int = 5 * 1024 * 1024); func read() throws -> Value?; func write(_ value: Value) throws }`. The on-disk form is `{"schemaVersion": Int, "payload": …}`; `read()` returns `nil` for a missing file.
- `struct MigrationRegistry: Sendable { init(steps: [Int: @Sendable (Data) throws -> Data]); func migrate(_ payload: Data, from: Int, to: Int) throws -> Data }`, one version at a time, validating after the final step.
- Behavior from Q7: undecodable or invalid content moves the file to `<name>.corrupt` and `read()` throws `corrupt` once; `incompatible` leaves the file untouched; over `maxBytes` throws `tooLarge` before reading the body. On macOS, `write` copies the previous file to `<name>.v<oldVersion>.bak` before the first write in a newer schema.

Tests:

- Round trip for each Task 3 value type, including a `PublisherState` with `handledRequests` entries: the dictionary is keyed by `RequestID`, and a non-`String` key encodes as an array, so assert the decoded value equals the original and its JSON survives an unknown extra field.
- A synthetic v0 to v1 to v2 migration chain runs in order and rewrites the file only after the last step succeeds; a throwing middle step leaves the original bytes.
- A migration that would yield a percentage of 101, a negative timestamp, an empty publisher ID, or a sequence below the stored floor is rejected, not accepted.
- File larger than `maxBytes` by one byte is `tooLarge`; exactly `maxBytes` decodes. An unknown mandatory version is `incompatible(foundVersion:)` with the bytes unchanged.
- Missing file reads as `nil`; the Mac backup exists after a newer-schema write and not after a same-version write.

**Checkpoint A** ends here: run the complete gate and commit `feat(storage): add persistence core`.

## Task 3: Reader, publisher, and Watch stores

Files: `Stores/FilePublisherStore.swift`, `Stores/FileReaderStore.swift`, `Stores/FileWatchCacheStore.swift`; tests `FilePublisherStoreTests`, `FileReaderStoreTests`, `FileWatchCacheStoreTests`.

Consumes: `VersionedCodableFile`, `ProcessFileLock`. Produces: `FilePublisherStore: PublisherStore`, `FileReaderStore: ReaderStore`, `FileWatchCacheStore: WatchCacheStore`, each `init(locations: StorageLocations, writer: AtomicFileWriter = …)`. `transact` is: take the lock, read (or a default value: `PublisherState()`, `WatchCacheState()`, and for the reader a `ReaderState` with a new random `InstallationID` persisted on first use), run the closure, write the whole value once, release. A throwing closure writes nothing. `FilePublisherStore.nextSequence()` increments and writes inside one `transact` before returning the new value.

Tests:

- **Atomicity:** a closure that throws leaves the bytes identical; a write failure injected after the closure runs leaves the previous file and rethrows; no state has a snapshot from one commit and a sequence from another.
- **Contention:** 50 concurrent `transact` increments through two store instances over the same files lose no update.
- **Sequence:** `nextSequence()` returns a strictly increasing value across a new store instance created after each call (a simulated relaunch), and a failed write does not return the incremented value.
- **Installation ID** is generated once, survives relaunch, and is retained across the Forget Mac state changes the use cases make.
- **Lifecycle:** `setupPending` and `destroyPending` survive relaunch.
- **Watch cache:** `cleared`, `localEraseHold`, and `pendingInstallation` survive relaunch.

## Task 4: Snapshot facades, preferences, gate, and diagnostics

Files: `Stores/FileSnapshotStore.swift`, `Stores/ReaderSnapshotStore.swift`, `Stores/WatchSnapshotStore.swift`, `Stores/DefaultsPreferenceStore.swift`, `Stores/FileNotificationReconcileGate.swift`, `Stores/LogDiagnosticsSink.swift`; tests alongside each.

Produces:

- `FileSnapshotStore: LocalSnapshotCommitting` (Mac): its own versioned file with `load`, `clear`, `commitLocal`, under its own lock.
- `ReaderSnapshotStore: SnapshotStore` and `WatchSnapshotStore: SnapshotStore`: init with the matching store; `load()` returns `state.snapshot`; `clear()` runs `transact` setting it to `nil`.
- `DefaultsPreferenceStore: PreferenceStore`, `init(defaults: UserDefaults)`, keys derived from the `HomeSlot` raw value; `notificationOptIn` is `nil` until set.
- `FileNotificationReconcileGate: NotificationReconcileGate`, `init(locations:clock: AppClock, lease: Duration = .seconds(30))`: `claim()` returns `nil` while a live claim exists, reclaims an expired one, and `release` ignores a claim that no longer owns the gate.
- `LogDiagnosticsSink: DiagnosticsSink`, `init(locations:capacity: Int = 200)`: logs each event with `OSLog` privacy-marked fields and appends it to a bounded ring file; `history()` returns oldest first.

Tests:

- Facades: a `commitLocal` then `load` round trip; `clear` on the Reader facade changes only the snapshot and leaves the pairing and sequence in the same `ReaderState`.
- Preferences: opt-in is per slot (setting one leaves the others `nil`), `complicationEnabled` defaults to `false`, and two `UserDefaults` suites do not share values.
- Gate: a second claim returns `nil`; a claim at exactly its expiry is reclaimable (and one second before is not); a late `release` of a reclaimed claim does not free the new holder; two gate instances over one directory behave the same.
- Diagnostics: the ring holds the last 200 of 201 events, in order; the file survives relaunch; an event encoded to disk contains only enum, number, and date values (no `String` field is present in the JSON beyond enum raw values and keys).

## Task 5: Integration with the real use cases

Files: `StorageIntegrationTests.swift`.

Run P1-M5's use cases over the real stores in a temporary directory, with `FakeAppClock` and the other fakes for every non-storage port:

- `IngestRelaySnapshot`: two instances share one `FileReaderStore`; the loser of a concurrent claim reports `inProgress`; a result from an expired claim is rejected after a new claim; a cached ETag with no snapshot is not sent.
- `PublishSnapshot` and `nextSequence`: restart the store between the sequence write and a failed send; the next publication uses a higher sequence.
- `ForgetMac`: an interruption retains `forgetCleanupPending`; a late in-flight result is rejected; a new pairing's Watch payload waits for the matching erase receipt.
- `SetUpRelay` and `DestroyRelay`: `setupPending` and `destroyPending` survive relaunch and block publication.
- `HandleManualRefreshRequests`: a handled request ID survives relaunch and does not trigger another Codex read.
- Notification reconcile: a widget-process commit sets `needsAppReconcile` in the same replacement as the snapshot; an interrupted pass leaves the flag set.

**Checkpoint B** ends here: run the complete gate and commit `feat(storage): add file-backed stores`.

## Task 6: Close-out

Remove `ResetRadarStorageModule.swift` and `ResetRadarStorageTests.swift`, run `git grep -n ResetRadarStorageModule` to confirm nothing remains, update storage.md (answered questions, facade names, size cap, corrupt-versus-incompatible, lock timeout), the docs index, phase-1.md (`Done`), the changelog, and this milestone's evidence. Run the complete gate from a clean checkout and commit `docs: close P1-M6`.

## Coverage of the storage.md test list

| storage.md test | Task |
|---|---|
| Interrupted atomic replacement and corrupted JSON | 1, 2 |
| Crash recovery for `ReaderBundle` and `WatchCacheBundle` | 3 |
| Every supported migration and an unknown mandatory version | 2 |
| Compare-and-swap under concurrent writers; two processes contending for the lock | 1, 3 |
| `claimFetch` contention; lease expiry; late result; ETag invalidation; atomic commit | 5 |
| Two-process notification reconciliation and interrupted recovery | 4, 5 |
| Sequence persistence before return | 3, 5 |
| Pending relay setup and destroy surviving relaunch | 3, 5 |
| Manual-refresh result surviving relaunch; reader wait interrupted | 5 |
| Forget Mac interruption, late result, stale Watch payload, new pairing erase wait | 5 |
| File protection and permissions | 1 |
| Debug and release location separation | 1 |

## Review focus

Inputs the spec implies but its test list does not name; each has a test in the owning task.

1. A `[RequestID: Date]` dictionary that encodes as a key-value array and fails to decode after a schema change (Task 2).
2. A process killed after the lock is taken: the kernel frees `flock` on exit, so no stale lock file blocks the next launch (Task 1).
3. A corrupt or empty (zero-byte) file at first launch must not crash or silently reset a paired reader (Task 2, Q7).
4. A file one byte over the size cap, and exactly at it (Task 2).
5. Two roots that differ only by the `Debug` flavor, and a root that does not exist yet (Task 1).
6. `needsAppReconcile` set by a widget commit must survive the app and widget racing on the same bundle (Task 5).

## Risks

- **Lock choice.** `flock` is advisory and per open file description. Every writer must go through `ProcessFileLock`; a store that writes without it silently loses updates. Mitigation: only the stores hold the file URLs, and Task 3 contention tests cover each.
- **Platform file protection.** `completeUntilFirstUserAuthentication` cannot be verified on the Mac gate. Mitigation: the policy mapping is unit-tested now and the device check is recorded for P1-M14 and P1-M16.
- **Port changes.** If a store cannot be written without changing an Application port, stop and record it in the changelog; M7, M10 and M11 depend on those signatures.
