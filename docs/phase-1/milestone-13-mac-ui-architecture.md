# P1-M13: Mac UI implementation plan

Status: Active

Polish the Mac composition's SwiftUI views without changing the Domain, Application, or provider
contracts. This sequence follows the [Mac UI goal](milestone-13-mac-ui-overview.md) and the
binding [UX GUI](../ux-gui.md).

1. Rework Sources Settings into Codex and Claude Code cards. The Codex table reads configured
   account labels and selected `CODEX_HOME` folders from owner-only local configuration. A draft
   row collects Alias and an absolute Home Folder, then uses the existing discovery, preview,
   and confirmation flow; a new alias is saved in the owner-only account catalog before the
   collector rebuilds and publishes the new source. Reject surrounding whitespace and missing
   Home Folder directories before discovery. A configured row offers confirmed Home Folder
   replacement while retaining its account identity and alias.
2. Polish Home, Account List and Details, ring and status presentation, the sidebar, and the
   menu-bar view while retaining the M12 collector lifecycle.
3. Add one Mac process-owned, bounded Global Messages history and reuse its tabbed message pane
   beneath the Main and Settings detail columns. Show curated collector and owner-flow status,
   keeping the message view independent of the selected screen.
4. Bridge `PublishOutcome` from the Mac `PublicationDriver` into that history. Show fixed,
   reason-specific copy for stopped, oversized, unavailable-secret, and inactive-relay outcomes;
   emit changes only once until publication recovers.
5. Add a Mac-only, owner-readable rotating JSONL log under separate Development and Release
   `~/Library/Logs` directories. Record typed lifecycle, publication, and diagnostic categories
   without free-form provider material; retain up to eight UTC calendar days and bound each day's
   file segments. Expose the exact directory in Diagnostics for local Codex and Claude Code runs.
6. Finish remaining Settings styling, accessibility review, affected documentation, and the
   full [validation gate](../contribution-guide.md#required-validation).
