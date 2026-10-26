# P1-M15: Scheduling sequence

Status: Active

Implementation and verification order for the [M15 overview](milestone-15-scheduling-overview.md). The existing [Scheduling](../architecture/scheduling.md), [iOS app](../architecture/ios-app.md), [Application](../architecture/application.md), [Storage](../architecture/storage.md), and [approved UX](../ux-gui.md) remain the behavior contracts.

## 1. Establish the M14 handoff and baseline

Start from the M14 reader implementation through `c9735ff`, then record the final revision and a
clean complete gate after M14's concurrent close-out work settles. Do not absorb its uncommitted
packaging or evidence edits. Inspect the live `ReaderComposition` and `ReaderEnvironment`, the
placeholder widget bundle, App Group and Keychain entitlements, `ReaderStore` transaction
boundaries, synthetic scenarios, and post-commit seams. Record which M14 owner-run checks remain
open. M9 remains a separate active gate; its exit does not block this work, and M15 tests must not
claim the M9 cellular or billing results.

Use the [M15 scheduling device runbook](../research/m15-scheduling-device-runbook.md) before
using a paired owner device. Record commands, OS and build versions, expected vs observed results,
and elapsed times without tokens, pairing packages, raw provider payloads, or account identifiers.
Start the 24-hour background interval observation as soon as the installable task driver exists.

## 2. Validate ActivityKit behavior and contract gaps

Run the owner-required iPhone ActivityKit spike with synthetic eligible five-hour windows:
foreground start and stop, content and alias update, stale rendering, reset or invalidation end,
person dismissal, several simultaneous activities, Dynamic Island selection, system end near eight
hours, Lock Screen retention for up to four more hours, app suspension, and no Activity on iPad.
Include a stale-at-start reading and a provider reset beyond eight hours. Verify the approved
fresh-only start, `startedAt + 8 hours` horizon, immediate policy end after an out-of-horizon
update, and soonest-reset relevance with stable global account-number ties. Capture any mismatch
with the approved lifecycle; do not replace owner policy with a rule inferred from system limits.

Correct the inner contracts before wiring frameworks. Add `WindowSelection` and its exact resolver;
migrate standard preference keys; carry bounded display descriptors; make authorization and
post-commit outcomes typed; and add a committed publisher/sequence identity to `CommitEvent`.
Every newer reader commit atomically sets `needsAppReconcile`, including app commits. The app
clears it only after all installed stages complete for that same revision. Add a cancellation path
that releases a fetch lease without changing transport state or backoff. Keep policy and
snapshot-derived desired state in Application and framework mapping in Scheduling.

## 3. Implement Scheduling and Mac reset notifications

Implement `NotificationScheduler` with `UNUserNotificationCenter`: map authorized, provisional,
denied, not-determined, failed, and future-unknown states; build versioned namespaced identifiers;
store the non-secret selection schema in `userInfo`; build bounded localized copy from
Application-provided data; and schedule non-repeating UTC calendar triggers for absolute reset
instants. Preserve legacy standard identifiers and use a deterministic digest for additional
windows. Reconcile complete trigger and content state, then read pending requests back. Remove
malformed owned requests, but leave every unrelated identifier untouched. Use
`SetNotificationOptIn` from each Account Details window action; leave denied and provisional
choices recorded and show the correct Settings state rather than repeatedly prompting.

Reconcile after commits, owner choice, permission changes observed on activation,
alias/window-label changes, time-zone/clock changes, account replacement, and startup. Exercise
the largest valid window set the source can supply. If the reference OS cannot retain every desired
request, fail the evidence gate and return to the owner; do not silently choose windows. Use the
default sound and present foreground banners consistently on iPhone, iPad, and Mac while keeping
provisional delivery quiet.

Wire the M12 `ResetNotificationHook` in the Mac environment. Mac General Settings shows authorization state; Account Details owns the per-window control. Exercise background Mac collection with its main window closed, changed reset, removed account, denied permission, and later permission change. Confirm notification work cannot interrupt collection or publication.

Update `project.yml` so `ResetRadarMac` links the existing local `ResetRadarScheduling` product.
Update `ResetRadarKit/Package.swift` so `ResetRadarSchedulingTests` depends directly on
`ResetRadarScheduling`, `ResetRadarDomain`, `ResetRadarApplication`, and
`ResetRadarTestSupport`. Add no external package.

Implement `LiveActivityController` behind iOS-only ActivityKit compilation. Map the
`ResetActivityAttributes` content and `staleDate` from `ReconcileLiveActivities`, keeping
immutable window identity and `startedAt` in static attributes, and alias, source state, precision,
percentage, observation, and reset in dynamic content. Map the Application-provided relevance rank
to `ActivityContent` metadata. List only this app's activities; expose running state;
and make the foreground Account Details action Start or Stop as appropriate. End with immediate
dismissal. Keep the iPad controller unavailable and never start an activity from a background,
widget, or refresh driver. Reject a start whose observation is stale or whose reset exceeds
`startedAt + 8 hours`; end a running activity whose updated reset crosses that horizon. Assign
highest Dynamic Island relevance to the soonest reset, with stable global account number as the
tie-breaker.

## 4. Complete app and widget scheduling pipelines

In the app process, run widget reload, reset-notification reconciliation, and Live Activity
reconciliation after a committed ingest. On launch and foreground activation, reconcile durable
work before starting a network read. Keep the pending marker when any installed stage is
retryable, the final state write fails, or a newer publisher/sequence is current. A submitted
WidgetCenter reload is complete without claiming a rendered update. On Forget Mac, cancel every
identifier in the owned reset namespace and only those identifiers, end this app's activities,
read the pending list back, reload widgets, and retry unfinished local cleanup before pairing
again. A late fetch must not repopulate any surface.

Register the single `BGAppRefreshTask` exactly once before app launch completes, with its checked-in
identifier; a failed registration is a visible diagnostic, not a silent loss of refresh. Submit
the same identifier when leaving the foreground and after each task so the system atomically
replaces its queued request; do not cancel first. Use `ReaderRefreshPolicy.nextBackgroundRequest`,
record submission failure, and retry on the next eligible app event. The expiration handler
cancels ingest and releases its claim without recording offline/backoff. Completion runs exactly
once, after the replacement request is submitted, and reports whether useful work completed.
Do not post a manual Codex request. Test launch, accidental duplicate registration without
actually invoking the fatal system path, replacement submission, reset-proximate dates, first-run
state, expiration before/during each phase, offline or locked Keychain, failed submission, late
result, and resubmission. [Apple's background-task guide](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app) requires registration during launch and treats `earliestBeginDate` as scheduling input, not an execution promise.

Give the widget extension its own injected object graph over the shared bundle, shared App Group
preferences, and Keychain access group. On a WidgetKit timeline request, call
`IngestRelaySnapshot(.widgetReload)` with the bounded client timeout; policy enforces the
five-minute successful-refresh threshold and the shared 15-second minimum. Never use a preflight
or uncommitted response. After a widget commit, reconcile already-opted-in notifications within
the remaining extension time while leaving app-only work pending. Verify bidirectional preference
visibility, cross-process claim and notification-gate contention, expiration, and interruption
immediately before and after the atomic commit.

## 5. Build widget, App Intent, and Live Activity views

Replace the placeholder widget bundle with `systemSmall` Home Screen and
`accessoryRectangular` Lock Screen widgets configured for any valid account window, and a
`systemMedium` Home Screen widget configured for one account's standard windows. List choices
from `LoadUsageDetails` and render through the exact-selection Application query. A removed
selection becomes unavailable rather than retargeting another window and resumes only when the
exact ID returns. Render alias with the approved truncation, percentage used, reset and freshness
state, and no invented zero. Emit an entry now and at each known stale, reset, or invalidation
boundary; use dynamic date text for the countdown. Request a new timeline at the earlier of 30
minutes and the next change that cannot be rendered from existing entries. Use `.never` while
unpaired or local cleanup blocks reads. Verify stale and
post-reset display when a reload is delayed or the extension never runs. [Apple's WidgetKit guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/) describes per-widget 24-hour budgets, typical 40–70 refreshes, and roughly five-minute minimum entry spacing.

Use a `WidgetConfigurationIntent` with a dynamic, cache-only window picker and an
`AppIntentTimelineProvider` for the configurable widgets. Its entity query must reconstruct an
unavailable placeholder for a saved ID that is absent from current options. Keep this intent
distinct from the read-only usage App Intent: the latter accepts the same exact selection and
returns identifying alias/product/window context plus committed-cache percentage, reset time,
source, observation time, and state. Neither parameter query nor action fetches. Keep result and
widget behavior consistent for missing, stale, expired, and incompatible windows. [Apple's configurable-widget guide](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget/) documents the intent/provider pairing.

Add the foreground Start/Stop Live Activity action to eligible iPhone Account Details. The Lock
Screen and Dynamic Island views use the shared attributes, system timer text ending at zero, and
`isStale` after the observation's current-data expiry. A running activity whose reading becomes
stale stays visible until its known reset unless the observation becomes invalid for another
reason. Reconcile on app commits and next app execution after widget commits; end when the reset
passes, the observation or account is invalid, the owner stops it, the Mac is forgotten, or the
system disables activities. An app that never runs at reset cannot guarantee immediate dismissal;
the system ends active presentation after eight hours and may retain the ended Lock Screen view
for up to four more. Show availability in Settings and keep actions absent on iPad and weekly
windows. [Apple's ActivityKit lifecycle guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) describes stale presentation and the system limits.

## 6. Verify on runtimes and close

Run focused Scheduling, Application, app, widget, App Intent, and UI tests while implementing. Use deterministic clocks and fake framework boundaries for event order, retries, and policy; use device checks for delivery and system lifecycle that simulators cannot prove. On iPhone and iPad, verify App Group and Keychain access after first unlock and after Sideloadly re-sign, widget-only cache commit and notification replacement/cancellation, time-zone change, all-window selection, and a widget reload under the system budget outside Xcode's debugger. On iPhone, verify Live Activity start, update, stale appearance, reset end on the next app execution, and iPad absence. On Mac, verify local notification delivery from the collector without its main window. Record the actual 24-hour background-task intervals, including gaps; do not infer guaranteed background delivery from an earliest begin date.

Run the complete [contribution-guide gate](../contribution-guide.md#required-validation) from the final worktree, with M14's iPhone and iPad tests enabled. Inspect generated target entitlements and `git diff --check`; check local Markdown links. Update affected user-facing, installation, architecture, phase, and changelog docs with the implementation evidence. Leave unchecked any criterion without direct evidence, especially physical-device or elapsed-time checks.
