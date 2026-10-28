# Product behavior

Status: Active

Product scope: what the app does and what it deliberately does not do.

## Distribution

- Reset Radar is for the owner's personal use only.
- The first version is signed with the owner's free Apple account and sideloaded. It is not distributed through the App Store or TestFlight.
- Sideloadly is the supported iPhone, iPad, and embedded-watch installation and seven-day refresh path.
- Supported minimums are iOS, iPadOS, and watchOS 27.0, and macOS 26.7.1. The reference devices are listed in [Platform targets](architecture.md#platform-targets). LiveContainer is not a supported runtime because it cannot register the app's WidgetKit extension.
- Installation must retain the widget and watch targets and pass physical-device checks for app-group sharing, local notifications, widgets, paired-watch installation and synchronization, and refresh without data loss. See [personal-use-sideloading.md](research/personal-use-sideloading.md).

## Usage tracking

- Each service supports multiple simultaneous allowance windows.
- Every window can display a timestamped percentage used, such as separate five-hour and weekly allowances, beside its reset time.
- Usage percentages and reset instants are acquired automatically. Manual percentage entry and manual reset rules are not supported.
- A Mac collector obtains Codex coding-allowance percentages from the installed Codex app-server and Claude Code coding-allowance percentages from Claude Code's derived status-line state, then sends credential-free snapshots to paired iPhones and iPads. This does not promise automatic coverage of every general ChatGPT or Claude web/mobile allowance. Private consumer endpoints and copied credentials are excluded.
- The first version supports any number of concurrently configured Codex accounts and one Claude
  Code account. Reset Radar assigns each a stable opaque local identifier, global Account #N, and
  optional Mac-authored alias; provider account identifiers never become display labels.
- The app always identifies the percentage source and freshness. It never derives usage from elapsed time.
- Usage semantics are specified in [usage-tracking.md](research/usage-tracking.md); automatic sources are in [automatic-usage-acquisition.md](research/automatic-usage-acquisition.md), and cellular transport choices remain under research in [mobile-network-synchronization.md](research/mobile-network-synchronization.md).

## First-version scope

Status: Active. Approved by the owner in [Phase 1 owner decisions](phase-1/owner-decisions.md).

- The Mac collector refreshes provider-reported percentages without exposing provider credentials to iPhone or watchOS. When the Mac or first-party CLI source is unavailable, the app shows stale/unavailable state rather than inventing a value.
- Account Details Refresh requests an immediate read only for the selected Codex account; Home
  Refresh requests all configured Codex accounts and reports outcomes per account. If the Mac does
  not respond in time, the app keeps the last valid data and says the refresh is pending or
  unavailable. Claude Code Refresh reads the relay; Claude Code still updates only after a real
  Claude Code response.
- Provider reset instants are stored as absolute instants and displayed in the OS's current local
  time zone. A user may opt into one local reset notification per account window on each iPhone,
  iPad, or Mac, including additional valid provider windows; the same reset can therefore alert
  on more than one device. A temporarily missing additional window cancels its pending request;
  its opt-in resumes only if that exact window returns. Fully authorized reset notifications use
  the default sound and show a foreground banner while Reset Radar is active; provisional
  authorization remains quiet.
- The iOS app runs natively on iPhone and iPad with the same Account List, Account Details,
  Settings, and widgets. iPad uses a split list/detail Home and has no Live Activities or paired
  Apple Watch.
- The app shows configurable small Home Screen and rectangular Lock Screen widgets and a read-only
  App Intent for any valid provider window; the medium widget shows one account's two standard
  windows. It includes user-started Live Activities for eligible five-hour windows, with an
  immediate Stop action for the selected running window. Start requires a fresh reading whose
  reset fits within the activity's eight-hour horizon. A stale running activity remains visibly
  stale until its known reset; if an updated reset leaves the horizon, the activity ends
  immediately. The soonest reset has highest Dynamic Island relevance, with stable account number
  as the tie-breaker. Weekly windows are not Live Activities. Widget timelines request routine
  reload after 30 minutes, but the system may delay or omit execution.
- The first version includes an Apple Watch app with an N-by-two account/window ring matrix,
  stable pastel account palettes, account-scoped details, and one configurable account-window
  complication. It receives normalized snapshots through the paired iPhone and does not connect
  directly to provider services or store provider or relay credentials.
- Forget Mac hides the iPhone cache immediately and finishes local secret and surface cleanup before reporting local completion. It reports Watch erasure as pending until one responding Watch confirms a local cache clear. The Watch offers an owner-confirmed local erase; an offline or other paired Watch, or a previously rendered complication, cannot be erased instantly from the iPhone.
- The first version retains only the latest valid percentage observation with its source, time, and freshness state. It excludes percentage threshold alerts, history, pace labels, and exhaustion forecasts.
- Normalized snapshots are encrypted on the Mac before an owner-operated Cloudflare relay stores them; only paired Apple devices hold the content key. Cloudflare can observe transport metadata but not the usage payload. The first version uses one authoritative Mac and foreground/manual plus opportunistic background refresh, with no APNs architecture.
- The Mac collector and pairing flow are required for the first usable version. The Mac collector is locally development-signed, without first-version notarization or an automatic updater.
- Non-goals: App Store or TestFlight distribution; reading usage with a session cookie, password or copied consumer token; API-key mode; manual reset rules; general ChatGPT or Claude consumer usage; managed organization plans; dependable push refresh; and percentage analysis features.
