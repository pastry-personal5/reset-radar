# Personal-use sideloading

Status: Active

Research for installing Reset Radar on the owner's iPhone and paired Apple Watch with a free Apple account. The owner chose personal use and sideloading; this document selects Sideloadly as the primary iPhone path and records the constraints the product must preserve.

Sources were rechecked on 2026-10-26. Xcode 27.1 exported a signed IPA with the expected four app and extension bundles. Sideloadly Normal Install, first launch after trust, and physical QR pairing succeeded on the reference iPhone on 2026-10-27; extension behavior, remaining first-unlock/cache checks, iPad validation, and Sideloadly re-signing remain pending. Xcode 27.1 was observed with **Xcode → Settings → Apple Accounts → Personal Team**; that team detail pane does not display a Team ID.

## Owner decision

- The first version is for the owner's personal use only.
- It uses a free Apple account (an Xcode Personal Team), not a paid Apple Developer Program membership.
- It is sideloaded rather than distributed through the App Store or TestFlight.
- Sideloadly is the primary installation and refresh path.
- LiveContainer is not a supported Reset Radar runtime while the product includes WidgetKit extensions. It may be reconsidered only if the app becomes extension-free.
- The first version includes an Apple Watch app paired with the iPhone app.

This decision removes App Store submission and store-listing work from the first-version scope. It does not relax vendor terms, trademark rules, privacy requirements, or Apple's code-signing restrictions.

## Recommendation

Use Sideloadly to sign and install a conventional Reset Radar IPA, keeping its widget and embedded watch app targets. Configure its refresh daemon and Wi-Fi refresh so the seven-day free provisioning profiles can be renewed while the Mac and iPhone can reach one another. Physical-device validation must prove that the resulting Personal Team signing installs and refreshes the watch app on the paired Apple Watch; the public research does not establish that workflow by itself.

The first signed install and paired Watch checks belong to P1-M16. Per the owner's 2026-10-26 decision, the full seven-day preservation observation is a Phase 1 exit criterion that may finish after M16 closes; the installation strategy is not validated for the first usable version until that observation passes.

Do not run Reset Radar inside LiveContainer. LiveContainer's own documentation says guest app entitlements are not applied to the host and guest app extensions cannot be registered with iOS. Reset Radar's Home Screen and Lock Screen widgets are WidgetKit app extensions, so they would not exist as normal system surfaces in that runtime. LiveContainer also documents special handling for local notifications and no remote push notifications; Reset Radar should not add those compatibility variables when conventional installation is available.

## Comparison

| Criterion | Sideloadly | LiveContainer | Decision impact |
|---|---|---|---|
| Installation model | Signs and installs the IPA as an iOS app. | Loads guest apps inside a host app rather than installing each guest normally. | Reset Radar needs normal iOS registration. |
| Free account | Supported; signatures are valid for seven days. | The host consumes a free-account slot and can hold many guest apps. | Slot savings are unnecessary for one personal app. |
| Refresh | Desktop daemon can re-sign automatically; Wi-Fi refresh requires initial pairing and network reachability. | The LiveContainer host still needs an installation/refresh route; official instructions recommend SideStore or AltStore and explicitly do not support installing LiveContainer with Sideloadly. | Sideloadly is the shorter single-tool workflow for Reset Radar itself. |
| App extensions | Sideloadly exposes controls to retain or remove IPA plug-ins; retaining the Reset Radar widget must be verified on device. | Guest app extensions are unsupported because iOS does not know the guest is installed. | LiveContainer conflicts with the planned widgets. |
| Entitlements | The signed app is limited to capabilities available to the free Personal Team. | Guest entitlements are not applied to the host. | Use only Personal Team capabilities and verify the final signed IPA. |
| Notifications | Conventional local-notification behavior, subject to signing and iOS settings. | Some guests require a LiveContainer-specific local-notification fix; remote push does not work. | Prefer conventional local notifications. |
| Isolation | Normal installed-app sandbox. | LiveContainer states that guest containers are not sandboxed from one another. | Conventional installation has the simpler privacy boundary. |

## Free-account constraints

Apple's current Personal Team limits are:

- Up to 10 App IDs, expiring after seven days.
- Up to three registered devices, expiring after seven days.
- Up to three installed apps per device under free provisioning.
- Development provisioning profiles expire seven days after issuance; the app must be re-signed and reinstalled before or after expiry.
- App Store Connect and TestFlight are not available to a free account.

Sideloadly documents automatic re-signing before expiry, but that is an operational convenience rather than a guarantee: the Mac-side daemon must be running, the device must be reachable, and Apple signing must succeed. Reset Radar must not promise uninterrupted operation across a missed refresh. The owner should refresh before day seven and confirm the app still launches afterward.

Apple's current capability table marks App Groups as available to free Apple Developer accounts. That is important because the main app and its WidgetKit extension need shared storage. Each target still needs correct identifiers, profiles, and entitlements, so physical-device validation must verify the actual Personal Team signing result rather than treating table eligibility as proof that Sideloadly preserves the extension correctly.

Remote push is out of scope. Reset Radar uses local notifications, so it does not depend on the Push Notifications capability or an APNs provider server.

Apple's capability table also makes app-owned iCloud Documents, CloudKit, and iCloud key-value storage unavailable to the free Apple Developer account. A user-selected iCloud Drive folder is a distinct document-picker path, not an app-owned iCloud container; [mobile-network-synchronization.md](mobile-network-synchronization.md) records the evidence and requires a physical-device signing spike before the architecture relies on it.

## Build and installation contract

The project must produce and validate this workflow:

1. Build an unsigned or development Reset Radar IPA containing the main app, widget extension, and watch app.
2. Inspect the IPA before installation and confirm the widget plug-in and embedded watch app are present.
3. In Sideloadly, use the owner's free Apple account, keep app extensions enabled, and do not inject tweaks or change the app name, icon, minimum iOS version, or bundle identifiers.
4. Install over USB for the first pairing, enable the required developer trust/developer mode prompts on the iPhone, and launch the app.
5. Confirm local notifications, shared app-group data, the Home Screen widget, and the Lock Screen widget on a physical iOS 26+ device.
6. Install and launch the companion on the paired Apple Watch; confirm iPhone-to-watch snapshot transfer, local cache behavior, reset-time display, and stale/offline presentation.
7. Enable Sideloadly's refresh daemon and Wi-Fi refresh, then prove one refresh cycle without losing app data, widget configuration, watch installation, or watch state.
8. Inspect the installed signatures and entitlements for the app, widget, and watch targets. Record the exact repeatable commands in the contribution guide.

Until those checks pass, sideloading is a selected distribution strategy, not a completed installation. Sideloadly itself is a developer workstation tool and is not an app dependency; it must not be bundled, linked, or copied into this Apache-2.0 repository.

## P1-M14 reader installation procedure

For routine installation, use the shorter
[Sideloadly user guide](../user-guide-for-sideloading.md). This procedure retains the maintainer
steps, package inspection, and evidence boundaries used to validate the distribution path.

The owner runs this procedure with synthetic data until the manual-refresh validation is accepted.
Never put an Apple ID, app-specific password, provisioning profile, pairing package, QR image,
Keychain entry, relay token, or usage reading in a command transcript or repository evidence.

1. In Xcode 27.1, use **Xcode → Settings → Apple Accounts** and select **Personal Team**. Do not
   search that pane for a Team ID; it does not show one. Connect the iPhone by USB, unlock it, trust
   the Mac, and check that it runs iOS 26.1 or newer. Finder may list an iPhone over Wi-Fi, so a
   Finder sidebar entry alone does not prove USB detection; confirm the iPhone appears in Xcode's
   device destination and later in Sideloadly's **iDevice** selector. Xcode shows no provisioned
   device until the owner completes device setup. Keep credentials and device identifiers out of
   evidence.
2. In the generated `ResetRadar.xcodeproj`, select **ResetRadar** under Targets, then open
   **Signing & Capabilities → Release**. The generated project's Release signing initially has
   **Automatically manage signing** off, **Team: None**, and no provisioning profile. Enable
   automatic signing and select the owner's Personal Team. The selection creates a managed
   profile and makes the team's 10-character identifier available in the generated project's
   Release signing setting. Copy that identifier into `DEVELOPMENT_TEAM` in the untracked
   `Config/Build/Local.xcconfig` (copied from `Local.xcconfig.template`), and add
   `CODE_SIGN_STYLE = Automatic` there. Regenerate with `Scripts/generate-project.sh`, then verify
   that the iOS app, iOS widget, Watch app, and Watch widget all resolve to the same team with
   automatic Release signing. The generated project is not the durable place to store this
   choice. The `ResetRadar` scheme archives in Release; Development is unsigned and only for
   simulators. Confirm the main bundle identifier remains
   `com.unidentifiedstealthstartup.ResetRadar` and the signed app's
   `ResetRadarKeychainAccessGroup` equals its Keychain entitlement.
3. Archive the `ResetRadar` scheme for a generic iOS device, then export the signed archive with
   Xcode 27.1's `debugging` method and automatic signing using the commands below. This CLI
   export succeeded with the owner's free Personal Team even though Apple's older Personal Team
   guidance warns that Organizer's Export control can be unavailable. Inspect the IPA for
   `ResetRadar.app`, its WidgetKit plug-in, the embedded Watch app, and its widget. Verify the
   signed app and widget bundle IDs, App Group and Keychain entitlements, and matching
   `ResetRadarKeychainAccessGroup` Info.plist value before Sideloadly signs again. Do not strip
   extensions, change bundle identifiers, or weaken entitlements. Record only sanitized
   pass/fail observations, not the IPA or signing material, in repository evidence.
4. In Sideloadly 0.71.1, **Apple ID Sideload** has **Use automatic bundle ID** on and says a free
   Apple Account cannot disable bundle-ID changes. That mode would violate Reset Radar's fixed
   identity, so do not use it for this IPA. Instead, select **Sideloadly Settings → Signing Mode →
   Normal Install** to install the already signed IPA without re-signing. Under **Advanced
   Options**, turn **Use automatic bundle ID** off, confirm **Dropping 0 of 1 plug-ins**, leave
   custom name, icon, entitlements, and tweak injection unset, and leave AutoRefresh off. Select
   the iPhone explicitly under **iDevice**; if only **Apple Silicon** appears, do not start
   installation to the Mac. On 2026-10-27 this mode completed at 100%, and CoreDevice found the
   main app under its unchanged bundle identifier on the owner's iOS 27.0.1 iPhone. Launch,
   extension registration, and renewal still need device evidence. On 2026-10-27 the
   owner successfully exercised QR pairing on the physical iPhone; no pairing material or usage
   data was retained as repository evidence. This does not prove
   that Sideloadly can automatically re-sign the app while preserving its identity. After device pairing makes the
   control available, turn on **Settings → Privacy & Security → Developer Mode** on the iPhone,
   restart it, and confirm with its passcode. If launching Reset Radar shows **Untrusted
   Developer**, open **Settings → General → VPN & Device Management**, select the owner's
   development identity under Developer App, and follow the Trust or **Allow & Restart** prompt.
   Keep the iPhone online for certificate verification, then launch Reset Radar after its first
   unlock. On 2026-10-27 the first launch showed Untrusted Developer; after the owner completed
   the device trust flow, Reset Radar launched successfully.
5. In the installed app, verify the Home setup state, scan or manually paste a newly created
   pairing package, compare the exact confirmation code with the Mac, and wait for activation and
   one authenticated publication. Lock and unlock the device, relaunch the app, and verify the
   committed sequence and cached rows persist without a Keychain prompt.
6. Inspect the installed app and widget entitlements on the owner-controlled machine. Record only
   the presence of the expected App Group and matching Keychain access group; redact the Team ID.
   If Sideloadly changed either identifier, the app reports that it can't open its data, or
   pairing reports that it could not be saved, stop and return the signing result to the owner;
   do not weaken the explicit group.
   Repeat pairing/cache persistence on the reference iPad. A cellular read is recorded separately
   because M9 did not establish that runtime behavior.
7. A seven-day renewal path remains open. Do not enable Sideloadly's automatic **Apple ID
   Sideload** re-signing for Reset Radar while it requires bundle-ID changes with this free
   account. Before the profile expires, a new Xcode `debugging` export and another **Normal
   Install** may be tested as a manual renewal path; verify the same bundle identity, pairing,
   committed sequence, widget configuration, and Watch state. If automatic re-signing cannot
   preserve those values, return the distribution decision to the owner rather than accepting a
   destructive re-pair as equivalent evidence.

The app contains status-only notification and Live Activity surfaces in M14. Widget, notification,
Live Activity, and Watch delivery preservation are M15/M16 evidence and must not be claimed here.

### Verified Xcode 27.1 IPA export

Run from the repository root after step 2. The temporary directory holds signing material; keep
the archive, IPA, and Xcode logs out of the repository and out of shared evidence.

```sh
install_workdir=$(mktemp -d /private/tmp/reset-radar-install.XXXXXX)
xcodebuild archive \
  -project ResetRadar.xcodeproj -scheme ResetRadar -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$install_workdir/ResetRadar.xcarchive" -allowProvisioningUpdates
cat > "$install_workdir/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>debugging</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$install_workdir/ResetRadar.xcarchive" \
  -exportPath "$install_workdir/export" \
  -exportOptionsPlist "$install_workdir/ExportOptions.plist" \
  -allowProvisioningUpdates
```

The result is `"$install_workdir/export/ResetRadar.ipa"`. On 2026-10-26 the archive and IPA
contained the main app, iOS widget, Watch app, and Watch widget; their bundle IDs matched the
project, the iOS app and widget carried the expected App Group and Keychain entitlements, and
the app's Info.plist Keychain group matched its signature. The extracted app's signature passed
`codesign --verify --deep --strict` with normal host Keychain access. A restricted sandbox gave
`CSSMERR_TP_NOT_TRUSTED`, so an isolated trust error needs a host-context recheck before treating
it as an invalid bundle.

## Security and privacy

- Download Sideloadly only from its official site. Do not use repackaged downloads or online signing services.
- Sideloadly requires an Apple ID for signing and offers saved credentials. Treat the workstation account and its stored credential material as sensitive; do not put credentials, passwords, signing certificates, or provisioning profiles in the repository or logs.
- Sideloadly's current FAQ says an app-specific password works only with a paid Apple Developer
  account and anisette disabled. The **Normal Install** path does not need Apple Account entry in
  Sideloadly because Xcode already signed the IPA. If a future approved refresh path uses **Apple
  ID Sideload**, the owner enters the password and any two-factor code directly in Sideloadly;
  never put either in chat, logs, or the repository. Keep two-factor authentication enabled and
  review Sideloadly's saved-credentials choice before enabling automatic refresh.
- Do not use Sideloadly's tweak injection or IPA mutation features for Reset Radar.
- LiveContainer warns that all guest data is accessible to the host build and that guest containers are not isolated from each other. If it is ever evaluated, use only the official open-source build and never place vendor credentials in a guest app.

## Architecture and validation consequences

- Reserve stable, owner-specific bundle identifiers for the main app, widget extension, and watch targets; do not churn App IDs during development because the free account has a seven-day/10-ID budget.
- Keep App Groups in the architecture, but add a physical-device signing spike before relying on shared storage.
- Treat notification, widget, and paired-watch acceptance on free-signed physical devices as release criteria.
- Do not add App Store metadata, TestFlight automation, StoreKit, receipt validation, or paid-program-only capabilities.
- Document data preservation across re-sign/reinstall. If Sideloadly changes the application identifier or reinstall behavior, stop and fix the signing configuration rather than accepting data loss.

## Open validation items

- Can Sideloadly 0.71.1 **Normal Install** preserve the already signed main app, WidgetKit
  extension, and embedded Watch app on iOS 27.0.1?
- Can the same Personal Team and Sideloadly workflow preserve, install, and refresh the embedded watch app on the owner's paired Apple Watch?
- Does the resulting app-group entitlement match in the main app and widget after Sideloadly signs the IPA?
- Does automatic Wi-Fi refresh preserve the app container, widget selection, scheduled local notifications, shared defaults, watch installation, and watch state?
- How many of the owner's existing free-provisioned app and App ID slots are already occupied?
- Can any Sideloadly automatic re-sign path preserve the exported IPA's identifiers, extensions,
  App Group, and Keychain entitlements for this free Personal Team? Its current Apple ID Sideload
  option says automatic bundle-ID changes cannot be disabled for a free account.

These checks need owner-run signing and physical-device evidence; public documentation and simulator tests do not establish the result.

## Sources

Checked 2026-10-19 and rechecked 2026-10-26:

- [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account): Personal Team App ID, device, app, and seven-day profile limits; paid-program feature boundary.
- [Apple supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios): capability availability by membership, including App Groups for free Apple Developer accounts.
- [Apple configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): sharing data between an app and extension.
- [Mobile-network synchronization](mobile-network-synchronization.md): app-owned iCloud capability boundary and user-selected iCloud Drive folder candidate.
- [Sideloadly](https://sideloadly.io/): free-account support, seven-day validity, automatic refresh, Wi-Fi pairing, and extension controls.
- [Sideloadly FAQ](https://sideloadly.io/faq): free-account app-specific password limit, same-account refresh, and overwrite behavior.
- [Sideloadly trust guidance](https://sideloadly.io/faq): VPN & Device Management path for Untrusted Developer.
- [Apple manually installed app trust](https://support.apple.com/en-gb/118254): current iOS Trust/Allow & Restart and online verification behavior; written for enterprise apps, so the exact Personal Team prompt is confirmed on the owner device.
- [Current Xcode account help](https://help.apple.com/xcode/mac/current/en.lproj/devaf282080a.html): Personal Team account setup and on-device testing.
- [Current Xcode device help](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html): connect, unlock, trust, and automatic signing for a physical device.
- [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device): pairing prerequisite, settings path, restart, and confirmation.
- [Apple's archived Personal Team export note](https://developer.apple.com/library/archive/qa/qa1915/): Organizer export may be unavailable for a free Personal Team; verify current Xcode behavior on the owner machine.
- [LiveContainer README](https://github.com/LiveContainer/LiveContainer): runtime model, entitlement, extension, notification, and isolation limitations.
- [LiveContainer installation guide](https://livecontainer.github.io/docs/installation): supported installation routes and explicit statement that Sideloadly is not supported for installing LiveContainer.
