# Official mobile usage access

Status: Draft

The owner wants an optional iPhone/iPad mode that can read current Codex and Claude Code allowance windows while the Mac is asleep or off. This note checks whether vendor-supported device login and usage APIs can provide that mode without transferring the Mac's provider credentials.

## Owner direction

On 2026-10-20, the owner preferred an official mobile sign-in/API over copying an existing session. When this optional mode is selected, the phone must fetch independently. Device login is preferred if the vendor supports it. The owner has no vendor beta access or private API documentation to supply.

The existing Mac collector and credential-free relay remain the defined first-version path. An optional direct source can be designed only for a provider whose published terms and API explicitly allow a third-party iOS client to obtain the same subscription percentage-used and absolute reset windows.

## Current evidence

| Provider | Documented sign-in and usage surface | Result for an independent Reset Radar phone source |
|---|---|---|
| Codex | The [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs) exposes `account/rateLimits/read` to a running Codex host. The [Codex SDK](https://github.com/openai/codex/blob/main/sdk/python/docs/getting-started.md) documents a device-code login for that host. [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source) documents an open-source app OAuth flow for eligible Responses inference; its [sign-in instructions](https://developers.openai.com/siwc/token-sharing-open-source/sign-in) use a browser and loopback callback, and its [usage guidance](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions) directs users to ChatGPT Settings. | Device-code login exists for Codex, but the reviewed official material does not establish a supported native iOS Codex host or a subscription-window read endpoint available to a third-party iOS client. Inference access or an API-key rate-limit header does not prove access to Codex allowance percentages. |
| Claude Code | The [status-line interface](https://code.claude.com/docs/en/statusline) supplies five-hour and seven-day `rate_limits` after a Claude Code API response. Anthropic's [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api) reports organization API usage, not personal Claude Code subscription windows. Its [credential policy](https://code.claude.com/docs/en/legal-and-compliance) says third-party developers may not offer Claude.ai login in their own apps or collect, store, or intermediate Claude.ai session tokens. | No documented, permitted third-party device-login and subscription-window API path was found. Claude Code's first-party status-line export remains the usable source. |

These are documentation findings, not proof that no future vendor API can exist. Recheck the official documents before any direct-mode implementation. Do not treat a successful login, an inference request, an exhausted-limit error, or organization API usage as the requested percentage and reset data.

## Faster refresh while the Mac is available

The existing iPhone Refresh action performs an immediate conditional relay read. It can return quickly, but its Codex observation is only as recent as the Mac's last five-minute poll; it cannot wake a sleeping Mac. Claude Code remains last-response data even if the Mac is awake.

The owner selected a Mac-assisted path for the first version. An authenticated reader posts a short-lived, rate-limited request to the relay; an awake Mac polls for it, makes one coalesced Codex app-server read, and publishes an encrypted acknowledgement and result. No provider credential leaves the Mac. The protocol, quota calculation, replay and abuse limits, and latency spike are specified in the [architecture](../architecture.md) and remain validation gates. This cannot provide independent-phone access, and it cannot force a fresh Claude Code observation without a new Claude Code response.

## Conditional design, if a vendor supplies the missing support

For each independently supported provider, the iPhone/iPad app would offer an explicit **Direct from provider** source choice. Its sign-in would start the vendor's documented device authorization flow, show the vendor verification address and short code, and receive device-scoped credentials through that flow. The app would store them in its own non-synchronizing device Keychain items, never copy the Mac's session, never send them to the relay or Watch, and provide sign-out and revocation guidance. A provider adapter would request the official subscription usage window response and normalize it into the existing `UsageSnapshot` semantics, with source, observation time, reset instant, account scope, and compatibility state visible in the UI.

The source choice would be per provider. Selecting direct access for one provider must not make the other provider appear current. The Mac path would remain available when direct access is not supported or chosen. Conflict authority, source switching, account matching, cross-process credential access, refresh rate, device loss, and Sideloadly re-sign behavior need a separate architecture decision and physical validation before the mode is built.

## Entry gate

No direct mobile credential or provider adapter is added until all of the following are evidenced for that provider:

1. An official device-login flow explicitly available to a third-party native iOS client, or another official native sign-in flow the owner accepts.
2. An official, permitted API that returns the subscription percentage-used and absolute reset instants for the windows Reset Radar displays, without generating an inference turn.
3. Credential storage, refresh, revocation, and account-selection contracts compatible with personal sideloading and app/widget process boundaries.
4. An owner decision updating the provider-specific trust boundary, source precedence, UI, and validation checklist.

Until then, the requested independent-phone mode is unavailable. The architecture must not substitute copied consumer tokens, private endpoints, API-key throughput headers, or inferred percentages.
