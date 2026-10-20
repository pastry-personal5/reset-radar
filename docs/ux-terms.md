# UX terms

Status: Active

This is the canonical vocabulary for visible user interface components, and their code-facing names. Use the exact component terms in UI text and accessibility-visible names; use the mapped lower-camel or snake-case names in implementation identifiers when a component is represented there.

## Canonical product and source terms

The interface distinguishes a tracked product from the mechanism that supplied an observation.

| Concept | Visible term | Code-facing name | Usage |
|---|---|---|---|
| OpenAI coding product | **Codex** | `codex` | Use for the tracked product and its allowance windows. Do not use **Codex CLI** as the product name. |
| Anthropic coding product | **Claude Code** | `claudeCode` | Use for the tracked product and its allowance windows. Do not shorten this to **Claude**, which would imply broader consumer-product coverage. |
| Codex acquisition source | **Codex app-server** | `codexAppServer` | Use only in source, provenance, compatibility, and diagnostics text. |
| Claude Code acquisition source | **Claude Code status line** | `claudeCodeStatusLine` | Use only in source, provenance, freshness, compatibility, and diagnostics text. |

## Canonical components

| Component | Visible term | Code-facing name | Usage |
|---|---|---|---|
| Four-cell primary usage summary | **Allowance Grid** | `allowanceGrid` | The logical two-column, two-row arrangement on iPhone, Mac, and Apple Watch Home. |
| Circular window infographic | **Allowance Ring** | `allowanceRing` | Shows percentage used for exactly one product allowance window, filling from 0% toward 100%. |
| Product-scoped usage destination | **Usage Details** | `usageDetails` | Shows both tracked windows, reset timing, provenance, freshness, and availability for either Codex or Claude Code. |
| Detailed presentation of one window | **Window Details** | `windowDetails` | A section inside Usage Details for one allowance window. |
| Contextual setup prompt | **Setup Banner** | `setupBanner` | Keeps the Allowance Grid visible while explaining missing setup and offering the next pairing or collector action. |
| Five-item iOS navigation | **Main Toolbar** | `mainToolbar` | Appears at the bottom of the iPhone app and uses the system's adaptive tab bar or sidebar presentation on iPad. Each item has a bitmap icon and a text label. |
| First Main Toolbar destination | **Home** | `home` | Contains the Allowance Grid. |
| Second Main Toolbar destination | **Benefits** | `benefits` | Uses a gem bitmap icon and currently contains no content. |
| Third Main Toolbar destination | **Community** | `community` | Uses a community bitmap icon and currently contains no content. |
| Fourth Main Toolbar destination | **Insight** | `insight` | Uses an insight bitmap icon and currently contains no content. |
| Fifth Main Toolbar destination | **All** | `all` | Uses a three-horizontal-bars bitmap icon and currently contains no content. |
| macOS top-level navigation | **Main Sidebar** | `mainSidebar` | Contains Home, Benefits, Community, Insight, and All in the same order as the iOS Main Toolbar. |
| Application configuration destination | **Settings** | `settings` | Opens from the top-right Settings button on iOS All and from the standard macOS Settings scene. |
| Watch-face presentation | **Allowance Complication** | `allowanceComplication` | Shows one user-selected allowance window from the Watch cache. |
| User-started short-window activity | **Reset Live Activity** | `resetLiveActivity` | Shows one eligible five-hour window on iPhone until reset or invalidation. |

Toolbar icons are original, neutral, monochrome template bitmaps that accept platform tint. The icon metaphors, in toolbar order, are house, faceted gem, three-person group, lightbulb, and three horizontal bars.
