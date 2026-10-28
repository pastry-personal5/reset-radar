# Mac installation and recovery

Status: Active

An owner-run procedure for installing, configuring, updating, recovering, and removing the
locally built Reset Radar Mac collector. It keeps the Release signing identity stable, never asks
the app to bypass Gatekeeper or show a Keychain prompt, and separates relay mutations from local
setup.

## What this guide can complete today

The Mac collector, its source configuration, relay publication, and the P1-M14 iPhone/iPad reader
are available now. Follow the reader’s owner-run [installation procedure](research/personal-use-sideloading.md#p1-m14-reader-installation-procedure)
for Sideloadly and physical-device checks; an unscanned pairing code remains harmless until a
reader is ready to accept it.

The owner performs every Cloudflare login, deployment, secret entry, and billing check. Never
send a signing team identifier, a token, a pairing package, a QR image, Keychain data, or a
provider response to an agent or put it in the repository.

For Mac collector troubleshooting, the installed Release app uses `~/Library/Logs/ResetRadar/`;
Development uses the separate
`~/Library/Logs/ResetRadar.dev/`. These owner-only JSON Lines retain at most eight UTC days and
contain fixed, redacted event fields. Coding agents running under this macOS account can inspect
the Development folder directly for startup and publication root-cause analysis.

## Before the first install

1. Confirm the Apple-silicon Mac meets the toolchain requirements in the [contribution guide](contribution-guide.md#setup-and-development). Reset Radar Mac builds are arm64-only and do not run on Intel Macs.
   Generate the ignored project from the checked-in specification:

   ```sh
   Scripts/generate-project.sh
   ```

2. Create the ignored local Release-signing file from its template. In
   `Config/Build/Local.xcconfig`, set `DEVELOPMENT_TEAM` to the stable Personal Team already
   selected in Xcode; leave `CODE_SIGN_IDENTITY = Apple Development`. This is the one identity
   every installed Release build must use. Do not commit this file.

   ```sh
   cp Config/Build/Local.xcconfig.template Config/Build/Local.xcconfig
   ```

3. Open `ResetRadar.xcodeproj`. Select the `ResetRadarMac` scheme and **My Mac**, then use the
   scheme editor to make its **Run** action use **Release**. Build the scheme. The `Check Mac
   signing` post-action must report success; it rejects an ad-hoc signature, a missing team, or a
   helper signed by another team. A Development build is deliberately unsigned and is not an
   install candidate.

4. Find the resulting `ResetRadarMac.app` in Xcode's Products group, reveal it in Finder, and
   copy it to `/Applications`. If a previous installed copy exists, quit it from the menu bar
   first and replace only the bundle. Do not delete Application Support or Keychain items.

5. Open the copied app from Finder with **Open**. Approve the locally built app only if macOS
   Gatekeeper asks. Gatekeeper approval is expected for a local, non-notarized build; a Keychain
   prompt is not. If a Keychain prompt appears, cancel it, quit Reset Radar, and use
   [Locked Keychain or unexpected prompt](#locked-keychain-or-unexpected-prompt).

6. Open **Settings → General**. The expected initial message is **Signing and non-interactive
   Keychain access are available.** The launch-at-login switch remains optional; if enabled, use
   the displayed **Registration** state as the result. A requested toggle alone is not proof that
   macOS accepted it.

## Configure sources

Configure only sources that are already installed and signed in under the same macOS login.
Reset Radar never reads provider credential files or uses API-key mode.

1. In **Settings → Sources → Codex**, select **Add** in the empty table row. Enter an Alias and
   one absolute Home Folder (`CODEX_HOME`); when discovery needs it, enter an absolute `codex`
   executable path. Select **Discover**. The folder must exist and have no leading or trailing
   whitespace. The table has no fixed Codex source-count limit.
2. Each offered Codex option shows its `CODEX_HOME` above the executable path. Select **Preview**
   for the intended home and confirm that the same home, executable, and every allowlisted
   environment value appear under **Confirm exact change**. Select **Confirm and Apply** only if
   they are correct. The alias is saved with the newly configured source. Use the next Add row
   for a second home. Use **Save Home Folder** on a configured row to correct its folder through the
   same preview and confirmation while keeping its alias and account. Each confirmation rebuilds
   the collector immediately. Repeat the Add-row flow for every additional Codex home.
3. In the **Claude Code** card, choose **Set Up Claude Code Connection**, then **Preview**.
   Inspect the displayed `~/.claude/settings.json` path and helper path before selecting
   **Confirm and Apply**. The
   setup directly edits only the proved-safe `statusLine.command` in that file and keeps a narrow
   restore record. If the existing command cannot be proved safe, Reset Radar leaves it untouched.
   It accepts one executable path inside your home folder or the exact `bash $HOME/<script>` form
   when the trusted executable script has a Bash shebang and synthetic output matches. Other
   arguments or shell expansion remain blocked; keep those commands unchanged unless you have an
   equivalent directly executable replacement.
4. Confirm that the Codex table shows each configured Alias and Home Folder, and that the Claude
   Code card shows its configured source. Removing a source stops it locally but does not modify
   data already stored in the relay. **Restore Previous Setting** is the reversal for the
   Claude Code integration.

The Mac Account List reads its local snapshot even before relay setup. Unavailable rings after
source setup mean that the selected source has not supplied a usable window; review its Source
state in Account Details and correct its Home Folder if needed. Relay setup is required only for
publishing readings to other devices.

## Deploy and bind the relay

This section changes Cloudflare state. Start only when the owner is ready to use the included,
single-tenant Worker and has reconfirmed the Workers Free, no-paid-add-on, disabled-observability
requirements in [Cloudflare synchronization](research/cloudflare-synchronization.md).

1. From an owner-controlled terminal that is authenticated to the intended Cloudflare account,
   deploy the reviewed Worker. The command intentionally suppresses Wrangler's potentially
   sensitive output.

   ```sh
   npm --prefix relay run deploy:remote
   ```

2. In the Cloudflare dashboard, obtain that Worker's assigned canonical HTTPS `workers.dev`
   origin. It has no path, query, fragment, port, or credentials; it is not a URL embedded in this
   repository. Do not substitute a custom domain or a preview/version URL.

3. In **Settings → Relay & Pairing**, enter that origin and select **Prepare Relay**. Reset Radar
   generates and holds the actual tokens only in its local Keychain, then displays the two
   64-character lowercase SHA-256 values labelled `WRITE_TOKEN_DIGEST` and
   `ADMIN_TOKEN_DIGEST`.

4. In the Worker secret settings, create or replace exactly these secrets with the displayed
   digest values: `WRITE_TOKEN_DIGEST` receives the write digest and `ADMIN_TOKEN_DIGEST` receives
   the administration digest. The displayed values are digests, not bearer tokens. Do not try the
   interactive `npm run secrets:provision` prompt here: that prompt correctly expects raw tokens,
   which the app never reveals.

5. Return to Reset Radar and select **Activate Relay**. Activation deliberately wipes the remote
   relay before binding this Mac, so it revokes any existing reader state and starts a new relay
   lifecycle. It is safe for a new relay; for a replacement relay, make sure that reset is
   intended. Success reads **Relay setup is active.** If it says activation was interrupted,
   publication remains paused; correct the Worker-secret or network problem and select
   **Activate Relay** again rather than preparing a different relay.

6. On an installed iPhone or iPad reader, open All → Settings → Pairing & Sync. On the Mac, use
   **Create QR Pairing Code** and scan it there, compare the Pairing Confirmation Code on both
   devices, confirm on the reader, and wait for **Reader paired.** QR is the default. **Copy
   pairing package…** is a warned fallback for the reader's paste field: treat the clipboard
   contents like a password and let Reset Radar clear it when safe.

## Verify the installed collector

Before relying on it, check all of the following in the installed Release app:

- **General** reports signing and non-interactive Keychain access as available, with no Keychain
  dialog.
- **Sources** lists the intended Codex and/or Claude Code source and contains no unreviewed
  environment or status-line change.
- **Relay & Pairing** reports **Relay setup is active**. After a source obtains usage data, its
  publication uses the configured `workers.dev` relay; the collector's normal launch path does
  not fall back to synthetic fixtures.
- If launch at login is enabled, **Registration** reports `enabled`. If it reports approval is
  required, approve the item in **System Settings → General → Login Items** and then reopen or
  refresh General Settings.

## Update

1. Keep `Config/Build/Local.xcconfig` and the same Personal Team identity. Regenerate the project
   if necessary and build another Release `ResetRadarMac.app`.
2. Quit the running app from its menu-bar **Quit** command; merely closing the main window leaves
   the collector running.
3. Replace `/Applications/ResetRadarMac.app` with the new bundle and open it through Finder.
4. Recheck **Settings → General**. With the unchanged team identity, existing Application Support
   and Keychain state remain usable. A changed identity must use the recovery path instead; do not
   approve a Keychain prompt to work around it.

There is no in-app downloader or automatic updater. A storage migration may create a recoverable
local backup; do not erase it while confirming the update.

## Uninstall

This procedure is intentionally ordered. Removing the application first cannot revoke data on a
relay that is still configured or unavailable.

1. In **Settings → Relay & Pairing**, choose **Destroy Relay…** and confirm. Wait for **Relay data
   and local relay secrets were destroyed.** If the app says destruction is paused, leave the app
   and its local state in place, restore connectivity or unlock the login keychain, and retry.
2. In **Settings → General**, disable **Launch at login** and confirm that **Registration** is not
   `enabled`.
3. In **Settings → Sources**, choose **Restore Previous Setting** if the Claude Code
   setup was used. Do not manually overwrite `~/.claude/settings.json`; restoration refuses to
   overwrite a changed or unsafe setting.
4. Quit Reset Radar. In Finder, remove the Release support directory
   `~/Library/Application Support/ResetRadar`; it contains the installed helper and its
   owner-only Claude Code session records. Do not remove `ResetRadar.dev`, which belongs to
   Development builds, unless that separate data is also intentionally being discarded.
5. In **Keychain Access**, search for the exact service
   `com.unidentifiedstealthstartup.ResetRadarMac.transport` and delete only the matching Reset
   Radar generic-password items. Do not delete the `.dev` service unless intentionally removing
   Development data too.
6. Remove `/Applications/ResetRadarMac.app`.

## Recovery

| Situation | Safe response |
|---|---|
| Missing or damaged app | Rebuild and install a Release bundle with the recorded Personal Team identity. Existing Release Application Support and Keychain items can then be reused. |
| Login item needs approval | Open **System Settings → General → Login Items**, approve Reset Radar if macOS offers it, then reopen General Settings and check the reported registration state. |
| Codex discovery or CLI incompatibility | Re-enter the intended absolute `CODEX_HOME` and executable paths, review the fresh launch preview, and apply it. Do not rely on an ambient shell profile. |
| Claude Code configuration is unsafe | Leave the existing command unchanged. The preview message distinguishes a helper installation problem from an existing command that needs a trusted, directly executable path. Repair the cause outside Reset Radar, then retry Preview. |
| Changed signing identity | Rebuild using the identity that created the existing Release state. If that identity is unavailable, run relay setup again and later re-pair every reader; the app never exposes the raw recorded team identifier. |
| Lost Mac | From a separately controlled, authenticated route, destroy the relay state. On the replacement Mac, install with its chosen stable identity, complete relay setup, and re-pair every reader. |

### Locked Keychain or unexpected prompt

Unlock the macOS login keychain, return to **Settings → General**, and select **Retry**. Reset
Radar makes non-interactive Keychain calls only: while the keychain is unavailable, publication
pauses and the app retries every minute and when the login session becomes active. Once this
process has read its secrets, a later lock does not stop its in-memory session until quit, relay
setup replacement, or Destroy Relay.

If a Keychain dialog appears at any point, cancel it. Treat it as evidence that the Release
signing or Keychain state is not provable, then follow the changed-identity path above rather than
granting interactive access.
