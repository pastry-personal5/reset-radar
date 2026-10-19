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
| Four-cell primary usage summary | **Allowance Grid** | `allowanceGrid` | The logical two-column, two-row arrangement on the first iPhone and Mac screens. |
| Circular window infographic | **Allowance Ring** | `allowanceRing` | Shows percentage used for exactly one product allowance window, filling from 0% toward 100%. |
| Product-scoped usage destination | **Usage Details** | `usageDetails` | Shows both tracked windows, reset timing, provenance, freshness, and availability for either Codex or Claude Code. |
| Detailed presentation of one window | **Window Details** | `windowDetails` | A section inside Usage Details for one allowance window. |
| Contextual setup prompt | **Setup Banner** | `setupBanner` | Keeps the Allowance Grid visible while explaining missing setup and offering the next pairing or collector action. |
| Five-item iOS bottom navigation | **Main Toolbar** | `mainToolbar` | Appears at the bottom of the iOS app. Each item has a bitmap icon above its text label. |
| First Main Toolbar destination | **Home** | `home` | Contains the Allowance Grid. |
| Second Main Toolbar destination | **Benefits** | `benefits` | Uses a gem bitmap icon and currently contains no content. |
| Third Main Toolbar destination | **Community** | `community` | Uses a community bitmap icon and currently contains no content. |
| Fourth Main Toolbar destination | **Insight** | `insight` | Uses an insight bitmap icon and currently contains no content. |
| Fifth Main Toolbar destination | **All** | `all` | Uses a three-horizontal-bars bitmap icon and currently contains no content. |

Other component terms remain to be defined during the interface interview.
