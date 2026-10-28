# Product limitations

Status: Active

This document centralizes the product boundaries and operational cautions for Reset Radar. It
complements the approved scope in [product behavior](product-behavior.md) and the detailed
installation and recovery procedures.

## Security and privacy boundaries

- Reset Radar does not copy, save, or send provider credentials. Codex and Claude Code remain
  responsible for their own sign-in state; Reset Radar receives only derived allowance readings.
- Usage snapshots and optional reader device profiles are encrypted before the Cloudflare relay
  stores them. The relay cannot read either payload, but it stores opaque account-targeted refresh
  metadata and can observe network addresses, request times, sizes, routes, status codes, and
  opaque identifiers. See [software architecture](architecture.md#system-context-and-trust-boundaries).
- Enter Apple Account credentials only in Sideloadly when its documented installation flow asks
  for them. Never place credentials, pairing packages, or diagnostic logs in an issue or commit.

## Availability and data limits

- Reset Radar shows only provider-reported coding allowances from the installed Codex app-server
  and Claude Code status line. It does not cover general ChatGPT or Claude web/mobile use,
  managed organization plans, API-key usage, or every provider limit.
- It does not fabricate usage or reset values. If the Mac, source, or relay is unavailable, the
  last valid reading can remain visible as stale or unavailable.
- Manual percentage entry, manual reset rules, usage history, forecasts, threshold alerts, and
  dependable push refresh are not available.
- One authoritative Mac collects and publishes the readings. iPhone, iPad, and Watch apps depend
  on pairing with that Mac; the Watch receives data through the paired iPhone.

## Platform and installation limits

- Reset Radar is for personal use with the owner's free Apple account. Its supported path does
  not require an annual Apple Developer Program enrollment fee, but it uses Sideloadly and needs
  periodic re-signing. Apple documents free registration and personal-device testing separately
  from the paid program membership. It is not distributed through the App Store or TestFlight.
- Supported minimums are iOS, iPadOS, and watchOS 27.0, plus macOS 26.7.1. Mac builds require
  Apple silicon (`arm64`); Intel Macs are unsupported.
- The product has no automatic updater or first-version notarization. Follow the
  [Mac installation and recovery guide](mac-installation-and-recovery.md) and the
  [Sideloading guide](user-guide-for-sideloading.md).

## Native implementation boundary

The Apple apps use native Swift and SwiftUI: there is no Python runtime, web app, or HTML/CSS/
JavaScript user interface. This does not mean the whole product avoids JavaScript: the encrypted
Cloudflare relay is a separate strict TypeScript service that runs on the Workers JavaScript
runtime. See [relay architecture](architecture/relay.md).
