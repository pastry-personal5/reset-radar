# Mac Keychain access without prompts

Status: Active

How the Mac collector stores its relay secrets so it never shows a Keychain dialog, including across rebuilds. The research compares the options and records the owner's choice. It also defines the validation spike that must confirm the claims not yet proven on the owner's Mac.

Checked on 2026-10-19 against Apple's current documentation (fetched through Context7) and the owner's Mac.

## 1. Problem

The Mac app holds the relay content key, the write and administration tokens, every registered read token, and the account-scope secret. It runs unattended as a login item, so any Keychain dialog stalls publication until the owner answers it.

On 2026-10-19 the owner's Mac had **no code-signing identity**: `security find-identity -v -p codesigning` reported zero valid identities. Every build would therefore be ad-hoc signed, and ad-hoc signing breaks Keychain access on every rebuild.

## 2. Background

**Two implementations.**
- `[documented]` macOS has a file-based keychain and a data-protection keychain. `SecItem` calls target the file-based keychain unless `kSecUseDataProtectionKeychain` or `kSecAttrSynchronizable` is set (TN3137).

**Data-protection keychain.**
- `[documented]` Data-protection items are scoped by access groups. On macOS, the `keychain-access-groups` entitlement is restricted and must be authorized by a provisioning profile (TN3125).
- `[documented]` An App Group identifier can also serve as an access group ("Sharing access to keychain items among a collection of apps").

**File-based keychain.**
- `[documented]` A code signature's designated requirement is the rule the system uses to decide whether two builds are the same code (TN3127).
- `[inferred — confidence: high]` File-based items carry an access list naming trusted applications by their designated requirement. An Apple Development-signed app's requirement names its bundle identifier and signing certificate, so a rebuild satisfies it. An ad-hoc signature's requirement is its own code hash, so every rebuild is a different application and access needs a dialog.
- `[inferred — confidence: medium]` The file-based keychain also checks a partition list, such as `teamid:<team>`. Ad-hoc code has no team identifier, which is a second reason it prompts.

**Suppressing dialogs.**
- `[documented]` `kSecUseAuthenticationUISkip` skips items that require user authentication.
- `[documented gap]` No document fetched for this review states which API suppresses the file-based keychain's access-confirmation dialog and returns an error instead. The spike in section 5 must determine it.

## 3. Options

| Option | How it avoids prompts | Cost or risk | Result |
|---|---|---|---|
| **A. Stable Apple Development signing with the login keychain** | Every build is signed by one Personal Team identity, so the designated requirement and team stay stable across rebuilds and updates. All calls are non-interactive. | Needs an identity created once in Xcode. A changed identity, certificate, or bundle identifier breaks access, and recovery is re-pairing. | **Selected by the owner on 2026-10-19.** |
| B. Owner-only file, no Keychain | Secrets live in a `0600` file in Application Support, excluded from backup. No Keychain call exists. | Any process running as the owner can read the file. Drops the "Keychain, never files" rule on Mac. | Rejected by the owner. |
| C. Data-protection keychain with a provisioning profile | Access groups replace access lists, so the signing certificate stops mattering. | Requires a profile-authorized entitlement. A free-account profile is assumed to expire weekly, which would stop a login item from launching. That is confirmed for iOS, not yet for macOS (section 5, step 8). | Rejected unless step 8 shows otherwise. |
| D. Access list opened to all applications | No dialog for any application. | Uses deprecated `SecAccess` APIs and exposes the secrets to every process. | Rejected. |
| E. Custom keychain file with a known password | Unlocked programmatically. | `SecKeychainCreate` is deprecated in the macOS 12 SDK, and the stored password protects nothing. | Rejected. |

## 4. Selected design

The design is option A, with three additions:

- **Build check.** A build phase rejects ad-hoc signing.
- **Isolation.** Debug builds use a separate Keychain service, and tests use an in-memory store.
- **Fail-fast recovery.** A failure that would need a dialog pauses publication and leads to a recovery screen instead of a prompt.
- **Running-process cache.** Once the signed app has read secrets successfully, a later login-Keychain lock does not evict the in-memory copy or pause publication. The recovery screen distinguishes this from a failed read at startup; the owner can quit the app to stop the running publisher.

The binding contract is in the [Mac app](../../architecture/mac-app.md#signing-and-keychain) and [Transport](../../architecture/transport.md#secret-store) architecture.

## 5. Validation spike

Run with a throwaway harness app on the owner's Mac, using synthetic secrets only. Record each result in [spike results](spike-results.md).

The owner-run [Mac Keychain validation spike runbook](mac-keychain-validation-spike-runbook.md) provides the isolated harness source, exact commands, observation rules, and cleanup sequence. It is an execution aid; this section remains the binding question and pass criterion.

1. **Identity.** Create the Personal Team Apple Development identity in Xcode. Record its type and team identifier, but not the certificate's personal name.
2. **Stable rebuild.** Sign the harness with that identity, create an item, change the code, rebuild, and read the item again. Record `codesign -d -r-` output with the personal name redacted, and whether any dialog appeared.
3. **Ad-hoc failure.** Build the harness ad-hoc and read the same item with each candidate non-interactive mechanism:
   - `kSecUseAuthenticationUISkip`;
   - an `LAContext` with interaction not allowed; and
   - `SecKeychainSetUserInteractionAllowed(false)`.

   For each, record whether a dialog appeared and which status was returned. Select the mechanism that returns an error with no dialog.
4. **Login launch.** Reboot, let the harness start as a login item, and confirm it reads without a dialog.
5. **Locked keychain.** Lock the login keychain, read, and record the status. Note whether it can be told apart from step 3's status.
   Also lock it after a successful harness read and confirm that the documented in-memory cache continues without another Keychain read; quit and relaunch while still locked to confirm publication cannot restart from an empty cache.
6. **Lifetime.** At least eight days after signing, confirm the harness still launches and reads without a dialog.
7. **Certificate renewal.** If Xcode issues a new development certificate (for example after revoking the old one), record whether existing items are still readable. If not, confirm the recovery path works.
8. **Profile expiry.** Add a profile-requiring capability to a copy of the harness, and record the embedded profile's expiry and the launch behavior after it.

The spike passes when steps 2, 4, and 6 read without any dialog and step 3 returns an error with no dialog. Any other result returns the storage decision to the owner.

## Sources

- [TN3137: On Mac keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains): the file-based and data-protection keychains, and `SecItem` targeting.
- [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles): restricted entitlements on macOS, including `keychain-access-groups`.
- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements): designated requirements.
- [`kSecUseDataProtectionKeychain`](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain): data-protection behavior on macOS.
- [Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps): access groups, including App Group identifiers.
- [`kSecUseAuthenticationUISkip`](https://developer.apple.com/documentation/security/ksecuseauthenticationuiskip): skipping items that require authentication.
