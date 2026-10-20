# Product behavior

Status: Active

Product scope: what the app does and what it deliberately does not do.

## Distribution

- Reset Radar is for the owner's personal use only.
- The first version is signed with the owner's free Apple account and sideloaded. It is not distributed through the App Store or TestFlight.
- Sideloadly is the supported iPhone, iPad, and embedded-watch installation and seven-day refresh path.
- Supported minimums are iOS and iPadOS 26.6.2, watchOS 26.6, and macOS 26.7.1. The reference devices are listed in [Platform targets](architecture.md#platform-targets). LiveContainer is not a supported runtime because it cannot register the app's WidgetKit extension.
- Installation must retain the widget and watch targets and pass physical-device checks for app-group sharing, local notifications, widgets, paired-watch installation and synchronization, and refresh without data loss. See [personal-use-sideloading.md](research/phase-1/personal-use-sideloading.md).

## Usage tracking

- Each service supports multiple simultaneous allowance windows.
- Every window can display a timestamped percentage used, such as separate five-hour and weekly allowances, beside its reset time.
- Usage percentages and reset instants are acquired automatically. Manual percentage entry and manual reset rules are not supported.
- A Mac collector obtains Codex coding-allowance percentages from the installed Codex app-server and Claude Code coding-allowance percentages from Claude Code's derived status-line state, then sends credential-free snapshots to paired iPhones and iPads. This does not promise automatic coverage of every general ChatGPT or Claude web/mobile allowance. Private consumer endpoints and copied credentials are excluded.
- The app always identifies the percentage source and freshness. It never derives usage from elapsed time.
- Usage semantics are specified in [usage-tracking.md](research/phase-1/usage-tracking.md); automatic sources are in [automatic-usage-acquisition.md](research/phase-1/automatic-usage-acquisition.md), and cellular transport choices remain under research in [mobile-network-synchronization.md](research/phase-1/mobile-network-synchronization.md).

## First-version scope

Status: Active. Approved by the owner in [Phase 1 owner decisions](phase-1/owner-decisions.md).

- The Mac collector refreshes provider-reported percentages without exposing provider credentials to iPhone or watchOS. When the Mac or first-party CLI source is unavailable, the app shows stale/unavailable state rather than inventing a value.
- A manual Codex or all-product Refresh on iPhone or iPad requests an immediate Codex read from an awake Mac through the relay, then retrieves the encrypted result. If the Mac does not respond in time, the app keeps its last valid data and says the Mac refresh is pending or unavailable. A Claude Code-only Refresh reads the relay; Claude Code still updates only after a real Claude Code response.
- Provider reset instants are stored as absolute instants and displayed in the OS's current local time zone. A user may opt into one local reset notification per Home window on each iPhone, iPad, or Mac; the same reset can therefore alert on more than one device.
- The iOS app runs natively on iPhone and iPad with the same Home, Usage Details, Settings, and widgets. iPad has no Live Activities and no paired Apple Watch.
- The app shows configurable Home Screen and Lock Screen widgets, includes user-started Live Activities for eligible five-hour windows, and offers a read-only App Intent. Weekly windows are not Live Activities.
- The first version includes an Apple Watch app with the same two-by-two Allowance Grid, product-scoped details, and one configurable-window complication. It receives normalized snapshots through the paired iPhone and does not connect directly to provider services or store provider or relay credentials.
- Forget Mac hides the iPhone cache immediately and finishes local secret and surface cleanup before reporting local completion. It reports Watch erasure as pending until one responding Watch confirms a local cache clear. The Watch offers an owner-confirmed local erase; an offline or other paired Watch, or a previously rendered complication, cannot be erased instantly from the iPhone.
- The first version retains only the latest valid percentage observation with its source, time, and freshness state. It excludes percentage threshold alerts, history, pace labels, and exhaustion forecasts.
- Normalized snapshots are encrypted on the Mac before an owner-operated Cloudflare relay stores them; only paired Apple devices hold the content key. Cloudflare can observe transport metadata but not the usage payload. The first version uses one authoritative Mac and foreground/manual plus opportunistic background refresh, with no APNs architecture. Real usage cannot use the relay until the required synthetic-data spike passes.
- The Mac collector and pairing flow are required for the first usable version. The Mac collector is locally development-signed, without first-version notarization or an automatic updater.
- Non-goals: App Store or TestFlight distribution; reading usage with a session cookie, password or copied consumer token; API-key mode; manual reset rules; general ChatGPT or Claude consumer usage; managed organization plans; dependable push refresh; and percentage analysis features.
