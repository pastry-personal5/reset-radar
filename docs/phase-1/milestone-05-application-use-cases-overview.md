# P1-M5: Application use cases overview

Status: Done

Implement `ResetRadarApplication` and `ResetRadarTestSupport` as specified in [Application](../architecture/application.md): every port, the typed outcome and error taxonomy, the four policies, snapshot reduction, and every use case and query, tested against in-memory fakes. No adapter, composition root, or UI changes.

## Goal

`ResetRadarApplication` imports only `ResetRadarDomain` and Foundation, defines the complete and stable port surface that Storage, Transport, Scheduling, WatchSync, and ProviderAdapters implement, and contains every use case, policy, and read model in [application.md](../architecture/application.md). `ResetRadarTestSupport` has one in-memory fake per port. All tests pass in the complete gate in the [contribution guide](../contribution-guide.md).

## Why the scope is the whole module

[phase-1.md](phase-1.md) lists Application as the module of P1-M5 only, and P1-M6, M7, M10, and M11 depend on it. No later milestone owns a use case, so everything in application.md lands here. Four adapter milestones build on the ports, so a port signature is the one thing this milestone must not get wrong; see [Risks](milestone-05-application-use-cases-sequence.md#risks).

## Entry criteria

- [x] P1-M4 is `Done` and merged to `main`; P1-M5 starts on a fresh branch from `main` (`feat/p1-m5-application-use-cases`). Evidence: branch cut from `74c7f32`.
- [x] The owner has answered the [open questions](#open-questions) or accepted each recommendation, and the answers are in the [changelog](changelog.md). Evidence: 2026-10-23 changelog entry.
- [x] A clean-checkout gate passes before any change (baseline). Evidence: generate, format lint, swiftlint, import check, and Mac `xcodebuild test` passed on the branch before any change.

## In scope

- All 20 ports in the application.md Ports table (plus the three snapshot-commit role protocols if Q4 is accepted), as `Sendable` protocols named for the product need, with the exact method sets in the [sequence](milestone-05-application-use-cases-sequence.md#task-2-ports-and-fakes).
- The error and outcome taxonomy ([Task 1](milestone-05-application-use-cases-sequence.md#task-1-error-and-outcome-taxonomy)): the application.md text names outcomes piecemeal and never defines them as a whole.
- `PublicationPolicy`, `ReaderRefreshPolicy`, `ComplicationBudgetPolicy`, `BackoffPolicy`, and snapshot reduction with change classification.
- Every use case and query in application.md, Mac, iOS, Watch, and shared.
- One in-memory fake per port in `ResetRadarTestSupport`, which imports only Domain and Application.
- Domain changes the taxonomy needs, such as new `DiagnosticEvent.Category` cases with factories and updated golden JSON. The owner permits any Domain change, including incompatible ones (Q1), but this milestone makes only those it needs.
- Doc updates: [application.md](../architecture/application.md) for each answered question and the spec corrections below, [storage.md](../architecture/storage.md) and [transport.md](../architecture/transport.md) where a port shape changes what they must implement, this file's evidence, the [phase doc](phase-1.md), and the [changelog](changelog.md).

## Out of scope

- Any adapter implementation: file stores and locks (P1-M6), crypto, Keychain and HTTP (P1-M7), notification and Live Activity mechanics (P1-M15), WatchConnectivity (P1-M16), provider parsing (P1-M10, P1-M11).
- Timers, scene-phase handling, background tasks, and widget reloads; these are drivers in the composition roots (P1-M12 to P1-M16).
- Formatting and copy; UI turns read models into text.
- Real cross-process locking. Here, "two processes" means two use-case instances sharing one fake store; the `flock` evidence belongs to P1-M6.
- Any external dependency, build-tool, or repository-layout change. The one `Package.swift` edit, a test-target dependency on Domain (Task 2), is owner-approved.

## Spec corrections to make

Reading application.md against domain.md, storage.md, transport.md, relay.md, and mac-app.md found these gaps. Each is settled by an open question below and then written into application.md in this milestone.

1. **No error taxonomy.** Only the phase goal names it. `RelayOutcome`, `SecretStoreError`, and the per-use-case outcomes are used but never listed.
2. **Timers.** "Use cases own no timers" contradicts `RequestMacRefresh` (poll every five seconds for 45) and `PairReader` (poll activation, revoke at expiry). [mac-app.md](../architecture/mac-app.md) already puts activation polling in a driver.
3. **Backoff jitter.** `BackoffPolicy` needs randomness, but no port supplies a non-secret random number and policies must be deterministic.
4. **Complication budget state.** "Transfers remain" and "complication enabled" have no owner in the `ReaderStore` field list or the `PreferenceStore` description.
5. **Remote-forced read throttle.** The 30-second limit has no stated persistence, and `PublisherStore` keeps handled IDs only.
6. **Background request formula.** `max(now + 1 min, min(lastSuccess + 15 min, nextReset + 1 min))` is undefined when `lastSuccess` or `nextReset` is absent.
7. **Pending activation versus manual refresh.** "Ordinary refresh and widget fetches are paused" does not say whether a manual refresh is.
8. **Snapshot-store shape.** One `SnapshotStore` carries a Mac, an iOS, and a Watch commit; no platform uses all three.
9. **Read-model fields.** `HomeReadModel` and the other models are named but their fields are not.

## Open questions

Answered by the owner on 2026-10-23 (see [changelog.md](changelog.md)); they are decided. Scope stays one milestone with three checkpoints. Answers 1 and 10 differ from the recommendation text below: Q1 allows any Domain change, not only additive ones, and Q10 renames the port to `AppClock`. Every other answer accepted the recommendation.

1. **Domain edits.** The taxonomy needs diagnostic categories Domain lacks (publication stopped, oversized envelope, secrets unavailable, relay failure class). Recommended adding them as enum cases. **Decided:** the owner allows any Domain change, compatible or not.
2. **Waiting inside a use case.** Recommend `AppClock.sleep(for:)` (cancellable) used only by `RequestMacRefresh`'s bounded 45-second wait; every repeating timer stays in drivers, and `PairReader` exposes `pollActivation()` and `revokeIfExpired()` for the Mac driver. Alternative: make `RequestMacRefresh` return a next-due instant and have the iOS driver re-invoke it, which pushes the wait state into the driver and the claim store.
3. **Jitter source.** Recommend `BackoffPolicy.delay(afterFailures:randomUnit:)` taking a `Double` in `0...1`, with `SecretGenerator.randomUnit()` added to the existing port. Alternative: a new `RandomSource` port, rejected as another adapter for one number.
4. **Snapshot-store shape.** Recommend a base `SnapshotStore` (`load`, `clear`) refined by three role protocols, `LocalSnapshotCommitting` (Mac), `RemoteSnapshotCommitting` (iOS), and `WatchSnapshotCommitting`, so a use case depends on the narrowest port and no fake implements a commit it cannot use. Storage's facades implement what each platform needs.
5. **Read models.** Recommend plain `Sendable` structs of Domain types and `Date`s only, no strings or formatting, with the fields in the [sequence](milestone-05-application-use-cases-sequence.md#task-13-queries-and-read-models).
6. **Persisted counters and flags.** Recommend the complication transfer count, its day, and the last transfer's values in `ReaderStore`, the complication-enabled flag in `PreferenceStore`, and the last remote-forced read time in memory only (a restart permits one read, bounded by the relay's own 60-second request limit), with handled IDs still persisted. This adds fields to the storage.md lists.
7. **Manual refresh while awaiting activation.** Recommend that every fetch, manual included, is suppressed until activation succeeds; only the `AcceptPairing` retry reaches the relay. A manual tap reports `pairingPending`.
8. **Background request with missing inputs.** Recommend `lastSuccess` absent gives `now + 1 min`, and `nextReset` absent gives `lastSuccess + 15 min`, both still floored at `now + 1 min`.
9. **Complication budget window.** The "48 a day" limit needs a definition of a day. Recommend a rolling 24 hours of persisted transfer timestamps, which matches how the system allowance is counted without depending on the time zone. Alternative: a local calendar day.
10. **The port name.** application.md names the port `Clock`, which shadows Swift's `Clock` protocol inside the module. **Decided:** rename the port `AppClock` and amend application.md (lines for the rules, the diagram, and the Ports table); no other architecture doc names it.

## Completion checklist

- [x] Entry criteria hold, with evidence in the changelog and baseline gate output. Evidence: 2026-10-23 changelog entries; baseline gate passed before any change.
- [x] The `Clock` port is renamed `AppClock` in application.md and `git grep -nw Clock docs/architecture` finds no port reference. Evidence: the grep prints only the sentence explaining the rename.
- [x] Checkpoint A (Tasks 1 to 4) has passed the gate and is committed (commit `6c311dc`), so P1-M6, P1-M7, P1-M10, and P1-M11 may start from it. The owner declined a review gate; later port changes go through the changelog.
- [x] The Mac `xcodebuild test` run reports the `ResetRadarApplicationTests` cases by name, with their count recorded. Evidence: 238 tests in 35 suites after the review fixes (49 at checkpoint A).
- [x] `ResetRadarApplication` imports only Domain and Foundation, `ResetRadarTestSupport` only Domain, Application, and Foundation, and `Scripts/check-imports.sh` passes. Evidence: `git grep '^import'` over both source folders lists only those modules; the script passed.
- [x] Every port in the application.md table exists with the signatures in the sequence and has a fake in `ResetRadarTestSupport`; a test proves each fake satisfies its protocol contract (for example, a rejected compare-and-swap, a lost lease, an `interactionRequired` secret failure). Evidence: `FakeContractTests` covers every fake's contract (clock sleep and cancellation, `interactionRequired`, redacted `SecretValue`, cipher size edges, codec rules, account scoping, transaction atomicity and serialization, sequence never repeating, gate lease, relay queues and hold). Deviates in the store signatures (`load` and `transact` replace `claimFetch`, `commitResult`, `commitRemote`, and `commitWatch`; `WatchCacheStore` is new): see the 2026-10-23 changelog entry, which awaits owner confirmation.
- [x] The taxonomy is complete: every HTTP status in [relay.md](../architecture/relay.md) maps to one `RelayOutcome` case, and every case maps to a `TransportStatus` or a stated no-op, in a table test. Evidence: `TaxonomyTests` (`mappingTable`, `everyCaseHasARow`, `statusContractNamesEveryRelayStatus`) and `RelayStatusContract`.
- [x] Each policy has table-driven tests at every threshold from application.md, on both sides of the boundary (see the sequence's [review focus](milestone-05-application-use-cases-sequence.md#review-focus)). Evidence: `BackoffPolicyTests`, `PublicationPolicyTests`, `ComplicationBudgetPolicyTests`, `ReaderRefreshPolicyTests`.
- [x] `CollectUsage` passes the change classification, retained, dropped, account-scope, and state-only cases, and commits without assigning a relay sequence. Evidence: `SnapshotReducerTests`, `CollectUsageTests`.
- [x] `PublishSnapshot` persists the sequence before sending, rejects an encoded envelope of 65,537 bytes without sending and accepts 65,536, and stops automatic retry on each stop case. Evidence: `PublishSnapshotTests`.
- [x] Manual refresh passes on both sides: Mac coalescing, the 30-second throttle, publication before acknowledgement; reader wait with a matching result versus every non-completing signal, and no POST for a Claude Code-only action. Evidence: `HandleManualRefreshRequestsTests`, `RequestMacRefreshTests`.
- [x] Pairing and ingestion pass the lease, ETag, pairing-floor, staging-recovery, lost-activation, and re-pair cases against fakes shared by two use-case instances. Real cross-process evidence is deferred to P1-M6 and recorded as such. Evidence: `AcceptPairingTests`, `IngestRelaySnapshotTests`, `SetUpRelayTests`, `PairReaderTests`, `DestroyRelayTests`; `flock` evidence stays with P1-M6.
- [x] The Watch ordering, tombstone, erase receipt, local-erase hold, and complication-budget cases pass. Evidence: `CommitWatchPayloadTests`, `EraseWatchDataTests`, `ConfirmWatchEraseTests`, `ForwardToWatchTests`, `ForgetMacTests`.
- [x] Notification and Live Activity reconciliation pass opt-in, replacement, cancellation, expiry, time-zone, account-replacement, `staleDate`, and each end condition. Evidence: `ReconcileResetNotificationsTests`, `SetNotificationOptInTests`, `ReconcileLiveActivitiesTests`.
- [x] Queries pass at threshold crossings and distinguish local cleanup, pending Watch erasure, and confirmed erasure. Evidence: `QueriesTests`.
- [x] The placeholder `ResetRadarApplicationModule`, `ResetRadarTestSupportModule`, and their smoke test are removed, with no remaining reference. Evidence: the files were removed in Task 1; `git grep` finds no reference outside the plan docs.
- [x] Complete gate passes from a clean checkout (Mac run only for Xcode tests, per the suspension in the [changelog](changelog.md)). Evidence: all seven gate commands passed after the final change; the Mac `xcodebuild test` run reports 71 Domain and 238 Application tests (35 suites) by name.
- [x] Docs updated: application.md corrections, storage.md and transport.md port-shape notes, README index, phase-1.md status, changelog. Evidence: application.md, storage.md, transport.md, phase-1.md, the changelog, and this file; the README index already lists both milestone files.

## Checkpoints

The work is one milestone in three reviewable series, each ending with a passing gate and one conventional commit, so P1-M6 to P1-M11 can start from checkpoint A:

- **A: contracts** (Tasks 1 to 4): taxonomy, ports, fakes, policies.
- **B: Mac and reader flows** (Tasks 5 to 11): collection, publication, relay administration, ingestion, manual refresh, pairing, Forget Mac.
- **C: Watch, reminders, and queries** (Tasks 12 to 14), then close-out (Task 15).
