# UX GUI

Status: Active

This document defines the owner-approved interface behavior. Product scope is in
[product-behavior.md](product-behavior.md); component vocabulary is in
[ux-terms.md](ux-terms.md).

## App icon

The iOS and iPadOS Home Screen icon is an original radar mark: two concentric reading rings,
a sweep, and one highlighted reading dot on a dark background. The universal app uses the same
icon on iPhone and iPad; the system supplies the rounded mask and appearance variations. The
Apple Watch app uses a simplified, higher-contrast version of the same mark with circular-safe
spacing for the system-applied Watch mask.

## First iPhone screen

The iOS app shows a five-item **Main Toolbar** along the bottom edge. Every toolbar item has an original, neutral, tintable bitmap icon above its label. The fixed items are:

- first: **Home**, with a house icon;
- second: **Benefits**, with a gem bitmap icon;
- third: **Community**, with a three-person-group bitmap icon;
- fourth: **Insight**, with a lightbulb bitmap icon; and
- fifth: **All**, with a three-horizontal-bars bitmap icon.

On iPad, the Main Toolbar uses the system's adaptive tab bar or sidebar presentation. Its
destinations, order, icons, Home, and Settings are the same as on iPhone.

Selecting Home shows a vertically scrolling **Account List**. Reset Radar supports at most two
Codex accounts and one Claude Code account in the first version. Each configured account occupies
one inset, rounded **Account Row**, and rows use localized natural order by their displayed
alias. The displayed alias is the custom Account Alias when present and the stable `Account #N`
default otherwise. A stable account number breaks an equivalent-sort tie.

An Account Row is one compact horizontal card. Its small alias label is pinned to the top-leading
corner, with Codex or Claude Code as quieter secondary text in the same leading identity area.
The five-hour and weekly **Allowance Rings** follow horizontally, and a circular, neutral,
tintable bitmap arrow button ends the row with the accessible label “Account Details.” Percentage
Used stays inside each ring and its window name remains visible.
Reset Time and freshness copy live in Account Details instead of the compact row. A stale,
waiting, or unavailable ring uses a distinct status symbol as well as complete accessibility
text; unavailable is never rendered as 0%. At accessibility text sizes the row may reflow while
preserving that logical order.

Rows use native platform spacing, a quiet material or grouped background, a subtle boundary, and
enough vertical padding to keep the two rings legible without recreating a grid. The arrow remains
visually subordinate to usage while its complete hit region meets the platform's accessibility
target size.

Selecting the row or its arrow opens that account's **Account Details**. Selecting a ring opens
the same destination with that Window Details section initially emphasized. Long aliases use
middle truncation in compact layouts while accessibility exposes the complete alias.

Before pairing or when no account is configured, Home shows an empty Account List with a
prominent **Setup Banner** explaining the next setup or pairing action. When setup is only partly
complete, the banner coexists with every configured row and offers the next useful action. It
never fabricates or hides an account row. A configured account remains present when its source is
signed out, offline, incompatible, or otherwise unavailable.

On iPhone and iPad, account configuration is known only from an authenticated Mac publication.
Before activation finishes, a validated pairing preflight is hidden and Home explains that
pairing is still being confirmed. After activation but before the first publication, Home says it
is waiting for Mac data; it does not claim that the Mac has no configured accounts. Once a
snapshot exists, a later relay error keeps its account rows visible with their actual freshness
and a separate sync problem. Pairing & Sync reports the pending activation retry and directs the
owner to a fresh package when registration is rejected. A denied camera permission leaves manual
paste available; pairing text is never
read from the pasteboard without the owner's action or shown again after confirmation.

Home exposes Refresh for the whole Account List. It requests all configured Codex accounts as one
manual-refresh target and performs the ordinary relay read for Claude Code; feedback stays
account-specific so one failure does not conceal a sibling success. Account Details has the
separate single-account Refresh described below.

Refresh feedback distinguishes a successful relay contact from a completed Mac response. A
request accepted by the relay is shown as waiting, not as new usage. A matching encrypted result
can report success or source unavailability for each requested Codex account; an unrelated
publication, timeout, rate limit, offline Mac, or cancelled foreground wait does not claim Mac
completion. The last valid reading stays visible with its observation time. A Claude Code-only
Refresh reports the ordinary relay-read result without suggesting that Claude Code was forced
to produce a new reading.

On iPad, Home is a two-column split view: the Account List remains in the leading column while
the selected account's details appear in the trailing column. It restores the last device-local
selection when that account still exists and otherwise selects the first account in that order. When the
list is empty, the trailing column shows setup guidance instead of fabricated details.

Selecting Benefits, Community, Insight, or All shows that destination's intentionally empty screen for now. All shows a Settings icon in its top-right corner; selecting it opens Settings.

## Mac app

The Mac uses a native Main Sidebar containing Home, Benefits, Community, Insight, and All. Home
uses a split Account List and Account Details presentation equivalent to iPad. The leading list
uses the same compact row content and localized natural order as iPhone; the trailing pane restores the last
valid device-local selection or selects the first account. The other four destinations are empty.

The small top-leading alias label is editable on Mac. Selecting it turns it into an inline editor; Sources Settings
offers the same action. Saving publishes a metadata-only encrypted snapshot immediately, without
advancing a usage observation. An alias is at most 32 UTF-8 bytes and must contain at least one
visible letter, number, punctuation, or symbol. It may preserve case and leading or trailing ASCII
spaces. Non-ASCII spaces, line/paragraph separators, control or format characters such as
zero-width and bidirectional controls, private-use or unassigned characters, Unicode
noncharacters, and an exact duplicate of another account's effective displayed label are rejected.
Letters from international scripts and emoji that need no zero-width joiner remain valid; explicit
shaping controls do not. Clearing the field restores the stable `Account #N` default; entering
only spaces shows a validation error instead.

Throughout source, relay, and pairing setup, the Mac keeps the Account List visible. A Setup
Banner offers the next action and coexists with already configured rows; the list is empty only
when no account is configured.
The Codex Sources table rejects a Home Folder with surrounding whitespace or a missing directory
before discovery. Each configured Codex row offers Save Home Folder, which previews and confirms an
exact replacement without removing the account or its alias.
Claude Code setup identifies whether preview failed because its helper could not be verified or
the existing status-line command cannot be safely composed. Neither failure changes Claude Code
settings. Sources states that confirmation directly edits `~/.claude/settings.json`; a trusted
`bash $HOME/<script>` command can be composed while retaining its current visible output.

Closing the main window leaves the menu-bar collector running. Its menu shows one status line per
account, followed by Refresh All, Open Reset Radar, Settings, and Quit. Settings opens through the
standard macOS Settings scene and Command-comma.

In Mac Settings, the main detail pane groups settings by purpose into separate, clearly titled
cards. Each section uses the same inset, rounded card treatment and vertical spacing; the cards
scroll above the persistent Global Messages Pane. Keep related controls and explanatory text
together in their card; show transient setup feedback in a card as well. General separates
launch-at-login controls from signing and Keychain recovery; Sources separates Codex and Claude
Code; Relay & Pairing separates relay setup, reader pairing, and paired devices; About uses native
sections for product information, license, and owner-initiated GitHub feedback and support links.
Diagnostics collection remains active without a Settings destination.

Main and Settings share one Global Messages history. A pane at the bottom of each detail column,
to the right of its sidebar, shows a boxed **Global Messages** tab title above a scrollable area
about eight text lines tall. Message text is two points smaller than normal body text; newer
messages follow older ones and the view follows the latest entry. The pane shows curated
collector, source, relay, pairing, device, and recovery messages. Its bounded history lives only
for the current app session and contains no provider responses or secret values.
When publication stops or pauses safely, the pane names the typed reason, such as a publisher
conflict, rejected write token, incompatible payload, oversized envelope, unavailable secrets, or
inactive relay state. Repeated attempts do not repeat an unchanged reason; a later successful
publication reports recovery. The inactive-relay message explains that local readings remain
available without relay setup.

## Apple Watch app

Watch Home uses an N-by-two ring matrix, where N is the number of configured accounts and the two
columns are the five-hour and weekly windows. Rows use the same account order as Home but show
no visible account alias. Each row and its two rings use a distinct pastel Account Palette derived
from the stable global account number, so its color assignment stays fixed until that account is
removed and remains distinct from every other active row: Account #1 uses lavender, Account #2
uses mint, and Account #3 uses peach. Each family combines a pastel surface tint with a
contrast-compliant ring and text accent and adapts to light, dark, and increased-contrast
appearances. The palette never carries usage or source state; status still uses its required
symbol and accessibility text. Every ring's accessibility description includes the complete
alias, product, window, Percentage Used, reset, and freshness. Selecting a ring opens compact
Account Details for that account with the selected window emphasized and the same accent.
Watch Home has no navigation title or **Accounts** section heading. The Account List appears
first, followed by a full-width **Refresh** text button and then an **Advanced** button. Advanced
opens the **Advanced Action** screen, which contains the local data controls; neither control is
pinned or a top-toolbar item.

The Watch app also offers an owner-confirmed **Erase Watch Data** action. It clears the local cache and prevents later usage delivery until the owner chooses **Reset Watch Pairing**. A complication may keep its previously rendered frame until watchOS processes a reload or the owner removes it.

The Allowance Complication shows one configured account window's percentage used and freshness.
It shows a middle-truncated alias in families with room; compact families retain the account in
accessibility text. Stale or unavailable data must remain visibly distinct from a current value.

## Account Details

Each configured account has one Account Details destination. It identifies the alias and product,
then shows the five-hour and weekly windows first, followed by every other valid provider-reported
window. The ring selected from Home receives initial visual emphasis.

For each window, show:

- an Allowance Ring and exact Percentage Used;
- the window label;
- a relative reset countdown and the absolute reset date and time in the OS's current local time zone;
- Last Updated and the data state; and
- an explicit explanation when data is stale, unavailable, incompatible, signed out, offline, or awaiting a post-reset refresh.

The provenance and synchronization area shows the acquisition source, the Collector Mac's publication status, Last Synced for the receiving device, and source compatibility status. Technical versions and error detail remain behind a diagnostics disclosure instead of competing with primary usage information.

The Account Details primary action requests the freshest data for only that account. On Mac it
refreshes that account's first-party source subject to its independent adapter backoff. On iPhone
and iPad, a Codex account Refresh posts an authenticated, short-lived request containing only the
account's opaque Reset Radar identifier, then checks the encrypted relay for its result. A Claude
Code account Refresh performs the ordinary relay read without creating a provider response. Home
Refresh requests all configured Codex accounts together and performs the ordinary relay read for
Claude Code. Successful account reads are committed even when a sibling fails, and the result is
reported per account. Timeout or an offline Mac leaves the last valid data visible. The phone
never directly contacts Codex or Claude Code. Account Details never presents history, forecasts,
pace analysis, or threshold controls.

On iPhone, Pairing & Sync reports interrupted local Forget Mac cleanup separately from completed local deletion and Watch erasure. When the Watch is unreachable, it says erasure is pending and explains that the old Watch cache may remain until reconnection or an owner-confirmed erase in the Watch app. It reports one responding Watch cache as cleared only after an acknowledgement; it does not claim that another paired Watch or a previously rendered complication frame was erased. The iPad has no Watch state.

On Mac, QR scanning is the default pairing transfer. Manual Copy requires a separate tap and warns that the package contains a long-lived content key and may reach other nearby devices through Universal Clipboard. The app conditionally clears its own unchanged clipboard value after pairing, expiry, or view closure, but explains that a copied package cannot be recalled from another device. Relay & Pairing also states that locking the login Keychain after the collector has started does not stop its running publisher; quitting the app stops it.

On iPhone, iPad, and Mac, each valid provider-reported account window, including an additional
Account Details limit, has an off-by-default reset-notification control that applies only to that
device. A notification is scheduled only while that window has a known future Reset Time.
Notification copy identifies the account by its displayed alias. Enabling the first control on a
device triggers that device's system authorization request. Fully authorized notifications use
the default sound and show a banner while Reset Radar is active on iPhone, iPad, or Mac;
provisional authorization remains quiet. On iPhone,
eligible five-hour windows also offer Start Live Activity; activities never start automatically
and visibly identify the alias. Start is unavailable with an explanation when the reading is
already stale or its reset is beyond the eight-hour activity horizon. While that exact window has
a running activity, the action becomes Stop Live Activity and ends it with immediate dismissal.
Watch Account Details has neither control; the Watch shows the iPhone's forwarded notifications.

## Widgets and Live Activities

On iPhone and iPad, small Home Screen and rectangular Lock Screen widgets show one user-configured
valid provider window, including an additional Account Details limit. Circular and inline Lock
Screen widget families are not part of this version. The read-only App Intent accepts
the same all-window selection and identifies the selected alias, product, and window in its
cache-only result. The medium Home Screen widget shows both standard windows for one
user-configured account. A temporarily missing additional window becomes unavailable and resumes
only if the same exact window ID returns; a changed ID never silently takes its place.
Widgets visibly identify the middle-truncated alias, include freshness, and render only from the
committed local cache. When the system reloads a widget, it may first refresh that cache from the
relay if the last successful refresh is more than five minutes old. A timeline requests routine
reload after 30 minutes; the request is not a promise that the system will run it then.

A Reset Live Activity, available on iPhone only, shows one eligible five-hour account window. It
starts only from a foreground Account Details action, receives local opportunistic updates,
displays stale state honestly until its known reset even if the reading ages, and ends on the next
app execution after reset, observation invalidation for another reason, or removal of its
account. It also ends immediately if an updated reset moves beyond its fixed eight-hour horizon.
When several activities run, the soonest reset receives highest Dynamic Island relevance; equal
reset instants use stable global account number. Weekly windows never start Live Activities. A
widget or complication whose account was removed becomes unavailable until the owner chooses
another account; it never silently retargets.

