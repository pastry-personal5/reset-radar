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

On iPad, the same root uses the system's adaptive tab bar or sidebar presentation with the same five destinations in the same order; everything below applies unchanged.

Home contains one **Allowance Grid**. The grid has four logical cells in this fixed reading order:

1. Codex five-hour allowance.
2. Codex weekly allowance.
3. Claude Code five-hour allowance.
4. Claude Code weekly allowance.

Each cell contains one **Allowance Ring** for exactly one product and allowance window. The grid is logically two columns by two rows: Codex occupies the top row and Claude Code occupies the bottom row; five-hour windows occupy the left column and weekly windows occupy the right column.

Selecting either Codex ring opens Codex **Usage Details**. Selecting either Claude Code ring opens Claude Code **Usage Details**. The selected ring determines which **Window Details** section receives initial emphasis; it does not create a separate destination for each window.

The Allowance Grid remains present before pairing and when setup is incomplete. A contextual **Setup Banner** shares Home without replacing the grid and contains the next required setup or pairing action.

Benefits, Community, Insight, and All are intentionally empty destinations for now. All contains a top-right Settings action; Settings is a separate destination rather than content inside All.

## Mac app

The Mac root uses a **Main Sidebar** with Home, Benefits, Community, Insight, and All in the same order as iOS. Benefits, Community, Insight, and All are intentionally empty. Home contains the same **Allowance Grid** as iPhone, with the same four cells, fixed logical placement, and reading order.

Selecting a ring follows the same product-scoped Usage Details containment as iPhone.

The grid also remains present before collector setup is complete. The Setup Banner contains the next required collector, relay, or pairing action.

Settings is a separate standard macOS scene. Closing the main window does not stop collection; the menu-bar companion owns background status and commands to reopen the window, refresh all sources, open Settings, or quit.

## Apple Watch app

Watch Home contains the same logical two-by-two Allowance Grid. Selecting a ring opens compact product-scoped Usage Details with both standard windows; it contains no notification or Live Activity controls. The Watch has no top-level Main Toolbar or Main Sidebar. Its local data controls include an owner-confirmed erase and a separate Reset Pairing action.

The **Allowance Complication** contains one user-selected window. Both the app and complication read only the Watch's last valid local cache.

## Usage Details

Each product has one Usage Details destination containing:

1. Product identity and overall acquisition availability.
2. Window Details for the five-hour allowance.
3. Window Details for the weekly allowance.
4. Observation provenance and synchronization status.
5. Refresh and diagnostics actions appropriate to the current platform.

Each Window Details section owns only the latest observation and current reset state. History, forecasts, pace analysis, and threshold configuration are not contained in Usage Details.

## Settings containment

iOS Settings, on iPhone and iPad, contains Pairing & Sync, notification authorization status, Live Activity authorization status on iPhone, Privacy & Data, Diagnostics, and About. Per-window notification and Live Activity actions remain in Usage Details. On iPhone, Pairing & Sync owns the pending or confirmed Watch-erasure state after Forget Mac; iPad has no Watch state.

Mac Settings contains General, Sources, Relay & Pairing, Diagnostics, and About. General owns launch at login and notification authorization status; Sources owns Codex and Claude Code configuration; Relay & Pairing owns relay setup, QR/manual pairing, the warned Manual Copy action, paired-device revocation, destruction, Keychain-cache disclosure, and recovery status.
