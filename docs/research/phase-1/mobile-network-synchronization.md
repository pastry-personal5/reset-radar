# Mobile-network synchronization

Status: Active

Research on cost-savvy ways to move the Mac collector's credential-free usage snapshots to the owner's iPhone while it is away from the Mac's LAN and using cellular data. It separates foreground availability, store-and-forward delivery, and dependable background notification because no transport provides all three under the current free-account signing decision. The detailed Cloudflare design is in [cloudflare-synchronization.md](cloudflare-synchronization.md).

Sources were checked on 2026-10-19. No cloud account was created, no service was configured, and no real usage snapshot was uploaded.

## 1. Verdict and recommendation

Cloudflare Workers with a SQLite-backed Durable Object is the conditionally approved store-and-forward path. Store only application-encrypted snapshots plus the minimal protocol metadata in the [current relay design](../../architecture/relay.md); keep the content key on the paired Mac, iPhones, and iPads.

The owner accepted `workers.dev` as the relay hostname. No custom domain is required or purchased while the US$0 requirement applies.

- Cloudflare's Durable Object storage is strongly consistent and transactional, unlike eventually consistent Workers KV. It can atomically reject replayed sequences and replace the latest snapshot.
- Durable Objects and Workers both have Free-plan allocations far above this personal workload. US$0 requires the account to remain on Workers Free, use `workers.dev`, disable logs and traces, and enable no paid product; a Free-plan quota failure stops requests rather than producing metered overage charges.
- The Mac and iPhone can reach the relay over ordinary HTTPS, including cellular, and the iPhone can read the last snapshot after the Mac sleeps.
- Cloudflare still sees network and invocation metadata. It also becomes an availability and deployment dependency, so logs, secrets, rate limiting, deletion, rollback, and account ownership are product concerns.
- A relay does not provide dependable iOS background wake-up. The first version must promise cached, timestamped observations refreshed in foreground or opportunistically in background.

Recommended validation order:

1. Complete the synthetic-data Worker plus Durable Object spike in [cloudflare-synchronization.md](cloudflare-synchronization.md), with one authoritative Mac, up to three independent readers, and the manual Codex request path.
2. Prove end-to-end encryption, separate reader/write/administration credentials, strict sequence enforcement, disabled logs, cellular reads, manual-request limits and latency, quota behavior, deployment rollback, and teardown.
3. Retain iCloud Drive and Tailscale as researched alternatives only. A failed Cloudflare spike returns transport selection to the owner rather than adopting either automatically.
4. Defer multiple publishing Macs until the owner approves their merge and revocation semantics.
5. If dependable push-driven background refresh is required, revisit the paid Apple Developer Program and APNs. Cloudflare storage alone cannot wake a free-provisioned iOS app on demand.

The owner conditionally approved this recommendation, accepted Cloudflare's metadata and operations boundary, and limited the first version to one authoritative Mac. The architecture may freeze the transport only after the required synthetic-data spike passes; no real usage data may reach the relay before then.

## 2. What “on the go” requires

Three capabilities must not be conflated:

| Capability | Meaning | Needed for |
|---|---|---|
| Foreground reachability | The iPhone can fetch while on cellular when the user opens or refreshes Reset Radar. | Current values on demand. |
| Store-and-forward | A service retains the last encrypted snapshot after the Mac disconnects or sleeps. | Useful mobile access when the Mac is no longer online. |
| Background wake-up | iOS launches or resumes Reset Radar promptly after new data exists. | Near-real-time threshold alerts and unattended widget refresh. |

A VPN provides foreground reachability but not storage. A cloud file or key-value store provides storage but does not itself wake the app. APNs can signal new data, but Push Notifications is not available under the current free Personal Team and delivery is still system-controlled.

The product must therefore promise cached, timestamped observations—not continuous live state. Local reset notifications can remain dependable enough for known dates because they are scheduled from cached data; newly crossed usage thresholds cannot be promised immediately under free signing.

## 3. Option comparison

| Option | Expected recurring cost | Mobile-network behavior | Free Personal Team | Privacy and security | Main limitation | Disposition |
|---|---:|---|---|---|---|---|
| User-selected iCloud Drive folder | $0 while the account has free capacity; snapshots are only kilobytes | Store-and-forward across Mac and iPhone; foreground read does not require the Mac to remain online | Plausible through `UIDocumentPickerViewController`; physical-device spike required | Same Apple Account controls access; add app-layer authenticated encryption because standard iCloud protection is not end-to-end | No prompt background wake-up; sync latency has no product SLA; permission/bookmark and quota failures | No-custom-relay fallback |
| App-owned CloudKit private database | US$99/year Developer Program membership under the current free-account decision; private data also counts against the user's iCloud quota | Native store-and-forward, change subscriptions, conflict APIs, and offline queues | No. Apple's setup requires active Developer Program membership | Private database is user-owned and account-gated; encrypted fields gain stronger protection, especially with Advanced Data Protection | Conflicts with the decided free-account distribution and adds paid membership | Reconsider only if membership changes |
| Tailscale direct pull | $0 Personal plan for this device count | Works over cellular through direct WireGuard paths or encrypted relay fallback; VPN On Demand supports cellular | Yes for Reset Radar: it uses normal networking while the separately installed Tailscale app owns the VPN entitlement | WireGuard protects traffic end to end; still authenticate Reset Radar messages and restrict tailnet access | No store-and-forward, Mac must be awake, adds a Tailscale/identity account, and competes with another on-demand VPN | No-cloud-storage fallback |
| Cloudflare Worker plus SQLite Durable Object | US$0 only under the audited Free-only contract: no Workers Paid subscription, custom domain, observability, Logpush, or other paid product | Internet-reachable, strongly consistent store-and-forward even while the Mac sleeps | Yes for foreground HTTPS; does not add APNs | Store encrypted usage snapshots plus minimal protocol metadata; use separate read, write, delete, and content-encryption secrets | Public endpoint, Cloudflare metadata, shared account quotas, pricing changes, quota exhaustion, and no prompt background wake-up | Conditionally approved |
| Cloudflare Worker plus KV | $0 at expected personal volume within current free limits | Internet-reachable store-and-forward, but cross-location reads can see old values | Yes for foreground HTTPS; does not add APNs | Same encryption requirements as the Durable Object path | Eventual consistency and lack of atomic update make replay/conflict handling unnecessarily weak | Rejected as primary storage |
| Direct Bonjour/LAN protocol | $0 | Works only on the same reachable network unless combined with a VPN | Yes, subject to local-network behavior and signing validation | Can use explicit pairing and an authenticated encrypted protocol | Does not meet cellular away-from-home requirement by itself | LAN-only baseline |
| Router port forwarding or a public Mac endpoint | Often $0 in fees | Can reach an awake Mac over the Internet | Yes | Requires hardened public TLS/authentication and exposes a home endpoint | Dynamic addressing, carrier NAT, firewall upkeep, and a much larger attack surface | Reject |

### Expected relay volume

The original one-reader baseline of a 4 KiB publish and read every five minutes is 576 Worker requests per day. The selected design now has three readers, foreground polling, heartbeat publication, widget reloads, and bounded manual Mac-assisted Codex refresh. Its conservative intended-client maximum is about 69,500 requests per day, including Mac acknowledgements; see [Relay capacity](../../architecture.md#relay-capacity). Cloudflare currently includes 100,000 Worker requests/day, 100,000 Durable Object requests/day, 100,000 SQLite rows written/day, 5 million rows read/day, and 5 GB of Durable Object storage on Free. These quotas are account-wide, so another Worker or rejected abuse traffic can reduce headroom. The spike must measure real request, CPU, duration, row, and cellular costs.

The [Cloudflare cost audit](cloudflare-synchronization.md#2-zero-cost-contract-and-hidden-fee-audit) is part of this recommendation. Its principal hidden-fee paths are the US$5/month Workers Paid minimum plus overages, domain registration/renewal, paid Logpush, paid-account observability overages after the announced 2026-12-01 pricing change, unrelated account workloads, and third-party telemetry or CI. The strict configuration uses `workers.dev`, per-Worker secrets, no paid add-on, and no logs or traces. Cloudflare pricing is not a lifetime guarantee and must be rechecked before deployment.

KV remains useful evidence rather than the selected store: Cloudflare says its reads are eventually consistent and can expose an older value for 60 seconds or more. The strongly consistent Durable Object avoids making that delay part of replay and conflict correctness.

## 4. iCloud paths are not equivalent

### User-selected iCloud Drive folder

The iPhone asks the owner to choose a folder using `UIDocumentPickerViewController`. Apple says the returned security-scoped URL can cover current and future directory contents and can be saved as a bookmark for later launches. Reads must start security-scoped access, use file coordination, and stop access afterward. Permission can be revoked, bookmarks can become stale, and files may need downloading before their bytes are local.

The Mac collector writes a normal file into the same user-visible iCloud Drive folder. This avoids an app-owned ubiquity container and gives the owner a visible recovery/debug surface. It also means Reset Radar must tolerate the owner moving, deleting, restoring, or manually copying the file.

The public documentation establishes the API shape but not the final signing result. Physical-device validation must verify that folder selection, bookmark restoration, cellular download, widget-cache update, and Sideloadly refresh all preserve access.

### App-owned iCloud Documents and CloudKit

Apple lists iCloud Documents, CloudKit, and iCloud key-value storage as membership-dependent capabilities. CloudKit's enablement instructions require an active Apple Developer Program membership with appropriate permissions, and enabling CloudKit also adds Push Notifications.

Those services are therefore not valid assumptions for the current free Personal Team architecture. Paying the US$99 annual membership would make CloudKit the cleanest Apple-native store-and-forward candidate, but that is a distribution/cost decision rather than a free synchronization technique.

## 5. Common encrypted snapshot protocol

The transport must never contain a provider token, CLI path, account email, prompt, response, project path, or raw provider log. The visible outer envelope contains only protocol/encryption versions, an opaque publisher ID, a monotonically increasing sequence, a nonce, and authenticated ciphertext. Source observation times, normalized allowance windows, and availability state stay inside that ciphertext.

Generate a random 256-bit content key on the Mac, transfer it once with an owner-confirmed QR or equivalent pairing ceremony, and store it in each device's Keychain. Encrypt the canonical payload with CryptoKit AES-GCM and authenticated outer metadata. Reject invalid authentication tags, unknown mandatory versions, sequence rollback, implausible future timestamps, and an unexpected publisher ID.

The transport commits to local cache only after the complete envelope validates. A corrupt, partially synchronized, replayed, or unavailable relay response must leave the last valid cache intact and visibly stale. File-based fallbacks additionally require atomic replace and coordinated reads.

The initial design allows exactly one writer. If multiple Macs are approved later, give each publisher its own identity, credential, and sequence space; merge by provider account/window identity and observation time rather than allowing several Macs to overwrite one sequence. The Cloudflare authentication, pairing, deletion, logging, and recovery design is specified in [cloudflare-synchronization.md](cloudflare-synchronization.md).

## 6. Failure and freshness contract

Every path must expose these states without pretending that receipt time equals observation time:

- `current`: a valid observation within the source-specific freshness window;
- `stale`: last valid observation exists but is too old;
- `offline`: transport or Mac is unavailable, with cached data retained;
- `authorization-required`: relay credentials were rejected or revoked and re-pairing is required;
- `permission-required`: the selected folder permission or bookmark was revoked/stale;
- `quota-or-sync-error`: iCloud or relay could not accept or download the snapshot;
- `invalid-snapshot`: authentication, schema, publisher, sequence, or time validation failed.

The app should refresh on foreground activation and user request. A user-started Codex Refresh may ask an awake Mac to read through the relay, while a WidgetKit reload may perform a conditional relay read if the last successful fetch is more than five minutes old. Opportunistic background refresh may improve freshness, but tests and product copy must remain correct if the system never grants it. Widgets always render from the committed App Group cache and never contact the Mac directly.

## 7. Validation checklist

- Complete every synthetic-data Cloudflare spike check in [cloudflare-synchronization.md](cloudflare-synchronization.md), including sequence, authority, logging, deletion, quota, cellular, deployment, and rollback checks.
- Verify authenticated-encryption failure, replay, publisher mismatch, future time, and unknown schema behavior with fixtures.
- Re-sign through Sideloadly and confirm the Keychain keys, cached sequence, widget state, and scheduled local notifications survive as expected.
- Measure foreground latency, battery, and cellular data use at the intended refresh schedule.
- If the Cloudflare spike fails, prove `UIDocumentPickerViewController` folder selection/bookmark restoration or compare a Tailscale pull before changing the primary architecture.
- Confirm every condition in [Phase 1 owner decisions](../../phase-1/owner-decisions.md) remains satisfied before freezing the architecture.

## Sources

Checked 2026-10-19:

- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories): document-picker folder access, security-scoped URLs, bookmarks, file coordination, revocation, and failure handling.
- [Apple: Keep files up to date with iCloud Drive](https://support.apple.com/guide/icloud/mm19ef899373/icloud): cross-device file synchronization and storage accounting.
- [Apple: Manage iCloud storage](https://support.apple.com/en-asia/108922): included 5 GB capacity and full-quota behavior.
- [Apple: iCloud data security overview](https://support.apple.com/en-us/102651): standard protection versus Advanced Data Protection and iCloud Drive end-to-end encryption.
- [Apple: CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase): account requirement, ownership, visibility, and user-quota accounting.
- [Apple: Enabling CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app): active Developer Program membership, iCloud container, and Push Notifications setup.
- [Apple: Supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios): membership-dependent iCloud and push capabilities.
- [Apple Developer Program membership](https://developer.apple.com/programs/whats-included/): US$99 annual fee or local equivalent.
- [Apple: Background Tasks](https://developer.apple.com/documentation/backgroundtasks): system-scheduled refresh and processing APIs.
- [Tailscale pricing](https://tailscale.com/pricing): $0 Personal plan and current personal limits.
- [Tailscale connection types](https://tailscale.com/docs/reference/connection-types): direct, peer-relay, and DERP paths with WireGuard end-to-end encryption.
- [Tailscale VPN On Demand](https://tailscale.com/docs/features/client/ios-vpn-on-demand): automatic cellular/Wi-Fi connection behavior and one-on-demand-VPN limitation.
- [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/): current Worker, Durable Object, and KV free limits, the Paid-plan minimum, and metered overages.
- [Cloudflare `workers.dev`](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/): included hostname and intended personal/hobby use.
- [Cloudflare Observability pricing](https://developers.cloudflare.com/observability/pricing/): announced 2026-12-01 logging/tracing allowances and Paid overages.
- [Cloudflare KV writes](https://developers.cloudflare.com/kv/api/write-key-value-pairs/): eventual consistency, cross-location visibility delay, and single-key write limit.
- [Cloudflare Durable Object storage](https://developers.cloudflare.com/durable-objects/best-practices/access-durable-objects-storage/): strongly consistent transactional storage and deletion.
- [Cloudflare synchronization](cloudflare-synchronization.md): detailed primary-candidate storage, protocol, threat, privacy, operations, and spike analysis.
