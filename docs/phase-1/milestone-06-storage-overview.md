# P1-M6: Storage overview

Status: Planned

Implement `ResetRadarStorage` as specified in [Storage](../architecture/storage.md): versioned JSON files, atomic replacement, a cross-process `flock`, migration, typed preferences, and redacted diagnostics behind the P1-M5 store ports. No composition-root, UI, transport, or relay changes.

## Goal

`ResetRadarStorage` imports only Domain, Application, Foundation, and OSLog, and gives every store port in [application.md](../architecture/application.md) a file-backed implementation: `SnapshotStore` (with `LocalSnapshotCommitting`), `ReaderStore`, `PublisherStore`, `WatchCacheStore`, `PreferenceStore`, `NotificationReconcileGate`, and `DiagnosticsSink`. The P1-M5 use cases run unchanged against them. All tests pass in the complete gate in the [contribution guide](../contribution-guide.md).

## Why this milestone is next

[phase-1.md](phase-1.md) lists M6, M7 and M8 as parallel after M5. Storage comes first because P1-M12 (Mac collector), P1-M14 (iOS), and P1-M16 (Watch) all need it, it has no owner-run work, and P1-M5 deferred its real cross-process evidence here (the "two processes" cases ran as two use-case instances over one fake). M7 and M8 stay independent and can follow in either order.

## Entry criteria

- [x] P1-M5 is `Done` and merged to `main`; P1-M6 starts on a fresh branch (`feat/p1-m6-storage`). Evidence: the branch is cut from `9752fd1`, the merged P1-M5 head.
- [x] The owner has answered the [open questions](#open-questions) or accepted each recommendation, and the answers are in the [changelog](changelog.md). Evidence: 2026-10-23 changelog entry.
- [ ] A clean-checkout gate passes before any change (baseline).

## In scope

- The seven port implementations above, with the type names in the [sequence](milestone-06-storage-sequence.md).
- The persistence core: `StorageLocations`, `AtomicFileWriter`, `ProtectionPolicy`, `ProcessFileLock`, `VersionedCodableFile`, `MigrationRegistry`, and `StorageError`.
- Owner-only permissions on macOS (`0700` directories, `0600` files), the Debug/release location split, and the Mac backup copy before a newer schema is written.
- Real `flock` contention evidence between independent file descriptors (and a child process if Q3 allows), replacing the P1-M5 fake-based stand-in.
- Doc updates: [storage.md](../architecture/storage.md) for the answered questions and the facade names, [application.md](../architecture/application.md) only if a port changes, this file's evidence, the [phase doc](phase-1.md), the [docs index](../README.md), and the [changelog](changelog.md).

## Out of scope

- Secrets, Keychain, crypto, HTTP (P1-M7, P1-M12). Storage never holds a token, key, or ciphertext.
- Choosing the App Group container or Application Support location at runtime: composition roots pass a root URL (P1-M12, M14, M16). Storage resolves nothing from entitlements.
- iPhone, iPad, and Watch file-protection verification on a device or simulator (the runs are suspended; see the [changelog](changelog.md)). This milestone proves the policy mapping and the Mac behavior; the device check moves to P1-M14 and P1-M16.
- Any product decision. A use case still decides what "newer" means; the store only applies the atomic change it is asked for.
- Any external dependency, build-tool, or repository-layout change. The one `Package.swift` edit, adding `ResetRadarDomain` and `ResetRadarApplication` to the `ResetRadarStorageTests` dependencies (Q4), needs owner approval.

## Open questions

Answered by the owner on 2026-10-23: every recommended default is accepted (see [changelog.md](changelog.md)). They are decided.

1. **Location injection.** Recommend `StorageLocations(root: URL, flavor: .release | .debug)` with `.debug` appending a `Debug` subdirectory, and a Mac convenience `StorageLocations.macApplicationSupport(flavor:)`. Composition roots pass the App Group URL on iOS and watchOS. Alternative: Storage resolves `containerURL(forSecurityApplicationGroupIdentifier:)` itself, which needs the group ID inside the package.
2. **Lock waiting.** `flock` blocks a thread, and store calls are `async`. Recommend `LOCK_NB` polling every 10 ms with a 5 s timeout that throws `StorageError.lockTimeout`, so a stuck process cannot starve the cooperative pool. Alternative: a dedicated serial queue with a blocking `flock`.
3. **Cross-process evidence.** Recommend contention between two independently opened descriptors in one process (`flock` locks belong to the open file description, so this is the kernel mechanism a second process hits), plus one real child-process test through `/usr/bin/lockf` only if Task 1's check confirms it uses `flock(2)`. Alternative: a test-only helper executable target, which needs a `Package.swift` and XcodeGen change and owner approval.
4. **Test-target imports.** Recommend adding `ResetRadarDomain` and `ResetRadarApplication` to `ResetRadarStorageTests`, as P1-M5 did for its tests, because `--explicit-target-dependency-import-check=error` rejects an undeclared import. This is a target dependency inside the package, not an external dependency.
5. **Snapshot facade names.** storage.md names one `FileSnapshotStore`, but the Mac commits and the iOS and Watch only read. Recommend `FileSnapshotStore` for the Mac (`LocalSnapshotCommitting`) plus `ReaderSnapshotStore` and `WatchSnapshotStore` read facades, and a storage.md update.
6. **Bounds.** Recommend a 200-event diagnostics ring, a 30-second `NotificationReconcileGate` claim (taken from the injected `AppClock`), and a 5 MiB cap on any decoded file so a corrupted or hostile file cannot exhaust memory. The spec fixes none of these.
7. **Corrupt versus incompatible.** Recommend two errors with different recovery: `StorageError.corrupt` (undecodable or invalid; the file is moved aside as `*.corrupt` and the store starts empty, with a diagnostic) versus `StorageError.incompatible` (unknown mandatory version; the file is left untouched, nothing is replaced, and the error propagates so the use case reports `incompatible`). Alternative: never discard a corrupt file, which blocks the app until the owner intervenes.

## Completion checklist

- [ ] Entry criteria hold, with evidence in the changelog and baseline gate output.
- [ ] Checkpoint A (Tasks 1 and 2) has passed the gate and is committed, so the stores can build on the core.
- [ ] `ResetRadarStorage` imports only Domain, Application, Foundation, and OSLog; `Scripts/check-imports.sh` passes.
- [ ] Interrupted atomic replacement and corrupted JSON leave the last valid file readable, and a decoded file over the size cap is rejected without loading it. Evidence: `AtomicFileWriterTests`, `VersionedCodableFileTests`.
- [ ] Every supported migration runs one version at a time; an unknown mandatory version leaves the file untouched and surfaces `incompatible`; a migration cannot accept an invalid percentage, timestamp, publisher, or sequence; the Mac backup exists before the first newer-schema write. Evidence: `MigrationRegistryTests`.
- [ ] Two descriptors contending for `ProcessFileLock` serialize, and a lock times out as `lockTimeout` instead of hanging. Evidence: `ProcessFileLockTests`.
- [ ] `ReaderStore.transact` and `PublisherStore.transact` replace the whole bundle atomically; a throwing closure changes nothing; concurrent writers lose no update; the iOS snapshot and reader state, and the Watch snapshot and sequence, are never split after an interrupted replacement. Evidence: `FileReaderStoreTests`, `FileWatchCacheStoreTests`, `FilePublisherStoreTests`.
- [ ] `nextSequence()` is on disk before it returns and never repeats after a crash. Evidence: `FilePublisherStoreTests`.
- [ ] The P1-M5 lease, late-result, ETag-invalidation, Forget Mac tombstone, and pending-setup cases pass when the real use cases run over the real stores. Evidence: `StorageIntegrationTests`.
- [ ] Notification reconciliation across two gate instances and an expired claim passes. Evidence: `FileNotificationReconcileGateTests`.
- [ ] Preferences are per slot and per device and are not shared across stores; the diagnostics ring is bounded and holds only `DiagnosticEvent` values. Evidence: `DefaultsPreferenceStoreTests`, `LogDiagnosticsSinkTests`.
- [ ] File permissions are `0700`/`0600` on macOS, the `ProtectionPolicy` mapping is tested for each platform, and Debug and release roots never overlap. Evidence: `StorageLocationsTests`, `ProtectionPolicyTests`.
- [ ] The placeholder `ResetRadarStorageModule` and its smoke test are removed, with no remaining reference.
- [ ] Complete gate passes from a clean checkout (Mac run only for Xcode tests). Evidence: all gate commands passed after the final change; the Mac `xcodebuild test` run reports the new Storage tests by name.
- [ ] Docs updated: storage.md answers and names, README index, phase-1.md status, changelog. Evidence: the files changed in the closing commit.

## Checkpoints

- **A: persistence core** (Tasks 1 and 2): locations, atomic writer, protection, lock, versioned files, migration.
- **B: stores** (Tasks 3 to 5): reader, publisher, Watch, snapshot facades, preferences, gate, diagnostics, then integration with the real use cases and close-out (Task 6).
