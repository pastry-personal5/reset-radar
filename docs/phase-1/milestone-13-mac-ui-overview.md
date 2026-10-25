# P1-M13: Mac UI overview

Status: Active

Polish the functional Mac screens from P1-M12 while preserving their source, relay, and
confirmation behavior. The [implementation plan](milestone-13-mac-ui-architecture.md) starts with
the owner-facing Sources settings layout.

## Scope

- Present Codex sources in a card with Alias and Home Folder columns, an empty add row, and an
  editable new row; keep discovery, exact-change preview, confirmation, and the two-account cap.
- Present Claude Code connection actions in their own card, preserving guided setup and restore.
- Continue with Account List and Details, rings, sidebar, menu-bar status, and remaining Settings
  styling in later M13 work.

## Completion checklist

- [x] Claude Code Sources accepts the owner's existing `bash $HOME/<script>` status line only
  when the script is trusted and its output matches direct execution on the synthetic payload;
  the confirmed Settings action edits only the user `statusLine` command, preserves the prior
  command for restoration, and leaves all other shell forms untouched. Evidence: the installed
  command's two synthetic invocations matched without exposing output; all three Bash wrapper
  regressions and the complete delegated contribution-guide gate passed on 2026-10-25 (703 Mac
  tests, 0 strict SwiftLint violations, format/import checks, 59 relay tests, TypeScript, and
  Wrangler dry run).
- [x] Reject a Codex Home Folder with surrounding whitespace or a missing directory before
  discovery; offer confirmed replacement of a configured Codex home without removing its
  account, and explain that local readings continue when relay publication is inactive.
  Evidence: 18 focused Mac tests, the complete delegated contribution-guide gate (0 strict
  SwiftLint violations, Mac tests, 59 relay tests, TypeScript, Wrangler dry run), and diff hygiene
  passed on 2026-10-25.
- [x] Codex Add discovers an owner-installed executable through the login shell when it is
  outside the standard Homebrew paths, while retaining the selected Home Folder and exact
  preview. Evidence: the owner's local executable resolves in a clean login shell; the focused
  Mac discovery-context tests, complete delegated contribution-guide gate, and `git diff --check`
  passed on 2026-10-25.
- [x] The Mac writes structured, owner-only troubleshooting logs with daily and size rotation,
  retains only the current UTC day and seven prior days, and keeps Development and Release in
  separate documented `~/Library/Logs` directories. Safe lifecycle, publication, and redacted
  diagnostic events support local agent root-cause analysis; raw provider identities, usage,
  paths, and secrets never enter the log. Evidence: four focused rotation/privacy tests and the
  delegated complete contribution-guide gate on 2026-10-25 (project generation, format, strict
  lint, imports, Mac tests, 59 relay tests, TypeScript, Wrangler dry run).
- [x] The Global Messages Pane reports the typed reason when Mac publication stops or pauses
  safely, without raw relay responses, credentials, or retry spam. Evidence: focused Mac driver
  and message tests plus the delegated complete gate on 2026-10-25 (project generation, format,
  strict lint, imports, Mac tests, relay tests, TypeScript, Wrangler dry run).
- [x] Main and Settings render one shared Global Messages history at the bottom of their detail
  panes, to the right of their sidebars. The pane has a boxed tab title, a scrollable area about
  eight lines tall at 2 pt below the normal text size, and newest messages below older ones.
  Collector and owner-flow events appear without exposing secrets. Evidence: bounded-history Mac
  test and the delegated complete gate on 2026-10-25 (project generation, format, strict lint,
  imports, Mac tests, relay tests, TypeScript, Wrangler dry run).
- [x] The Sources screen shows the two cards; its Codex table has a right-aligned Add icon when a
  slot is free, accepts Alias and Home Folder in a new row, shows configured homes, and retains
  preview, confirmation, alias editing, removal, and Claude Code connection actions. Evidence:
  focused Mac alias tests and the complete delegated gate on 2026-10-25 (project generation,
  format, strict lint, imports, Mac tests, relay tests, TypeScript, Wrangler dry run).
- [x] Refine Sources Settings so the Codex card has a visually bounded Alias/Home Folder table
  with one empty Add row or an inline Alias/Home Folder draft, and the Claude Code card clearly
  offers guided connection setup and restoration. Preserve source preview and confirmation;
  verify the complete contribution-guide gate. Evidence: the delegated gate on 2026-10-25
  passed project generation, format, strict lint, imports, Mac tests, 59 relay tests, TypeScript,
  and Wrangler dry run.
- [x] The Sources card heading reads exactly **Codex**, with supporting copy that does not read
  like a second "Codex Sources" heading. Evidence: source-copy inspection and the delegated
  complete contribution-guide gate on 2026-10-25.
- [x] Review the active Mac UI implementation and keep Home's account list and selected details
  current after a source report commits or an alias changes in either Mac view. Verify the update
  paths with focused Mac tests and the contribution-guide gate. Evidence: Home report and
  bidirectional alias tests plus the delegated complete gate on 2026-10-25 (project generation,
  format, strict lint, imports, Mac tests, 59 relay tests, TypeScript, Wrangler dry run).
- [x] Mac Home Account List shows each configured account's five-hour and weekly Percentage Used
  when its default window has a presentable reading; stale readings carry a status symbol, and
  waiting or unavailable windows show no fabricated percentage. Verify both window mappings and
  missing/reset cases with focused tests and the contribution-guide gate. Evidence: three Mac
  allowance-ring tests and the delegated complete gate on 2026-10-25 (project generation,
  format, strict lint, imports, Mac tests, 59 relay tests, TypeScript, Wrangler dry run).
- [x] In a built Development app, Settings visibly shows all five sidebar sections and the shared
  Global Messages Pane below the selected section. Evidence: live macOS inspection of General,
  Sources, and About confirmed the visible sidebar, section switching, and persistent messages;
  the final contribution-guide checks passed on 2026-10-25 (Mac tests after a transient Claude
  restore retry, format, strict lint, imports, relay tests, TypeScript, and Wrangler dry run).
- [x] Claude Code setup installs or refreshes its verified helper before preview, and a blocked
  preview reports the actual helper or existing-command reason without changing Claude Code
  settings. Evidence: the focused configurator restore suite passed 10 tests, including missing
  and outdated helper recovery with unsafe settings preserved; the delegated complete
  contribution-guide gate and `git diff --check` passed on 2026-10-25.
- [x] Document the Mac Settings card rule and present each category in the Settings detail pane
  as a card in General, Sources, Relay & Pairing, Diagnostics, and About. Preserve the existing
  controls, confirmation flows, and shared Global Messages Pane. Evidence: all five sections use
  the shared Settings card and scroll layout; the delegated complete contribution-guide gate
  passed on 2026-10-25 (project generation, formatting, strict lint, imports, Mac tests, relay
  tests, TypeScript, and Wrangler dry run), as did `git diff --check`.
- [ ] Remaining M13 Mac UI scope is implemented and validated against the UX documents.
- [ ] The complete contribution-guide gate passes from the final M13 state and affected docs are
  updated.
