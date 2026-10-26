# P1-M14: iOS core app sequence

Status: Active

Implement the [M14 overview](milestone-14-ios-core-app-overview.md) through the existing
[iOS composition contract](../architecture/ios-app.md), [Application use cases](../architecture/application.md),
and [approved UX](../ux-gui.md). This is implementation order and evidence planning, not a new
system design.

## 1. Establish the baseline and device procedure

Confirm the overview entry criteria and run the current complete gate. Inspect the generated
`ResetRadar` scheme, iPhone 17 Pro Max and iPad Air 11-inch (M2) iOS 26.1 simulator availability,
entitlements, scaffold app/test targets, and the current `ResetRadarKit` interfaces. In particular,
use `LoadHome`, `LoadUsageDetails`, `LoadPairingStatus`, and `VisibleSnapshot` rather than adding a
second account-details query. Keep the Xcode project generated from `project.yml`. Write the
owner-run install and re-sign procedure before
handling real pairing material; the procedure records commands and sanitized observations, never
Apple credentials, pairing text, tokens, keys, or raw usage.

## 2. Compose the reader and prove local transactions

Build one app-owned environment that passes the App Group URL and entitlement-expanded Keychain
access group into Storage and Transport. Inject the clock, relay transport, Keychain backend,
camera/pasteboard boundary, scene events, and local selection store so tests can drive failures.
Use `FileReaderStore` and `ReaderSnapshotStore` over the same atomic bundle; keep network work
outside short locked sections and hold the app background assertion only for each claim or commit.
Wire staging recovery, activation retry, and pending local Forget Mac cleanup at launch before
starting a reader fetch. Verify first-unlock errors, cross-process lease behavior with an
independent store instance, and crash-safe transaction boundaries with focused tests. M15 adds
the actual widget process and suspension-expiry device exercise.

## 3. Pair, ingest, refresh, and forget

Connect the QR scanner and manual paste to `AcceptPairing`: decode and preview, display the exact
package confirmation code, require explicit confirmation, preflight without activation, save
secrets and state, then activate. A lost activation response resumes idempotently. A relay `401`
after expiry or revocation returns to setup. Cover an authenticated first-publish `404`, invalid
packages, and a failed local save without activation. Pairing a different Mac requires Forget Mac
first. Request camera access only for scanning; leave manual paste usable if access is denied.
Avoid automatic clipboard reads, persistence of the raw package, and logging of its secrets.

Drive `IngestRelaySnapshot` on foreground activation and one tick every 60 seconds while a scene
is active. Use the policy's claim and outcome rather than a view-owned timer threshold. Connect
the visible Refresh actions to `RequestMacRefresh` only for Codex targets; cancel the 45-second
result wait when the scene becomes inactive without repeating the POST. A saved matching request
marker may resume within its original deadline; expiry never authorizes an automatic new POST.
Use the ordinary relay-read outcome for Claude Code. Show relay contact, accepted request, and
matching Mac result as distinct states. Reload read models after commits, transport changes, and
their next presentation change instant. Test authenticated matching results, sibling outcomes,
unrelated publications, rate limiting, timeouts, token failure, and stale-cache retention.

Connect owner-confirmed Forget Mac through the existing use case. Persist the clear and pending
Watch-erasure marker, erase the local cache and secrets, cancel any existing local surfaces, and
retry unfinished cleanup on launch. Until M16 provides Watch delivery, an injected link can leave
the clear pending but must never fabricate a receipt; the UI must say what remains on an
unreachable Watch. Verify old in-flight results cannot restore the former publisher's state.

## 4. Build the approved iPhone and iPad presentation

Implement shared screen models and components in `ResetRadarUI` over Application read models,
keeping adapter imports out of the UI module. Compose the five fixed destinations in the app.
Home shows configured rows in localized natural alias order and the highest-priority Setup
Banner, including partial setup. Each row retains two standard rings and a neutral Account
Details action; unavailable is not 0% and every status has text, symbol, and accessibility copy.
Account Details shows standard windows first, then all valid additional windows with local reset
time, freshness, provenance, and the account-specific Refresh outcome.

The reader knows configured accounts only after a visible authenticated publication. Present
pairing activation and awaiting first publication as separate empty Home states, and keep rows
visible with a sync problem when a later read fails. Derive banner and Pairing & Sync copy from
`LoadPairingStatus` and transport state, not from an empty `LoadHome` alone. Never expose the
validated preflight snapshot while activation is pending.

On iPhone, push details from a row or ring and show the selected ring's window first. On iPad,
keep list and details in a split view, restore a valid device-local selection, and use the first
ordered account when that selection disappears; clear the selection when the list empties. Use
stable account IDs so a changed alias does not redirect details. Add Settings with Pairing & Sync,
Privacy & Data, Diagnostics, and About. Show notification authorization status and, on iPhone, Live Activity
authorization status without offering M15 controls before their drivers exist. Use the approved
bitmap metaphors and complete VoiceOver labels. Inspect compact and large accessibility text
layouts, the ring and arrow hit regions, and VoiceOver's row-to-window order. Do not put source
configuration or alias editing on the phone.

## 5. Restore tests, run the device checks, and hand off

Replace smoke-only app and UI tests with focused tests for environment wiring, local recovery,
reader outcomes, navigation, ordering, unavailable rings, iPad selection, settings, and
accessibility. Add the iPhone and iPad `xcodebuild test` invocations to the
[contribution-guide gate](../contribution-guide.md#required-validation) and `Makefile`; leave
the Watch test run suspended for M16. Run the full gate on the final worktree.

Build and inspect an installable IPA with the existing app, widget, and embedded Watch targets.
With the owner present, use Sideloadly and the free Personal Team on the reference iPhone and
iPad, inspect the installed App Group and Keychain entitlements, pair to the approved relay,
verify first-unlock/locked-device behavior and cache persistence, then observe one seven-day
re-sign. A physical cellular read would provide new evidence because M9 waived that check;
record the result without claiming widget, background, or Watch behavior. If signing changes
bundle identity or loses data, stop and return the distribution decision to the owner. Update
the installation guide and record only redacted evidence.

Before real usage takes the manual-refresh path, run the owner-approved synthetic checks for
request authentication, revoked-reader denial, replay and rate limits, sleeping-Mac timeout,
source-result publication and acknowledgement, latency, and worst-case Workers Free accounting.
Record failures as decision points, not as permission to weaken the contract.

Hand M15 the app commit and lifecycle hooks, pending notification/activity reconciliation, and
extension-sharing evidence still due. Hand M16 the saved Watch clear, receipt requirement, and
paired-Watch checks still due. Close the overview only against direct evidence.
