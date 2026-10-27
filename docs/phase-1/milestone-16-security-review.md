# P1-M16 runtime security review

Status: Active

This table traces every system failure row and trust boundary through the current implementation.
M16 closes only Watch-owned rows after automated and paired-device evidence; earlier-milestone gaps
remain explicitly owned and do not become passes through the M16 waiver.

## Failure behavior trace

| Failure condition | Owner | Implemented path and current evidence | Status and remaining proof |
|---|---|---|---|
| Provider absent or signed out | M10/M11 | ProviderAdapters state feeds Domain presentation; adapter fixture suites. | Open with M10 source calibration; not an M16 closure row. |
| Adapter incompatible or malformed | M10/M11 | Per-account source state and bounded adapter parsers. | Open with M10 calibration; not an M16 closure row. |
| Unsafe Claude Code command | M11 | Safe-command analysis leaves settings unchanged; ProviderAdapters tests. | Proved by M11 automated evidence; physical settings evidence remains with M11. |
| One invalid window | M4 | Domain per-window validation and fixtures. | Proved by Domain tests. |
| Reset with no new data | M4/M13–M16 | `PresentationPolicy` removes the percentage; UI and timeline tests cover state derivation. | Automated proof exists; Watch rendered-state inspection remains M16 device work. |
| Removed Home window after reset | M4/M13–M16 | Exact slot resolution becomes unavailable without retargeting. | Automated proof exists; Watch complication inspection remains M16 device work. |
| Mac-assisted request times out | M9/M14 | Reader request result matching retains cache. | Open with M9/M14 runtime evidence; not an M16 closure row. |
| Codex account changes | M10/M15 | Scoped reducer and scheduling reconciliation. | Open with M10 source calibration; not an M16 closure row. |
| Claude Code account changes | M11 | Same-kind merge and ageing policy. | M11 automated evidence recorded; runtime calibration remains with M11. |
| Concurrent Claude Code sessions | M11 | Newest proven observation wins in the session merger. | M11 automated evidence recorded. |
| Mac sleeps or quits | M12/M16 | Device caches retain original `observedAt`; presentation ages locally. | Mac proof belongs to M12; offline Watch ageing remains M16 device work. |
| Mac network lost | M12 | Publisher retains state and reacts to path recovery. | Open runtime observation with M12; not an M16 closure row. |
| Second Mac instance | M12 | Process lock activates the existing app. | M12 evidence; not an M16 closure row. |
| Mac Keychain interaction required | M7/M12 | Non-interactive secret reads and paused publication. | Open owner-run Keychain observation; not an M16 closure row. |
| iPhone secrets before first unlock | M7/M14 | Keychain failure maps to `secretsUnavailable` while cache remains. | Open M14 physical first-unlock evidence. |
| Pairing preflight, save, or activation fails | M7/M14 | Staged secrets and `awaitingActivation` recovery. | Automated proof exists; remaining device evidence belongs to M14. |
| Reader commit precedes post-commit work | M14–M16 | `needsAppReconcile` and current publisher/sequence check; Watch is an installed pipeline stage. | M16 automated app/widget catch-up passed on 2026-10-27; remaining M14 physical evidence stays with M14. |
| `304` after local cache loss | M14 | ETag invalidation and unconditional retry. | M14 automated evidence; not an M16 closure row. |
| Delayed Watch message after Forget Mac or re-pair | M16 | Installation ID, delivery revision, exact-payload confirmation, tombstone, and erase hold in `CommitWatchPayload`. | Automated replay/fault tests passed on 2026-10-27; reordered physical delivery remains open. |
| Watch unreachable during Forget Mac | M16 | iPhone persists the clear; Watch persists receipt retry; UI reports pending until a matching receipt. | Automated persistence tests passed on 2026-10-27; offline paired-device clear and rendered complication remain open. |
| Oversized source/relay response or redirect | M10/M14 | Bounded provider/transport readers and redirect rejection. | Evidence remains with owning milestones; Watch wire input is separately bounded in M16. |
| Relay unauthorized | M9/M14 | Reader stops automatic access and requires pairing. | Open M9 remote evidence; not an M16 closure row. |
| Relay publication conflict | M9/M12 | Publisher stops publication. | Open M9 remote evidence; not an M16 closure row. |
| Relay quota, rate limit, or outage | M9/M14 | Backoff retains cache and exposes transport state. | Open M9 remote evidence; Watch cached-state rendering remains M16 device work. |
| Replay, wrong key, invalid tag, or publisher | M7/M14 | Transport verifies before ReaderStore commit. | Automated proof exists; remote evidence stays with M9/M14. |
| Unknown mandatory schema or protocol | M4/M7/M16 | Domain, transport, and Watch wire codecs reject unknown versions while retaining cache. | Watch codec tests passed on 2026-10-27; cross-version paired delivery remains open. |
| Watch unreachable | M16 | Watch skips interactive send when unreachable; iPhone application context remains authoritative. | Adapter tests passed on 2026-10-27; paired reachability and stale-cache observation remain open. |
| Notification or Live Activity denied | M15 | Scheduling preserves usage and exposes denied state. | Open M15 device evidence; not an M16 closure row. |

## Trust-boundary trace

| Trust boundary | Owner | Implemented path and current evidence | Status and remaining proof |
|---|---|---|---|
| First-party tools → Mac | M10/M11 | Allowlisted normalized records; raw input stays adapter-local. | Open owner-present source/log inspection. |
| Claude Code settings → helper | M11 | Provably safe composition and narrow restore record. | M11 automated proof; physical settings check remains with M11. |
| Mac Keychain → publisher | M7/M12 | Stable-signature Keychain adapter. | Open owner-run signed Keychain observation. |
| Mac pairing screen → reader | M7/M13/M14 | Canonical package plus full-package confirmation code. | M14 physical QR is recorded; tampered/manual paths remain with M14. |
| Reader local save → relay activation | M7/M14 | Local secret/state commit precedes idempotent activation. | Automated proof exists; remaining runtime fault checks stay with M14. |
| Mac → Cloudflare | M7/M9 | Canonical AES-GCM envelope; relay stores ciphertext. | Open M9 deployed inspection. |
| Reader token → manual request → Mac | M8–M14 | Account-targeted operation, rate limits, expiry, and matching encrypted result. | Open M9/M14 runtime evidence. |
| Cloudflare → iPhone/iPad | M7/M14 | Authenticated, publisher-bound, ordered atomic commit. | Automated proof exists; M9/M14 runtime evidence remains open. |
| iOS app ↔ widget | M6/M14/M15 | App Group store, bounded lock, durable reconcile flag. | Open M14/M15 physical App Group and suspension evidence. |
| iPhone → Watch | M16 | Strict credential-free `WatchPayload`, typed codec, revision ordering, installation confirmation, and durable erase receipt. | Automated codec/order/fault proof and signed-package entitlement inspection passed on 2026-10-27; paired-device delivery, re-pair, and runtime secret inspection remain open. |
| Cache → notifications and Live Activity | M15 | Absolute reset instants, opt-in, and stale dates. | Open M15 runtime evidence; not an M16 closure row. |

## M16 closure boundary

M16 may close only after the final automated gate and reference-device run prove the two Watch
failure rows and the iPhone-to-Watch boundary above. The table intentionally leaves M9, M14, M15,
and owner-run evidence open under their named owners; those gaps remain Phase 1 work and are not
converted into accepted residuals here.
