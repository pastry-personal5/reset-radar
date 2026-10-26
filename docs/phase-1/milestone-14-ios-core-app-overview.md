# P1-M14: iOS core app overview

Status: Active

Build the universal iPhone and iPad reader app around the existing Application, Storage, and
Transport contracts. The [sequence](milestone-14-ios-core-app-sequence.md) orders composition,
pairing, refresh, presentation, simulator tests, and owner-run installation evidence. M14 starts
only after its [Phase 1 dependencies](phase-1.md#order-and-dependencies) are done.

## Goal and entry

An owner can pair an iPhone or iPad with the Mac, read and retain authenticated encrypted relay
snapshots, view every configured account, request the approved account-scoped Codex refresh, and
forget the Mac locally. The iPhone and iPad test runs return to the complete gate. The first
installable iOS build starts the seven-day Sideloadly re-sign observation.

Entry evidence must show M6, M7, M9, and M13 `Done`, including M9's deployed synthetic-data
verdict and any accepted limitations. The M9 cellular waiver does not prove iOS runtime behavior.
Record the starting revision, worktree state, available iOS 26.1 simulator destinations, and a
passing baseline gate before implementation. If M9 fails a criterion, follow its owner-decision
path before starting M14. M10's account-aware contracts must be present in the worktree; do not
reintroduce the earlier single-account model.

## Entry and baseline record

Recorded on 2026-10-26, when the owner directed completion of M14:

- **Revision.** `e1abe5d` on `main`. The worktree already held the uncommitted M14 plan, the
  restored iOS gate commands, and an earlier partial reader draft.
- **Destinations.** Xcode 27.1 with the iOS 26.1 iPhone 17 Pro Max and iPad Air 11-inch (M2)
  simulators.
- **Dependencies.** M6, M7, and M13 are `Done`. M9 is `Active`: its compatible
  promotion-and-rollback item and its dated verdict are open. M10 is `Active`, and its
  account-aware contracts are present. **The entry criterion is unmet.** The owner's instruction
  started the agent-side work, but it is not recorded as an M9 waiver. The 2026-10-25 owner
  decision lets real usage reach the relay before M9 closes.
- **Baseline.** Project generation and the iPhone build passed. The iPhone test run failed: the
  unsigned Development app had no App Group on the simulator and crashed at launch, and three
  Mac-only Keychain tests ran on iOS. The full gate was not green before implementation.
- **M9 limitation.** M9's cellular waiver remains a waiver. No M14 simulator result is cellular
  evidence. A physical cellular read stays a separate, optional owner observation in the
  [installation procedure](../research/personal-use-sideloading.md#p1-m14-reader-installation-procedure).

## Open owner questions

Implementation choices awaiting owner review. Neither is adopted in a binding architecture
document.

1. **Screen-model placement.** [UI](../architecture/ui.md#screen-models) places observable screen
   models in `ResetRadarUI`. The reader keeps value-type derivations there (`AllowanceDisplay`,
   `WindowSection`, `ReaderSetupStep`, `RefreshFeedback`, `PairingSyncText`, and
   `AccountSelection`). Its published screen state lives in the app's `ReaderEnvironment`, which
   is also the scene, ticker, and manual-refresh driver. The Mac app keeps its screen models in
   the Mac target too. Keep this split, or move the observable state into `ResetRadarUI`?
2. **Unsigned Development storage.** Development builds are unsigned, so the simulator has no App
   Group entitlement. `ReaderComposition` falls back to the app's own Application Support
   directory with the `Debug` flavor, in Development only; Release still fails closed. Keep this
   fallback, or sign Development builds?

## In scope

- One `ResetRadar` object graph with an App Group reader bundle, read-only snapshot facade,
  explicit shared Keychain access group, relay gateway, pairing codec, and injected system
  boundaries. Development storage and secrets stay isolated from the installed app.
- QR scanning and manual paste of the exact pairing package; local confirmation-code comparison,
  authenticated preflight, durable local save before activation, pending-activation retry, and
  recovery or re-pairing through Forget Mac. Never display a preflight snapshot as paired usage.
- Foreground activation and 60-second foreground-tick ingest through `ReaderRefreshPolicy`, plus
  scene-aware manual refresh. Home posts one `allCodex` request; Codex Account Details targets one
  opaque account ID; Claude Code Account Details only reads the relay. Show relay contact and Mac
  completion separately, preserve the last valid cache on failure, and cancel a visible wait when
  the scene leaves the foreground.
- The five-destination Main Toolbar, Home Account List and Setup Banner, iPhone Account Details
  navigation, iPad split Home with device-local selection, per-account window details and
  provenance, and Settings with Pairing & Sync, notification authorization status, iPhone Live
  Activity authorization status, Privacy & Data, Diagnostics, and About. Benefits, Community,
  Insight, and All keep their approved empty-state behavior. Use original neutral, tintable bitmap
  toolbar and Account Details icons.
- Owner-confirmed Forget Mac with atomic local cache and pairing removal, Keychain cleanup,
  retryable interrupted-cleanup state, and honest pending Watch-erasure wording on iPhone. The
  durable Watch clear remains queued until M16 wires WatchConnectivity; M14 never claims a Watch
  was erased without its receipt. Forget Mac does not revoke the relay reader; revocation remains
  a Mac action. No Watch state appears on iPad.
- `ResetRadarTests`, `ResetRadarUITests`, and shared UI component tests for composition and the
  visible reader flows, including the fixed iPhone and iPad simulator destinations. Restore both
  iOS test commands to the documented complete gate.
- A repeatable IPA and Sideloadly installation procedure and owner-run iPhone/iPad checks for
  App Group access, signed Keychain access after first unlock, pairing, cache persistence, and a
  seven-day re-sign. Record sanitized evidence and the scope of any uncompleted device check.
- Synthetic security, latency, rate-limit, sleeping-Mac, and Free-tier evidence for the
  Mac-assisted manual-refresh path before it carries real usage, as required by
  [owner decisions](owner-decisions.md#architecture-review-decisions).

## Boundary and handoff

- [P1-M15](phase-1.md#p1-m15-scheduling) owns `BGTaskScheduler`, notification opt-in and
  reconciliation, widgets, App Intent, Live Activities, and their extension-process ingest and
  physical-device checks. M14 provides the app composition and post-commit handoff points they
  need; it does not claim widget or background-timing behavior is validated.
- [P1-M16](phase-1.md#p1-m16-watch) owns the WatchSync driver, Watch app and complication, clear
  receipt delivery, and paired-Watch installation evidence. M14 persists the pending clear and
  reports it accurately until that delivery path exists.
- No provider credential enters iOS. The phone contacts only the approved HTTPS relay, never a
  Codex or Claude Code source. No protocol, reset rule, dependency, build tool, distribution
  method, or owner-approved UX change is part of this milestone.

## Completion checklist

- [ ] App composition and reader presentation are implemented with focused iPhone and iPad
  simulator tests; evidence will be the generated project targets and the restored documented
  `xcodebuild test` commands.
- [x] Define M14 reader setup, delivery, and Refresh feedback vocabulary in the UX terms;
  distinguish confirming pairing, waiting for Mac data, preserved-cache sync problems, Refresh
  results, cleanup, and Watch-erasure status. Evidence: [UX terms](../ux-terms.md#canonical-ios-pairing-sync-and-refresh-feedback) updated on 2026-10-26.
- [x] Review the existing Application contracts and approved iPhone/iPad UX before implementation;
  correct architecture names and spell out reader visibility, account selection, and refresh
  feedback. Evidence: `LoadHome`, `LoadUsageDetails`, `LoadPairingStatus`, `VisibleSnapshot`,
  `AcceptPairing`, and `RequestMacRefresh` were compared with the iOS/UI architecture and UX docs
  on 2026-10-26; the M14 entry gate and scaffold status remain explicit.
- [ ] Entry criteria and baseline are recorded; M9 limitations are carried into M14's device
  evidence without being described as passing cellular behavior.
- [ ] The iOS composition uses the shared App Group and explicit Keychain access group; physical
  first-unlock, locked-device, and Development/Release isolation checks have dated evidence.
- [ ] Pairing by QR and manual paste, exact-code confirmation, preflight, activation retry,
  expiry/revocation, staging recovery, and re-pair through Forget Mac have focused tests and
  owner-visible results.
- [ ] The reader ingests and commits only authenticated, strictly newer snapshots. Concurrent
  claims, lock/lease expiry, unexpected `304`, invalid envelope, offline relay, and a late result
  after Forget Mac preserve the correct last-valid or cleared state.
- [ ] Home and account-scoped Refresh follow the approved Codex/Claude Code behavior, expose
  per-account outcomes and the 45-second wait/cancellation boundary, and have synthetic tests
  for mismatched or delayed results and an unavailable Mac. The owner-run manual-refresh evidence
  covers authentication, replay/rate limits, sleeping-Mac timeout, encrypted acknowledgement,
  latency, and Free-tier capacity before this path uses real data.
- [ ] iPhone and iPad show the approved navigation, list ordering, empty and unavailable states,
  all valid Account Details windows, provenance, Settings routes, icons, and accessibility labels.
  Activation and first-publication guidance never infer Mac account setup from an empty local
  snapshot. Simulator UI tests exercise both reference destinations and large text sizes.
- [ ] Forget Mac completes local erasure or exposes retryable cleanup, never resurrects an old
  cache, and distinguishes pending from acknowledged Watch erasure. M16's delivery dependency is
  recorded without treating an unreachable Watch as cleared.
- [ ] The iPhone and iPad `xcodebuild test` commands are documented and included in the complete
  gate; project generation, formatting, strict lint, imports, Mac tests, both iOS destinations,
  and relay checks pass from the final worktree.
- [x] iOS simulator test time is measured and reduced without dropping coverage or changing the
  reference simulators: UI tests poll instead of waiting on XCTest's one-second predicate checks,
  and the gate tests both iOS destinations concurrently in one `xcodebuild test`. Evidence on
  2026-10-26: in alternating same-machine runs, the iPhone UI tests fell from 136.7 s and 137.0 s
  to 86.3 s and 87.4 s, and the iPad UI tests from 164.7 s to 101.7 s. The iOS test phase of the
  gate took 109.8 s for both destinations, against 151.3 s plus 210.0 s run one after another
  before. All 524 tests passed, and `make gate` passed in 142.7 s.
- [x] UI tests that launch the same synthetic scenario with the same arguments share one launch,
  in an order where no step changes what a later step checks, and keep every assertion. Evidence
  on 2026-10-26: the 68 UI assertions are unchanged, and four fewer launches run on each
  destination. The iPhone UI suite fell from 86.3 s to 75.5 s and the iPad suite from 101.7 s to
  81.2 s; the iPhone sample ran under load 44. `make gate` passed in 118.5 s, with an iOS phase
  of 93.4 s, and a repeated `make test-ios-ipad` passed in 91.5 s.
- [ ] The owner-run install procedure records package contents and installed entitlements,
  paired-reader behavior on physical iPhone/iPad, and one seven-day Sideloadly re-sign preserving
  the app's pairing and committed sequence. Widget/notification and Watch preservation remain
  separately evidenced in M15/M16.
- [ ] Affected user-facing, setup, phase, and architecture docs match the implementation; M14
  is marked `Done` only after the checklist has direct evidence.
