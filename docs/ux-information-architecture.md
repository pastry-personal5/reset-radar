# UX information architecture

Status: Active

The Standard Layout is the conceptual containment model for the app. It records structure only; visual and interaction rules are in [ux-gui.md](ux-gui.md).

## First iPhone screen

The iOS app root contains a five-item **Main Toolbar** at the bottom. Its destinations are ordered:

1. **Home**.
2. **Benefits**.
3. **Community**.
4. **Insight**.
5. **All**.

On iPad, the same root uses the system's adaptive tab bar or sidebar presentation with the same
five destinations in the same order.

Home contains one vertically scrolling **Account List** with at most two Codex accounts and one
Claude Code account. Each configured account owns one **Account Row** containing its displayed
alias in a top-leading label, product, five-hour Allowance Ring, weekly Allowance Ring, and Account
Details action. Rows use localized natural order by alias with the stable account number as
the tie-breaker.

Home also owns **Refresh** for the whole Account List. It targets all configured Codex accounts
and performs the ordinary relay read that can update Claude Code. Account Details owns the
separate single-account Refresh action.

Selecting a row opens that account's **Account Details**. Selecting either ring opens the same
destination and determines which **Window Details** section receives initial emphasis. It does not
create a separate destination for each window.

Home contains no fabricated rows before pairing or account setup. A contextual **Setup Banner**
shares Home with the Account List and contains the next required setup or pairing action. It may
appear above existing rows when only part of setup is incomplete. Configured rows remain in the
list during signed-out, offline, incompatible, stale, and unavailable states.
On iPhone and iPad, the first authenticated Mac publication establishes which accounts exist;
pending activation and awaiting first publication have an empty list and distinct guidance.

On iPad, Home is a split destination: the Account List remains in the leading column and Account
Details occupies the trailing column. It restores the last device-local account selection when
valid and otherwise selects the first account in that order. With no configured account, the trailing pane
shows setup guidance rather than an Account Details destination.

Benefits, Community, Insight, and All are intentionally empty destinations for now. All contains a top-right Settings action; Settings is a separate destination rather than content inside All.

## Mac app

The Mac root uses a **Main Sidebar** with Home, Benefits, Community, Insight, and All in the same
order as iOS. Benefits, Community, Insight, and All are intentionally empty. Home uses the same
split Account List and Account Details containment as iPad. The alias is editable from its Home
row and from Sources Settings; both entry points operate on the same Mac-authoritative metadata.

The Account List remains present throughout collector, relay, and pairing setup. The Setup Banner
contains the next required action and coexists with any already configured account rows; the list
is empty only when no account is configured.

Settings is a separate standard macOS scene. Closing the main window does not stop collection;
the menu-bar companion owns one status item per account and commands to reopen the window,
refresh all accounts, open Settings, or quit.

The Global Messages Pane sits at the bottom of the detail area in both the main window and
Settings, to the right of each window's sidebar. Both panes display the same session-local message
history, independent of the selected account or Settings section.

## Apple Watch app

Watch Home contains an N-by-two Allowance Ring matrix: one row per configured account in Home's
localized natural order and columns for five-hour and weekly windows. It does not show aliases on Home. Each row
uses a distinct, stable pastel Account Palette derived from the global account number; the palette
does not encode usage or source state. Selecting a ring opens compact Account Details for its
account and selected window; accessibility still identifies the alias and product. Account Details
contains no notification or Live Activity controls. The Watch has no top-level Main Toolbar or
Main Sidebar. Its local data controls include **Erase Watch Data** and the separate **Reset Watch
Pairing** action.

The **Allowance Complication** contains one user-selected account window. Both the app and
complication read only the Watch's last valid local cache.

## Account Details

Each configured account has one Account Details destination containing:

1. Displayed alias, product identity, and acquisition availability.
2. Window Details for the five-hour allowance.
3. Window Details for the weekly allowance.
4. Window Details for every additional valid provider-reported limit.
5. Observation provenance and synchronization status.
6. Account-scoped Refresh and diagnostics actions appropriate to the current platform.

Each Window Details section owns only the latest observation and current reset state. History,
forecasts, pace analysis, and threshold configuration are not contained in Account Details.

## Settings containment

iOS Settings, on iPhone and iPad, contains Pairing & Sync, notification authorization status, Live
Activity authorization status on iPhone, Privacy & Data, Diagnostics, and About. Per-window
notification and Live Activity actions remain in Account Details. On iPhone, Pairing & Sync owns
the pending or confirmed Watch-erasure state after Forget Mac; iPad has no Watch state.

Mac Settings contains General, Sources, Relay & Pairing, Diagnostics, and About. General owns
launch at login and notification authorization status. Sources owns Codex and Claude Code account
configuration, replacement/removal confirmation, and alias editing. Relay & Pairing owns relay
setup, QR/manual pairing, the warned Manual Copy action, paired-device revocation, destruction,
Keychain-cache disclosure, and recovery status.
