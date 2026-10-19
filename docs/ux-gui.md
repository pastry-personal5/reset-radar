# UX GUI

Status: Active

This document defines the current interface and records owner-approved GUI behavior separately under a planned heading. Product scope is in [product-behavior.md](product-behavior.md); component vocabulary is in [ux-terms.md](ux-terms.md).

## First iPhone screen

The iOS app shows a five-item **Main Toolbar** along the bottom edge. Every toolbar item has a bitmap icon above its label. The fixed items currently are:

- first: **Home**;
- second: **Benefits**, with a gem bitmap icon;
- third: **Community**, with a community bitmap icon;
- fourth: **Insight**, with an insight bitmap icon; and
- fifth: **All**, with a three-horizontal-bars bitmap icon.

Selecting Home shows a two-by-two **Allowance Grid** of circular **Allowance Rings**:

| | Five-hour window | Weekly window |
|---|---|---|
| **Codex** | Top left | Top right |
| **Claude Code** | Bottom left | Bottom right |

Each ring presents percentage used for its assigned allowance window as a circular infographic. The ring fills from 0% toward 100%. The interface must preserve the logical placement above even if accessibility adaptation changes physical sizing or flow.

Each grid cell identifies its product and window, places the numeric percentage used inside the ring, and provides a compact reset countdown plus freshness state. Selecting a ring opens the product's Usage Details with that window initially emphasized.

Before pairing or when required setup is incomplete, the same grid stays visible and affected rings use an explicit unavailable state rather than fabricated values. A prominent **Setup Banner** explains the current blocker and offers the next setup or pairing action. It does not replace the grid with mandatory onboarding.

Selecting Benefits, Community, Insight, or All shows that destination's intentionally empty screen for now.

## First Mac screen

The first Mac screen uses the same two-by-two **Allowance Grid**, circular **Allowance Rings**, and cell placement as the first iPhone screen. Platform-appropriate physical sizing may differ, but the represented information and logical arrangement do not.

Before source, relay, or pairing setup is complete, the Mac grid remains visible with explicit unavailable states and a Setup Banner offering the next action.

## Usage Details

Codex and Claude Code each have one Usage Details view. Both windows remain visible; the window selected from the Allowance Grid receives initial visual emphasis.

For each window, show:

- an Allowance Ring and exact percentage used;
- the window label;
- a relative reset countdown and the absolute reset date and time in the OS's current local time zone;
- the observation time and freshness or availability state; and
- an explicit explanation when data is stale, unavailable, incompatible, signed out, offline, or awaiting a post-reset refresh.

The provenance and synchronization area shows the acquisition source, the authoritative Mac's publication status, the receiving device's last successful synchronization time, and source compatibility status. Technical versions and error detail remain behind a diagnostics disclosure instead of competing with primary usage information.

The primary action requests the freshest data available to that platform. On Mac it refreshes the first-party source subject to adapter backoff; on iPhone it refreshes from the encrypted relay and does not directly contact Codex or Claude Code. The view never presents history, forecasts, pace analysis, or threshold controls.

