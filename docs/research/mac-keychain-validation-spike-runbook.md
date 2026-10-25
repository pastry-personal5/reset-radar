# Mac Keychain validation spike runbook

Status: Active

This owner-run procedure creates a short-lived, signed macOS app bundle that holds one generated synthetic Keychain value. It validates the P1-M2 Mac Keychain contract without creating the production project, connecting to the relay, or accessing Codex, Claude Code, or any real secret.

## 1. Authority, scope, and stop conditions

Run this only on the owner's Mac and only with the owner present. The harness and every file it writes live under the owner's local Application Support directory, never in this repository. It is test code: do not merge it, distribute it, or promote it to the production app without separate P1-M3 review.

The harness creates one 32-byte random value in the login Keychain. It never prints, exports, transmits, or logs that value. It does not use a provider credential, relay token, account identifier, real usage response, entitlement from Reset Radar, Keychain access group, App Group, or a data-protection Keychain item.

Stop, leave the P1-M2 validation item unchecked, and record the outcome as a failure or deferral if any of the following happens:

- The only available signing choice is ad hoc, or the selected identity is not an **Apple Development** identity belonging to the owner's Personal Team.
- The signed harness shows a Keychain access dialog after a rebuild, when launched at login, or at the eight-day check.
- An ad-hoc or prelaunch-locked read can succeed only by approving a dialog. Never approve such a dialog; dismiss it and record that it appeared.
- A command would require a provider credential, a real relay secret, a Cloudflare login, an entitlement from the production app, or a new dependency/build tool.
- The Keychain cannot be unlocked again by the owner through Keychain Access, or a command would affect an item other than the harness's synthetic service.

This runbook validates the selected login-Keychain design from [Mac Keychain access](mac-keychain-access.md) and the contracts in [Mac app](../architecture/mac-app.md#signing-and-keychain) and [Transport](../architecture/transport.md#secret-store). It does not validate iOS Keychain access, App Groups, the relay, or production `SMAppService` UI; P1-M3 validates those in the real targets.

## 2. What counts as evidence

The owner must observe whether a dialog appears; command output cannot prove its absence. Record no screenshots containing a dialog, certificate personal name, account identifier, or Keychain value.

For each action, record the following in a private worksheet while it runs:

| Field | Record |
|---|---|
| Date and attendance | UTC date/time and `owner-present` |
| Environment | macOS, Xcode, Swift compiler version |
| Signing | `Apple Development` type, redacted team identifier, and whether Hardened Runtime is present |
| Harness run | Generated run identifier, mode, UI policy, and signed or ad-hoc build |
| Observation | Returned status, process exit status, and whether a Keychain dialog appeared |
| Result | Pass, fail, or deferred plus the specific blocker |

At completion, add a dated redacted summary to [spike-results.md](spike-results.md), using its entry template. Do not add a result before the test has actually run.

## 3. Prerequisites and safe environment capture

Close screen sharing and terminal recording before starting. Do not enable shell tracing (`set -x`). This spike does not use a password in a command, environment variable, file, or clipboard.

First save work and inspect the available identities. This prints certificate subjects to the terminal; do not copy its raw output into project evidence.

```zsh
sw_vers
xcodebuild -version
xcrun swiftc --version
security find-identity -v -p codesigning
```

In the last command's output, find the SHA-1 fingerprint for the owner's Personal Team `Apple Development` identity. Do not use `Sign to Run Locally`, `-`, a distribution identity, or a certificate belonging to another team. Paste only that fingerprint into this shell variable; a fingerprint is an identifier, not a secret.

```zsh
keychain_spike_identity='PASTE_THE_40_HEX_FINGERPRINT_HERE'
security find-identity -v -p codesigning | grep -F -- "$keychain_spike_identity"
```

If the second command produces no matching `Apple Development` line, stop. Create the owner's Personal Team development identity in Xcode first, then restart this procedure. Do not substitute another signing mode.

Create a private, per-run directory and an identifier for this run. The directory is deliberately outside the checkout and is mode `0700`.

```zsh
keychain_spike_run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
keychain_spike_root="$HOME/Library/Application Support/ResetRadarSpikes/MacKeychain/$keychain_spike_run_id"
keychain_spike_active_config="$HOME/Library/Application Support/ResetRadarSpikes/MacKeychain/active.json"
keychain_spike_app="$keychain_spike_root/KeychainSpike.app"
keychain_spike_binary="$keychain_spike_app/Contents/MacOS/KeychainSpike"
keychain_spike_adhoc_app="$keychain_spike_root/KeychainSpikeAdHoc.app"
keychain_spike_adhoc_binary="$keychain_spike_adhoc_app/Contents/MacOS/KeychainSpike"
mkdir -p "$keychain_spike_app/Contents/MacOS"
chmod 700 "$keychain_spike_root"
printf 'run=%s\nstarted_utc=%s\n' "$keychain_spike_run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$keychain_spike_root/run.txt"
```

Only one Keychain spike may be active at once, because the app's login-launch mode reads the `active.json` pointer below. Stop if a prior active run has not been cleaned up:

```zsh
if [ -e "$keychain_spike_active_config" ]; then
  printf 'An earlier Keychain spike is still active: %s\n' "$keychain_spike_active_config" >&2
  exit 1
fi
```

## 4. Create the disposable harness

The following commands create an actual `.app` bundle rather than a bare command-line executable, so `SMAppService.mainApp` can register it for the login-launch observation. `LSUIElement` prevents it from opening a normal Dock application window.

Create its harmless configuration. The service name and paths are not secrets. The synthetic Keychain bytes are generated inside the process and never appear in this file.

```zsh
keychain_spike_service="org.reset-radar.spike.keychain.$keychain_spike_run_id"
cat > "$keychain_spike_root/config.json" <<EOF
{
  "service": "$keychain_spike_service",
  "account": "synthetic-secret",
  "reportPath": "$keychain_spike_root/harness-report.log"
}
EOF
cp "$keychain_spike_root/config.json" "$keychain_spike_active_config"
chmod 600 "$keychain_spike_root/config.json" "$keychain_spike_active_config"
plutil -lint "$keychain_spike_root/config.json"
```

Create the bundle metadata:

```zsh
cat > "$keychain_spike_app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>KeychainSpike</string>
  <key>CFBundleIdentifier</key>
  <string>org.reset-radar.spike.keychain</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>KeychainSpike</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.7.1</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF
plutil -lint "$keychain_spike_app/Contents/Info.plist"
```

Create the harness source. Its `create` action writes a non-synchronizing 32-byte generated item to the default file-based login Keychain; it deliberately omits `kSecUseDataProtectionKeychain`. `read` reports only the item length and Security status. `cache-wait` intentionally performs exactly one Keychain read, waits for a non-secret signal file, and then uses its in-memory `Data` value without another Keychain call.

```zsh
cat > "$keychain_spike_root/KeychainSpike.swift" <<'EOF'
import Darwin
import Foundation
import LocalAuthentication
import Security
import ServiceManagement

private let buildMarker = "initial"

private struct Configuration: Decodable {
  let service: String
  let account: String
  let reportPath: String
}

private enum InteractionPolicy: String {
  case skip
  case context
  case legacy
}

private enum ProbeError: Error {
  case invalidArguments(String)
  case configuration(String)
  case security(OSStatus)
}

private func value(after flag: String, in arguments: [String]) -> String? {
  guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
    return nil
  }
  return arguments[index + 1]
}

private func statusText(_ status: OSStatus) -> String {
  let message = SecCopyErrorMessageString(status, nil) as String? ?? "unmapped Security status"
  return "status=\(status) message=\(message)"
}

private func appendReport(_ configuration: Configuration, _ line: String) {
  let timestamp = ISO8601DateFormatter().string(from: Date())
  let output = "\(timestamp) \(line)\n"
  print(output, terminator: "")

  let url = URL(fileURLWithPath: configuration.reportPath)
  do {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(output.utf8)
    if FileManager.default.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } else {
      try data.write(to: url, options: .atomic)
    }
  } catch {
    print("report-write-failed error=\(error.localizedDescription)")
  }
}

private func loadConfiguration(arguments: [String]) throws -> Configuration {
  let configPath = value(after: "--config", in: arguments)
    ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/ResetRadarSpikes/MacKeychain/active.json").path
  let url = URL(fileURLWithPath: configPath)
  do {
    return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
  } catch {
    throw ProbeError.configuration("cannot read configuration at \(configPath): \(error.localizedDescription)")
  }
}

private func itemQuery(_ configuration: Configuration, returnData: Bool) -> [String: Any] {
  var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: configuration.service,
    kSecAttrAccount as String: configuration.account,
    kSecAttrSynchronizable as String: false,
    kSecMatchLimit as String: kSecMatchLimitOne,
  ]
  if returnData {
    query[kSecReturnData as String] = true
  }
  return query
}

private func readItem(
  configuration: Configuration,
  policy: InteractionPolicy
) -> (OSStatus, Data?) {
  var query = itemQuery(configuration, returnData: true)
  var result: CFTypeRef?
  var legacyInteractionWasDisabled = false

  switch policy {
  case .skip:
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
  case .context:
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
  case .legacy:
    let settingStatus = SecKeychainSetUserInteractionAllowed(false)
    guard settingStatus == errSecSuccess else {
      return (settingStatus, nil)
    }
    legacyInteractionWasDisabled = true
  }

  defer {
    if legacyInteractionWasDisabled {
      _ = SecKeychainSetUserInteractionAllowed(true)
    }
  }

  let status = SecItemCopyMatching(query as CFDictionary, &result)
  return (status, result as? Data)
}

private func createItem(configuration: Configuration) -> OSStatus {
  let byteCount = 32
  var bytes = [UInt8](repeating: 0, count: byteCount)
  let randomStatus = bytes.withUnsafeMutableBytes { buffer in
    SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
  }
  guard randomStatus == errSecSuccess else {
    return randomStatus
  }

  var query = itemQuery(configuration, returnData: false)
  query[kSecValueData as String] = Data(bytes)
  return SecItemAdd(query as CFDictionary, nil)
}

private func deleteItem(configuration: Configuration) -> OSStatus {
  var query = itemQuery(configuration, returnData: false)
  query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
  return SecItemDelete(query as CFDictionary)
}

private func requireSuccess(_ status: OSStatus) throws {
  guard status == errSecSuccess else {
    throw ProbeError.security(status)
  }
}

private func run() throws -> Int32 {
  let arguments = Array(CommandLine.arguments.dropFirst())
  let mode = value(after: "--mode", in: arguments) ?? "login-read"
  let configuration = try loadConfiguration(arguments: arguments)

  switch mode {
  case "create":
    let status = createItem(configuration: configuration)
    appendReport(configuration, "action=create build=\(buildMarker) \(statusText(status))")
    try requireSuccess(status)

  case "read":
    guard let rawPolicy = value(after: "--policy", in: arguments), let policy = InteractionPolicy(rawValue: rawPolicy) else {
      throw ProbeError.invalidArguments("read requires --policy skip, context, or legacy")
    }
    let (status, data) = readItem(configuration: configuration, policy: policy)
    let length = data?.count ?? 0
    appendReport(configuration, "action=read policy=\(policy.rawValue) build=\(buildMarker) length=\(length) \(statusText(status))")
    try requireSuccess(status)
    guard length == 32 else {
      throw ProbeError.invalidArguments("read returned an unexpected synthetic item length")
    }

  case "cache-wait":
    guard let rawSignal = value(after: "--signal", in: arguments) else {
      throw ProbeError.invalidArguments("cache-wait requires --signal PATH")
    }
    let signalURL = URL(fileURLWithPath: rawSignal)
    let readyURL = URL(fileURLWithPath: rawSignal + ".ready")
    let (status, data) = readItem(configuration: configuration, policy: .skip)
    appendReport(configuration, "action=cache-first-read length=\(data?.count ?? 0) \(statusText(status))")
    try requireSuccess(status)
    guard let cachedData = data, cachedData.count == 32 else {
      throw ProbeError.invalidArguments("cache first read returned an unexpected synthetic item length")
    }
    FileManager.default.createFile(atPath: readyURL.path, contents: Data())
    let deadline = Date().addingTimeInterval(600)
    while !FileManager.default.fileExists(atPath: signalURL.path), Date() < deadline {
      Thread.sleep(forTimeInterval: 1)
    }
    guard FileManager.default.fileExists(atPath: signalURL.path) else {
      throw ProbeError.invalidArguments("cache-wait timed out without a signal")
    }
    appendReport(configuration, "action=cache-use no-second-keychain-read=true length=\(cachedData.count) status=0")

  case "login-register":
    if #available(macOS 13.0, *) {
      let service = SMAppService.mainApp
      if service.status != .enabled {
        try service.register()
      }
      appendReport(configuration, "action=login-register status=\(service.status)")
    } else {
      throw ProbeError.invalidArguments("SMAppService.mainApp requires macOS 13 or later")
    }

  case "login-status":
    if #available(macOS 13.0, *) {
      appendReport(configuration, "action=login-status status=\(SMAppService.mainApp.status)")
    } else {
      throw ProbeError.invalidArguments("SMAppService.mainApp requires macOS 13 or later")
    }

  case "login-unregister":
    if #available(macOS 13.0, *) {
      let service = SMAppService.mainApp
      if service.status != .notRegistered {
        try service.unregister()
      }
      appendReport(configuration, "action=login-unregister status=\(service.status)")
    } else {
      throw ProbeError.invalidArguments("SMAppService.mainApp requires macOS 13 or later")
    }

  case "delete":
    let status = deleteItem(configuration: configuration)
    appendReport(configuration, "action=delete \(statusText(status))")
    try requireSuccess(status)

  case "login-read":
    let (status, data) = readItem(configuration: configuration, policy: .skip)
    appendReport(configuration, "action=login-read policy=skip build=\(buildMarker) length=\(data?.count ?? 0) \(statusText(status))")
    try requireSuccess(status)
    guard data?.count == 32 else {
      throw ProbeError.invalidArguments("login read returned an unexpected synthetic item length")
    }

  default:
    throw ProbeError.invalidArguments("unknown --mode \(mode)")
  }

  return EXIT_SUCCESS
}

do {
  exit(try run())
} catch ProbeError.security(let status) {
  fputs("KeychainSpike failed: \(statusText(status))\n", stderr)
  exit(EXIT_FAILURE)
} catch {
  fputs("KeychainSpike failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
EOF
```

Build and sign the app with the selected identity. This uses the current macOS SDK and has no entitlement file, profile, package, or third-party dependency.

```zsh
xcrun --sdk macosx swiftc \
  -framework Security \
  -framework LocalAuthentication \
  -framework ServiceManagement \
  "$keychain_spike_root/KeychainSpike.swift" \
  -o "$keychain_spike_binary"
codesign --force --sign "$keychain_spike_identity" --options runtime --timestamp=none "$keychain_spike_app"
codesign --verify --strict --verbose=2 "$keychain_spike_app"
codesign -dvv "$keychain_spike_app" 2>&1 | awk -F= '/^(Identifier|TeamIdentifier|Runtime)=/ { print }'
codesign -d -r- "$keychain_spike_app" 2>&1
```

The last command is the designated requirement evidence. It can include a certificate personal name. Review it on screen, record a redacted form in the worksheet, and do not copy the unredacted output into `spike-results.md`.

## 5. Step 1 and 2: create under stable signing, then rebuild

Create the synthetic item once with the Apple Development-signed app. A successful result must say `length=32`; it never contains the generated value.

```zsh
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode create
```

Change only the marker, rebuild, re-sign with the exact same identity, and read the original item using the first non-interactive candidate. Watch for a dialog during the read. If one appears, dismiss it rather than approving access.

```zsh
perl -0pi -e 's/buildMarker = "initial"/buildMarker = "rebuild"/' "$keychain_spike_root/KeychainSpike.swift"
xcrun --sdk macosx swiftc \
  -framework Security \
  -framework LocalAuthentication \
  -framework ServiceManagement \
  "$keychain_spike_root/KeychainSpike.swift" \
  -o "$keychain_spike_binary"
codesign --force --sign "$keychain_spike_identity" --options runtime --timestamp=none "$keychain_spike_app"
codesign --verify --strict --verbose=2 "$keychain_spike_app"
codesign -dvv "$keychain_spike_app" 2>&1 | awk -F= '/^(Identifier|TeamIdentifier|Runtime)=/ { print }'
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
```

Record the dialog observation and exit status. This step passes only when the rebuilt signed app reads the item successfully with no dialog.

## 6. Step 3: compare ad-hoc non-interactive candidates

Make an ad-hoc copy of the app. Do not run its `create` mode and do not approve any Keychain prompt; it must only attempt reads of the item created above.

```zsh
ditto "$keychain_spike_app" "$keychain_spike_adhoc_app"
codesign --force --sign - --timestamp=none "$keychain_spike_adhoc_app"
codesign --verify --strict --verbose=2 "$keychain_spike_adhoc_app"
codesign -dvv "$keychain_spike_adhoc_app" 2>&1 | awk -F= '/^(Signature|Identifier|TeamIdentifier|Runtime)=/ { print }'
```

Run all three candidates one at a time. A nonzero exit status is expected for a safe failure. For each command, note whether macOS displayed a dialog before the command returned. If a dialog appears, click **Deny** or **Cancel**, never **Allow**.

The compiler will warn that `SecKeychainSetUserInteractionAllowed` is deprecated. That warning is expected: this candidate is explicitly required for comparison with the two modern per-query mechanisms. It is test-only and does not authorize use of the deprecated API in production.

```zsh
"$keychain_spike_adhoc_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
printf 'exit=%s policy=skip\n' "$?"

"$keychain_spike_adhoc_binary" --config "$keychain_spike_root/config.json" --mode read --policy context
printf 'exit=%s policy=context\n' "$?"

"$keychain_spike_adhoc_binary" --config "$keychain_spike_root/config.json" --mode read --policy legacy
printf 'exit=%s policy=legacy\n' "$?"
```

`legacy` restores `SecKeychainSetUserInteractionAllowed(true)` before the process exits, even on a failed read. If the process is interrupted, run this harmless recovery command from the still-signed harness before continuing:

```zsh
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy legacy
```

Choose the candidate that returns an error without a dialog. The production design remains unresolved if none does. Record the Security status for all three, even if one candidate is selected.

## 7. Step 4: login launch

The signed harness registers itself through `SMAppService.mainApp`. Record the status. If System Settings asks for approval of the login item, that is a login-item authorization, not a Keychain access dialog; approve or deny it deliberately and record the outcome.

```zsh
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode login-register
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode login-status
```

Restart the Mac manually from the Apple menu after saving other work. Do not use a password-bearing shell command to unlock the Keychain after restart. Log in normally, wait 30 seconds, then run:

```zsh
cat "$keychain_spike_root/harness-report.log"
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode login-status
```

The report must include an `action=login-read` success with `policy=skip` and `length=32`. Observe that no Keychain dialog appeared at login. A successful login registration alone is insufficient; the automatic read must succeed.

## 8. Step 5: locked Keychain behavior

Use Keychain Access to unlock the login keychain before beginning this section. Do not run `security unlock-keychain` with a password in the shell.

### 8.1 Lock before a fresh read

Lock the default login keychain, then attempt a new signed-process read. The command may return a nonzero exit status; record it and confirm that no dialog appeared.

```zsh
security lock-keychain
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
printf 'exit=%s prelaunch-locked\n' "$?"
```

Manually unlock the login keychain in Keychain Access after this command finishes. Record whether the status can be distinguished from the selected ad-hoc failure status. The expected product behavior is an `interactionRequired`-class failure that pauses a new publisher, never a prompt or silent replacement.

### 8.2 Lock after an in-memory read

This proves the documented running-process cache behavior. The harness makes its only Keychain read before it signals readiness. After the login keychain is locked, the signal makes it use only the already-held `Data` value.

```zsh
keychain_spike_signal="$keychain_spike_root/cache-continue"
rm -f "$keychain_spike_signal" "$keychain_spike_signal.ready" "$keychain_spike_root/cache-wait.log"
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode cache-wait --signal "$keychain_spike_signal" > "$keychain_spike_root/cache-wait.log" 2>&1 &
keychain_spike_cache_pid="$!"
for keychain_spike_attempt in {1..30}; do
  [ -e "$keychain_spike_signal.ready" ] && break
  sleep 1
done
test -e "$keychain_spike_signal.ready"
security lock-keychain
touch "$keychain_spike_signal"
wait "$keychain_spike_cache_pid"
cat "$keychain_spike_root/cache-wait.log"
```

The final line must state `action=cache-use no-second-keychain-read=true length=32 status=0`. The owner must then prove that a new process cannot resume publication while the keychain remains locked:

```zsh
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
printf 'exit=%s relaunch-while-locked\n' "$?"
```

Unlock the login keychain manually with Keychain Access when these two observations are complete. The expected combination is: the already-running process uses its cache, but the later fresh process fails without a dialog.

## 9. Step 6: eight-day lifetime

Keep the signed app bundle and its synthetic Keychain item intact for at least eight complete 24-hour periods after the first `create` command. Do not rebuild it, change its bundle identifier, move it, delete its service, or run the cleanup section before this result is recorded.

At or after day eight, with the login keychain unlocked, run:

```zsh
date -u +%Y-%m-%dT%H:%M:%SZ
cat "$keychain_spike_root/run.txt"
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
printf 'exit=%s eight-day-read\n' "$?"
```

Record the elapsed time, status, and dialog observation. This passes only if the original signed harness reads the original synthetic item without a dialog.

## 10. Step 7 and 8: renewal and profile observations

These are observations, not permission to revoke a working personal certificate or change the production signing strategy.

### Certificate renewal

If Xcode naturally creates a new Apple Development certificate during this spike, record the before/after certificate fingerprints privately and repeat the signed `read --policy skip` command. If the existing item is no longer readable, stop and verify the owner recovery path: rebuild with the recorded identity when available, or delete the synthetic item and record that real relay setup would require re-pairing. Do not test recovery with real relay state.

### Profile expiry

The selected production design intentionally has no profile-requiring entitlement. To test the rejected alternative, create a separate copy of this harness in a temporary Xcode macOS App project, enable a capability that Xcode confirms requires a provisioning profile, and let Xcode manage signing. Do not add the entitlement to the signed harness above and do not reuse its synthetic Keychain service.

After Xcode produces a copy with `embedded.provisionprofile`, inspect only its expiry date:

```zsh
keychain_spike_profile_app='/ABSOLUTE/PATH/TO/THE/SEPARATE/PROFILED/HARNESS.app'
test -f "$keychain_spike_profile_app/Contents/embedded.provisionprofile"
security cms -D -i "$keychain_spike_profile_app/Contents/embedded.provisionprofile" > "$keychain_spike_root/profile.plist"
plutil -extract ExpirationDate raw "$keychain_spike_root/profile.plist"
rm -f "$keychain_spike_root/profile.plist"
```

Record the expiry and eventual launch behavior. If no separate profile-requiring harness can be created before P1-M3, record this sub-observation as deferred with that structural blocker. It does not alter the core pass criteria from [Mac Keychain access](mac-keychain-access.md#5-validation-spike).

## 11. Evidence entry and pass decision

Append a redacted entry like the following only after the applicable observations have happened:

```markdown
### Mac Keychain validation — YYYY-MM-DD

- **Attendance:** Owner-present.
- **Question:** Can one Apple Development-signed macOS app access its file-based login-Keychain item without a dialog after a rebuild, at login, and after eight days, while unsafe or unavailable access fails closed?
- **Method and versions:** macOS <version>; Xcode <version>; Swift <version>; throwaway `KeychainSpike.app`; synthetic 32-byte generic-password item; no profile, entitlement, relay, provider data, or network activity.
- **Measured values:** Stable rebuild: <status/no-dialog>; ad-hoc skip/context/legacy: <status and dialog outcome for each>; login: <status/no-dialog>; prelaunch lock: <status/no-dialog>; post-read lock cache: <result>; fresh relaunch while locked: <status/no-dialog>; elapsed lifetime: <duration/result>.
- **Result:** Pass, fail, or deferred. <If fail or deferred, name the exact condition and owner decision needed.>
```

The spike passes only when all of the following are observed:

1. The stable Apple Development-signed rebuild reads without a Keychain dialog.
2. The `SMAppService.mainApp` login launch reads without a Keychain dialog.
3. The eight-day signed harness read succeeds without a Keychain dialog.
4. At least one ad-hoc candidate returns an error without a dialog.
5. A Keychain locked before process launch prevents a fresh read without a dialog.
6. A process that read successfully before a later lock uses its cache, while a fresh process launched after that lock cannot read.

If any item fails, do not change the selected storage approach in code. Return the storage decision to the owner as required by [Mac Keychain access](mac-keychain-access.md#5-validation-spike).

## 12. Cleanup after the final evidence is recorded

Do not clean up until the eight-day result and any desired renewal/profile observations are recorded. The commands below unregister only this harness, remove only the synthetic item identified by its run-specific configuration, and delete only its run directory. They do not affect production Keychain items, provider credentials, or the relay.

First confirm the paths point to the expected run directory, then unregister the login item and delete the synthetic item:

```zsh
printf '%s\n' "$keychain_spike_root" "$keychain_spike_service" "$keychain_spike_app"
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode login-unregister
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode delete
"$keychain_spike_binary" --config "$keychain_spike_root/config.json" --mode read --policy skip
printf 'exit=%s expected-not-found-after-delete\n' "$?"
```

The final read must fail with an item-not-found-style status. Remove the active pointer only if it still points at this run, then delete the exact run directory:

```zsh
if cmp -s "$keychain_spike_root/config.json" "$keychain_spike_active_config"; then
  rm -f "$keychain_spike_active_config"
fi
rm -rf "$keychain_spike_root"
unset keychain_spike_cache_pid keychain_spike_signal keychain_spike_service
```

The deleted harness files are recoverable only from the owner's backups; the synthetic Keychain item has already been deleted by the harness. If the `delete` action fails, do not remove the run directory: retain it and record the cleanup failure so the owner can safely inspect the exact synthetic service later.
