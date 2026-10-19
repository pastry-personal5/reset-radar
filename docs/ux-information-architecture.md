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

Home contains one **Allowance Grid**. The grid has four logical cells in this fixed reading order:

1. Codex five-hour allowance.
2. Codex weekly allowance.
3. Claude Code five-hour allowance.
4. Claude Code weekly allowance.

Each cell contains one **Allowance Ring** for exactly one product and allowance window. The grid is logically two columns by two rows: Codex occupies the top row and Claude Code occupies the bottom row; five-hour windows occupy the left column and weekly windows occupy the right column.

Selecting either Codex ring opens Codex **Usage Details**. Selecting either Claude Code ring opens Claude Code **Usage Details**. The selected ring determines which **Window Details** section receives initial emphasis; it does not create a separate destination for each window.

The Allowance Grid remains present before pairing and when setup is incomplete. A contextual **Setup Banner** shares Home without replacing the grid and contains the next required setup or pairing action.

Benefits, Community, Insight, and All are intentionally empty destinations for now.

## First Mac screen

The first Mac screen contains the same **Allowance Grid** as the first iPhone screen. It uses the same four cells, containment, fixed logical placement, and reading order.

Selecting a ring follows the same product-scoped Usage Details containment as iPhone.

The grid also remains present before collector setup is complete. The Setup Banner contains the next required collector, relay, or pairing action.

## Usage Details

Each product has one Usage Details destination containing:

1. Product identity and overall acquisition availability.
2. Window Details for the five-hour allowance.
3. Window Details for the weekly allowance.
4. Observation provenance and synchronization status.
5. Refresh and diagnostics actions appropriate to the current platform.

Each Window Details section owns only the latest observation and current reset state. History, forecasts, pace analysis, and threshold configuration are not contained in Usage Details.
