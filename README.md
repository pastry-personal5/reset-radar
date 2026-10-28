# Reset Radar

Reset Radar monitors Codex and Claude Code allowance usage across your Mac, iPhone, iPad, and Apple Watch.

The iPhone, iPad, and Apple Watch apps use an original radar icon with reading rings and a
highlighted dot; the Watch artwork is simplified for legibility in the app grid.

*See what’s left. Know when it resets.*

The Collector Mac reads coding-allowance data from Codex and Claude Code without copying provider credentials. Reset Radar shares encrypted, timestamped readings with the owner's iPhone, iPad, and Apple Watch, where it shows Percentage Used, Reset Times, and data state in apps, widgets, Reset Live Activities, and an Allowance Complication.

The project is in its Foundation phase. The Mac collector, local package, Cloudflare relay,
iPhone/iPad reader, scheduling surfaces, and Apple Watch app are implemented; their remaining
physical-device validation is still in progress. It is designed for personal sideloading with a
free Apple account, not App Store or TestFlight distribution. The mobile apps require iOS,
iPadOS, or watchOS 27.0 or later. The Mac main window and Settings
share a Global Messages pane for collector and setup status, including the reason publication
stops safely. Mac Settings offers a Codex source table with login-shell executable discovery and a
Claude Code connection card. The table keeps its Add row after any number of configured Codex
accounts; review each selected `CODEX_HOME` in the
[installation guide](docs/mac-installation-and-recovery.md#configure-sources).
The Mac collector supports Apple silicon only; every Mac build is arm64-only and Intel Macs are unsupported.
Mac Settings groups each section's controls into titled cards above Global Messages.
The Mac Home account list and selected details refresh as the collector commits new readings;
alias edits from Home or Sources update both open views and show local-save and relay-delivery
feedback separately.
Claude Code setup verifies its local helper, then directly edits `~/.claude/settings.json` from
Settings after an exact preview and confirmation. It preserves a safe existing status-line
command, including a trusted `bash $HOME/<script>` form, and explains when composition is blocked.
Home rows show five-hour and weekly Percentage Used when those provider windows have readings.
The Mac menu bar shows each configured account's five-hour and weekly status and opens the main
window with Open Reset Radar. It also shows the last successful relay publication or an attention
state. An open menu updates reading status as time passes. If Release signing fails, collection
pauses and Settings explains how to recover. Home's Main Sidebar and Account Details show every provider window, reset and freshness
information, and account-specific Refresh. A setup banner points to the next source, relay, or
pairing action while keeping configured accounts visible.
Local Mac readings do not require relay setup; the relay publishes them to other devices.
Relay & Pairing shows the relay's durable setup state and a Paired Devices list with each reader's
status, short ID, pairing date when known, and a confirmed Revoke action. About offers GitHub
feedback links and opens the repository if you want to support Reset Radar there.

On iPhone and iPad, Reset Radar pairs with the Collector Mac by scanning its QR code or pasting
its Pairing Package, after you compare the Pairing Confirmation Code on both devices. Home lists
each account the Mac publishes with its five-hour and weekly rings; Account Details shows every
window with its reset time, freshness, and source. Refresh on Home asks the Mac to read all Codex
accounts and reports each account's result separately; a Claude Code Refresh reads the relay
only. When the relay can't be reached, the last valid readings stay visible beside a Sync Problem.
Settings → Pairing & Sync offers Forget Mac, which erases this device's pairing and cached usage
but does not revoke it on the Mac. The reader is installed with Sideloadly using the owner-run
[sideloading user guide](docs/user-guide-for-sideloading.md). Maintainers can use the detailed
[installation procedure](docs/research/personal-use-sideloading.md#p1-m14-reader-installation-procedure)
for package inspection and physical-device evidence.
The initial signed iPhone installation and QR-pairing flow have been exercised; the procedure
also tracks the remaining device and renewal checks.

On Apple Watch, Home shows one two-ring row per configured account with stable lavender, mint, or
peach account palettes and no visible alias; accessibility identifies every account and window.
Home omits a navigation title; its full-width Refresh text button is the final scrollable row
after the account list and local data controls.
Account Details shows all provider windows, reset times, freshness, and unavailable/offline state.
The rectangular Allowance Complication is configured for one exact account and standard window.
The Watch keeps an aged local cache, can request an iPhone refresh, and offers owner-confirmed
local erase and pairing-reset controls. Initial paired-device installation, background delivery,
App Group, complication, and offline-erasure validation follows the
[M16 Watch runbook](docs/research/m16-watch-device-runbook.md).

The Mac app keeps a redacted troubleshooting history for up to eight days. Development uses
`~/Library/Logs/ResetRadar.dev/` and Release uses `~/Library/Logs/ResetRadar/`; these logs remain
available for troubleshooting even though Diagnostics is no longer a Settings destination. See
the [contribution guide](docs/contribution-guide.md) for a local inspection command.

## Documentation

- [Product behavior](docs/product-behavior.md) defines the approved scope and non-goals.
- [Software architecture](docs/architecture.md) defines the system and platform targets.
- [Documentation index](docs/README.md) links all active design, research, and planning documents.

## License

Licensed under the Apache-2.0 license. See [LICENSE](LICENSE).

## Contributing

See the [contribution guide](docs/contribution-guide.md). AI coding agents must also follow [AGENTS.md](AGENTS.md).
Use `make gate` for bounded, sequential validation of the reference iPhone, iPad, Watch, Mac,
and relay targets. Simulator checks require host CoreSimulator access; sandbox failures report
an actionable preflight error.
