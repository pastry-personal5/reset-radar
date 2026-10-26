# P1-M15: Scheduling validation

Status: Active

This record separates implemented and automated M15 evidence from the owner-run device and elapsed-time checks that remain open. It contains no credentials, pairing material, provider payloads, account identifiers, or raw usage.

## Implementation review

The 2026-10-27 review corrected the draft in the following areas:

- exact standard-or-additional `WindowSelection` identity, bounded digest identifiers, legacy
  standard preference keys, exact-selection widget lookup, and preflight/cleanup cache hiding;
- complete notification desired state and metadata, provisional and future authorization states,
  owned-request cleanup with read-back, foreground presentation policy, Mac composition, and
  reconciliation after owner, commit, activation, alias, clock, and time-zone changes;
- atomic `needsAppReconcile` marking for every newer commit, publisher/sequence-checked clearing,
  explicit complete/retryable stages, pairing-preflight catch-up, and background expiration that
  releases its lease without recording a transport failure;
- one registered background-refresh path, policy-derived replacement submission, resubmission
  before completion, and visible registration/submission failure state;
- small and rectangular all-window widgets, medium standard-window widgets, a cache-only read
  intent, 30-minute routine requests, known transition entries, and `.never` while usage is not
  eligible to be shown; and
- fresh-only iPhone Live Activity start, fixed eight-hour horizon, dynamic alias/content,
  deterministic relevance, explicit Stop, stale presentation, invalidation/end behavior, and no
  iPad controller.

The review also fixed defects found after the first implementation pass: additional-window system
identifiers and preference keys are bounded; provisional authorization schedules quietly; widget
reads cannot expose pairing preflight data; medium widgets may refresh; notification metadata
retains subsecond absolute fire instants; reset opt-ins remain editable when no future reset is
currently known; Mac Settings observes authorization changes; and running Live Activities end for
an incompatible source. The final simulator pass exposed and fixed two more defects: expiration
could strand a fetch lease because the storage lock rejects a cancelled task, and making the new
window controls individually accessible had removed the parent window's spoken state summary.
Lease cleanup now runs in a fresh ownership-checked task, and the parent summary coexists with its
interactive children.

## Automated evidence

Final focused Swift package validation on 2026-10-27 passed 79 Domain tests in 13 suites, 270
Application tests in 37 suites, 88 Storage tests in 16 suites, and six Scheduling tests in one
suite. Those 443 tests cover exact selection and preference migration, durable catch-up,
cancellation and late-result rejection, notification reconciliation, fresh-only activity starts,
horizon and relevance policy, background completion/expiration, retryable stages, marker-write
failure, incompatible-source cleanup, widget queries, and absolute subsecond trigger mapping.

The same package run built successfully but its full test result was not green in this host:
one pre-existing Transport Keychain authentication-context test and five ProviderAdapters Claude
Code restore tests failed in environment-dependent system stubs. These failures are not counted as
passing M15 evidence and must be distinguished from a final clean contribution gate.

## Open runtime evidence

The following claims remain owner-run and are not implied by simulator builds or unit tests:

- the ActivityKit spike and physical iPhone/iPad Start, update, stale, relevance, Stop, policy-end,
  system-end, and no-iPad-action checks;
- notification delivery, foreground banner/default sound, provisional quiet behavior, capacity,
  replacement/cancellation, time-zone display, and Mac background collection with its window
  closed;
- widget configuration and late-timeline behavior on iPhone and iPad, widget-only commit catch-up,
  first-unlock App Group/Keychain sharing, and extension behavior after Sideloadly re-sign; and
- at least 24 hours of observed background executions, recording actual intervals without
  claiming the requested earliest date is a cadence guarantee.

Use the [M15 device runbook](../research/m15-scheduling-device-runbook.md) for these checks. M15
stays `Active`, and its physical and elapsed-time checklist items stay unchecked, until dated
redacted results are added here.

## Final gate

The automated contribution gate passed on 2026-10-27 over the dirty working tree containing this
M15 review and the already-present concurrent M14, architecture, and sideloading documentation
changes; no commit revision was assigned. The gate was run as its individual documented commands
so SwiftPM and Xcode could use isolated `/private/tmp` caches and so Xcode checks could run in the
main environment after the delegated runner's nested sandbox rejected `sandbox-exec`:

- project generation, `Scripts/lint-swift-format.sh`, `swiftlint --strict --no-cache`,
  `Scripts/check-imports.sh`, and `git diff --check` passed; strict lint reported zero violations
  across 361 files;
- `Scripts/check-mac-architecture.sh` built the isolated unsigned Release product and verified the
  two Mac Mach-O executables are arm64-only;
- the macOS test scheme passed on `platform=macOS`, and generic unsigned Development builds passed
  for macOS and iOS;
- the complete `ResetRadar` scheme passed concurrently on
  `platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.1` and
  `platform=iOS Simulator,name=iPad Air 11-inch (M2),OS=26.1`, including the app and UI tests; and
- the relay passed 28 Workers Vitest tests, 31 shared Node tests, strict TypeScript checking, and
  the Wrangler deployment dry run.

This closes the automated gate, not the runtime evidence above. M15 remains `Active`, and its
physical and elapsed-time checklist items remain unchecked.
