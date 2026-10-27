# P1-M16 validation record

Status: Active

Current automated evidence and upstream handoff for the Watch milestone. Paired-device observations
remain in the separate owner-run runbook and must not be inferred from simulator or package tests.

## Implementation baseline

| Item | Recorded state |
|---|---|
| Starting revision | `102503e46776` (`docs(phase): record milestone review updates`, 2026-10-27) |
| Starting worktree | Clean; the current uncommitted diff is M16 implementation and documentation work. |
| iPhone destination | `platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.1` |
| iPad destination | `platform=iOS Simulator,name=iPad Air 11-inch (M2),OS=26.1` |
| Watch destination | `platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)` |
| Generated project | `Scripts/generate-project.sh`; `ResetRadar.xcodeproj` remains ignored and generated from `project.yml`. |

## M14/M15 handoff inspected

- `FileReaderStore` replaces one `ReaderState` value transactionally. `IngestRelaySnapshot` marks
  `needsAppReconcile` before post-commit work, and `AfterCommitPipeline` clears it only for the same
  publisher and committed sequence.
- App commits run widget reload, notification reconciliation, Live Activity reconciliation, and
  the installed Watch step in order. Widget commits leave durable app reconciliation for launch.
- iPhone Forget Mac persists the local clear, the monotonic Watch delivery revision, and
  `watchErasePending` before attempting WatchConnectivity or secret cleanup. Pairing status keeps
  pending and confirmed Watch erasure distinct.
- iPad composition has no Watch stage. The iPhone composition creates the shared session bridge,
  forwards current ReaderStore snapshots, serves bounded interactive replies, and consumes typed
  erase receipts.
- The Watch app and rectangular complication use their Watch-side App Group cache only. The Watch
  target imports no Transport or provider adapter, and the complication has no WatchConnectivity
  dependency.
- `project.yml` embeds the Watch app in the iPhone app and the complication in the Watch app, with
  the approved identifiers and App Group entitlements. The Watch test plan includes Domain,
  Application, Storage, WatchSync, UI, and the Watch app test bundle.

M9 deployment/billing, remaining M14 physical reader checks, and M15 notification, widget, and
ActivityKit device checks remain with those milestones. This handoff record neither waives nor
passes them.

## Automated evidence

| Date | Command/scope | Result |
|---|---|---|
| 2026-10-27 | Focused Swift package run for WatchSync, Application, and Account Palette | Passed: WatchSync 6 tests, Account Palette 2 tests, Application 275 tests before the later M16 additions; the final run supersedes this result. |
| 2026-10-27 | `Scripts/generate-project.sh && make test-watch` | Passed once after WatchSync, AppIntent, and timeline-policy compile repairs; the final run supersedes this result. |
| 2026-10-27 | `git diff --check` | Passed during implementation; rerun in the final gate. |
| 2026-10-27 | `make format-check lint imports` | Passed after the final refactor: swift-format clean, SwiftLint reported zero violations across 371 files, and the import-boundary package build completed. |
| 2026-10-27 | Focused Swift package run for WatchSync, Application, UI, and Storage | Passed after final formatting: WatchSync 12 tests in 3 suites, UI 29 tests in 9 suites, Application 279 tests in 38 suites, and all selected Storage suites. |
| 2026-10-27 | Focused Claude Code configurator package run | Passed 20 tests in 3 suites. This isolated an earlier concurrent Xcode Mac-run failure as process interference. |
| 2026-10-27 | `Scripts/generate-project.sh && make test-watch` | Passed on the final formatted code; Xcode completed the Watch test action in 24.658 seconds. |
| 2026-10-27 | `make mac-arch-check` | Passed: every Mac target setting and both inspected Release Mach-O executables were arm64 only. |
| 2026-10-27 | `make test-mac` | Passed when rerun alone. The first run overlapped relay CI and transiently failed 12 configurator cases that all passed both the focused package rerun and this isolated complete run. |
| 2026-10-27 | `make relay-ci` | Passed: install, 28 Workers Vitest tests, 31 script tests, typecheck, generated bindings, and Wrangler deployment dry-run. `npm audit` reported 4 moderate and 3 high dependency findings; dependency changes require separate owner approval. |
| 2026-10-27 | Signed IPA package and entitlement inspection | Passed for the existing 4,418,883-byte IPA: the iPhone app embeds the Watch app and Watch complication; the approved four app/extension identifiers are present; every component has the shared App Group; Watch components expose only application/team identity, App Group, and development-signing entitlements. |

## Simulator gate blocker

A combined iPhone/iPad invocation before the final lint-driven refactor completed the iPhone
destination successfully. The iPad destination then lost multiple test runners with `Test crashed
with signal kill`; Xcode spent its 600-second diagnostic window on the iPad simulator and the
command failed. The result bundle showed runner crashes rather than assertion failures. Because
the post-refactor iPhone rerun could not materialize a worker, the earlier iPhone pass is not
claimed as final-gate evidence.

Subsequent isolated iPad runs could not materialize an XCTest worker. Recovery attempts were
limited to the approved simulator models and included terminating only the stuck Xcode processes,
restarting the named iPad simulator, erasing only that test simulator, restarting the user-level
CoreSimulator service after shutting down the named iPhone and iPad simulators, restarting
`testmanagerd`, and an otherwise identical serial run with Xcode parallel testing disabled. Each
run remained blocked waiting for workers beyond the earlier completion window. After the service
restart, an isolated iPhone rerun developed the same missing-worker condition; it was terminated
after the same bounded observation. No assertion from the final code failed in these retries.

This is not accepted as a gate pass. The complete `make gate` row and M16 remain open until a clean
host session completes the documented iPhone/iPad command.

## Physical-device readiness

The reference physical iPhone 17 Pro Max was attached and reported available and paired by
`devicectl`. The paired physical Watch was not exposed as a separately available installation
target, and the required workflow uses Sideloadly plus owner interaction. No install or device
observation is inferred from attachment or package inspection.

The sandboxed SwiftPM manifest cannot start because the toolchain invokes `sandbox-exec` and lacks
its module-cache access. The same documented commands run successfully with the approved
toolchain access; this is an execution-environment constraint, not accepted evidence for a skipped
check.

## Still required for closure

- the final complete contribution gate after the local XCTest worker service can launch the
  iPhone/iPad destinations cleanly;
- rendered Watch app/background-delivery and complication observations on the reference devices;
- the complete runtime security table with Watch rows closed; and
- every sanitized reference-device observation in the paired Watch runbook, including the initial
  free-signed install and Watch App Group proof.
