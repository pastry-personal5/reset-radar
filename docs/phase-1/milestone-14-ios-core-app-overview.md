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
  account-aware contracts are present. The entry criterion was unmet when work started. The
  owner waived the M9 dependency for M14 on 2026-10-26
  ([M9 entry waiver](owner-decisions.md#p1-m14-decisions)); M9 stays `Active`. The 2026-10-25
  owner decision lets real usage reach the relay before M9 closes.
- **Baseline.** Project generation and the iPhone build passed. The iPhone test run failed: the
  unsigned Development app had no App Group on the simulator and crashed at launch, and three
  Mac-only Keychain tests ran on iOS. The full gate was not green before implementation.
- **M9 limitation.** M9's cellular waiver remains a waiver. No M14 simulator result is cellular
  evidence. A physical cellular read stays a separate, optional owner observation in the
  [installation procedure](../research/personal-use-sideloading.md#p1-m14-reader-installation-procedure).

## Owner decisions

On 2026-10-26 the owner resolved both implementation questions and the entry gap. The decisions
are recorded in [owner decisions](owner-decisions.md#p1-m14-decisions):

1. **Screen-model placement.** Keep the split. `ResetRadarUI` holds the value-type presentation
   derivations, and the app's `ReaderEnvironment` holds the observable screen state. Adopted in
   [UI screen models](../architecture/ui.md#screen-models).
2. **Unsigned Development storage.** Keep the Development-only Application Support fallback;
   Release still fails closed. Adopted in [iOS composition](../architecture/ios-app.md#composition).
3. **M9 entry.** M14 proceeds and may close under an owner waiver while M9 stays `Active`.

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

- [x] Publish a user-facing Sideloadly guide for the verified signed-IPA **Normal Install** flow,
  link it from the documentation index and setup guidance, and include a privacy-safe example
  screenshot with the Apple Account, device details, and desktop background redacted. Evidence on
  2026-10-27: [the guide](../user-guide-for-sideloading.md) distinguishes the successful initial
  iPhone install from open renewal and extension checks, and its example image uses opaque
  redactions plus a neutral replacement background.
- [ ] The root Makefile provides a phony `ipa` target that creates the signed iPhone package at
  `.build/ipa/ResetRadar.ipa` using the verified Release archive and `debugging` export flow, but
  preserves an existing package. Evidence pending.
- [x] The root Makefile provides phony `iphone`, `ipad`, and `watch` targets that generate the
  project and build the corresponding Development scheme for each reference simulator without
  enabling the suspended Watch test run. Evidence on 2026-10-27: `make -qp` reports all three as
  phony dependencies of `generate`; `make iphone`, `make ipad`, and `make watch` each build their
  documented reference simulator successfully; and `make help` lists the three targets.
- [x] Give the universal iPhone/iPad app an original, vendor-neutral Home Screen icon; keep an
  editable source, include the compiled icon in both simulator and Release app bundles, and
  inspect it at Home Screen size. Evidence on 2026-10-27: the 1024-pixel opaque icon and editable
  SVG are checked in; a rounded 60-pixel preview remains legible. Generic iOS Simulator and
  unsigned Release builds contain `Assets.car`, `CFBundleIconName=AppIcon`, and both iPhone and
  iPad icon metadata. `make gate` and `git diff --check` pass.
- [x] App composition and reader presentation are implemented with focused iPhone and iPad
  simulator tests; evidence will be the generated project targets and the restored documented
  `xcodebuild test` commands. Evidence on 2026-10-26: the generated `ResetRadar` scheme builds
  the app, widget, and Watch targets. `ResetRadarTests`, `ResetRadarUITests`, and the shared UI
  component tests pass in `make test-ios-ipad` on both reference simulators.
- [x] Define M14 reader setup, delivery, and Refresh feedback vocabulary in the UX terms;
  distinguish confirming pairing, waiting for Mac data, preserved-cache sync problems, Refresh
  results, cleanup, and Watch-erasure status. Evidence: [UX terms](../ux-terms.md#canonical-ios-pairing-sync-and-refresh-feedback) updated on 2026-10-26.
- [x] Review the existing Application contracts and approved iPhone/iPad UX before implementation;
  correct architecture names and spell out reader visibility, account selection, and refresh
  feedback. Evidence: `LoadHome`, `LoadUsageDetails`, `LoadPairingStatus`, `VisibleSnapshot`,
  `AcceptPairing`, and `RequestMacRefresh` were compared with the iOS/UI architecture and UX docs
  on 2026-10-26; the M14 entry gate and scaffold status remain explicit.
- [x] Entry criteria and baseline are recorded; M9 limitations are carried into M14's device
  evidence without being described as passing cellular behavior. Evidence: the
  [entry and baseline record](#entry-and-baseline-record) states that the entry criterion was
  unmet and that the owner waived it on 2026-10-26. The installation procedure records a cellular
  read separately, and no simulator result here is cellular evidence.
- [ ] The iOS composition uses the shared App Group and explicit Keychain access group; physical
  first-unlock, locked-device, and Development/Release isolation checks have dated evidence.
  Agent-side evidence on 2026-10-26: `ReaderCompositionTests` show that Release requires the App
  Group container, that the Keychain group must be the expanded shared group, and that Development
  storage stays in its own `Debug` directory. An unsigned Release build for `generic/platform=iOS`
  embeds `ResetRadarWidgets.appex` and `ResetRadarWatch.app`, with
  `ResetRadarWatchWidgets.appex` inside the Watch app. Its `ResetRadarKeychainAccessGroup` value
  ends in `group.com.unidentifiedstealthstartup.ResetRadar`, and the team prefix stays empty
  until the build is signed. **Open:** the owner-run physical checks.
- [x] Pairing by QR and manual paste, exact-code confirmation, preflight, activation retry,
  expiry/revocation, staging recovery, and re-pair through Forget Mac have focused tests and
  owner-visible results. Agent-side evidence on 2026-10-26: `ReaderPairingTests` cover pasted and
  invalid packages, the confirmation code before any save, lost and overlapping activation, expiry
  or revocation, a first-publication `404`, a failed preflight or local save, staging recovery,
  re-pairing after Forget Mac, and manual paste staying usable when the camera is not. The iPhone
  and iPad UI tests show the camera-unavailable and invalid-package messages. **Open:** the
  simulator has no data scanner, so the owner exercised a real QR scan successfully on
  2026-10-27. No pairing package, confirmation code, token, or usage data was recorded.
- [x] The reader ingests and commits only authenticated, strictly newer snapshots. Concurrent
  claims, lock/lease expiry, unexpected `304`, invalid envelope, offline relay, and a late result
  after Forget Mac preserve the correct last-valid or cleared state. Evidence on 2026-10-26:
  `ReaderDeliveryTests` (strictly newer commits, offline and unverifiable envelopes, unexpected
  `304`, locked secrets, a live lease seen by an independent store, and a late result after
  Forget Mac), with lease expiry in
  `StorageIntegrationTests.concurrentLoserIsInProgressAndExpiredClaimResultIsRejected` and
  `IngestRelaySnapshotTests.aLateResultFromAnExpiredClaimIsRejected`.
- [ ] Home and account-scoped Refresh follow the approved Codex/Claude Code behavior, expose
  per-account outcomes and the 45-second wait/cancellation boundary, and have synthetic tests
  for mismatched or delayed results and an unavailable Mac. The owner-run manual-refresh evidence
  covers authentication, replay/rate limits, sleeping-Mac timeout, encrypted acknowledgement,
  latency, and Free-tier capacity before this path uses real data. Agent-side evidence on
  2026-10-26: `ReaderRefreshTests` cover the single `allCodex` post, an opaque per-account
  target, Claude Code reads without posting, and the 45-second timeout. They also cover leaving
  the foreground without reposting, a mismatched result that keeps waiting until a delayed match
  completes, a sleeping Mac, and per-account lines for rate-limited, already-completed,
  unreachable-relay, and revoked-token refusals. **Open:** the owner-run evidence against the
  deployed relay.
- [x] iPhone and iPad show the approved navigation, list ordering, empty and unavailable states,
  all valid Account Details windows, provenance, Settings routes, icons, and accessibility labels.
  Activation and first-publication guidance never infer Mac account setup from an empty local
  snapshot. Simulator UI tests exercise both reference destinations and large text sizes.
  Evidence on 2026-10-26: `ReaderHomeUITests` and `ReaderSettingsUITests` pass on both reference
  simulators. They include the accessibility-XXXL row and check that an Account Row's
  accessibility elements, which VoiceOver follows by default, run alias, five-hour ring, weekly
  ring, then Account Details at default and accessibility sizes. This is an element-order check,
  not a VoiceOver session. Screenshot inspection of the synthetic paired Home on both simulators,
  at default and accessibility-XXXL sizes, found three defects, now fixed. The iPad sidebar
  overlapped the two rings; it now has room for a full row, and no ring button is narrower than
  its circle. The Account Details bitmap had flattened edges, so the iOS app now uses the intact
  M13 Mac asset. The in-ring percentage stayed small at accessibility sizes, so the row's rings
  now grow with Dynamic Type, up to 96 pt.
- [x] Forget Mac completes local erasure or exposes retryable cleanup, never resurrects an old
  cache, and distinguishes pending from acknowledged Watch erasure. M16's delivery dependency is
  recorded without treating an unreachable Watch as cleared. Evidence on 2026-10-26:
  `ReaderDeliveryTests` (local erasure with a pending Watch clear and no receipt, no iPad Watch
  state, retryable interrupted cleanup, and no restored cache after a late result),
  `ReaderFeedbackTests.watchErasureIsPendingUntilAReceiptAndThenNamesOnlyTheRespondingWatch`,
  `ReaderSettingsUITests.testInterruptedCleanupIsRetryableAndWatchErasureStaysPendingOnIPhone`,
  and the [boundary](#boundary-and-handoff) recording M16's delivery dependency.
- [x] The iPhone and iPad `xcodebuild test` commands are documented and included in the complete
  gate; project generation, formatting, strict lint, imports, Mac tests, both iOS destinations,
  and relay checks pass from the final worktree. Evidence on 2026-10-26: the
  [contribution guide](../contribution-guide.md#required-validation) and `Makefile` run both
  destinations in `make test-ios-ipad`. `make gate` passed in 2 min 0 s from this worktree, with
  0 SwiftLint violations, every iPhone and iPad test case passing, 28 relay tests passing, and a
  clean relay typecheck and deployment dry run.
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
  separately evidenced in M15/M16. Agent-side evidence on 2026-10-26: the Personal Team Release
  archive and `debugging` IPA export succeeded; all four bundles were present, the iOS app and
  widget carried matching App Group and Keychain entitlements, and the exported app signature
  verified with host Keychain access. **Open:** Sideloadly and physical-device evidence.
  Sideloadly 0.71.1's Apple ID Sideload mode reports mandatory bundle-ID changes for this free
  account. On 2026-10-27 its Normal Install mode completed at 100%, and CoreDevice found the main
  app on the reference iPhone under the unchanged identifier. Launch, pairing, extension, and
  automatic seven-day re-sign evidence remain unresolved. The first launch displayed Untrusted
  Developer; after owner trust, Reset Radar launched successfully on 2026-10-27.
- [x] The owner-run installation instructions match the current Xcode Apple Accounts interface,
  do not require a Team ID from a screen that does not show one, and distinguish a verified
  Personal Team IPA export from an unverified export or packaging route. Evidence: the revised
  [installation procedure](../research/personal-use-sideloading.md#p1-m14-reader-installation-procedure)
  and the owner-run signing and installation result. Xcode 27.1's CLI `debugging` export passed
  on 2026-10-26; Sideloadly Normal Install placed the unchanged main app on the reference iPhone,
  and owner trust allowed it to launch on 2026-10-27. Pairing and renewal remain open under the
  broader physical-device checklist.
- [ ] Affected user-facing, setup, phase, and architecture docs match the implementation; M14
  is marked `Done` only after the checklist has direct evidence. Agent-side evidence on
  2026-10-26: [UI](../architecture/ui.md#screen-models) and
  [iOS composition](../architecture/ios-app.md#composition) adopt the owner's decisions and match
  the code. On 2026-10-27 the user, setup, phase, and verification docs were updated for the
  successful physical iPhone QR pairing. **Open:** final closure documentation after the
  remaining owner-run evidence above.
