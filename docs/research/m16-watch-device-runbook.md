# P1-M16 paired Watch validation

Status: Active

Owner-run, synthetic-data procedure for the initial free-signed Watch installation, Watch App
Group, WatchConnectivity, offline erasure, and complication evidence required to close M16. Record
only redacted outcomes and timings; never retain pairing packages, tokens, identifiers, or raw
provider output.

## Preconditions

- Use the reference iPhone 17 Pro Max and its paired Apple Watch Series 11 (42mm).
- Record the iPhone and Watch OS versions, Xcode build, Reset Radar revision, and wall-clock start.
- Use the stable Personal Team configuration in the untracked `Config/Build/Local.xcconfig`.
- Start the Mac collector with its synthetic source mode and use synthetic account aliases and
  percentages. Do not capture the pairing QR code or manual package.
- Keep the full seven-day Sideloadly preservation observation separate as the Phase 1 exit item.
  This run proves only the initial install and current M16 behavior.

## 1. Build and inspect the signed package

Move any existing `.build/ipa/ResetRadar.ipa` out of the way if a fresh package is required, then
run `make ipa`. Do not delete an uninspected package. Record pass/fail and the generated file's
size, not its signing identity or embedded profile.

In a temporary directory, inspect the package without copying it into the repository:

```sh
workdir=$(mktemp -d /private/tmp/reset-radar-watch-evidence.XXXXXX)
unzip -q .build/ipa/ResetRadar.ipa -d "$workdir"
find "$workdir/Payload" -maxdepth 6 -type d \
  \( -name '*.app' -o -name '*.appex' \) -print
codesign -d --entitlements :- "$workdir/Payload/ResetRadar.app" 2>&1 \
  | plutil -p -
find "$workdir/Payload/ResetRadar.app" -type d \
  \( -name '*.app' -o -name '*.appex' \) -print
```

Confirm and record only these facts:

- the iPhone app contains the Watch app and the Watch app contains the complication extension;
- all three signed Watch/iPhone components use their approved bundle identifiers;
- the iPhone, Watch app, and Watch complication contain
  `group.com.unidentifiedstealthstartup.ResetRadar`;
- no Watch component contains Keychain, provider-credential, network-client, Push Notifications,
  iCloud, or CloudKit entitlements; and
- every Mac slice check remains separate from this IPA inspection.

Remove the temporary directory after recording the redacted result.

## 2. Initial free-signed installation

1. Install the new IPA on the reference iPhone with Sideloadly **Normal Install**, following the
   existing sideloading guide. Do not use Apple ID Sideload or allow bundle-ID rewriting.
2. Trust and launch the iPhone app if the current Personal Team build requires it.
3. In the iPhone Watch app, install Reset Radar from **Available Apps** if automatic companion-app
   installation has not already installed it. If this stays on **Installing**, record the stalled
   result and use the signed **ResetRadarWatch** scheme's direct Xcode Run procedure in the
   [sideloading guide](../user-guide-for-sideloading.md#run-the-watch-app-from-xcode). Keep the
   Sideloadly-installed iPhone app in place and record which path installed the Watch app.
4. Launch Reset Radar on the Watch and record whether its empty state appears without a crash.
5. Add the rectangular Reset Radar Allowance complication to a face. Confirm its configuration
   lists synthetic account aliases and the Five-hour and Weekly choices.
6. Record install start/end, first iPhone launch, first Watch launch, complication-add time, and
   redacted pass/fail. Do not capture Apple Account, device IDs, provisioning profiles, or the
   Watch pairing record.

This successful installation begins the separate seven-day preservation clock recorded in the
Phase 1 exit evidence.

## 3. Watch App Group and foreground delivery

1. Pair the iPhone reader to the synthetic Mac publication using the normal owner-confirmed flow.
2. Keep both devices awake and open. Wait for the iPhone Home to show the synthetic accounts.
3. Open the Watch app. Confirm its N-by-two matrix has one row per account, no visible aliases on
   Home, accessible full account/window descriptions, and the expected stable palette:
   Account #1 lavender, #2 mint, and #3 peach.
4. Open each ring. Confirm Account Details shows alias, product, exact percentage used, window,
   relative and absolute reset, Last Updated, freshness, and any stale/offline explanation.
5. Select one account/window in the complication. Confirm the exact alias/window renders and a
   later cache read by the complication matches the Watch app. This is the direct Watch App Group
   proof; an app-only cache read is insufficient.
6. Record foreground application-context latency from iPhone commit to Watch display.

## 4. Interactive refresh and complication transfer

1. Change a synthetic standard-window percentage on the Mac and allow it to publish.
2. Open the Watch app while the iPhone is reachable. Record request time, iPhone wake/handling,
   reply time, durable Watch commit, and visible update time.
3. Confirm no Mac-assisted Codex request was created by the Watch activation.
4. Make one eligible Home-slot change after the persisted 30-minute spacing permits it. Record
   that the application context is sent regardless of complication eligibility and that a
   complication transfer occurs only while enabled and while system budget remains.
5. Confirm the complication eventually reloads to the committed value. Treat the reload request
   time and rendered-frame time as separate evidence.

## 5. Offline ageing and changed installation

1. Disconnect or power off the iPhone while leaving the Watch usable.
2. Open the Watch app. Confirm the interactive refresh returns immediately to cached content.
3. Advance beyond the synthetic freshness threshold and known reset. Confirm the original
   `observedAt` ages to stale and then reset-awaiting-refresh/unavailable without showing 0%.
4. Restore reachability and record ordinary application-context recovery.
5. Using an approved reinstall that changes the iPhone installation ID, deliver a new synthetic
   payload. Confirm the Watch holds the old cache and previews the exact pending accounts until
   the owner confirms **Use New iPhone Installation**. Do not record the installation ID itself.

## 6. Local erase and Reset Watch Pairing

1. Put the iPhone offline. On Watch choose **Erase Watch Data** and confirm the destructive sheet.
2. Confirm the Watch cache becomes empty, the complication reload is requested, and Home does not
   accept later usage while the local erase hold is active.
3. Record the previously rendered complication frame separately if watchOS retains it temporarily;
   do not call that a failed cache erase.
4. Choose **Reset Watch Pairing**, confirm it, and verify the revision floor still rejects an older
   delayed payload before a newer usage payload is accepted.

## 7. Forget Mac while Watch is offline

1. Restore a current synthetic cache, then take the Watch offline.
2. Choose **Forget Mac** on the iPhone. Confirm iPhone usage disappears immediately and its Watch
   erasure status says pending/unconfirmed across iPhone app termination and relaunch.
3. Pair the iPhone to a new synthetic Mac publication while the old Watch clear remains pending.
   Confirm no newer usage replaces the saved clear in Watch application context or refresh reply.
4. Reconnect the Watch. Record clear delivery, durable empty-cache commit, complication reload
   request, queued receipt, iPhone receipt handling, and the transition to confirmed erasure.
5. Deliver duplicate and stale synthetic receipts/messages. Confirm they do not restore usage or
   alter the confirmation.

## Evidence record

For each section record: UTC start/end, OS/build versions, repository revision, redacted command or
owner action, expected result, observed result, and pass/fail. Link the sanitized record from the
M16 overview. If a platform or signing assumption fails, stop and return the result to the owner;
do not change distribution, device, App Group, or security behavior to make the check pass.
