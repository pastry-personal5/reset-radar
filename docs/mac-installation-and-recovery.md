# Mac installation and recovery

Status: Active

How the owner installs, updates, recovers, and uninstalls the locally built Reset Radar Mac
collector without losing relay control or prompting for Keychain access.

## Install

1. In Xcode, select the owner's stable Personal Team and Apple Development identity in the
   untracked `Config/Build/Local.xcconfig` described by the contribution guide.
2. Build the `ResetRadarMac` scheme with the Release configuration. Its post-action rejects an
   ad-hoc app, a missing team identifier, or an embedded status-line helper signed by a different
   team.
3. Move `ResetRadarMac.app` to `/Applications`. On first launch, use Finder's **Open** action and
   approve the locally built application if Gatekeeper asks. Reset Radar itself never bypasses or
   changes Gatekeeper.
4. In **Settings → Sources**, select each explicit `CODEX_HOME` folder and optionally its Codex
   executable. Review the exact allowlisted environment before confirming. Then preview and
   confirm the Claude Code status-line helper installation; an unsafe existing command is left
   unchanged.
5. In **Settings → Relay & Pairing**, enter the included canonical `workers.dev` origin, prepare
   setup, install the displayed token digests as Worker secrets, and activate. Pair readers by QR
   code. Clipboard copy is a warned fallback.
6. Optionally enable **Launch at login**. The displayed state comes from `SMAppService.mainApp`,
   including approval-required and error states.

## Update

Build the replacement with the same Personal Team identity, quit Reset Radar, and replace only
the application bundle. Do not erase Application Support or Keychain items. There is no in-app
downloader or automatic updater. A changed signing identity routes to recovery instead of causing
a Keychain prompt.

## Uninstall

Use this order so the owner does not strand relay credentials or Claude Code configuration:

1. Choose **Destroy Relay** and retry until remote deletion succeeds.
2. Disable **Launch at login** and confirm its reported state.
3. Restore the prior Claude Code status-line setting, if requested.
4. Remove the installed `reset-radar-statusline` helper and its owner-only session records.
5. Erase Reset Radar's local Application Support directory and Keychain items.
6. Quit Reset Radar and remove the application bundle.

Destroy Relay is deliberately retryable: a remote failure keeps local state and publication
paused. Removing the app first cannot revoke data on an unavailable or still-configured relay.

## Recovery

- **Missing app:** rebuild and install the Release app with the same Personal Team identity.
  Application Support and Keychain state can then be reused.
- **Lost Mac:** deploy or access the relay separately and destroy its state; readers must be
  re-paired after a replacement Mac performs setup.
- **Rejected login item:** open System Settings → General → Login Items, approve Reset Radar if
  offered, then refresh General Settings. The app never reports the requested toggle as success.
- **Incompatible CLI:** select the intended explicit executable and `CODEX_HOME` again, review
  the new launch preview, and confirm replacement. For Claude Code, repair the helper only after a
  safe preview; unsafe existing status-line commands remain untouched.
- **Changed signing identity:** rebuild with the recorded identity, or perform relay setup again
  and re-pair every reader. The raw team identifier remains only in local state.
- **Locked Keychain:** unlock the login keychain and choose Retry. Reads are non-interactive and
  retry every minute and when the login session becomes active. Secrets already cached in the
  current process remain usable until quit, setup replacement, or Destroy Relay.
