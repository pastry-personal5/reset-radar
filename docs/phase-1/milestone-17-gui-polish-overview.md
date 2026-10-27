# P1-M17: Experience, pairing, and synchronization polish overview

Status: Active

Polish the existing iPhone, macOS, and Watch presentation and repair the supporting alias,
pairing, and relay-management seams required for that presentation to remain truthful. Provider
acquisition, allowance semantics, pairing-package wire bytes, and platform distribution remain
unchanged; M17 adds the owner-approved encrypted reader-profile relay operation described below.
The [sequence](milestone-17-gui-polish-sequence.md) records the implementation and evidence order.

## Goal and entry

Make account rows read as one balanced horizontal unit, make Mac selection and message layout
calmer and clearer, and give Account Details a prominent, truthful executive summary. The
Watch Refresh action must visually match the adjacent Advanced action.

M17 starts after the relevant M14, M15, and M16 presentation work is available in the same
worktree. Their outstanding device, scheduling, and WatchConnectivity evidence remains with those
milestones: M17 neither reopens nor closes it. Record the starting revision, worktree state, and
affected simulator destinations before implementation. M17 may change local application and
storage and relay models where explicitly listed below, but no pairing-package wire bytes,
provider adapter, dependency, build-tool, signing, or product-distribution change is in scope.

## Owner-approved presentation behavior

- On iPhone and macOS, a compact Account Row places its alias and concise product name (`Codex`
  or `Claude Code`) on the leading side of the two rings and its Account Details action on the
  trailing side. At ordinary Dynamic Type sizes, both side groups are optically vertically
  centered against the ring group rather than top-aligned. Accessibility sizes may retain the
  existing readable reflow and logical VoiceOver order.
- The **iPhone-only** Home toolbar no longer has its bitmap Refresh action. Pull to Refresh
  remains the Home-wide refresh affordance; Account Details retains its account-scoped Refresh
  action. The iPad retains its current toolbar Refresh action because it shares the Home view but
  is not part of this request.
- On macOS, the selected Account List row uses one dedicated, appearance-aware background and
  foreground pair that is visibly selected, readable, and less harsh than the current system
  selection treatment. The implementation must avoid stacking this with a competing native List
  selection fill. It must preserve the independently meaningful state, source, and ring
  information.
- The selected row uses a subtle accent-tinted background with unchanged semantic primary and
  secondary foregrounds, plus a one-point accent border. Increased Contrast strengthens the
  border to two points. It does not apply an opaque accent foreground or reuse allowance/source
  status colors as selection meaning.
- On macOS Main, Global Messages spans the combined Account List and Account Details region
  below those panes. The Main Sidebar stays separate; Settings retains its existing
  detail-column-only Global Messages placement.
- On iPhone and macOS, show a distinct **Executive Summary** section before every window section
  only when a future standard-window reset is known. It has that visible heading, an
  accessibility-scaled, very large device-local absolute reset time, and a small reset-limit
  label. It shows no Percentage Used or state; the ordinary five-hour and weekly details below
  remain the truthful source for those values.
- The Executive Summary also shows the account's next reset as the earlier known future reset
  among the five-hour and weekly standard windows. Its localized absolute text has the form
  a device-local equivalent of `Oct 27, 2026 at 7:45 PM`, followed by `5h Reset` or `Weekly
  Reset` in small text. If only one future reset is known, use it; if neither is known, omit the
  card. Equal times use the five-hour limit as the stable tie-breaker.
- For Claude Code accounts, every visible Percentage Used surface shows a whole percentage with
  no tenths digit: `96.0%` displays as `96%`. This is display-only; retain the provider's raw
  one-decimal observation and floor non-integral values (`96.9%` displays as `96%`). Codex
  formatting remains provider-precision-driven.
- Pairing Confirmation Code changes from four grouped hexadecimal fields to exactly six decimal
  digits, including leading zeroes. It remains a deterministic display fingerprint of one exact
  encoded Pairing Package; the package, pairing wire format, confirmation flow, and activation
  checks do not change.
- A Mac alias edit is metadata-only. It must preserve the existing snapshot's collection time,
  observations, publisher identity, and every reader pairing field; its encrypted publication
  updates the displayed alias but neither requires re-pairing nor changes reader activation.
  The publication advances the relay envelope sequence normally; within the decrypted snapshot,
  only the targeted account alias changes.
- Alias feedback separates the durable local save from relay delivery. Show the delivery outcome
  both inline beside the edited alias and in session-local Global Messages. Pending or failed
  delivery must say that the alias was saved locally, retain the last valid reader cache, and
  never imply that pairing, source acquisition, or the alias validation failed.
- Inline alias feedback reads **Saved locally — publishing** during delay or backoff, becomes **Saved
  and available to devices** after success and clears when the editor closes, and keeps **Saved locally — couldn't publish**
  failure visible until a successful retry or a new edit. With no configured relay, show only
  **Saved locally** and do not present an error. Global Messages records each delivery-state
  transition for the session without duplicating unchanged retry events.
- macOS **Relay & Pairing** is a state-driven management screen. Its Relay Setup card must plainly
  distinguish Not Configured, Setup Pending, Configured, and Destroy Pending; “Configured” means
  durable local active relay state, not an invented current network-health claim. An active relay
  shows its canonical endpoint read-only; a pending relay keeps only the existing digest and
  activation workflow.
- Replace the arbitrary Mac-side `iPhone` device-name text field with a **Pair an iPhone or iPad**
  action. During pairing, the reader proposes `UIDevice.name`; when iOS supplies only a generic
  `iPhone` or `iPad`, the owner may edit that fallback on the reader before confirmation. After
  unchanged pairing activation succeeds, the reader independently reports a bounded encrypted
  profile containing only its display name and device class. Profile failure never fails or rolls
  back pairing and retries on later app executions. M17 does not depend on Apple's restricted
  user-assigned-device-name entitlement; if it is unavailable, the editable fallback remains.
- After pairing, iPhone/iPad Settings > Pairing & Sync shows **This Device** with its reported
  name. The owner may edit and resend it or choose **Use Device Name** to return to automatic
  `UIDevice.name` updates. Automatic names refresh when the app later observes a change; custom
  names remain stable until the owner changes or resets them. None of these actions re-pairs,
  rotates credentials, clears cache, or changes activation.
- This Device shows a separate profile-delivery state: **Available to Mac**, **Waiting to share**,
  or **Couldn't share — Retry**. A failed upload retains the chosen local name, queues retry for a
  later app execution, and offers a manual Retry action. It does not change pairing or snapshot
  transport status.
- The relay stores only opaque reader-profile ciphertext. A clean-break `/v2` profile write derives
  the reader ID from the activated read token, and an administration-authorized `/v2` reader list
  returns the opaque profile beside reader status. Profile encryption uses fresh randomness and
  binds the publisher ID, reader ID, and profile version as associated data. Revocation and relay
  destruction delete the corresponding profile. Existing pairing-package, preflight, activation,
  reader-cap, expiry, refresh-request, and revocation contracts remain unchanged.
- Reader profiles carry a persisted non-secret monotonic revision outside the ciphertext, bounded
  by the v1 sequence cap and also bound as associated data. The reader stores one exact encrypted
  body per revision for retry. The relay accepts a greater revision or a byte-identical retry,
  rejects a lower revision or conflicting bytes at the same revision, and therefore cannot let an
  older automatic/custom name overwrite a newer choice after network reordering.
- Version skew is non-destructive. If the configured relay does not yet support the profile
  routes, iPhone/iPad pairing still completes through v1, profile delivery reports failure and
  retries later, and Mac reconciliation falls back to the strict `/v1/readers` list with local or
  generic names. Unsupported profile routes never make readers appear revoked or erase local rows.
- For newly activated readers, the relay records its own activation timestamp and `/v2/readers`
  returns it as operational metadata. The Mac labels that timestamp **Paired**. A migrated reader
  without a relay activation timestamp retains its local observation date but labels it **First
  seen** rather than presenting it as an exact pairing time.
- Present Paired Devices as a proper list: one row per active, pending, missing-on-relay, or
  unknown relay reader, with a text-and-symbol status, relevant paired/expiry date, short reader
  identifier, and a per-row revoke action protected by confirmation. The empty state explains
  that no reader is paired and directs the owner to create a QR pairing code.
- Before profile delivery, a pending row is named **Awaiting iPhone or iPad**. After activation it
  uses the authenticated reader-reported name, or `iPhone or iPad` plus the short ID when no valid
  profile is available. The Mac never promotes pending copy into a claimed device name.
- Format the short identifier as `ID ` plus the final eight lowercase hexadecimal Reader ID
  characters. Show the device name as primary text, the identifier in smaller monospaced secondary
  text, and the status badge in a distinct appearance-aware color with both symbol and text. Color
  never carries reader identity or status by itself.
- Remove **Diagnostics** from macOS Settings navigation without removing its local diagnostic
  collection or logging capabilities. Redesign macOS **About** as a native List/Section-style
  screen: retain Reset Radar and License information, add a Feedback section with external
  GitHub repository and new-issue links plus a GitHub support action, and use the approved
  product-focused Reset Radar copy. The support action opens the repository for GitHub's native
  signed-in Star or Fork controls; it never stars or forks on the owner's behalf.
- In macOS Settings > Sources, give **Claude Code** the same structured list presentation as
  Codex rather than its current free-form stack. Harmonize Codex Alias and Home Folder inputs as
  peer labelled controls, and label its existing actions **Save Home Folder**, **Save Alias**, and
  **Remove**. The Home Folder action still follows the existing discovery, exact-preview, and
  confirmation path; no direct unreviewed replacement is introduced.
- Make every macOS Settings sidebar destination a near-full-width, consistently sized click target
  across the sidebar, while preserving its label, symbol, selected appearance, and accessibility
  state. In General, place an adjacent standard information button beside the Launch at Login
  toggle label; it presents an accessible explanatory overlay on demand. Remove the persistent
  registration-status line from that card, including unavailable/error wording.
- On Watch Home, Refresh uses the same non-prominent bordered visual treatment as Advanced while
  retaining its full-width label, tap target, and “Refresh from iPhone” accessibility label.

## In scope

- `ResetRadar/AccountRowView.swift` and `ResetRadarMac/MacMainView.swift`: row geometry,
  alignment, selection appearance, and preserved ring/details targets and accessibility.
- `ResetRadar/HomeView.swift`: remove only the compact-width iPhone Home toolbar Refresh action;
  identify iPhone by platform idiom rather than size class so every iPad window retains toolbar
  Refresh, and preserve `.refreshable` behavior with existing loading/disabled semantics.
- `ResetRadar/AccountDetailsScreen.swift`, `ResetRadarMac/MacAccountDetailsView.swift`, and
  shared `ResetRadarUI` presentation code when needed: one deterministic next-reset derivation
  and the iPhone/Mac Executive Summary card. Additional provider windows do not participate in
  this standard-window summary.
- Shared and platform-specific percentage presentation (iPhone/iPad, Mac, Watch, Watch
  complication, widgets, Live Activity, and accessibility labels): render Claude Code as a whole
  Percentage Used while retaining the raw observation precision for transport and storage.
- Live Activity content gains optional product identity for the shared formatter. Existing
  activities that decode without it retain legacy provider-precision display until reconciliation
  supplies product identity; app execution updates or dismisses them through the existing policy.
- `JSONPairingCodec`, pairing fixtures, Mac pairing presentation, and iPhone/iPad pairing
  presentation: derive and render the exact same zero-padded six-digit Pairing Confirmation Code.
- `UpdateAccountAlias`, publication classification, and paired-reader delivery: introduce a
  metadata-only update classification. Publish alias metadata promptly without presenting it as a
  source/window/account-scope transition or a fresh provider collection, and expose a distinct
  synchronization outcome inline and in Global Messages if post-save publication cannot complete.
- `RelaySetupViewModel`, `PairingViewModel`, `DevicesViewModel`, `ReconcileReaders`, the reader
  pairing flow, relay profile operations, and the Mac Relay Settings view: load durable relay
  lifecycle/endpoint state, move device naming to the reader, carry authoritative activation time
  or labelled legacy first-seen time in roster entries, and render the reader list and safe revoke
  controls from actual local/relay state.
- iPhone/iPad Pairing & Sync, `ReaderState`, and focused migration tests: persist automatic versus
  custom reader-profile naming, show and edit **This Device**, restore **Use Device Name**, and
  retry profile reporting without coupling it to snapshot ingestion or pairing health.
- `ResetRadarMac/SettingsViews.swift` and its focused tests: remove Diagnostics as a Settings
  destination, and present About in native List/Section styling with Reset Radar marketing copy,
  License, and external Feedback links plus a support action to the canonical GitHub repository
  and issue-creation URL.
- `README.md`, `docs/contribution-guide.md`, `docs/mac-installation-and-recovery.md`,
  `docs/ux-information-architecture.md`, `docs/ux-gui.md`, and `docs/architecture/mac-app.md`:
  remove maintained directions to Mac Settings > Diagnostics, retain the exact Development and
  Release log paths where useful, and distinguish removed navigation from preserved collection.
- `ResetRadarMac/SourceSettingsViews.swift`, `SourceSettingsComponents.swift`, and focused Mac
  presentation tests: give Claude Code configured/setup content the Codex list hierarchy and
  align Codex Alias/Home Folder fields plus their explicitly named save/removal actions without
  changing configuration, alias, preview, confirmation, restoration, or removal semantics.
- `ResetRadarMac/SettingsViews.swift` and focused Mac presentation tests: expand Settings sidebar
  button hit areas to the usable sidebar width and replace General's persistent Launch at Login
  registration-status text with a standard accessible information-button overlay.
- `ResetRadarMac/MacMainView.swift`: restructure Main so Global Messages is below both account
  columns, without altering the sidebar or session-local message history.
- `ResetRadarWatch/RootView.swift`: Refresh styling only; no change to Watch refresh transport,
  ordering, navigation, or Advanced actions.
- Focused unit, UI, and Mac presentation tests, visual inspection at the reference destinations,
  updated UX/architecture/phase documentation, formatting, lint, imports, and the complete gate.

## Out of scope

- A new refresh mechanism, source configuration on iPhone, alias editing behavior, changes to
  reset rules, historical/forecast/pace analysis, or a new data model.
- A pairing-package wire-format, pairing-key, registration-deadline, or activation contract change.
  The six-digit code remains an owner visual comparison, not an authenticator. The new encrypted
  reader profile is optional metadata delivered only after activation.
- Local-network discovery, a required special device-name entitlement, unapproved remote relay
  health probing, Mac-authored reader naming, or a change to reader-cap, revocation,
  relay-destruction, or clipboard rules.
- Deleting, disabling, uploading, or automatically attaching Diagnostics data; its removal is
  only from macOS Settings navigation. Feedback links open external GitHub pages and must not
  prefill or transmit account, pairing, relay, diagnostic, or other local data, or star/fork a
  repository without the owner's action in GitHub.
- A new provider configuration workflow, direct Home Folder replacement that bypasses preview and
  confirmation, altered Claude Code settings-file safeguards, alias rules, account caps, or
  removal/restore behavior.
- A change to the actual Launch at Login registration, authorization, retry, or recovery
  behavior; the General change is presentation and explanatory copy only.
- Global Messages content/retention, Settings layout, and any unfinished M14–M16 owner-run
  validation.

## Completion checklist

- [x] Record the owner-approved M17 experience scope, affected presentation and synchronization
  seams, reset-selection
  rule, non-goals, and validation boundary. Evidence: this overview and its implementation
  sequence, added on 2026-10-27; no application behavior is claimed by this planning item.
- [ ] Implement and verify M17 from revision `02ae6ed`. Starting worktree evidence on 2026-10-27:
  only the M17 planning additions in `docs/README.md`, `docs/phase-1/changelog.md`,
  `docs/phase-1/phase-1.md`, and the two new M17 plan files were present. Reference destinations
  are iPhone 17 Pro Max at ordinary and accessibility text sizes, iPad Air 11-inch (M2), Mac in
  light/dark/increased-contrast appearances, and Apple Watch Series 11 (42mm).
- [ ] iPhone and Mac Account Rows optically center their leading identity and trailing Account
  Details action against their rings at ordinary sizes, retain accessible reflow at large sizes,
  and preserve ring and Account Details activation/VoiceOver order.
- [ ] iPhone Home has no top-right bitmap Refresh action; iPhone pull to Refresh and Account
  Details account-scoped Refresh remain discoverable and behave as before, while the iPad toolbar
  Refresh action remains unchanged.
- [ ] macOS selected Account List rows use a contrast-safe appearance-aware foreground/background
  pair with the approved one-point/two-point border treatment, remain readable in light, dark,
  and increased-contrast appearances, and do not encode allowance or source state with selection
  color.
- [ ] macOS Main places Global Messages below the combined Account List and Account Details width,
  preserves the separate Main Sidebar, and does not change Settings' message-pane containment.
- [ ] iPhone and macOS Account Details render a distinct Executive Summary section before all
  window sections, with a large localized absolute reset time, small `5h Reset`/`Weekly Reset`
  label, and deterministic
  earliest-known standard reset selection for five-hour, weekly, single-known, absent, and
  equal-reset cases. The card is absent when no future standard reset exists.
- [ ] Every Claude Code Percentage Used presentation floors and displays a whole percent,
  including iPhone/iPad, Mac, Watch, Watch complication, widgets, Live Activity, and
  accessibility labels; raw stored and transmitted provider precision remains unchanged and
  Codex output is unaffected.
- [ ] Mac and iPhone/iPad show the same six-digit, zero-padded decimal Pairing Confirmation Code
  for an exact encoded package; package fixture bytes, QR/manual-paste behavior, preflight, and
  activation semantics remain unchanged.
- [ ] An alias edit while an iPhone is already paired preserves its endpoint, publisher ID,
  reader ID, minimum sequence, secrets, activation state, and committed cache; the next accepted
  envelope advances sequence normally while its decrypted snapshot changes only the targeted
  alias. A failed or delayed alias publication leaves
  the reader paired and the last valid cache visible. Local-save and relay-delivery outcomes are
  distinct, follow the approved pending/success/failure/no-relay lifecycle, and appear both beside
  the alias editor and in Global Messages.
- [ ] macOS Relay & Pairing clearly renders Not Configured, Setup Pending, Configured, and Destroy
  Pending from durable relay state, shows an active relay's canonical endpoint without claiming
  network health, and preserves the approved prepare/digest/activate and destroy flows.
- [ ] Pair an iPhone or iPad has no arbitrary Mac-side device-name input. The reader proposes its
  Apple-reported name, offers an editable device-side fallback for generic names, and reports the
  chosen name and device class in a bounded end-to-end encrypted profile after activation. Profile
  delay/failure preserves pairing and retries later; pending QR expiry, clipboard warning,
  six-digit confirmation, preflight, activation, and revocation behavior remain unchanged.
- [ ] Reader-profile writes are monotonic and idempotent: reordered or duplicated delivery cannot
  regress a newer device name, conflicting same-revision bytes are rejected, and profile revision
  never changes pairing or snapshot sequence.
- [ ] A new app against a pre-profile relay still pairs and reconciles through v1, labels profile
  reporting unavailable without changing pairing, and later reports/decrypts the profile after a
  relay upgrade without re-pairing.
- [ ] iPhone/iPad Pairing & Sync shows This Device after pairing, safely edits and resends a custom
  name, restores automatic naming with Use Device Name, refreshes changed automatic names on a
  later app execution, exposes Available/Waiting/Couldn't share with manual retry, and preserves
  credentials, activation, cached usage, and pairing throughout.
- [ ] Paired Devices is an accessible list with active, pending, missing-on-relay, unknown, and
  empty states; each new known reader includes its relay-authoritative pairing date and short
  non-secret `ID ab12cd34`-style suffix in smaller secondary text, while a migrated date is
  labelled First seen. Pending identity reads Awaiting iPhone or iPad, and a confirmed revoke
  updates the list without affecting other readers or relay configuration.
- [ ] macOS Settings no longer exposes Diagnostics while its local diagnostic capability remains
  untouched. About uses native List/Section presentation, shows the approved Reset Radar
  marketing copy, retains License information, and has Feedback links to the canonical GitHub
  repository and new-issue page without sharing local data. Its GitHub support action opens the
  repository for the owner's native Star or Fork action without automating either.
- [ ] macOS Sources presents Claude Code in the same accessible list hierarchy as Codex. Codex
  Alias and Home Folder controls have matching visual treatment, and its actions read Save Home
  Folder, Save Alias, and Remove while retaining discovery/preview/confirmation, alias, and
  destructive-removal safeguards.
- [ ] Every macOS Settings sidebar destination has a consistent near-full-sidebar-width hit
  target while retaining its selected and VoiceOver state. General shows an adjacent Launch at
  Login information button and accessible explanatory overlay; its card has no persistent
  registration-status or unavailable/error text.
- [ ] Watch Home Refresh has the same bordered treatment as Advanced while preserving its action,
  full-width hit target, and accessibility label.
- [ ] Focused presentation/UI tests and the complete contribution-guide gate pass; screenshots or
  direct simulator inspection cover iPhone, iPad, Mac light/dark selection, dynamic type, and
  Watch Home. Affected product, architecture, UX, phase, and changelog docs match the evidence.
- [ ] Apple build and test targets use reusable platform-isolated DerivedData caches; the reference
  simulator suites complete without cross-platform module-cache warnings or a stuck Xcode
  finalization process.
- [ ] The iOS, iPadOS, and watchOS deployment floors are 27.0, the binding platform and setup
  documentation agrees, and the complete contribution-guide gate passes against compatible
  simulator runtimes at or above that floor.

## Implementation evidence

On 2026-10-27 the focused Swift package suite passed 280 tests in 38 suites, the Mac suite passed
51 tests in 10 suites, the relay passed 29 Workers Vitest tests plus 31 Node tests and strict
TypeScript checks, and a standalone Watch build passed. The complete gate passed project
generation, swift-format, strict SwiftLint, import-boundary enforcement, and the arm64-only Mac
architecture check. A clean iPhone/iPad build then compiled the app and began passing tests on
both reference simulator destinations, but Xcode corrupted its result bundle after SDK-record
`invalidDigitCount` warnings and returned exit 75 without reporting a failing test. Reference-view
capture and owner-run physical-device evidence therefore remain unchecked.

A later validation hardening pass isolated reusable DerivedData by platform, declared the app test
targets' directly imported local package products, and removed four Swift compiler warnings. The
final retained state passed generation, format, strict lint, imports, relay CI, Mac and Watch test
actions, the arm64-only Mac architecture check, and a clean iPhone build-for-testing. Fresh caches,
single-destination actions, separate build/test actions, and a targeted CoreSimulator restart all
reproduced Xcode 27.1 stalling before XCTest launch while finalizing the test log and emitting
`invalidDigitCount(94232)`. The installed Xcode 26.1.1 fails the current Swift source and does not
support the Watch deployment floor, so it is not a valid fallback. The simulator-test and visual
inspection checklist items remain unchecked.

The 2026-10-27 deployment-floor update generated successfully with iOS, iPadOS, and watchOS 27.0
settings. Format, strict lint, imports, the relay suites, and the watchOS 27.0 suite passed. The
iOS gate cannot start because the approved iPhone 17 Pro Max and iPad Air 11-inch (M2) simulator
types exist only on iOS 26.1 on this Mac and are rejected by the new floor; compatible replacement
models require an owner decision. The Mac suite also retained one unrelated existing failure in
`ClaudeCodeConfiguratorRestoreTests.interruptedCompletionRefusesAMissingComposeArtifact()`.
