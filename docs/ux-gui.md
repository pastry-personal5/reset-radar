# UX GUI

Status: Active

This document defines the current interface and records owner-approved GUI behavior separately under a planned heading. Product scope is in [product-behavior.md](product-behavior.md); component vocabulary is in [ux-terms.md](ux-terms.md).

## First iPhone screen

The iOS app shows a five-item **Main Toolbar** along the bottom edge. Every toolbar item has an original, neutral, tintable bitmap icon above its label. The fixed items are:

- first: **Home**, with a house icon;
- second: **Benefits**, with a gem bitmap icon;
- third: **Community**, with a three-person-group bitmap icon;
- fourth: **Insight**, with a lightbulb bitmap icon; and
- fifth: **All**, with a three-horizontal-bars bitmap icon.

On iPad, the Main Toolbar uses the system's adaptive tab bar or sidebar presentation. Its destinations, order, icons, Home, and Settings are the same as on iPhone.

Selecting Home shows a two-by-two **Allowance Grid** of circular **Allowance Rings**:

| | Five-hour window | Weekly window |
|---|---|---|
| **Codex** | Top left | Top right |
| **Claude Code** | Bottom left | Bottom right |

Each ring presents Percentage Used for its assigned Allowance Window as a circular infographic. The ring fills from 0% toward 100%. The interface must preserve the logical placement above even if accessibility adaptation changes physical sizing or flow.

Each grid cell identifies its product and window, places the numeric Percentage Used inside the ring, and provides a compact Reset Time countdown plus data state. Selecting a ring opens the product's Usage Details with that window initially emphasized.

Before pairing or when required setup is incomplete, the same grid stays visible and affected rings use an explicit unavailable state rather than fabricated values. A prominent **Setup Banner** explains the current blocker and offers the next setup or pairing action. It does not replace the grid with mandatory onboarding.

Selecting Benefits, Community, Insight, or All shows that destination's intentionally empty screen for now. All shows a Settings icon in its top-right corner; selecting it opens Settings.

## Mac app

The Mac uses a native Main Sidebar containing Home, Benefits, Community, Insight, and All. Home uses the same two-by-two **Allowance Grid**, circular **Allowance Rings**, and cell placement as iPhone. Platform-appropriate physical sizing may differ, but the represented information and logical arrangement do not. The other four destinations are empty.

Before source, relay, or pairing setup is complete, the Mac grid remains visible with explicit unavailable states and a Setup Banner offering the next action.

Closing the main window leaves the menu-bar collector running. Its menu shows provider and synchronization status and actions for Refresh All, Open Reset Radar, Settings, and Quit. Settings opens through the standard macOS Settings scene and Command-comma.

## Apple Watch app

Watch Home uses the same logical two-by-two Allowance Grid and placement as iPhone and Mac. Rings use compact labels while retaining accessible product, window, percentage-used, reset, and freshness descriptions. Selecting either product's ring opens compact product-scoped Usage Details.

The Watch app also offers an owner-confirmed **Erase Watch Data** action. It clears the local cache and prevents later usage delivery until the owner chooses **Reset Watch Pairing**. A complication may keep its previously rendered frame until watchOS processes a reload or the owner removes it.

The Allowance Complication shows one configured window's percentage used and freshness. Stale or unavailable data must remain visibly distinct from a current value.

## Usage Details

Codex and Claude Code each have one Usage Details view. Both windows remain visible; the window selected from the Allowance Grid receives initial visual emphasis.

For each window, show:

- an Allowance Ring and exact Percentage Used;
- the window label;
- a relative reset countdown and the absolute reset date and time in the OS's current local time zone;
- Last Updated and the data state; and
- an explicit explanation when data is stale, unavailable, incompatible, signed out, offline, or awaiting a post-reset refresh.

The provenance and synchronization area shows the acquisition source, the Collector Mac's publication status, Last Synced for the receiving device, and source compatibility status. Technical versions and error detail remain behind a diagnostics disclosure instead of competing with primary usage information.

The primary action requests the freshest data available to that platform. On Mac it refreshes the first-party source subject to adapter backoff. On iPhone and iPad, a Codex or all-product Refresh posts an authenticated, short-lived request for an awake Mac to read Codex, then checks the encrypted relay for a result tied to that request. A Claude Code-only Refresh reads the relay without posting that request. The action reports separately whether the relay was reached and whether the Mac completed the Codex read; timeout or an offline Mac leaves the last valid data visible. The phone never directly contacts Codex or Claude Code, and this action cannot force a new Claude Code response. The view never presents history, forecasts, pace analysis, or threshold controls.

On iPhone, Pairing & Sync reports interrupted local Forget Mac cleanup separately from completed local deletion and Watch erasure. When the Watch is unreachable, it says erasure is pending and explains that the old Watch cache may remain until reconnection or an owner-confirmed erase in the Watch app. It reports one responding Watch cache as cleared only after an acknowledgement; it does not claim that another paired Watch or a previously rendered complication frame was erased. The iPad has no Watch state.

On Mac, QR scanning is the default pairing transfer. Manual Copy requires a separate tap and warns that the package contains a long-lived content key and may reach other nearby devices through Universal Clipboard. The app conditionally clears its own unchanged clipboard value after pairing, expiry, or view closure, but explains that a copied package cannot be recalled from another device. Relay & Pairing also states that locking the login Keychain after the collector has started does not stop its running publisher; quitting the app stops it.

On iPhone, iPad, and Mac, each standard window has an off-by-default reset-notification control that applies only to that device. Enabling the first control on a device triggers that device's system authorization request. On iPhone, eligible five-hour windows also offer Start Live Activity; activities never start automatically. Watch Usage Details has neither control; the Watch shows the iPhone's forwarded notifications.

## Widgets and Live Activities

On iPhone and iPad, small Home Screen and Lock Screen widgets show one user-configured allowance window. The medium Home Screen widget summarizes all four Home windows. Every widget includes freshness and renders only from the committed local cache. When the system reloads a widget, it may first refresh that cache from the relay if the last successful refresh is more than five minutes old.

A Reset Live Activity, available on iPhone only, shows one eligible five-hour window. It starts only from a foreground Usage Details action, receives local opportunistic updates, displays stale state honestly, and ends at reset or observation invalidation. Weekly windows never start Live Activities.

