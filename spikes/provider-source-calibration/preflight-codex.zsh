#!/bin/zsh

set -euo pipefail
umask 077

if (( $# != 1 )); then
  print -u2 -- "usage: zsh preflight-codex.zsh /private/tmp/reset-radar-source-calibration.XXXXXX/session.zsh"
  exit 2
fi
session_file="${1:A}"
if [[ "$session_file" != /private/tmp/reset-radar-source-calibration.*/session.zsh || ! -f "$session_file" ]]; then
  print -u2 -- "Refusing an unexpected session file."
  exit 1
fi
source "$session_file"
if [[ "$source_calibration_mode" != (codex|combined) ]]; then
  print -u2 -- "Disposable session has an invalid calibration mode."
  exit 1
fi
if (( ${#source_calibration_codex_launchers} == 0 \
    || ${#source_calibration_codex_launchers} != ${#source_calibration_codex_reports} )); then
  print -u2 -- "Disposable session has no valid codex-profile selections."
  exit 1
fi

for (( profile_index = 1; profile_index <= ${#source_calibration_codex_launchers}; profile_index += 1 )); do
  schema_root="$source_calibration_root/codex-$profile_index-schema"
  mkdir -p "$schema_root"
  (
    cd "$source_calibration_root"
    "${source_calibration_codex_launchers[$profile_index]}" \
      app-server generate-json-schema --out "$schema_root"
  )

  for required_file in \
    "$schema_root/ClientRequest.json" \
    "$schema_root/ClientNotification.json" \
    "$schema_root/v1/InitializeParams.json" \
    "$schema_root/v2/GetAccountResponse.json" \
    "$schema_root/v2/GetAccountRateLimitsResponse.json"; do
    [[ -f "$required_file" ]]
  done

  jq -e '
    (any(.. | objects; .const? == "account/read") or
      any(.. | arrays; index("account/read") != null)) and
    (any(.. | objects; .const? == "account/rateLimits/read") or
      any(.. | arrays; index("account/rateLimits/read") != null))
  ' "$schema_root/ClientRequest.json" >/dev/null
  jq -e '.required | index("clientInfo") != null' \
    "$schema_root/v1/InitializeParams.json" >/dev/null
  jq -e '
    (.required | index("requiresOpenaiAuth") != null) and
    (.properties.requiresOpenaiAuth.type == "boolean") and
    any(.definitions.Account.oneOf[]; .properties.type.enum == ["chatgpt"])
  ' "$schema_root/v2/GetAccountResponse.json" >/dev/null
  jq -e '
    (.required | index("rateLimits") != null) and
    (.properties.rateLimits != null) and
    (.properties.rateLimitsByLimitId != null) and
    (.properties.accountId.type | index("string") != null)
  ' "$schema_root/v2/GetAccountRateLimitsResponse.json" >/dev/null
  jq -e '
    any(.. | objects; .const? == "initialized") or
    any(.. | arrays; index("initialized") != null)
  ' "$schema_root/ClientNotification.json" >/dev/null
done

"$source_calibration_node" --check "$source_calibration_root/harness/codex-calibration.mjs"
"$source_calibration_node" --check "$source_calibration_root/harness/verify-reports.mjs"
if [[ "$source_calibration_mode" == combined ]]; then
  "$source_calibration_node" --check "$source_calibration_root/harness/claude-recorder.mjs"
  jq -e '.statusLine.type == "command"
    and (.statusLine.command | type == "string")
    and .statusLine.refreshInterval == 30' \
    "$source_calibration_root/claude-a-settings.json" >/dev/null
  jq -e '.statusLine.type == "command"
    and (.statusLine.command | type == "string")
    and .statusLine.refreshInterval == 30' \
    "$source_calibration_root/claude-b-settings.json" >/dev/null
fi

print -- "Installed Codex schemas for ${#source_calibration_codex_launchers} explicitly selected profiles and disposable harness preflight: PASS"

