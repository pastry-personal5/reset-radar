# P1-M15: Scheduling overview

Status: Active

Deliver per-device reset notifications, opportunistic iPhone and iPad background refresh, configurable widgets, a read-only App Intent, and user-started iPhone Reset Live Activities. The [sequence](milestone-15-scheduling-sequence.md) orders the implementation and evidence against the existing [Scheduling](../architecture/scheduling.md), [iOS app](../architecture/ios-app.md), and [Application](../architecture/application.md) contracts.

## Entry and review

- The implemented M14 reader handoff is on `main` through `c9735ff`. It provides the universal
  reader object graph, shared reader bundle and Keychain group, foreground/manual ingest,
  `ReaderEnvironment`, synthetic scenarios, and restored iPhone/iPad tests. The complete gate
  passed after the M15/M16 plans were integrated on 2026-10-27. M14 remains `Active` for its
  separately owned physical-device, manual-refresh, packaging, and re-sign evidence; do not
  convert that open evidence into M15 evidence.
- M14 remains M15's implementation dependency. Per the owner's 2026-10-26 instruction, M9's exit gate is not an M15 planning or implementation prerequisite. This does not mark M9 complete or turn its waived cellular check into evidence for widgets or background refresh.
- On 2026-10-26 the owner confirmed that reset notifications, small Home Screen widgets, rectangular Lock Screen widgets, and the read-only App Intent cover **all valid provider-reported windows**. Medium widgets still show the two standard windows. A five-hour Live Activity whose reading ages into stale state stays visible as stale until its known reset; it ends when the app next executes at or after that reset. If the app does not run, ActivityKit ends it by its eight-hour active-lifetime limit; no exact reset-time app wake is promised.
- On 2026-10-27 the owner chose the default notification sound and foreground banners on iPhone,
  iPad, and Mac. Provisional authorization remains quiet.
- On 2026-10-27 the owner chose a 30-minute routine WidgetKit reload request interval. Known
  presentation transitions remain timeline entries, and the interval is not a delivery promise.
- On 2026-10-27 the owner required fresh data to start a Live Activity, rejected resets outside
  the activity's `startedAt + 8 hours` horizon, and prioritized the soonest reset in the Dynamic
  Island with stable global account number as the tie-breaker. The owner approved the existing
  local Scheduling product for the Mac target and direct Domain/Application dependencies for
  Scheduling tests.
- The implementation baseline injected `PendingSchedulingReloader`,
  `PendingNotificationScheduler`, and `PendingLiveActivityController`; the widget bundle and
  `ResetRadarScheduling` implementation were placeholders, and the Mac hook was a no-op. The
  current M15 work replaces those seams and is tracked in the
  [validation record](milestone-15-scheduling-validation.md). The review findings below remain the
  acceptance criteria; an implemented path is not device evidence by itself.

## In scope

- Implement the `ResetRadarScheduling` adapters for local reset notification requests on iPhone, iPad, and Mac, and ActivityKit operations on iPhone. Wire the M12 Mac post-commit notification hook, per-window controls in Account Details, and authorization status in Settings. Keep opt-in off by default and device-local; request permission only from a user action.
- Reconcile one pending request per opted-in valid provider-reported window against the latest committed snapshot, including additional Account Details windows. Keep standard Home selections stable across provider-scope changes, and tie additional selections to their concrete `WindowID` so a new scope or limit cannot inherit an old opt-in. Replace or cancel a request when its reset or copy changes, the window disappears or expires, the account or source becomes ineligible, authorization changes, or the owner changes the opt-in. Keep the fire instant absolute through time-zone changes. The widget extension may reconcile already-authorized requests after its own commit, never prompt.
- Wire one `BGAppRefreshTask` identifier, policy-computed earliest begin date, replacement
  submission, cancellation on expiration, and an honest completion result. Expiration releases
  the fetch claim without recording a relay failure or backoff. Continue foreground and manual
  paths from M14. No background timing promise or push path is added.
- Replace the widget scaffold with configurable `systemSmall` Home Screen and `accessoryRectangular` Lock Screen widgets for any valid window, plus a `systemMedium` Home Screen widget for one account's two standard windows. Use an exact saved selection, the committed cache, policy-limited relay ingest on a WidgetKit reload, timeline entries at presentation changes, and an unavailable state when a selected window disappears. Add the read-only all-window App Intent with no network call. Treat reload dates as requests, never delivery guarantees.
- Add iPhone-only foreground Start and Stop Live Activity actions for an eligible five-hour
  standard window, local updates and end conditions, and Lock Screen/Dynamic Island views with a
  system countdown and stale presentation through the known reset. ActivityKit availability and
  the iPad absence are explicit. Starting requires a fresh reading whose reset fits within the
  eight-hour horizon; a running activity ends if an update moves its reset beyond that horizon.
  The soonest reset receives highest Dynamic Island relevance, with stable account number as the
  tie-breaker. Perform the required ActivityKit device spike before freezing the implementation.
- Complete the app/widget reconciliation handoff and Forget Mac cleanup. An interrupted widget notification pass remains retryable; the app catches up Live Activities and other pending work on its next execution. Widget and activity surfaces never show preflight, invalid, or post-forget data.
- Verify tests and owner-run physical-device behavior, including app/extension App Group and Keychain access, notification delivery and time-zone behavior, WidgetKit reload limits, Live Activity lifecycle, background-task intervals over 24 hours, and Sideloadly re-sign preservation of extension access.

## Out of scope

- WatchSync, the Watch app and complication, and Watch delivery/erase receipts remain P1-M16. The existing pending-clear contract remains intact.
- Provider polling, relay deployment or protocol changes, APNs, push updates, percentage alerts, and manual reset values remain outside M15.
- M9's Cloudflare verdict and M14's pairing/manual-refresh device evidence remain separately owned. M15 device evidence records what it actually exercises.

## Review findings to resolve during implementation

1. The code has no `WindowSelection`; `PreferenceStore`, `ResetRequest`, notification identifiers,
   and reconciliation still support only standard `AccountWindow`s. Add the Domain selection and
   exact resolver first, then migrate existing standard preference keys without changing their
   meaning. Persist the versioned selection value, use a bounded digest-based identifier for an
   additional `WindowID`, and keep the legacy standard request identifiers stable. Widget and App
   Intent entity identifiers use the same versioned identity and return an unavailable placeholder
   for a saved additional selection that is temporarily absent.
2. `IngestRelaySnapshot` currently sets `needsAppReconcile` only for a widget commit. An app can
   crash after its atomic snapshot commit and before post-commit work, losing every surface update.
   Set the marker in the same transaction for every newer reader snapshot. Carry publisher ID and
   relay sequence in `CommitEvent`; clear the marker only after every installed stage reports
   success and a transaction proves the same publisher/sequence is still current. A newer commit,
   stage failure, process cancellation, or marker-write failure retains the marker. Run pending
   work before the launch/foreground network read.
3. `AfterCommitStep` and several system ports erase failures, while
   `AfterCommitPipeline.run` suppresses the final state-write error. Give each required stage a
   typed `complete` or `retryable` outcome. Widget/complication reload counts as complete once the
   system request is submitted, not once the surface renders. Notification read, add, remove, and
   read-back failures remain retryable; an unreadable activity store does too. Unsupported stages
   on a platform are explicit no-ops rather than silent placeholders.
4. `IngestRelaySnapshot` maps a cancelled URL request to a transport failure and backoff. A
   `BGAppRefreshTask` expiration is not evidence that the relay is offline. Add a cancellation path
   that releases only the matching lease, preserves the last transport status, ETag, and failure
   count, completes the background task once as unsuccessful, and still submits the replacement
   request. A late network result after lease release cannot commit.
5. The authorization model lacks `provisional`, request errors, and a future-unknown state, while
   `ReaderSystemStatus` separately maps the same framework status and currently collapses
   provisional into authorized. Make the scheduling adapter the single authorization source.
   A denied or provisional choice stays recorded; a framework failure or unknown status is not
   treated as denial, authorization, or permission to prompt again. The widget never requests
   authorization.
6. Notification cleanup needs two views of pending requests: typed supported Reset Radar requests
   for reconciliation, and every identifier in the reserved Reset Radar namespace for cleanup.
   Hashing must not make the request irreversible, so versioned non-secret selection metadata
   travels in `userInfo`. Unknown app notifications remain untouched; malformed owned requests
   are removed. Because removal has no completion result, reconciliation and Forget Mac read the
   pending list back and remain retryable while an owned request is still present. A platform
   capacity failure is a failed evidence gate, not permission to silently prioritize windows.
7. `ResetRequest` and activity content lack the bounded snapshot-derived alias, product, window
   display descriptor, source state, and precision required by the approved UI. Application owns
   the typed desired state; Scheduling owns localized framework copy and rendering attributes and
   never reads Storage. Compare the complete pending request, not only `fireAt`. Keep alias in
   dynamic Live Activity content and add an explicit stop operation and running-state query.
8. The iOS app and widget must construct `DefaultsPreferenceStore` from the shared App Group
   `UserDefaults` suite in Release. Development fallback uses an isolated debug suite, and the Mac
   uses its target-local suite. Test independent app/extension instances, first write/read in each
   direction, exact-ID migration, and an unavailable suite without falling back to unrelated
   standard defaults.
9. `LoadHome` exposes standard slots, while `LoadUsageDetails` exposes all current windows. Add a
   small Application query that resolves one `WindowSelection` and returns the bounded account,
   product, window, presentation, and next-change values used by widgets and the read-only App
   Intent. The dynamic picker still lists choices from the complete committed-cache details. The
   App Intent returns identifying context as well as percentage, reset, source, observation time,
   and state; neither path fetches the relay.
10. The current fixed fifteen-minute widget reload request can consume 96 requests per day per
    configured widget, while Apple's documented typical budget is 40–70 refreshes over a rolling
    24-hour period. Timeline entries should carry predictable stale/reset transitions and dynamic
    countdowns without extension execution. Use the owner-selected 30-minute routine interval as
    an earliest request, coalesce app-triggered reloads by widget kind, and use `.never` when
    unpaired or local cleanup blocks reads. [Apple WidgetKit guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)
11. Register the sole `BGAppRefreshTask` before launch completes and only once. Submitting another
    request with the same identifier replaces the queued request, so do not create a cancel/submit
    gap. Test registration rejection, submission errors, system cancellation, completion exactly
    once, and resubmission. `earliestBeginDate` is only a lower bound. [Apple background-task guidance](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)
12. The reference app can run one Live Activity for each standard five-hour account window. The
    owner chose fresh-only starts, an eligibility horizon of `startedAt + 8 hours`, immediate end
    when an update moves a reset beyond that horizon, and soonest-reset Dynamic Island priority
    with stable global account number as the tie-breaker. Device evidence must distinguish the
    app's policy end from system end at eight hours and Lock Screen retention for up to four more
    hours. [Apple ActivityKit guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## Selection contract

The approved [UX](../ux-gui.md#account-details) and the owner's 2026-10-26 answers require all valid windows for reset notifications, small Home Screen and rectangular Lock Screen widgets, and the read-only App Intent. Model a saved `WindowSelection` as either the stable `AccountWindow` for an account's default five-hour or weekly window, or the concrete `WindowID` for an additional window. The latter includes provider scope and limit identity, so a changed or removed window becomes unavailable rather than silently selecting a sibling. Keep the existing standard opt-in values when migrating storage. A missing additional window has no scheduled request; a subsequent report of the exact same identity resumes its retained opt-in and widget selection, while a different identity needs a new choice. Medium widgets, Home rings, Watch complication, and five-hour Live Activities continue to use standard windows.

## Resolved owner decisions

- Reset notifications use the default sound and show foreground banners on iPhone, iPad, and Mac;
  provisional authorization remains quiet.
- Widget timelines request routine reload after 30 minutes, as an earliest request only.
- Live Activity starts require a fresh reading and a reset no later than `startedAt + 8 hours`.
  A later reset update outside that horizon ends the activity immediately. The soonest reset has
  highest Dynamic Island relevance, with stable global account number as the tie-breaker.
- The Mac target may link the existing local `ResetRadarScheduling` product. Scheduling tests may
  depend directly on Domain and Application. No external dependency is added.

## Completion checklist

- [x] Implement and verify the M15 scheduling product: selection-aware notification reconciliation,
  app and Mac framework composition, background refresh, widgets/App Intent, and iPhone Live
  Activities. Evidence: 443 focused Domain, Application, Storage, and Scheduling tests plus the
  2026-10-27 [M15 validation record](milestone-15-scheduling-validation.md) and passing automated
  contribution gate; physical-device and elapsed-time evidence remains separately required below.
- [x] Enforce the owner's Apple-silicon-only Mac build decision for every configuration and add a
  gate check that builds the unsigned Release app and helper, proves both Mach-O executables contain
  only `arm64`, and records the supported architecture in the binding build documentation.
  Evidence: on 2026-10-27 `make mac-arch-check` resolved the app, helper, and Mac test target to
  `arm64` with `x86_64` excluded in Development and Release, then built the unsigned Release app
  and verified its two Mach-O executables were arm64-only. `git diff --check` also passed.

- [x] The post-M14 plan review checks the current reader implementation and current Apple platform
  contracts, records every correction in the affected architecture documents, and either resolves
  each newly exposed product choice with the owner or leaves implementation explicitly blocked on
  that choice. Evidence: the 2026-10-27 review findings, owner interview, linked contract updates,
  delegated passing complete gate, changed-document link check, and `git diff --check`.
- [x] Planning review covers the binding UX, owner decisions, Application and Storage contracts, M14 handoff, physical-device evidence, and the M9 exception; the overview and sequence are linked from the phase plan and docs index. Evidence: the two review passes and linked planning documents on 2026-10-26. At that review's baseline the iOS runs were still suspended; M14 subsequently restored them.
- [x] The owner resolved all-window notification, widget, App Intent, exact-ID return, rectangular Lock Screen family, and stale Live Activity behavior on 2026-10-26; the selection and cleanup contract is recorded above and in [owner decisions](owner-decisions.md). Implementation evidence remains open in the items below.
- [x] The second review reconciled the owner choices with Domain, Application, Storage, Scheduling, iOS composition, product, and UX documents; it corrected M9's phase dependency and checked background-task, WidgetKit, and ActivityKit assumptions against the linked Apple documentation. Evidence: the review findings, selection contract, updated design documents, and phase changelog on 2026-10-26.
- [ ] M14's code handoff and the final pre-M15 baseline are recorded after M14's concurrent
  close-out changes settle; M15 does not absorb or overwrite M14's open owner evidence.
- [x] The 2026-10-27 owner decisions above are recorded in owner decisions and reconciled through product,
  UX, architecture, plan, and changelog documents before affected implementation begins.
- [ ] Scheduling adapters, app and Mac composition, controls, and authorization behavior pass focused tests for all-window opt-in, standard-key migration, exact-ID return, provisional/denied states, absolute UTC triggers, copy changes, replacement, cancellation, the maximum valid window set, and no permission prompt from the widget.
- [ ] Cross-process notification reconciliation and `needsAppReconcile` catch-up survive an app
  crash immediately after commit, gate contention, expiration, scheduling failure in either
  process, app/widget races, and Forget Mac without resurrecting old data; Forget Mac confirms
  owned pending requests were removed before reporting local cleanup complete.
- [ ] Background task registration, replacement submission, policy date, expiration without a
  false transport failure, completion exactly once, lease release, late-result rejection, and
  resubmission pass deterministic tests. The owner records actual intervals over 24 hours without
  claiming a guaranteed cadence.
- [ ] All approved widget sizes, exact all-window selection for small/Lock Screen widgets and App Intent, medium standard-window configuration, timeline changes, missing-window presentation, policy-limited reload ingest, and read-only App Intent pass focused tests and iPhone/iPad inspection without assuming system reload timing.
- [ ] The ActivityKit spike is recorded before implementation is frozen. iPhone start/update/stale/end behavior and Lock Screen/Dynamic Island rendering pass focused and physical-device checks; iPad exposes no Start control.
- [ ] Physical iPhone/iPad and Mac checks record notification replacement/cancellation, time-zone display, widget-only commit and extension expiry, first-unlock sharing, Sideloadly re-sign preservation, and stated limits of the evidence without retaining secrets or raw usage.
- [x] The final complete contribution-guide gate, including the M14-restored iPhone and iPad runs,
  passes; affected product, architecture, installation, and phase docs match the result. Evidence:
  the 2026-10-27 [M15 validation record](milestone-15-scheduling-validation.md). M15 remains
  `Active` because the unchecked runtime and handoff items below are still required.
