# P1-M15 scheduling device runbook

Status: Active

This owner-run, synthetic-data-only procedure collects the physical iPhone, iPad, and Mac evidence required by P1-M15. It records observable scheduling behavior and timing limits without retaining relay credentials, pairing packages, account identifiers, provider payloads, or screenshots containing them.

## Authority and recording rules

Run only with the owner present, using the personal-device installation procedure in
[personal-use-sideloading.md](personal-use-sideloading.md#p1-m14-reader-installation-procedure).
Use the app's synthetic scenarios or generated fixtures; do not pair a real account solely for
this procedure. Stop and leave the corresponding M15 checklist item unchecked if a result needs a
credential, an unapproved service, a manual reset value, or a behavior not described in
[product behavior](../product-behavior.md) and [Scheduling](../architecture/scheduling.md).

For every run, record privately: UTC start/end time, device model and OS, app build revision,
whether it was signed/re-signed, synthetic scenario name, expected result, observed result, and
pass/fail/deferred. Record elapsed intervals, not raw usage, account labels, device identifiers,
pairing text, tokens, or screenshots that expose them.

## Preflight

1. Generate the project and run the applicable automated gate. Record the exact revision.
2. Install the signed app and widget extension on the reference iPhone and iPad using Sideloadly.
   Confirm the app and widget extension launch after first unlock.
3. Install the Mac collector using the normal signed configuration. Keep the Mac main window
   closed for the background-collection checks.
4. Select a synthetic snapshot containing two standard windows and at least one additional
   provider window. Confirm every surface says percentage **used**, never remaining.

## iPhone and iPad notifications

For each device, use Account Details to enable a reset reminder for a five-hour standard window,
weekly standard window, and additional window. Confirm permission is requested only for the
explicit enable action, the choice remains shown after denied or provisional authorization, and
the Settings status matches the system status.

Then, using synthetic snapshots, observe and record:

- changed reset time replaces the prior request rather than producing a duplicate;
- removed, incompatible, expired, and changed-additional-ID windows cancel only their own
  requests;
- time-zone change preserves the absolute fire instant while changing local presentation;
- enabling every valid window is either retained by the platform or produces a recorded capacity
  failure—never a silent priority choice;
- Forget Mac removes pending Reset Radar requests, Live Activities, widgets, and cached data;
  unrelated system notifications remain present.

## Widgets and App Intent

On both devices, configure a small Home Screen widget and rectangular Lock Screen widget for an
additional window, then change its concrete provider scope/limit ID. Confirm it becomes
unavailable and does not choose a sibling; confirm it resumes only when the exact ID returns.
Configure the medium widget for one account and confirm it shows its five-hour and weekly standard
windows. Invoke the read-only App Intent and confirm it reads cache data without a relay request.

Observe stale and post-reset presentation while delaying a WidgetKit reload. Record WidgetKit's
actual reload timestamps over the run, but never infer a delivery guarantee from the requested
30-minute interval. Perform one widget-only committed update and verify an already-authorized
notification reconciliation and the later app catch-up behavior.

## iPhone Live Activities

On iPhone only, start and stop an eligible fresh five-hour activity from Account Details. Verify
the Lock Screen and Dynamic Island show the synthetic percentage used and reset countdown. Record
alias/content update, stale presentation through the known reset, reset end on the next app
execution, invalidation end, user dismissal, and several simultaneous account activities.

Also test a stale-at-start reading and a reset beyond eight hours; neither may start an activity.
Update a running activity beyond its original eight-hour horizon and confirm immediate policy end.
Record the system end near eight active hours and any Lock Screen retention separately from an
app policy end. On iPad, confirm the Start control is absent.

## Background refresh observation

Begin this observation as soon as the installed driver is available and keep it running for at
least 24 hours outside Xcode's debugger. Record every actual background execution, its elapsed
time since the previous successful refresh, reset proximity, outcome, and any gap. Verify an
expiration does not present an offline state or add failure backoff, and that a later foreground
refresh remains possible. The data proves observed behavior only; it does not promise a cadence.

## Re-sign and final evidence

After Sideloadly re-sign, repeat first-unlock sharing, one widget-only cache read, an
already-authorized notification replacement, and a Live Activity start on iPhone. Confirm App
Group and Keychain access remain available without exposing their contents. Add a dated redacted
summary to the M15 validation record, then update only checklist items directly supported by the
recorded evidence.
