# P1-M17: Experience, pairing, and synchronization polish sequence

Status: Active

Implement [the M17 overview](milestone-17-gui-polish-overview.md) as coordinated presentation,
local application-state, and storage work. This sequence preserves the approved pairing wire,
reader activation, allowance, provider-acquisition, and Watch contracts.

## 1. Establish the presentation baseline

Inspect the current `AccountRowView`, `MacAccountRow`, iPhone and Mac Account Details cards,
`MacMainView`, and Watch Home before changing layout. Capture reference simulator screenshots at
ordinary and accessibility text sizes, and Mac light/dark/increased-contrast appearances. Record
the initial worktree and run focused existing presentation tests. Do not hand-edit the generated
Xcode project.

## 2. Build the shared Executive Summary derivation first

Add a pure, tested presentation derivation near the existing allowance-display vocabulary. It must
consume the same uniquely resolved standard windows as `WindowSection` rather than independently
matching raw provider limits. Given those five-hour and weekly windows and `now`, choose the
earliest reset strictly after `now`; choose five-hour if both instants match. Format the selected
reset as device-local absolute date/time plus the fixed short `5h Reset` or `Weekly Reset` label.
Handle a missing or ambiguous standard window and no future reset explicitly by returning no
summary. The summary is reset-only; it does not duplicate Percentage Used or state.

Render a distinct section before every window section on iPhone and macOS when the derivation
returns a future reset. Give it the visible heading **Executive Summary**, a stable accessibility
identifier, a large Dynamic-Type-aware primary absolute time, and the small limit label. Keep the
individual five-hour and weekly sections, their exact reset times, and their actions unchanged.

## 3. Normalize Claude Code display precision

Centralize Percentage Used formatting at the presentation boundary so every surface follows one
rule. When the account product is Claude Code, floor to the lower whole percentage (`96.0%`
becomes `96%` and `96.9%` becomes `96%`); for Codex, keep the current provider-precision behavior.
Pass product identity through the shared display model or its formatter instead of mutating
`RawObservation.fractionDigits`, snapshots, relay payloads, reminder payloads, or persisted data.
Replace the independent Mac and Live Activity formatting paths with that policy, and confirm the
Watch app, Watch complication, iOS widgets, and accessibility labels use it too.

Add optional product identity to Live Activity content so already-running activities remain
decodable across the update. A legacy activity with no product retains its existing
provider-precision presentation until the normal reconciliation path updates it with product
identity or dismisses it; never guess Claude Code from `fractionDigits`.

## 4. Shorten the Pairing Confirmation Code

Keep the confirmation-code input as the exact canonical base64url Pairing Package text. Hash it
with the existing SHA-256 function, interpret its first four digest bytes as an unsigned
big-endian integer, reduce that value modulo `1_000_000`, and render the result as six ASCII
decimal digits with leading zero padding and no separators. This changes only the human-comparison
display from 64 bits of hexadecimal text to a six-digit decimal value; it does not change the
package encoding, the digest of package bytes retained for clipboard cleanup, any token/key,
preflight, or relay activation.

Update the transport fixture's expected display code and codec tests. Add deterministic vectors,
including a leading-zero result, and prove Mac QR creation plus iPhone/iPad QR and manual-paste
preview show the same code. Preserve the existing rule that the code is neither logged nor entered
as a credential; owner comparison remains required before any local save or activation.

## 5. Make alias propagation pairing-safe

The current alias path rebuilds the local `UsageSnapshot` at the edit clock and reports a generic
`.transition`, then sends it through the ordinary publication driver. That conflates metadata
with source/window/account-scope change and lacks a paired-reader regression seam. Replace it with
an explicit metadata-only change classification: retain the prior snapshot's `generatedAt`,
observations, sources, windows, diagnostics, publisher identity, and manual-refresh results;
replace only the catalog metadata; and publish it promptly as an alias synchronization update.

Do not alter `ReaderPairing`, Keychain values, reader registration, pairing package fields, or
relay wire bytes. A publication failure after the durable catalog/local-snapshot commit must leave
the phone paired and its last valid cache intact. Surface that as alias synchronization pending or
failed rather than implying a broken pairing; retry only through the established publication
policy. Report the local save separately from post-save relay delivery both inline beside the
edited alias and through session-local Global Messages. Neither surface may describe delivery
failure as an invalid alias, failed local save, source failure, or lost pairing.

Use an explicit alias-delivery state rather than the general validation-message string. During
delay or backoff keep **Saved locally — publishing** inline. On publication success show **Saved and
available to devices**, then clear it when the editor closes. Keep **Saved locally — couldn't publish** visible until a successful
retry or a new edit. If no relay is configured, show **Saved locally** without an error. Append
state transitions to Global Messages, but suppress duplicate messages for unchanged retries.

The successful encrypted publication uses the next normal relay sequence and therefore is not
byte-identical to its predecessor. After decryption, assert that `generatedAt`, observations,
sources, windows, diagnostics, manual-refresh results, publisher identity, and every non-target
account remain identical; only the targeted alias differs.

The root-cause review records that the available redacted Mac log has successful publications and
no reader-registration or relay-rejection event after the reported alias changes. It therefore
does not prove the alias edit revoked pairing. The repair prevents the observed coupling and adds
the missing evidence instead of treating temporal proximity as proof of a credential failure.

## 6. Clean up macOS Relay & Pairing

Load `PublisherState` whenever Relay & Pairing appears and after prepare, activation, destruction,
or retry. Model the card as four durable states: **Not Configured** (explain that iPhone/iPad
pairing is unavailable and offer relay setup), **Setup Pending** (show canonical origin, the two
existing deployment digests, and Activate), **Configured** (show a checkmark, read-only canonical
origin, and that the relay is configured), and **Destroy Pending** (show that publication remains
stopped and offer the existing destruction retry). Never label durable local state as online,
connected, or reachable without a separate successful remote operation.

Replace the Mac `Device name` text field with a single **Pair an iPhone or iPad** action. Retain
the existing five-minute deadline, activation polling, six-digit code, Manual Copy warning, and
conditional clipboard cleanup. On the reader, propose `UIDevice.name`; if it is the generic
`iPhone` or `iPad`, let the owner edit the fallback before confirming. Validate the exact chosen
text as visible Unicode within a 64-byte UTF-8 limit. Do not require or add Apple's restricted
user-assigned-device-name entitlement in M17.

Keep `/v1/readers/activate` empty-body and idempotent. After activation, best-effort upload a
canonical, bounded reader profile containing only the chosen display name and device class through
a new authenticated `/v2/reader-profile` operation. Encrypt it with fresh randomness under the
existing content key and bind the publisher ID, reader ID, and profile version as associated data.
The relay derives reader identity from the activated token and stores only opaque ciphertext. Add
an administration-authorized `/v2/readers` list for profile ciphertext and status while preserving
the strict `/v1/readers` response. Retry an absent or failed profile on later app execution without
changing pairing state. Revoke and destroy remove profile ciphertext with the reader row.

Persist a profile revision from `1` through `2^53 - 1`, separate from snapshot sequence. Bind that
revision into the profile associated data and expose only the revision plus encrypted body to the
relay. Generate and durably retain one exact encrypted body for each pending revision so retries
are byte-identical. Accept a greater revision and an identical same-revision retry; reject lower
revisions and conflicting same-revision bytes without mutation. A later edit supersedes the local
pending body so a delayed task cannot retry an older revision after the newer choice commits.

Treat an unsupported `/v2` profile route as version skew, not reader failure. Pair and activate
through the unchanged v1 path, retain the pending profile for retry, and have Mac reconciliation
fall back to `/v1/readers` plus local/generic metadata. After the relay upgrades, the next app
execution reports the profile and the next Mac reconciliation adopts it without re-pairing.

When activation first succeeds, have the relay record its own timestamp. Return it from
`/v2/readers` as bounded operational metadata and persist it on Mac reconciliation. Render that
value as **Paired**. Preserve an existing local `pairedAt` when migrating a reader whose relay row
has no activation timestamp, but render it as **First seen**. Never substitute a reader clock for
the relay timestamp or silently relabel a first-observed time as exact activation.

Persist a reader-local profile naming mode. A non-generic `UIDevice.name` starts in automatic mode;
a device-side edit starts custom mode. In Pairing & Sync, show **This Device**, allow a validated
custom edit and resend, and provide **Use Device Name** to return to automatic mode. On later app
execution, automatic mode reports a changed Apple name while custom mode remains untouched. A
storage migration supplies a generic automatic fallback for an already-paired reader without
changing its pairing, cache, ETag, sequence, or Keychain secrets.

Persist profile-delivery status independently of snapshot transport. Pairing & Sync renders
**Available to Mac**, **Waiting to share**, or **Couldn't share — Retry** under This Device.
Failure keeps the chosen name, schedules the established next-app-execution retry, and exposes a
manual Retry action. Success clears only the pending profile marker; no profile outcome may mutate
pairing, activation, cached usage, ETag, or snapshot transport status.

Extend the roster read model to carry relay activation time or a labelled legacy first-seen time,
the decrypted reader-reported name and device class when available, and a display-safe short
reader-ID suffix; none is a pairing credential.

Render Paired Devices below the pairing card as a macOS list with an empty state and rows grouped
by status: active first, then pending, then missing-on-relay and unknown readers. Each row shows
**Awaiting iPhone or iPad** while pending, then the reader-reported name or an `iPhone or iPad`
fallback after activation, plus a status badge with text and symbol,
paired date for activated known readers or expiry for pending offers, and `ID ` plus the final
eight lowercase hexadecimal Reader ID characters. Render the name as primary text, that ID in
smaller monospaced secondary text, and the badge in a distinct appearance-aware status color; keep
the text and symbol so color is never the sole cue. Put **Revoke** on the trailing edge and
require a row-specific confirmation naming the visible reader before calling the existing
revocation use case. A missing-on-relay row explains that it was removed elsewhere; preserve the
existing reconciliation semantics rather than fabricating a reader or silently deleting local
history.

## 7. Rebalance Home account rows and refresh affordances

At normal text sizes, give the leading identity and trailing Account Details control the same
vertical alignment anchor as the rings on iPhone and Mac. Preserve the existing accessibility
layout branch and the alias → five-hour → weekly → Account Details accessibility sequence.
Retain all ring hit regions and avoid changing a row's routing semantics.

Remove the Home toolbar bitmap Refresh action only on iPhone. Use the platform idiom rather than
horizontal size class for that decision so iPad retains the action in full screen, Split View, and
other compact-width windows. Verify the existing iPhone scroll-view pull to refresh still calls the
approved home-wide path and that Account Details still offers its account-specific Refresh. Do not
substitute a new button or alter source-specific refresh rules.

## 8. Refine Mac selection and pane containment

Pass explicit selection state into the Mac row and use one custom selection treatment rather than
letting an opaque native List highlight compete with a second material. Choose semantic SwiftUI or
AppKit appearance-aware colors: a subtle accent-tinted background, unchanged semantic primary and
secondary foregrounds, a one-point accent border, and a two-point border when Increased Contrast
is enabled. Suppress the native List selection fill and avoid an opaque accent foreground. Keep
source state, stale state, and selection distinguishable without color alone.

Restructure only the Main Home container so the account list and detail pane share an upper row,
then put Global Messages below that row at their combined width. Keep the Main Sidebar outside
that region and retain the current message history, follow-latest behavior, and Settings layout.
Verify narrow-window clipping/minimum widths do not hide account controls or messages.

## 9. Match Watch action treatment

Apply the Advanced action's bordered style to the full-width Refresh label without changing its
task, disabled/reachability behavior, position, or accessibility identifier/label.

## 10. Simplify macOS Settings and About

Remove **Diagnostics** from the macOS Settings destination list and routing only. Keep its
existing local diagnostic collection, logging, and internal test seams intact: this change does
not delete data, turn off diagnostics, or make any information available to Feedback.

Update every maintained user, contributor, UX, and Mac architecture document that currently
directs someone to Settings > Diagnostics. Preserve the exact Development and Release log-folder
paths where they remain useful, and state that collection/logging still exists without a visible
Settings destination. Do not rewrite archived records.

Refactor **About** into native macOS `List`/`Section` presentation. Its **Reset Radar** card
replaces the current descriptive line with the approved marketing copy:

> Know your Codex and Claude Code allowance usage at a glance. Reset Radar keeps Percentage Used
> and reset times clear across your Mac, iPhone, iPad, and Apple Watch.

Retain License information in the same List-style experience. Add a **Feedback** section with two
clearly labelled external-link rows: **GitHub** opens
`https://github.com/pastry-personal5/reset-radar`; **Report an Issue** opens
`https://github.com/pastry-personal5/reset-radar/issues/new`. Use the platform external-link
affordance and the injected URL-opening seam; do not prefill an issue or collect/attach aliases,
usage, diagnostics, relay endpoints, pairing information, logs, or any other local data.

Add a compact **Support Reset Radar** button-style row in that List. It opens the same canonical
repository URL, where GitHub can present its own signed-in **Star** or **Fork** controls when
available. The app must not call a GitHub API, attempt an authenticated web mutation, assume that
either control is available, or report a Star/Fork result after handing off to the browser.

Add focused Mac tests that prove Diagnostics is absent from Settings navigation while the remaining
destinations still route, that the approved text and License remain visible, and that both Feedback
rows plus Support Reset Radar request precisely their canonical URLs. Inspect the List hierarchy
and button affordance in light and dark appearance and at increased text size before the complete
gate.

## 11. Unify macOS Sources provider settings

Make the **Claude Code** area of Sources a structured list using the same list hierarchy, row
insets, dividers, field/action alignment, and accessibility grouping as Codex. Retain the existing
Claude Code explanatory copy, setup and safe-restore controls, source-option preview, exact-change
confirmation, and configured account behavior; relocate them into clear list sections and rows
rather than a free-form vertical stack. The configured Claude Code row must continue to expose its
Alias editor, **Save Alias**, and confirmed destructive **Remove** action.

Within the Codex list, make Alias and Home Folder peer labelled editable controls with matching
field chrome, widths, baseline alignment, and error/focus treatment. Replace the current **Change
Home** label with **Save Home Folder**, retain **Save Alias**, and retain destructive **Remove**.
**Save Home Folder** starts the existing replacement/discovery flow and cannot write a folder
directly: whitespace/absolute-directory validation, source discovery, exact preview, and owner
confirmation still govern the replacement. Do not rename the preview-confirmation action in a way
that suggests it completed before confirmation.

Keep current account limits, configured account identity, alias validation, stale/pending preview
cancellation, Claude Code `~/.claude/settings.json` safeguards, restoration, and removal copy.
Do not let a list redraw lose unsaved input, make Restore destructive without its existing
confirmation, or turn a remove button into immediate deletion.

Add focused Mac presentation/UI tests for the Claude Code list sections and their existing actions,
Codex input-field parity, all three exact Codex action labels, field focus/validation behavior, and
the unchanged Home Folder preview/confirmation and removal/restore safeguards. Inspect empty,
configured, draft/replacement, and long-path/large-text states in light and dark appearance before
the complete gate.

## 12. Improve macOS Settings controls

Make each Settings sidebar destination button's labelled row occupy the same near-full usable
width of the sidebar, with consistent horizontal inset and height. The complete row remains the
click target, not merely the label or symbol. Preserve the existing section order, symbols,
selection indication, keyboard focus, and VoiceOver selected trait; do not change routing or add
new destinations.

In General's **Launch at login** card, place a standard circular information (`i`) control directly
beside the toggle's checkbox-and-label group. Selecting it presents a transient, accessible
popover/overlay that explains that Reset Radar can open automatically when the user signs in so
collection and reset monitoring can continue, and that the toggle controls this feature. The
overlay must have a clear dismiss action and must not claim activation state beyond the toggle's
actual state. Remove the persistent `Registration` row entirely, including `Registration
unavailable` and every other registration-status/error string; recoverability stays in its existing
Signing and Keychain card.

Add focused Mac tests for whole-row sidebar activation, consistent hit-target geometry, selected
accessibility state, information-button label/hint, overlay presentation and dismissal, and the
absence of Registration text from the Launch at Login card. Inspect keyboard focus, light/dark,
increased contrast, and large-text layouts before the complete gate.

## 13. Validate the integrated milestone

Add or update focused tests for every Executive Summary selection case, the stable summary
identifier, preserved action routes, iPhone-versus-iPad Refresh visibility, and accessibility
labels. Test Claude Code `96.0`, positive non-integral flooring, boundary values, and unchanged Codex formatting
across every shared and independent formatter. Test the six-digit code's exact digits,
leading-zero padding, fixture update, and unchanged pairing decode/preflight/activation behavior.

Add an end-to-end synthetic paired-reader regression: pair and activate a reader, commit an alias
edit on the Mac, publish and ingest its next envelope, then assert identical pairing endpoint,
publisher ID, reader ID, minimum sequence, Keychain secrets, and activation state alongside the
new alias. Cover alias publication success, delay/backoff, and terminal publication failure; none
may clear, revoke, replace, or falsely mark the reader unpaired. Add a concurrent alias-edit and
new-pairing case to prove the package's sequence floor and successful activation remain valid.

Add focused Mac presentation and view-model tests for every relay lifecycle card state, endpoint
visibility, removal of the arbitrary device-name control, pending offer expiry, roster ordering,
paired date and short-ID display, unknown/missing reader copy, revoke confirmation, failed list
refresh, and destroy-pending retry. Confirm existing QR/manual-copy, reader-cap, revocation, and
relay-destruction tests remain unchanged.

Cover relay-assigned activation time, idempotent activation retaining its original time, v2 list
encoding, legacy rows without that time, Paired versus First seen copy, and revocation/destruction
cleanup in the focused relay and roster tests.

Add focused reader-profile tests for automatic and generic names, device-side validation, custom
edit, Use Device Name reset, app-execution refresh, encrypted round-trip, ciphertext-only relay
storage, missing/undecryptable profile fallback, Reported/Waiting/Couldn't-report presentation,
manual and automatic retry, legacy reader migration, and the invariant that profile success or
failure cannot alter pairing or cached usage.

Test greater, lower, identical retry, conflicting same-revision, maximum revision, reordered
completion, and locally superseded pending-profile cases. Profile revision must remain independent
from snapshot sequence and pairing minimum sequence.

Add mixed-version tests for new reader/old relay, new Mac/old relay, old reader/new relay, profile
delivery after relay upgrade, and v2 failure with successful v1 reconciliation. None may revoke a
reader, clear local roster history, or require re-pairing.

After every focused suite passes, delegate the complete contribution-guide gate to the test
runner. Then inspect the listed iPhone, iPad, Mac, and Watch platform states and record concise
evidence in the overview before checking any behavior or milestone-completion item.
