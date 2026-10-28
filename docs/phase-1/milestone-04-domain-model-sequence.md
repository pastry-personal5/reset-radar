# P1-M4: Domain model sequencing

Status: Done

Order of work, interfaces, and tests for [P1-M4](milestone-04-domain-model-overview.md). Behavior is defined in [Domain](../architecture/domain.md); this file adds only the file layout, signatures, and test cases that file leaves open. Each task is test-first: write the named tests, watch them fail, implement, then commit.

## Constraints

- Sources in `ResetRadarKit/Sources/ResetRadarDomain/`, tests in `ResetRadarKit/Tests/ResetRadarDomainTests/`, Swift Testing only, Swift 6 strict concurrency, Foundation import only.
- Value types, `Sendable`; persisted or transmitted types `Codable` and schema-versioned. No `try?` that hides a failure; throw specific errors.
- Policies take `now: Date` and never read the clock. Run `swift-format` through `Scripts/lint-swift-format.sh`; do not hand-format.
- Iterate with `swift test --package-path ResetRadarKit --filter ResetRadarDomainTests`; run the full gate once at the end.
- Delete `ResetRadarDomainModule` and its smoke test once a real test exists, and drop any reference to them.

## Setup

Branch from `main` (not the P1-M3 branch), answer the overview's [open questions](milestone-04-domain-model-overview.md#open-questions), record the answers in the changelog, set P1-M4 to `Active` in [phase-1.md](phase-1.md), and run the baseline gate.

## Task 1: Wire conventions and identities

Files: `WireCoding.swift`, `SchemaVersion.swift`, `Identity.swift`; test `IdentityTests.swift`, `WireCodingTests.swift`.

Produces:

- `struct SchemaVersion: RawRepresentable, Codable, Hashable, Sendable` and `enum SchemaError: Error { case unsupported(found: Int, supported: ClosedRange<Int>) }`; a helper `SchemaVersion.require(_:in:) throws`.
- `enum WireCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }` using the date format chosen in open question 1, sorted keys on encode.
- `enum ProductID`, `SourceKind`, `HomeSlot` (`String` raw values equal to the ux-terms code-facing names; `HomeSlot.product` and `HomeSlot.duration` accessors); `struct WindowID(product:scope:limitID:durationMinutes:)`, `AccountScope` (16 bytes, `init?(data:)`), `PublisherID` (32 bytes), `ReaderID`, each `Codable & Hashable & Sendable`.
- Unknown-tolerant decoding as a property wrapper or helper, `@Tolerant`-style: unknown optional enum values yield `.unknown`; a closed identity (`ProductID`) throws.

Tests: round trip for each identity; `AccountScope` rejects 15 and 17 bytes; `WindowID` differs when scope differs and is equal for identical inputs; unknown optional enum value decodes to `.unknown`; schema version above the supported range throws `SchemaError.unsupported`.

## Task 2: DiagnosticEvent

Files: `DiagnosticEvent.swift`; test `DiagnosticEventTests.swift`.

Produces: `struct DiagnosticEvent: Codable, Sendable, Equatable` with `category: Category` (closed enum plus `unknown`), state enums, `durationSeconds`, sequence range, versions, `HTTPStatusClass`, and `timestamp`. Static factories per category; no initializer or factory parameter of type `String`, except enum raw values.

Tests: encoded JSON of every factory contains only enum, number, and date values (assert by decoding to `[String: Any]` and checking no unexpected string values); round trip. A compile-time absence is documented in a comment next to the type, not tested.

## Task 3: Windows, observations, and per-window validation

Files: `AllowanceWindow.swift`, `UsageObservation.swift`, `WindowValidation.swift`; test `WindowValidationTests.swift`.

Produces:

- `struct UsageObservation { usedPercent: Double; observedAt: Date; sourceVersion: String; fractionDigits: Int? }` with a failing `init(validating:...) throws(WindowValidationError)`: `usedPercent` finite in `0...100`; `-0.0` normalizes to `0`.
- `struct AllowanceWindow` with `id`, `product`, `limitID`, `label`, `durationMinutes` (positive when present), `isDefaultLimit`, `reportState` (`reported` | `retained`), `resetsAt`, `observation`, `providerLimitState`.
- `enum WindowValidation { static func validate(_ windows: [RawWindow], now: Date) -> (valid: [AllowanceWindow], diagnostics: [DiagnosticEvent]) }`, where `RawWindow` is the unvalidated decoded form; invalid windows are dropped individually, unknown-product windows are ignored with a diagnostic, duplicate `WindowID`s keep the first and emit a diagnostic.

Tests: percentages `0`, `0.1`, `99.9`, `100` accepted; `-0.0001`, `100.0001`, `.nan`, `.infinity`, `-.infinity` each rejected while a valid sibling survives; non-positive duration rejected; unknown product ignored; duplicate ID handled; the original invalid values never appear in the diagnostic.

## Task 4: Source records, snapshot, and manual refresh results

Files: `SourceState.swift`, `ProductSource.swift`, `SourceSnapshot.swift`, `UsageSnapshot.swift`, `ManualRefreshResult.swift`; tests `UsageSnapshotTests.swift`, `ManualRefreshResultTests.swift`.

Produces: `SourceState` (`reporting`, `unavailable`, `signedOut`, `sourceOffline`, `incompatible`); `ProductSource(product:kind:version:state:)`; `SourceSnapshot(source:windows:isCompleteReport:)`; `UsageSnapshot` with the fields in domain.md, decoding through Task 3 validation and rejecting a non-positive `heartbeatSeconds` (open question 5) and an unsupported schema version; `ManualRefreshResult(readerID:requestID:completedAt:outcome:)` with `outcome` `codexRead | sourceUnavailable`, and `enum ManualRefreshResults { static func retained(_:now:) -> [ManualRefreshResult]; static func result(for:requestID:in:now:) -> ManualRefreshResult? }`.

Rules to pin: retention is two minutes after `completedAt`; at most four per reader and twelve overall, dropping oldest first; a result matches only its own `ReaderID`.

Tests: golden JSON round trip for a two-product snapshot; unsupported schema rejects the whole snapshot; one bad window keeps the rest; thirteenth result and fifth per reader dropped oldest first; result exactly at 120 s retained, at 120.001 s expired; a result for another reader is not returned; a `completedAt` after `now` is treated as expired-or-invalid per the answer recorded in the changelog.

## Task 5: Home slot resolution

Files: `HomeSlotResolution.swift`; test `HomeSlotResolutionTests.swift`.

Produces: `enum HomeSlotResolution { case window(AllowanceWindow); case unavailable; case ambiguous([WindowID]) }` and `HomeSlotResolver.resolve(_ slot: HomeSlot, in: UsageSnapshot) -> (HomeSlotResolution, DiagnosticEvent?)`; matching is product, `isDefaultLimit`, and exact 300 or 10,080 minutes only.

Tests: one match; no match; non-default window with the right duration ignored; 299 and 301 minutes ignored; two default 300-minute windows give `ambiguous` plus a diagnostic; a Codex default and a Claude Code default never collide; an empty window list is `unavailable` for all four slots.

## Task 6: Presentation state, current-data windows, and liveness

Files: `CurrentDataWindow.swift`, `Presentation.swift`, `MacLiveness.swift`; tests `PresentationTests.swift`, `MacLivenessTests.swift`.

Produces:

- `enum CurrentDataWindow { static func seconds(for: ProductID) -> TimeInterval }` returning 900 for Codex and 3600 for Claude Code (candidate constants).
- `enum PresentationState { case unavailable, resetAwaitingRefresh, stale(reason: StaleReason), current }` with `StaleReason` (`sourceNotReporting`, `retained`, `observationOld`, `observationInFuture`); never `Codable`.
- `struct Presentation { state: PresentationState; nextChange: Date? }` and `PresentationPolicy.derive(window:source:now:) -> Presentation`, applying the domain.md rules in order.
- `MacLiveness.isPublishing(snapshot:now:) -> Bool`, true while `now - generatedAt <= 3 * heartbeatSeconds`.

Tests (one per boundary, table-driven):

- Precedence: no observation → `unavailable`; retained with no `resetsAt` → `unavailable`; retained past its reset → `unavailable` (rule 1 beats rule 2); `resetsAt == now` → `resetAwaitingRefresh`; one second before → not.
- Staleness: source not `reporting`; retained before reset; `observedAt` exactly at and one second past the window; `observedAt == now + 300 s` current and `+ 300.001 s` stale; all pass through to `current` otherwise.
- `nextChange` is the earliest of reset, observation expiry, and the five-minute skew instant still ahead of `now`, `nil` when none remain; after a returned instant the derived state differs.
- Liveness: at exactly three heartbeats publishing, just past it not; a fresh heartbeat on an old observation leaves state `stale`.
- Time-zone independence: for fixed instants, results are identical under three `TimeZone`s because inputs are `Date` only.

## Task 7: Transport, Watch, and pairing records

Files: `TransportStatus.swift`, `WatchPayload.swift`, `WatchEraseReceipt.swift`, `PairingPackage.swift`, `EnvelopeHeader.swift`; test `TransportRecordsTests.swift`.

Produces: `TransportStatus` (nine cases in domain.md); `WatchPayload` with a failing initializer that makes `cleared == true` and `snapshot != nil` unrepresentable; `WatchEraseReceipt`; `PairingPackage` (fields only; the codec stays in Transport); `EnvelopeHeader`. All schema-versioned and `Codable`.

Tests: golden JSON and round trip for each; a cleared payload with a snapshot is rejected; a receipt carries no usage or secret field (assert key set); unsupported schema versions rejected; an unknown `TransportStatus` inside a `WatchPayload` follows the answer to open question 6.

## Task 8: Close-out

Remove the placeholder module and smoke test; run `Scripts/check-imports.sh`; confirm `ResetRadarDomain` has no import but Foundation (`git grep -n '^import' ResetRadarKit/Sources/ResetRadarDomain`); update [domain.md](../architecture/domain.md) for any answered question, the [README index](../README.md), the changelog, and phase-1.md; run the complete gate once; record concise evidence in the overview and set P1-M4 to `Done`.

## Review focus

Inputs the spec implies but its test list does not name; each has a test in the owning task above.

1. Non-positive or absurd `heartbeatSeconds` (Task 4, 6).
2. `-0.0` and values like `100.00000001` from floating-point parsing (Task 3).
3. Duplicate window IDs and a snapshot with zero windows (Tasks 3, 5).
4. `completedAt` in the future on a manual-refresh result (Task 4).
5. Clock skew in both directions at exactly the five-minute edge and a Mac sleeping past the next-change instant (Task 6).

## Risks

- **Spec-silent wire details** (dates, precision, limit state) harden into fixtures in P1-M7; settle them before Task 1 rather than after.
- **Candidate current-data windows** may change after calibration; keep them in one function so P1-M10 and P1-M11 edit a single value.
- **Over-building Application concerns** (reduction, retention across reads) into Domain; `SourceSnapshot` stays a record until P1-M5.
- **Transport records drifting** from the codec P1-M7 writes; keep fields exactly as domain.md lists and let P1-M7 raise changes through the changelog.
