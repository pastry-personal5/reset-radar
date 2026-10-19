# Phase 1 owner decisions

Status: Active

This record captures the owner's 2026-10-19 decisions after reviewing the P1-M1 research results. These decisions constrain P1-M2 architecture work; validation gates listed here remain mandatory and are not implied to have passed.

## Product and security boundaries

| Research question | Owner decision | Consequence for P1-M2 |
|---|---|---|
| Q2: consumer credentials | Permanently exclude vendor passwords, browser session cookies, and consumer OAuth tokens. Reopening this boundary requires a new owner decision and written authorization from the relevant vendor. | Reset Radar must not request, read, copy, store, transmit, refresh, or log those credentials. It may store its own pairing, relay, and encryption secrets. |
| Q3: API-key mode | Do not include API-key support or reserve architecture for it. | API organization/project rate-limit headers are outside the product and source model. |
| Q5: ChatGPT defaults | Begin completely blank. Do not provide numeric defaults, templates, or prefilled recurrence examples. | Onboarding must require the user to create and confirm each manual rule. |
| Q6: identity | Keep the **Reset Radar** name and use a neutral original icon. Use service names only as descriptive interface text, without vendor logos, copied visual styling, or implied affiliation. | Bundle identity and assets must remain vendor-neutral. |
| Automatic coverage | Limit automatic percentages to coding allowances reported by Codex app-server and Claude Code. Other supported manual entries are reset-only and must not imply automatic coverage. | The Mac adapters and product copy must distinguish coding allowances from general ChatGPT or Claude web/mobile usage. |

## First-version behavior

- The Mac collector and pairing flow must ship with the first usable version. A reset-only iOS increment does not count as the first release.
- Include Live Activities for eligible short windows such as a five-hour window. Weekly windows remain app and widget content. Activation, update, expiration, and stale-state behavior require an ActivityKit spike before implementation is frozen.
- Include an Apple Watch app in the first version. It receives the normalized, credential-free model through its paired iPhone, shows reset times, latest usage, source, and freshness, and does not connect directly to provider services or hold provider credentials.
- Display provider-reported percentage used, from 0% toward 100%; do not invert it into percentage remaining.
- Do not include percentage threshold alerts, percentage history, pace labels, or exhaustion forecasts. Retain only the latest valid observation and its source, observation time, and freshness or availability state.
- Always display reset dates and times using the OS's current local time zone.

## Time-zone and scheduling semantics

- Store provider-reported resets and one-shot resets as absolute instants.
- Store each manual recurring rule with its selected time zone. The rule remains tied to that zone when the device's OS time zone changes.
- Apply daylight-saving transitions according to the recurring rule's selected time zone.
- When the OS time zone changes, re-render local presentation and safely rebuild notifications without reinterpreting the rule or changing its underlying reset instant.
- Maintain a small rolling set of pending notifications and rebuild it after relevant rule or system changes. P1-M2 must test DST transitions, manual OS time-zone changes, and the practical pending-request ceiling before choosing the exact horizon.

## Synchronization and freshness

- Conditionally approve an owner-deployed Cloudflare Worker plus SQLite-backed Durable Object on `workers.dev` as the primary cellular transport.
- Cloudflare may hold only application-encrypted snapshots and minimal protocol metadata; it must never receive provider credentials, plaintext usage data, or the content key. The owner accepts that Cloudflare can observe transport metadata such as IP address, request time, route, size, and status.
- Limit the first version to one authoritative publishing Mac.
- Use foreground and manual refresh plus opportunistic background refresh. Do not reserve an APNs or dependable push-update architecture in the first version. Widgets and Live Activities must show stale state honestly when updates are delayed.
- Choose separate Codex and Claude refresh and stale thresholds from P1-M2 source-specific tests. Always show observation time, and invalidate an observation after its reported reset instead of fabricating a replenished percentage.

Cloudflare approval becomes final only after the synthetic-data spike in [cloudflare-synchronization.md](../research/phase-1/cloudflare-synchronization.md) passes. No real usage data or provider adapter may connect to the relay before then. The spike must prove the security boundary, cellular path, deletion and recovery behavior, quota failure, repeatable deployment and teardown, and US$0 billing with no paid subscription or add-on.

## Personal-use Mac distribution

Use local development signing for the Mac collector. The first version does not require Developer ID notarization or an automatic updater; P1-M2 must instead define and validate installation, Gatekeeper handling, launch at login, CLI child-process access, update safety, and uninstall cleanup for the owner's Mac.

## Evidence still required

The interview resolves the owner choices, but not these validation tasks:

- Cloudflare synthetic-data, cellular, quota, deletion, deployment, teardown, and billing spike;
- DST, selected-zone recurrence, OS time-zone change, and pending-notification tests;
- Live Activity lifecycle and stale-state tests;
- signed-in Codex and Claude Code smoke tests that do not log raw responses or credentials;
- source-specific refresh and stale-threshold calibration;
- physical-device signing, WidgetKit/App Group behavior, and seven-day Sideloadly refresh without data loss;
- Apple Watch target signing, installation on the paired watch, iPhone-to-watch synchronization, stale/offline presentation, and data preservation across the seven-day refresh cycle; and
- Mac installation, login-item, update, and removal tests under local development signing.
