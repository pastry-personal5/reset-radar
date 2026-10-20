# Initial research on feasibility

Status: Active

Feasibility study of how Claude and ChatGPT expose allowance usage and reset times, what data is available, what iOS 26+ allows, and what existing tools do. Sources were checked on 2026-10-19; volatile vendor limits must be rechecked before they become shipped defaults.

Evidence labels apply to every substantive claim in this document:

- `[documented]` — supported by a linked first-party vendor or Apple source.
- `[observed]` — supported by a third-party listing, README, issue, or review; it was not independently tested.
- `[inferred — confidence: …]` — analysis derived from the evidence. The confidence note explains its strength.

In a table, the evidence label in a confidence/evidence cell applies to the entire row. Headings, research-scope declarations, questions awaiting decisions, and source metadata are not factual claims.

No account was logged into, no private endpoint was probed, and no credential was copied during this research.

## 1. Verdict and recommendation

**Verdict: feasible with constraints.**

- `[documented]` iOS can schedule a local notification for a known date while the app is not running, and WidgetKit can render a countdown without continuously running the extension. See section 4.
- `[documented]` Claude exposes consumer reset times in Settings > Usage for paid plans, and ChatGPT displays reset timing in-product when it is available. Neither vendor documents a public consumer-usage API. See section 2.
- `[documented]` Anthropic prohibits automated or non-human consumer access unless it uses an Anthropic API key or Anthropic explicitly permits it. OpenAI prohibits automatically or programmatically extracting data or output. See sections 3 and 5.
- `[inferred — confidence: high]` Reset Radar is feasible as an automatic coding-plan usage tracker when a Mac can read structured state from the installed first-party Codex and Claude Code tools. No supported direct iOS consumer-usage API was found, and private consumer endpoints remain excluded.

**Recommended first version:**

- `[inferred — confidence: high]` Automatically attach timestamped percentage-used observations and provider reset instants to open-ended allowance windows. The [usage-tracking study](usage-tracking.md) defines the semantics; [automatic usage acquisition](automatic-usage-acquisition.md) selects Codex app-server and Claude Code status-line sources on Mac; the [upstream audit](upstream-automatic-usage-sources.md) pins their current schemas and freshness differences.
- `[inferred — confidence: high]` Present the four standard Codex and Claude Code five-hour/weekly windows in the app, widgets, Watch app, complication, and read-only App Intent; allow user-started Live Activities for eligible five-hour windows.
- `[inferred — confidence: high]` Keep the data model open-ended rather than encoding exactly two windows per product. Both vendors state that limits vary by plan, model, feature, system conditions, or vendor discretion.
- `[inferred — confidence: high]` Reuse first-party CLI sign-in without reading its credentials and require no Reset Radar account or analytics service. The owner conditionally approved a Cloudflare Worker plus SQLite-backed Durable Object as the primary store-and-forward transport, with Cloudflare holding ciphertext but never the content key; final adoption requires the [Cloudflare study's](cloudflare-synchronization.md) synthetic-data spike to pass.
- `[documented]` Distribute for the owner's personal use with a free Apple account and Sideloadly. The separate [personal-use sideloading study](personal-use-sideloading.md) records the seven-day provisioning constraints and excludes LiveContainer while widgets remain in scope.

**Other automatic data:**

- `[documented]` API-key rate-limit headers provide machine-readable reset data for API traffic only.
- `[documented]` The owner excluded API-key mode and does not want the architecture to reserve an interface for it.

**Rejected default:**

- `[documented]` Session-cookie scraping and copied consumer OAuth tokens conflict with the vendors' published consumer terms unless the vendor grants explicit permission.
- `[observed]` Existing trackers demonstrate that these sources can expose accurate reset timestamps, but also document expired sessions, Cloudflare challenges, reauthentication, and provider changes.
- `[inferred — confidence: high]` Reset Radar should not ship these sources without written vendor authorization and a fresh App Review analysis.

## 2. Service matrix

`[documented]` The agreed consumer scope contains every individual Claude and ChatGPT tier available on the check date. `[inferred — confidence: high]` Managed Team, Business, Enterprise, Edu, and institutional plans are excluded because their limits may be administrator-specific. `[documented]` API-key usage is recorded separately because vendors bill and limit it separately from consumer subscriptions.

| Service and plan | Limit model | Reset time visible to the user | Machine-readable source | Auth needed | Terms-of-service stance | Confidence and dated source |
|---|---|---|---|---|---|---|
| Claude Free | Five-hour session window; amount varies with conversation length, model, feature, and demand. | No first-party page found that promises a usage dashboard for Free. | None documented for the consumer plan. | Claude account session for vendor UI; none for manual entry. | Manual entry allowed; automated consumer access forbidden absent explicit permission. | `[documented]` High for the window and terms. [Claude pricing](https://claude.com/pricing), [Consumer Terms](https://www.anthropic.com/legal/consumer-terms). Checked 2026-10-19. |
| Claude Pro | Five-hour session window plus a weekly limit. The weekly limit resets at a fixed account-assigned day and time. | Settings > Usage shows session consumption, time remaining, weekly consumption, and the next reset. | Claude Code can pass last-response five-hour/seven-day rate-limit state to a local status-line command; no supported third-party network API was found. | Existing Claude Code sign-in stays owned by Claude Code. | Reading derived local status-line state avoids automated third-party account access; private OAuth usage calls remain excluded. | `[documented]` High for plan behavior; `[observed]` medium for evolving CLI fields. [Pro plan](https://support.claude.com/en/articles/8325606-what-is-the-pro-plan), [usage best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| Claude Max 5x | Five-hour session at 5x Pro capacity plus weekly limits; Max also has a separate Fable weekly limit. | Settings > Usage. | Claude Code status-line state can expose standard five-hour/seven-day windows; scoped model windows may be absent. | Same as Pro. | Same as Pro. | `[documented]` High for plan behavior; `[observed]` medium for local field coverage. [Max plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan), [usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| Claude Max 20x | Five-hour session at 20x Pro capacity plus weekly limits; Max also has a separate Fable weekly limit. | Settings > Usage. | Claude Code status-line state can expose standard five-hour/seven-day windows; scoped model windows may be absent. | Same as Pro. | Same as Pro. | `[documented]` High for plan behavior; `[observed]` medium for local field coverage. [Max plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan), [usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| Claude API organization | Token buckets for requests and input/output tokens continuously replenish; spend limits are separate. | Claude Console Rate limits page. | `anthropic-ratelimit-*-reset` response headers contain full-replenishment timestamps in RFC 3339 form. | API key or supported API access token. | Allowed through the documented API. | `[documented]` High. [Anthropic API rate limits](https://platform.claude.com/docs/en/api/rate-limits). Checked through current Context7 documentation and the first-party page on 2026-10-19. |
| ChatGPT Free | Everyday text chat is unlimited subject to abuse safeguards; GPTs and tools such as uploads, images, voice, and data analysis have separate limits. | ChatGPT shows reset timing when an applicable limit is reached. | None documented for the consumer plan. | ChatGPT account session for vendor UI; none for manual entry. | Manual entry allowed; automated extraction forbidden. | `[documented]` High for the model, medium for individual tool clocks because they change. [Free Tier FAQ](https://help.openai.com/en/articles/9275245-using-chatgpt-s-free-tier-faq), [Terms of Use](https://openai.com/policies/terms-of-use/). Checked 2026-10-19. |
| ChatGPT Go | Everyday text chat is unlimited subject to safeguards; eligible features have higher limits than Free, while voice uses Free-tier limits. | ChatGPT displays reset timing when available. | None documented for the consumer plan. | Same as Free. | Same as Free. | `[documented]` Medium: the vendor documents categories, not durable quota values or every reset rule. [ChatGPT Go](https://help.openai.com/en/articles/11989085-what-is-chatgpt-go), [GPT-5.6 and GPT-6 Pro](https://help.openai.com/en/articles/20001354-gpt-56-and-gpt-6-pro-in-chatgpt). Checked 2026-10-19. |
| ChatGPT Plus | Variable message/tool caps; Work and Codex use five-hour and weekly allowances. | Model/tool notices show reset timing; Work and Codex expose Usage settings. | Installed Codex app-server exposes structured Codex/Work rate-limit snapshots; this does not cover every ChatGPT feature. | Existing Codex ChatGPT sign-in remains owned by Codex. | Local app-server integration avoids copied credentials; direct private endpoint extraction remains excluded. | `[documented]` High for Work/Codex clocks and the app-server schema; no durable numeric quota is published. [Plus](https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus), [paid Work/Codex resets](https://help.openai.com/en/articles/20001507-paid-weekly-work-and-codex-rate-limit-resets), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| ChatGPT Pro 100 | Higher plan-specific model/tool allowances; Pro models can use shared weekly or separate daily allowances, and Work/Codex have separate five-hour and weekly allowances. | ChatGPT displays a reset time when available; Work and Codex expose Usage settings. | Codex app-server covers exposed Work/Codex buckets, not every general ChatGPT model/tool allowance. | Same as Plus. | Same as Plus. | `[documented]` Medium because exact allowances and machine-readable bucket coverage are account- and rollout-dependent. [Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers), [GPT-5.6 and GPT-6 Pro](https://help.openai.com/en/articles/20001354-gpt-56-and-gpt-6-pro-in-chatgpt), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| ChatGPT Pro 200 | More usage than Pro 100; current and grandfathered allowances can differ. Pro-model and Work/Codex clocks remain separate. | Same as Pro 100. | Same Work/Codex-only app-server boundary as Pro 100. | Same as Plus. | Same as Plus. | `[documented]` Medium because the allowance changes on 2026-10-29 for eligible grandfathered accounts. [Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| ChatGPT Pro 500 | Highest current Pro allowance; some Ultrafast use consumes included allowance at a higher rate. Pro-model and Work/Codex clocks remain separate. | Same as Pro 100. | Same Work/Codex-only app-server boundary as Pro 100. | Same as Plus. | Same as Plus. | `[documented]` Medium because exact allowances are not published as stable numbers. [Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers), [release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [automatic acquisition](automatic-usage-acquisition.md). Checked 2026-10-19. |
| OpenAI API project | Request, token, daily, and image limits can apply; the first exhausted dimension wins. | Platform organization limits page. | `x-ratelimit-reset-requests`, `x-ratelimit-reset-tokens`, optional project-token headers, and `Retry-After`. Reset values are durations such as `1s` or `6m0s`. | API key or supported project credential. | Allowed through the documented API. | `[documented]` High. [OpenAI API rate limits](https://developers.openai.com/api/docs/guides/rate-limits). Checked through current Context7 documentation and the first-party page on 2026-10-19. |

Cross-service findings:

- `[documented]` Claude's paid weekly reset is not anchored to first use or subscription start; it is a fixed day and time assigned to the account and shown in Settings > Usage.
- `[documented]` A purchased ChatGPT Work/Codex reset starts a new weekly period with the first request after purchase; the next automatic reset is seven days after that request.
- `[documented]` Current ChatGPT consumer documentation intentionally avoids durable numeric caps for many models and tools and directs users to in-product state.
- `[documented]` Claude states that it may add weekly, monthly, model, or feature limits at its discretion; ChatGPT similarly varies limits by plan, model, feature, system conditions, and rollout.
- `[inferred — confidence: high]` Built-in presets would become stale product data. User-editable rules are a core requirement, not an edge-case feature.

## 3. Reset-time acquisition options

| Rank | Option | Reliability | Terms and legal risk | Effort and fragility |
|---|---|---|---|---|
| 1 | Mac collector using installed first-party CLI interfaces | `[documented]` Codex app-server exposes actively readable percentage/reset snapshots; Claude Code documents last-response rate-limit state in status-line and early-access function-hook surfaces. | `[inferred — confidence: high]` Low when Reset Radar invokes the local interface and never reads credentials or private endpoints. | `[observed]` Medium-high: requires installed/signed-in CLIs, schema adapters, staleness, and secure Apple-device synchronization. Selected automatic path. |
| 2 | Official API headers | `[documented]` High for API rate limits; irrelevant to consumer subscriptions. | `[documented]` Low when used as documented. | `[inferred — confidence: high]` Medium. A request consumes quota, keys require secure storage, and consumer/API concepts must stay visibly separate. |
| 3 | User-entered reset/rule or percentage | `[inferred — confidence: high]` Accurate to the user's entry and vendor display at that moment. | `[documented]` No vendor credential or automated access. | `[inferred — confidence: high]` Diagnostic fallback only; it does not satisfy the automatic-percentage requirement. |
| 4 | Consumer usage endpoint with session cookie or copied OAuth token | `[observed]` Existing tools obtain utilization and reset timestamps while endpoints remain compatible. | `[documented]` High: Anthropic bars automated consumer access absent permission; OpenAI bars automated extraction. App Review 5.2.2 also requires permission under the third party's terms. | `[observed]` High fragility: session expiry, Cloudflare challenges, reauthentication, endpoint changes, and account restrictions are reported by tracker documentation. |
| 5 | Embedded web view or DOM scraping | `[inferred — confidence: high]` Medium at best because layout and bot protection can change. | `[documented]` High for the same reasons as option 4. | `[inferred — confidence: high]` High ongoing maintenance and review risk. |
| 6 | Calendar or email signal | `[inferred — confidence: medium]` Low; no vendor reset email/calendar contract was found. | `[inferred — confidence: high]` Medium privacy risk because mail/calendar access is broader than the product need. | `[inferred — confidence: high]` High effort for a weak signal. |

- `[inferred — confidence: high]` The baseline is option 1; detailed algorithms and recent implementations are in [automatic-usage-acquisition.md](automatic-usage-acquisition.md).
- `[documented]` Options 4 and 5 require a user's session cookie or token and conflict with current consumer automation terms absent permission.
- `[inferred — confidence: high]` A password should never be requested: neither vendor documents password delegation to third-party trackers.

## 4. iOS capability analysis

### Local notifications

- `[documented]` Apple says, “Once scheduled, a notification request remains active until its trigger condition is met, or you explicitly cancel it.” [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
- `[documented]` `UNCalendarNotificationTrigger` uses `DateComponents`; Apple describes those components as evaluated in a calendar and time zone. One-shot absolute resets should therefore be stored as instants, while recurring wall-clock rules must preserve the user's intended calendar/time-zone semantics.
- `[documented]` The only Apple page found with a number says the deprecated `UILocalNotification` API keeps the next 64 scheduled notifications. The current `UNUserNotificationCenter` scheduling page does not publish a numeric cap. [Deprecated `UILocalNotification`](https://developer.apple.com/documentation/uikit/uilocalnotification).
- `[documented]` Focus lets the user allow or silence an app's notifications. Notification content also has an interruption level that the system evaluates against the current Focus. [Set up a Focus](https://support.apple.com/guide/iphone/set-up-a-focus-iphd6288a67f/ios), [`UNNotificationContent`](https://developer.apple.com/documentation/usernotifications/unnotificationcontent).
- `[inferred — confidence: high]` A scheduled request can be timely without being guaranteed to alert visibly. The UI must distinguish “scheduled” from “will interrupt you.”
- `[inferred — confidence: high]` No backend is required. Keep pending requests small and rebuild them after edits, launches, and material clock/time-zone changes.

### Background refresh and background tasks

- `[documented]` For `earliestBeginDate`, Apple says, “The system doesn’t guarantee launching the task at the specified date, but only that it won’t begin sooner.” [BGTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
- `[documented]` Apple's development guidance says the delay before a scheduled background task runs can be many hours. [Starting and terminating tasks during development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development).
- `[inferred — confidence: high]` Background polling cannot be the correctness mechanism for a reset alarm. It can refresh best-effort data, but the known reset must be scheduled directly as a local notification.
- `[documented]` No backend is required for `BGTaskScheduler`; it also cannot make exact polling dependable.

### Widgets and StandBy

- `[documented]` Apple says a frequently viewed widget typically receives “from 40 to 70 refreshes” per 24-hour budget, and timeline entries should be “at least about 5 minutes apart.” [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- `[documented]` The same page explains that a dynamic date can display a continuing countdown even while the widget extension is not running. StandBy refreshes at a system-defined rate outside the normal widget budget.
- `[inferred — confidence: high]` A timer-style reset countdown fits WidgetKit well because it does not require minute-by-minute timeline reloads.
- `[documented]` No backend is required for locally stored reset times. Widget push updates would add a server/APNs path and are unnecessary for the baseline.

### Live Activities

- `[documented]` Apple says, “A Live Activity can be active for up to eight hours”; it may remain on the Lock Screen for up to four more hours. Combined static and dynamic data cannot exceed 4 KB. [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
- `[documented]` A Live Activity cannot access the network. The app can update it locally while running; server-driven updates require ActivityKit push notifications through APNs.
- `[inferred — confidence: high]` The eight-hour active lifetime fits a five-hour session clock but not a weekly clock. The owner included Live Activities for eligible short windows; weekly windows remain app and widget content, and P1-M2 must validate lifecycle behavior.

### App Intents, Shortcuts, and Siri

- `[documented]` Apple describes an app intent as “an action that your app performs” and makes it available to Siri, Spotlight, Shortcuts, and widgets. [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent).
- `[inferred — confidence: high]` “When does my limit reset?” can return the app's stored computed date without network or background execution. An App Intent is an access surface, not a source of fresh vendor data.
- `[documented]` No backend is required for an intent over local data. Siri availability and phrasing remain under system control; the app cannot promise a specific voice presentation.

### Apple Watch, Lock Screen, and other surfaces

- `[documented]` WidgetKit supports Lock Screen widgets, and ActivityKit can present a Live Activity on a paired Apple Watch. The Live Activity retains the same lifetime, payload, and network constraints. [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
- `[documented]` The owner included an Apple Watch app in the first version. It receives normalized, credential-free snapshots through the paired iPhone rather than connecting directly to providers.
- `[inferred — confidence: high]` A watch complication or companion adds a target and synchronization/test surface but no new reset-time source. Defer it unless the owner prioritizes glanceability over implementation size.

### Push designs

- `[documented]` Remote notification delivery uses APNs and a provider server. ActivityKit push updates likewise require a server sending to APNs. [Notifications overview](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/index.html).
- `[inferred — confidence: high]` A server adds hosting, authentication, incident response, a privacy policy surface, and App Review disclosures without improving a clock the device already knows. The first version should not have one.

## 5. Privacy, security, and distribution

### Data inventory

- `[inferred — confidence: high]` The recommended mode stores service labels, user-defined rules, start/reset instants, notification preferences, and widget configuration. These values stay on device.
- `[documented]` Manual mode needs no vendor credential. API mode would need an API key. Cookie/OAuth scraping would hold a consumer-account bearer credential and is rejected by default.
- `[inferred — confidence: high]` No conversation content, prompts, outputs, contacts, mail, calendar, or precise location is needed.
- `[inferred — confidence: high]` The first version should have no third-party analytics or backend. If diagnostics are later added, that is a separate privacy decision.

### Credential storage if a later approved mode needs it

- `[documented]` Apple describes Keychain Services as encrypted storage for small secrets and advises using the most restrictive accessibility class that fits. [`Keychain Services`](https://developer.apple.com/documentation/security/keychain-services), [restricting accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility).
- `[documented]` `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is available only while the device is unlocked and does not migrate to another device. [Accessibility value](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).
- `[inferred — confidence: high]` If API keys are approved, store them in Keychain, default to a non-synchronizing `ThisDeviceOnly` accessibility class, never put them in app-group preferences, logs, crash metadata, or analytics, and delete them on disconnect.
- `[inferred — confidence: medium]` A widget normally does not need the credential; it should read only derived reset data from an app-group container. Any Keychain access group should be justified during architecture work rather than enabled preemptively.

### Vendor terms

- `[documented]` Anthropic's Consumer Terms prohibit crawling/scraping and, absent an API key or explicit permission, prohibit access “through automated or non-human means.” [Anthropic Consumer Terms](https://www.anthropic.com/legal/consumer-terms).
- `[documented]` OpenAI's Terms prohibit users from “Automatically or programmatically extract[ing] data or Output.” [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/).
- `[inferred — confidence: high]` A session-cookie or copied-token tracker is not a merely fragile implementation choice; without written permission it is incompatible with the current terms.

### App Store review

The owner has chosen personal-use sideloading with no first-version App Store or TestFlight release. The review findings below are retained for any future distribution change; vendor terms and trademark restrictions still apply outside App Review.

- `[documented]` Guideline 5.2.2 requires specific permission under a third-party service's terms when an app uses, accesses, monetizes, or displays that service's content; authorization must be supplied on request. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- `[documented]` Guideline 4.1(c) bars another developer's icon, brand, or product name in an app icon or name without approval. Guideline 5.2.1 bars protected third-party material without permission and misleading names or metadata.
- `[documented]` Guideline 5.1.1 requires an accessible privacy policy describing collection, use, sharing, retention, deletion, and consent even when the app collects no off-device data.
- `[documented]` Guideline 2.5.1 requires public APIs used for their intended purpose; 2.5.4 restricts background services to intended purposes; 2.5.16 requires widgets and notifications to relate to app functionality; 4.5.4 says push must not be required for the app to function.
- `[inferred — confidence: high]` A neutral app name/icon, derived local CLI data, public Apple APIs, and no vendor credentials inside Reset Radar form the lowest-risk posture. Plain-text service names inside the app still need accurate nominative use and no implication of affiliation.

## 6. Prior art

Detailed GitHub repository discovery, source/authentication patterns, licenses, maintenance signals, and issue evidence are in [github-prior-art.md](github-prior-art.md).

Every entry below is `[observed]`; none was installed or given credentials. “Issue/review signal” reports only evidence found in the linked public material, including an explicit absence of useful review volume.

| Tool | Platform and price | Reset-time source | Issue/review signal | Product lesson |
|---|---|---|---|---|
| [Claude Usage Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | macOS; free/open source | Claude Code OAuth credential, embedded browser session, manual `sessionKey`, or API key | README documents manual cookie extraction, session-key handling, and a statusline path that still needs the key; older security notes show the operational cost of credential migrations and signing. | Automatic accuracy comes with credential, signing, migration, and support work. |
| [Usage4Claude](https://github.com/f-is-h/Usage4Claude) | macOS; free/open source | Browser sign-in or manual Claude session key; supports Codex credentials | README troubleshooting names Cloudflare security blocks, periodic session expiry, token expiry under advanced security, endpoint throttling, and repeated Keychain prompts after self-signed updates. | Undocumented consumer endpoints impose recurring support costs even when the UI is polished. |
| [ClaudeStats](https://github.com/kynetic29/claude-stats) | Windows; free/open source | Local Claude Code logs/telemetry for estimates; optional browser session for authoritative resets | FAQ says local percentages can disagree with actual rate limiting and browser sessions expire. | Local observation is safer but approximate; live accuracy reintroduces a consumer session. |
| [CUStats Go](https://apps.apple.com/us/app/custats-go-ai-usage-tracker/id6757679404) | iPhone/iPad; US$8.99 on check date | Listing says multiple providers, model windows, widgets, and credentials in iOS Keychain; exact endpoints are not disclosed | The listing had too little public review detail to identify a recurring complaint. | There is an App Store market for a native, private, glanceable tracker, but listing acceptance does not prove vendor authorization. |
| [UsageScope](https://apps.apple.com/us/app/usagescope-ai-usage-tracker/id6759642037) | iPhone/Mac; free with in-app purchases | Connects provider accounts; exact source is not disclosed | Listing warns that data, refresh timing, and reset schedules depend on the provider and iOS background activity; it also notes a fix awaiting App Review. | Provider variance and background limits must be explicit user-facing caveats. |
| [Limits](https://apps.apple.com/tr/app/limits-ai-usage-tracker/id6783130074?platform=watch&see-all=reviews) | iPhone/Apple Watch; price varies by storefront | Listing markets live reset countdowns, widgets, and notifications; exact source is not disclosed | The accessible review sample was positive and too small to establish a recurring complaint. | Widget/Watch/reset-alert presentation is expected, but source transparency is a differentiator. |
| [SessionWatcher](https://sessionwatcher.com/) | macOS/Windows with iPhone/Watch beta; from US$6.99 on check date | Desktop tool data and provider credentials; summaries sync through the user's iCloud, with optional direct iPhone provider access | Public testimonials are positive; release notes show continuing fixes for iPhone connection state, inactive providers, and partial-window display. | A companion can work, but multiplies platforms, synchronization states, credentials, licensing, and support paths. |

Prior-art synthesis:

- `[observed]` Accurate products commonly depend on a browser session, CLI OAuth token, or provider-specific endpoint.
- `[observed]` Expired credentials, Cloudflare/security checks, background refresh, and mismatched estimates recur across public troubleshooting material.
- `[observed]` Widgets, reset notifications, pace indicators, multiple windows, and watch surfaces are the common presentation set.
- `[inferred — confidence: high]` Reset Radar can differentiate on automatic but transparent, timestamped local observations without copied credentials; onboarding must not imply that a snapshot is continuously authoritative while the Mac or CLI is offline.

## 7. Owner-approved scope and non-goals

The owner resolved the research questions in [Phase 1 owner decisions](../../phase-1/owner-decisions.md). The resulting scope is mirrored in [product-behavior.md](../../product-behavior.md).

### First version

- `[inferred — confidence: high]` Store a timestamped percentage-used observation and optional absolute provider reset independently for every open-ended source window, with provenance and explicit freshness or availability.
- `[documented]` Exclude manual percentage entry and manual reset rules; the later architecture interview superseded the earlier blank-manual-ChatGPT and recurrence decisions.
- `[documented]` Offer per-window opt-in reset notifications, configurable widgets, user-started Live Activities for eligible short windows, and a read-only App Intent.
- `[documented]` Include an Apple Watch app with the same two-by-two standard-window grid, product-scoped details, one configurable complication, and an offline cache received through iPhone.
- `[inferred — confidence: high]` Collect coding-allowance state on one authoritative Mac through installed first-party Codex and Claude Code interfaces and synchronize only normalized, application-encrypted snapshots to iPhone. Adopt the conditionally approved Cloudflare transport only after its spike passes; require no Reset Radar account, analytics, copied vendor credential, or server-side content key.
- `[documented]` Ship the Mac collector and pairing flow with the first usable version, and use foreground/manual plus opportunistic background refresh without reserving APNs support.

### Non-goals

- `[inferred — confidence: high]` No claim that local token/message counts equal provider allowance consumption.
- `[inferred — confidence: high]` No session cookie, password, copied OAuth token, DOM scraping, or undocumented consumer endpoint.
- `[inferred — confidence: high]` No Team, Business, Enterprise, Edu, or administrator-managed defaults.
- `[documented]` No API-key mode, percentage threshold alerts, percentage history, pace or exhaustion forecasts, or dependable push backend in the first version.
- `[documented]` No manual percentage entry, manual reset rule, or broader ChatGPT/Claude consumer-usage entry.
- `[inferred — confidence: high]` No private consumer endpoint. The Mac collector is required for automatic coding-allowance percentages.
- `[documented]` No App Store or TestFlight distribution; use the owner's free Apple account and Sideloadly as specified in [personal-use-sideloading.md](personal-use-sideloading.md).
- `[inferred — confidence: high]` No vendor marks in the app name or icon, and no claim of affiliation.

## 8. Owner decisions and risks

| ID | Owner decision | Consequence for P1-M2 |
|---|---|---|
| Q2 | Permanently exclude consumer passwords, session cookies, and OAuth tokens; an exception requires a new owner decision and written vendor authorization. | Credential boundary and data sources. |
| Q3 | Exclude API-key support and do not reserve architecture for it. | Source protocol shape. |
| Q5 | Remove manual percentage and reset-rule entry entirely, superseding the earlier blank setup decision. | Provider-reported observations and absolute reset instants only. |
| Q6 | Keep the Reset Radar name, use a neutral original icon, and use service names only as descriptive interface text without implied affiliation. | Bundle identity and UI assets. |
| Q7 | Include Live Activities for eligible short windows; keep weekly windows in the app and widgets. | Target and surface design; lifecycle behavior requires a spike. |
| Q8 | Store provider resets as absolute instants, present them in the OS-local zone, and maintain at most one opt-in notification for each standard Home window. | Scheduling model and tests. |
| Q10 | Exclude threshold alerts, percentage history, pace labels, and exhaustion forecasts. Keep only the latest valid observation and its provenance and freshness. | Observation retention, notifications, and presentation. |
| Q11 | Conditionally approve the encrypted Cloudflare relay, one authoritative Mac, and foreground/manual plus opportunistic background refresh with no APNs reservation. Exact source thresholds come from P1-M2 tests. | Synchronization, security, cost, deployment, and freshness. |

Resolved during this research:

- `[documented]` Former Q1/Q9 asked whether consumer percentage data was manual. The owner now excludes manual entry. The selected sources are Codex app-server and Claude Code status-line snapshots on Mac.
- `[documented]` Former Q4 asked whether to support multiple arbitrary windows. The owner requires simultaneous usage tracking such as five-hour and weekly percentages used, so the model must support multiple independent windows without a fixed two-field schema.
- `[documented]` An earlier question asked for Claude's weekly anchor. Claude now documents that paid weekly limits reset at a fixed account-assigned day/time, unchanged by session or subscription start, and visible in Settings > Usage. Reset Radar uses the automatic source's instant when present and shows it unavailable when absent.

Risks:

- `[documented]` Vendor plans and limits changed during 2026 and may change again.
- `[inferred — confidence: high]` Automatic snapshots can be wrong or stale when a CLI is offline, the Mac sleeps, schemas change, or provider surfaces disagree; the UI must show provenance, observation time, and unavailable state.
- `[documented]` Focus, notification settings, and system presentation affect whether a scheduled notification interrupts the user.
- `[inferred — confidence: high]` Automatic tracking makes the Mac collector, CLI compatibility, secure local synchronization, and stale-state recovery part of the core product rather than optional complexity.
- `[inferred — confidence: high]` Cloudflare improves store-and-forward availability but creates a public endpoint, a deployment lifecycle, a metadata processor, and a new quota/outage dependency. It does not improve iOS background wake-up.
- `[observed]` Provider percentages can be missing, rounded, stale, or inconsistent across first-party surfaces. Every observation needs a timestamp, source, and unavailable/stale state; see [usage-tracking.md](usage-tracking.md).
- `[inferred — confidence: medium]` Trademark and nominative-use review remains a legal/store-review risk even with a neutral bundle name.
- `[documented]` Free Personal Team provisioning expires every seven days. Sideloadly can automate refresh, but physical-device validation must prove extension signing, App Group sharing, and data-preserving refresh on the owner's device.

Proposed experiments, not performed here:

- `[inferred — confidence: high]` Test absolute notification replacement, cancellation, expiry, denial, and OS-local rendering after clock or time-zone changes.
- `[inferred — confidence: high]` Validate widget timer rendering at reset and after a device clock/time-zone change without relying on a timeline reload.
- `[inferred — confidence: high]` Test usage observation clamping, orientation, stale transitions, missing windows, and reset-cycle boundaries without fabricating a 0% value at a predicted reset.
- `[inferred — confidence: high]` Complete the synthetic-data Cloudflare, cellular, quota, deletion, and deployment checks in [cloudflare-synchronization.md](cloudflare-synchronization.md) before the conditionally approved transport becomes final or receives real usage data.

## 9. Research completion audit

`[inferred — confidence: high]` No additional broad public-source survey is needed. The owner decisions are recorded; the remaining work is bounded live or platform validation:

| Area | Public research result | Remaining evidence |
|---|---|---|
| Automatic scope | `[documented]` Codex app-server and Claude Code expose coding-allowance state. No supported source was found for every general ChatGPT or Claude web/mobile allowance. | The owner accepted coding-only automatic scope. UI copy and tests must never generalize it. |
| Cloudflare relay | `[documented]` Workers plus a SQLite Durable Object provide Free-plan, strongly consistent store-and-forward; [cloudflare-synchronization.md](cloudflare-synchronization.md) defines the threat, operations, and audited US$0 configuration. | The owner accepted the metadata boundary and one-Mac limit conditionally; complete the synthetic deployment, physical cellular test, and billing verification before final adoption. |
| Provider adapters | `[documented]` Current source schemas and update triggers are pinned in [upstream-automatic-usage-sources.md](upstream-automatic-usage-sources.md). | Owner-approved smoke test against installed signed-in tools without logging raw responses or credentials. |
| Claude status line | `[documented]` The status-line payload is the narrow credential-free export path. | Prove installation preserves an existing user status line, writes atomically, and becomes stale correctly without generating a Claude turn. |
| Mac lifecycle | `[documented]` `SMAppService` is Apple's macOS 13+ API for login items and launch agents; Developer ID notarization is the recommended outside-store distribution path but requires paid-program credentials. | The owner chose local development signing without first-version notarization or an automatic updater; prove launch-at-login, Gatekeeper instructions, CLI child-process access, update safety, and uninstall cleanup on the owner's Mac. |
| Apple-device signing | `[documented]` Free provisioning, App Groups, Sideloadly, WidgetKit, and the first-version Apple Watch decision are recorded in [personal-use-sideloading.md](personal-use-sideloading.md). | Physical iPhone and paired-watch signing and seven-day refresh cycle, including Keychain/cache/widget/notification/watch-state preservation. |
| Reset scheduling | `[documented]` Local notifications persist once scheduled, while background execution is not timely. | Test at most four absolute per-window requests for replacement, cancellation, expiry, authorization, clock changes, and OS-local presentation. |

Q2, Q3, Q5 to Q8, Q10, and Q11 are resolved in [Phase 1 owner decisions](../../phase-1/owner-decisions.md). More research should be commissioned only if validation fails or the owner changes a decided boundary—for example, multiple publishing Macs, dependable background alerts, API-key mode, or general ChatGPT/Claude automatic coverage.

## Source register

All sources below were checked on 2026-10-19. Volatile sources are marked for recheck before implementation freezes defaults.

| Source | Evidence used | Volatility |
|---|---|---|
| [Claude pricing](https://claude.com/pricing) | Individual plan inventory, five-hour model, relative capacity | High |
| [Claude Pro plan](https://support.claude.com/en/articles/8325606-what-is-the-pro-plan) | Five-hour and fixed weekly reset; Settings > Usage | High |
| [Claude Max plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan) | Max 5x/20x tiers and relative capacity | High |
| [Claude usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans) | Paid clocks and separate Fable weekly limit | High |
| [Claude usage best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | Usage dashboard contents | High |
| [Anthropic API rate limits](https://platform.claude.com/docs/en/api/rate-limits) | Token bucket and reset headers | Medium |
| [Anthropic Consumer Terms](https://www.anthropic.com/legal/consumer-terms) | Scraping, automation, credential, and brand restrictions | Medium; recheck terms date |
| [ChatGPT Free Tier FAQ](https://help.openai.com/en/articles/9275245-using-chatgpt-s-free-tier-faq) | Free limit categories and in-product reset display | High |
| [ChatGPT Go](https://help.openai.com/en/articles/11989085-what-is-chatgpt-go) | Go plan and feature-limit model | High |
| [ChatGPT Plus](https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus) | Plus price and variable limits | High |
| [ChatGPT Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers) | Pro 100/200/500 and changing allowances | Very high |
| [GPT-5.6 and GPT-6 Pro](https://help.openai.com/en/articles/20001354-gpt-56-and-gpt-6-pro-in-chatgpt) | Per-model daily/weekly/shared allowances | Very high |
| [Paid Work/Codex resets](https://help.openai.com/en/articles/20001507-paid-weekly-work-and-codex-rate-limit-resets) | Five-hour/weekly clocks and purchased-reset anchor | Very high |
| [OpenAI API rate limits](https://developers.openai.com/api/docs/guides/rate-limits) | Reset and retry headers | Medium |
| [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/) | Automated extraction restriction | Medium; recheck terms date |
| Apple documentation linked in sections 4 and 5 | Platform capabilities, limits, and Keychain behavior | Low to medium |
| [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Guidelines 2.5, 4.1, 4.5, 5.1, and 5.2 | Medium; recheck before submission |
| [Personal-use sideloading study](personal-use-sideloading.md) | Apple Personal Team limits; Sideloadly and LiveContainer comparison | High; recheck before physical-device validation |
| [Usage-tracking study](usage-tracking.md) | Remaining-percentage semantics, consumer/API acquisition options, prior-art failure modes, and data-model consequences | High; recheck before implementation freezes sources |
| [Automatic usage acquisition](automatic-usage-acquisition.md) | Recent GitHub code audit; Codex app-server, Claude status-line, and desktop-to-mobile security selection | High; recheck against installed CLI versions before implementation |
| [Pinned upstream source audit](upstream-automatic-usage-sources.md) | Exact Codex and Claude Code revisions; percentage/reset schemas, update triggers, missing-data rules, and compatibility fixtures | High; recheck on every supported CLI upgrade |
| [Mobile-network synchronization](mobile-network-synchronization.md) | Cloudflare primary candidate, iCloud Drive/Tailscale fallbacks, encryption boundary, and cellular/background constraints | Medium; recheck pricing and free-account capabilities before implementation |
| [Cloudflare synchronization](cloudflare-synchronization.md) | Durable Object selection, relay protocol, pairing, threat model, limits, privacy, operations, deletion, US$0 cost contract, hidden-fee audit, and validation spike | High; recheck Cloudflare pricing, logging defaults, and platform limits before deployment |
| [Apple `SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice) | Current login-item and launch-agent registration API | Low to medium |
| [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | Developer ID, hardened-runtime, Gatekeeper, and notarization boundary | Medium; recheck if Mac distribution expands beyond the owner |
| Prior-art pages linked in section 6 | Product behavior and public issue/review signals | High |
