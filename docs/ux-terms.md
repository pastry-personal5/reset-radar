# UX terms

Status: Active

Canonical vocabulary for interface copy, accessibility text, design discussion, and code. Use visible terms in user-facing text and the mapped lower-camel names in implementation; do not expose code-facing names to users.

## Canonical product and source terms

The interface distinguishes a tracked product from the mechanism that supplied an observation.

| Concept | Visible term | Code-facing name | Usage |
|---|---|---|---|
| OpenAI coding product | **Codex** | `codex` | Use for the tracked product and its allowance windows. Do not use **Codex CLI** as the product name. |
| Anthropic coding product | **Claude Code** | `claudeCode` | Use for the tracked product and its allowance windows. Do not shorten this to **Claude**, which would imply broader consumer-product coverage. |
| Codex acquisition source | **Codex app-server** | `codexAppServer` | Use only in source, provenance, compatibility, and diagnostics text. |
| Claude Code acquisition source | **Claude Code status line** | `claudeCodeStatusLine` | Use only in source, provenance, freshness, compatibility, and diagnostics text. |

## Canonical usage concepts

| Concept | Visible term | Code-facing name | Usage |
|---|---|---|---|
| One provider-defined limit and reset cycle | **Allowance Window** | `allowanceWindow` | Use **window** after the first clear reference. Do not call it a quota, bucket, plan, or period in interface text. |
| Provider-reported consumption | **Percentage Used** | `usedPercent` | Runs from 0% toward 100%. Never relabel or invert it as percentage remaining. |
| Latest timestamped provider value | **Usage Reading** | `usageObservation` | The percentage and its observation time. Use **reading** in interface text and **observation** in domain or diagnostic text. |
| Provider-reported end of a window | **Reset Time** | `resetsAt` | Show a relative countdown with the absolute date and time in the device's current time zone where space permits. |
| Time the provider value was observed | **Last Updated** | `observedAt` | Describes the Usage Reading, not relay or Watch delivery. Prefer “Updated 4 min ago” in compact surfaces. |
| Time this device last accepted a snapshot | **Last Synced** | `lastSuccessfulSyncAt` | Describes device delivery, not source freshness. Never substitute it for Last Updated. |
| One locally configured provider identity | **Account** | `account` | A Reset Radar row and navigation scope. It never exposes the provider account identifier. |
| Optional Mac-authored name for an account | **Account Alias** | `accountAlias` | When absent, the displayed alias is the stable **Account #N** default. A custom alias must contain a visible letter, number, punctuation, or symbol and uses the safe Unicode profile in Domain. It is editable only on Mac for now and is delivered inside the encrypted snapshot. “Displayed alias” elsewhere means this custom value or its default. |

## Canonical data states

These labels describe a Usage Reading. Transport and source explanations may add a reason, but do not replace the state or imply that old data is current.

| State | Visible term | Code-facing name | Usage |
|---|---|---|---|
| Valid reading inside its source-specific freshness window | **Current** | `current` | Show the Percentage Used and Last Updated time. |
| Last valid reading is too old or its source is not reporting | **Stale** | `stale` | Keep the last value with a stale treatment and a concise reason. |
| No presentable reading exists | **Unavailable** | `unavailable` | Show no percentage. Explain the next useful action when one exists. Never render this as 0%. |
| The reported reset passed and no new reading confirms the next cycle | **Waiting for Update** | `resetAwaitingRefresh` | Show no percentage and do not fabricate replenishment. |

## Canonical actions and device terms

| Concept | Visible term | Code-facing name | Usage |
|---|---|---|---|
| Ask for the freshest data available to the platform | **Refresh** | `refresh` | Account Details targets that account. Home targets all configured Codex accounts and also reads the relay for Claude Code. A Claude Code account Refresh cannot create a provider response. |
| Move an already produced snapshot to a device | **Sync** | `sync` | Reserve for relay or Watch delivery. Refresh may cause a sync, but the terms are not interchangeable. |
| Mac that reads sources and publishes snapshots | **Collector Mac** | `publisher` | Use in owner-facing setup and status text. **Authoritative Mac** remains the architecture term for its single-writer role. |
| Connect an iPhone or iPad to the Collector Mac | **Pair Mac** | `pairMac` | Names the setup action. Pairing transfers Reset Radar secrets, never provider credentials. |
| Remove the Mac relationship and local phone or tablet data | **Forget Mac** | `forgetMac` | Preserve pending Watch-erasure language until a matching Watch receipt arrives. |
| Clear the Watch cache and stop later delivery | **Erase Watch Data** | `eraseWatchData` | Owner-confirmed Watch action. Do not claim that a previously rendered complication frame was erased immediately. |
| Allow a Watch erased locally to receive data again | **Reset Watch Pairing** | `resetWatchPairing` | Separate from Erase Watch Data and from pairing an iPhone or iPad to the Collector Mac. |

## Canonical components

| Component | Visible term | Code-facing name | Usage |
|---|---|---|---|
| Primary account summary | **Account List** | `accountList` | The vertically scrolling Home collection on iPhone and the leading side of iPad and Mac split layouts. |
| One account's compact Home summary | **Account Row** | `accountRow` | Shows a small top-leading alias label, product, two standard Allowance Rings, and the Account Details action. The alias label is inline-editable on Mac only. |
| Watch-only account color cue | **Account Palette** | `accountPalette` | A stable pastel family derived from the global account number: #1 lavender, #2 mint, and #3 peach. Each has appearance-aware surface and contrast-compliant foreground variants. It distinguishes Watch rows without exposing an alias and never replaces status symbols or accessibility identity. |
| Circular window infographic | **Allowance Ring** | `allowanceRing` | Shows percentage used for exactly one product allowance window, filling from 0% toward 100%. |
| Account-scoped usage destination | **Account Details** | `accountDetails` | Shows every valid window, reset timing, provenance, freshness, and availability for one configured account. |
| Detailed presentation of one window | **Window Details** | `windowDetails` | A section inside Account Details for one allowance window. |
| Contextual setup prompt | **Setup Banner** | `setupBanner` | Shares Home with the Account List while explaining missing setup and offering the next pairing or collector action. |
| Five-item iOS navigation | **Main Toolbar** | `mainToolbar` | Appears at the bottom of the iPhone app and uses the system's adaptive tab bar or sidebar presentation on iPad. Each item has a bitmap icon and a text label. |
| First Main Toolbar destination | **Home** | `home` | Contains the Account List. |
| Second Main Toolbar destination | **Benefits** | `benefits` | Uses a gem bitmap icon and currently contains no content. |
| Third Main Toolbar destination | **Community** | `community` | Uses a community bitmap icon and currently contains no content. |
| Fourth Main Toolbar destination | **Insight** | `insight` | Uses an insight bitmap icon and currently contains no content. |
| Fifth Main Toolbar destination | **All** | `all` | Uses a three-horizontal-bars bitmap icon and currently contains no content. |
| macOS top-level navigation | **Main Sidebar** | `mainSidebar` | Contains Home, Benefits, Community, Insight, and All in the same order as the iOS Main Toolbar. |
| Application configuration destination | **Settings** | `settings` | Opens from the top-right Settings button on iOS All and from the standard macOS Settings scene. |
| Watch-face presentation | **Allowance Complication** | `allowanceComplication` | Shows one user-selected account window from the Watch cache. |
| User-started short-window activity | **Reset Live Activity** | `resetLiveActivity` | Shows one eligible five-hour account window on iPhone until reset, invalidation, or account removal. |

Toolbar icons are original, neutral, monochrome template bitmaps that accept platform tint. The icon metaphors, in toolbar order, are house, faceted gem, three-person group, lightbulb, and three horizontal bars.
