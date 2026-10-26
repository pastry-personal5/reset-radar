# Personal-use sideloading

Status: Active

Research for installing Reset Radar on the owner's iPhone and paired Apple Watch with a free Apple account. The owner chose personal use and sideloading; this document selects Sideloadly as the primary iPhone path and records the constraints the product must preserve.

Sources were checked on 2026-10-19. No Apple account credentials were entered, no tool was installed, and no app was signed during this research because the repository does not yet contain an Xcode project or IPA.

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

The owner runs this procedure with synthetic data until the manual-refresh validation is accepted.
Never put an Apple ID, app-specific password, provisioning profile, pairing package, QR image,
Keychain entry, relay token, or usage reading in a command transcript or repository evidence.

1. Copy `Config/Build/Local.xcconfig.template` to the untracked `Local.xcconfig`, enter the owner's
   Personal Team, run `Scripts/generate-project.sh`, and archive the `ResetRadar` scheme. The
   archive uses Release; Development builds are unsigned and only for the simulator. Signing with
   the same team that Sideloadly later uses keeps the `ResetRadarKeychainAccessGroup` Info.plist
   value equal to the installed Keychain entitlement. Confirm the main app identifier remains
   `com.unidentifiedstealthstartup.ResetRadar`; do not allow Sideloadly to rename the bundle or
   remove its extensions.
2. Export an IPA from Xcode's Organizer. Before signing, inspect the archive/IPA contents and
   record only whether it contains `ResetRadar.app`, its WidgetKit plug-in, and the embedded Watch
   app. Do not archive the actual file or its signing material as evidence.
3. In Sideloadly, select the owner’s free Personal Team, retain app extensions, disable tweaks and
   name/icon mutation, and install by USB to the reference device. Complete the device’s normal
   developer trust and Developer Mode prompts, then launch Reset Radar after its first unlock.
4. In the installed app, verify the Home setup state, scan or manually paste a newly created
   pairing package, compare the exact confirmation code with the Mac, and wait for activation and
   one authenticated publication. Lock and unlock the device, relaunch the app, and verify the
   committed sequence and cached rows persist without a Keychain prompt.
5. Inspect the installed app and widget entitlements on the owner-controlled machine. Record only
   the presence of the expected App Group and matching Keychain access group; redact the Team ID.
   If Sideloadly changed either identifier, the app reports that it can't open its data, or
   pairing reports that it could not be saved, stop and return the signing result to the owner;
   do not weaken the explicit group.
   Repeat pairing/cache persistence on the reference iPad. A cellular read is recorded separately
   because M9 did not establish that runtime behavior.
6. Enable Sideloadly’s refresh path and, after seven days, verify the installed reader still
   launches with the same pairing and committed sequence. If its bundle identity changes or data
   disappears, stop and return the distribution decision to the owner; do not accept a destructive
   re-pair as equivalent evidence.

The app contains status-only notification and Live Activity surfaces in M14. Widget, notification,
Live Activity, and Watch delivery preservation are M15/M16 evidence and must not be claimed here.

## Security and privacy

- Download Sideloadly only from its official site. Do not use repackaged downloads or online signing services.
- Sideloadly requires an Apple ID for signing and offers saved credentials. Treat the workstation account and its stored credential material as sensitive; do not put credentials, passwords, signing certificates, or provisioning profiles in the repository or logs.
- Prefer an Apple app-specific password where the signing flow supports it, and keep two-factor authentication enabled.
- Do not use Sideloadly's tweak injection or IPA mutation features for Reset Radar.
- LiveContainer warns that all guest data is accessible to the host build and that guest containers are not isolated from each other. If it is ever evaluated, use only the official open-source build and never place vendor credentials in a guest app.

## Architecture and validation consequences

- Reserve stable, owner-specific bundle identifiers for the main app, widget extension, and watch targets; do not churn App IDs during development because the free account has a seven-day/10-ID budget.
- Keep App Groups in the architecture, but add a physical-device signing spike before relying on shared storage.
- Treat notification, widget, and paired-watch acceptance on free-signed physical devices as release criteria.
- Do not add App Store metadata, TestFlight automation, StoreKit, receipt validation, or paid-program-only capabilities.
- Document data preservation across re-sign/reinstall. If Sideloadly changes the application identifier or reinstall behavior, stop and fix the signing configuration rather than accepting data loss.

## Open validation items

- Can Sideloadly 0.71.0 sign and preserve the Reset Radar WidgetKit extension with the owner's current Personal Team on iOS 26+?
- Can the same Personal Team and Sideloadly workflow preserve, install, and refresh the embedded watch app on the owner's paired Apple Watch?
- Does the resulting app-group entitlement match in the main app and widget after Sideloadly signs the IPA?
- Does automatic Wi-Fi refresh preserve the app container, widget selection, scheduled local notifications, shared defaults, watch installation, and watch state?
- How many of the owner's existing free-provisioned app and App ID slots are already occupied?

These are physical-device checks. They cannot be answered by public documentation or by the current docs-only repository.

## Sources

Checked 2026-10-19:

- [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account): Personal Team App ID, device, app, and seven-day profile limits; paid-program feature boundary.
- [Apple supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios): capability availability by membership, including App Groups for free Apple Developer accounts.
- [Apple configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): sharing data between an app and extension.
- [Mobile-network synchronization](mobile-network-synchronization.md): app-owned iCloud capability boundary and user-selected iCloud Drive folder candidate.
- [Sideloadly](https://sideloadly.io/): free-account support, seven-day validity, automatic refresh, Wi-Fi pairing, and extension controls.
- [LiveContainer README](https://github.com/LiveContainer/LiveContainer): runtime model, entitlement, extension, notification, and isolation limitations.
- [LiveContainer installation guide](https://livecontainer.github.io/docs/installation): supported installation routes and explicit statement that Sideloadly is not supported for installing LiveContainer.
