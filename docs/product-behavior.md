# Product behavior

Status: Active

Product scope: what the app does and what it deliberately does not do.

## Distribution

- Reset Radar is for the owner's personal use only.
- The first version is signed with the owner's free Apple account and sideloaded. It is not distributed through the App Store or TestFlight.
- Sideloadly is the supported iPhone and embedded-watch installation and seven-day refresh path. LiveContainer is not a supported runtime because it cannot register the app's WidgetKit extension.
- Installation must retain the widget and watch targets and pass physical-device checks for app-group sharing, local notifications, widgets, paired-watch installation and synchronization, and refresh without data loss. See [personal-use-sideloading.md](research/phase-1/personal-use-sideloading.md).

## Usage tracking

- Each service supports multiple simultaneous allowance windows.
- Every window can display a timestamped percentage used, such as separate five-hour and weekly allowances, beside its reset time.
- Usage percentages are acquired automatically; manual percentage entry is not the primary source.
- A Mac collector obtains Codex coding-allowance percentages from the installed Codex app-server and Claude Code coding-allowance percentages from Claude Code's derived status-line state, then sends credential-free snapshots to the paired iPhone. This does not promise automatic coverage of every general ChatGPT or Claude web/mobile allowance. Private consumer endpoints and copied credentials are excluded.
- The app always identifies the percentage source and freshness. It never derives usage from elapsed time.
- Usage semantics are specified in [usage-tracking.md](research/phase-1/usage-tracking.md); automatic sources are in [automatic-usage-acquisition.md](research/phase-1/automatic-usage-acquisition.md), and cellular transport choices remain under research in [mobile-network-synchronization.md](research/phase-1/mobile-network-synchronization.md).

## First-version scope

Status: Active. Approved by the owner in [Phase 1 owner decisions](phase-1/owner-decisions.md).

- Manual ChatGPT setup begins blank, without numeric defaults, templates, or prefilled recurrence examples. The user creates and confirms each manual rule.
- The Mac collector refreshes provider-reported percentages without exposing provider credentials to iPhone or watchOS. When the Mac or first-party CLI source is unavailable, the app shows stale/unavailable state rather than inventing a value.
- Rules are editable and show whether a reset was entered by the user or calculated from a rule. Recurring rules remain tied to their selected time zone; the interface displays dates in the OS's current local time zone and must not change rule semantics when that zone changes.
- The app computes the next reset, schedules a local notification, shows Home Screen and Lock Screen countdown widgets, includes Live Activities for eligible short windows, and offers a read-only App Intent. Weekly windows are not Live Activities.
- The first version includes an Apple Watch app that receives normalized snapshots through the paired iPhone and shows reset times, percentage used, source, and freshness. It does not connect directly to provider services or store provider credentials.
- The first version retains only the latest valid percentage observation with its source, time, and freshness state. It excludes percentage threshold alerts, history, pace labels, and exhaustion forecasts.
- Normalized snapshots are encrypted on the Mac before an owner-operated Cloudflare relay stores them; only paired Apple devices hold the content key. Cloudflare can observe transport metadata but not the usage payload. The first version uses one authoritative Mac and foreground/manual plus opportunistic background refresh, with no APNs architecture. Real usage cannot use the relay until the required synthetic-data spike passes.
- The Mac collector and pairing flow are required for the first usable version. The Mac collector is locally development-signed, without first-version notarization or an automatic updater.
- Non-goals: App Store or TestFlight distribution; reading usage with a session cookie, password or copied consumer token; API-key mode; services beyond the approved manual scope; managed organization plans; dependable push refresh; and percentage analysis features.
