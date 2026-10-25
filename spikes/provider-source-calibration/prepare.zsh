#!/bin/zsh

set -euo pipefail
umask 077

if (( $# == 4 )) && [[ "$1" == --mode && "$2" == claude \
    && "$3" == --expected-revision && -n "$4" ]]; then
  source_calibration_mode=claude
  codex_profile_count=0
  expected_revision="$4"
elif (( $# == 6 )) && [[ "$1" == --mode && "$2" == (codex|combined) \
    && "$3" == --codex-profile-count && "$4" == <-> \
    && "$5" == --expected-revision && -n "$6" ]] \
    && (( $4 >= 1 && $4 <= 2 )); then
  source_calibration_mode="$2"
  codex_profile_count="$4"
  expected_revision="$6"
else
  print -u2 -- "usage: zsh prepare.zsh --mode codex|combined --codex-profile-count COUNT --expected-revision COMMIT"
  print -u2 -- "   or: zsh prepare.zsh --mode claude --expected-revision COMMIT"
  exit 2
fi
typeset -a requested_codex_profiles
typeset -A seen_codex_profiles
for (( profile_index = 1; profile_index <= codex_profile_count; profile_index += 1 )); do
  IFS= read -r -s "profile_name?codex-profile name for private profile $profile_index: "
  print -u2
  if [[ "$profile_name" != [A-Za-z0-9]* || "$profile_name" == *[^A-Za-z0-9._-]* ]]; then
    print -u2 -- "Refusing an invalid codex-profile name."
    exit 1
  fi
  if [[ -n "${seen_codex_profiles[$profile_name]-}" ]]; then
    print -u2 -- "Refusing a duplicate codex-profile selection."
    exit 1
  fi
  requested_codex_profiles+=("$profile_name")
  seen_codex_profiles[$profile_name]=1
done
unset profile_name codex_profile_count

script_root="${0:A:h}"
repo_root="$(git -C "$script_root" rev-parse --show-toplevel)"
source_calibration_revision="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$expected_revision" != "$source_calibration_revision" ]]; then
  print -u2 -- "The checked-out revision does not match the owner-approved calibration revision."
  exit 1
fi
if [[ -n "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]]; then
  print -u2 -- "The calibration requires a clean worktree."
  exit 1
fi
if [[ "$source_calibration_mode" != codex ]] && pgrep -x claude >/dev/null 2>&1; then
  print -u2 -- "Close every Claude Code process before preparing the calibration."
  exit 1
fi

source_calibration_node="$(command -v node)"
if [[ "$source_calibration_mode" != claude ]]; then
  source_calibration_codex_profile="$(command -v codex-profile)"
fi
if [[ "$source_calibration_mode" != codex ]]; then
  source_calibration_claude="$(command -v claude)"
fi
source_calibration_root="$(mktemp -d /private/tmp/reset-radar-source-calibration.XXXXXX)"
preparation_complete=false
cleanup_failed_preparation() {
  if [[ "$preparation_complete" == false \
      && "$source_calibration_root" == /private/tmp/reset-radar-source-calibration.* \
      && -d "$source_calibration_root" ]]; then
    find "$source_calibration_root" -type f -exec chmod 600 {} + 2>/dev/null || true
    rm -rf -- "$source_calibration_root"
  fi
}
trap cleanup_failed_preparation EXIT

source_calibration_repo_root="$repo_root"
typeset -a source_calibration_codex_launchers
typeset -a source_calibration_codex_reports
source_calibration_repo_status_before="$(
  git -C "$repo_root" status --porcelain=v1 -z --untracked-files=all | shasum -a 256 | awk '{print $1}'
)"

mkdir -p "$source_calibration_root/harness"
chmod 700 "$source_calibration_root" "$source_calibration_root/harness"

for (( profile_index = 1; profile_index <= ${#requested_codex_profiles}; profile_index += 1 )); do
  profile_name="${requested_codex_profiles[$profile_index]}"
  profile_home="$("$source_calibration_codex_profile" path "$profile_name")"
  if [[ "$profile_home" != /* || ! -d "$profile_home" ]]; then
    print -u2 -- "codex-profile selection $profile_index has no initialized absolute home."
    exit 1
  fi
  launcher="$source_calibration_root/codex-profile-$profile_index"
  printf '#!/bin/zsh\nexec env CODEX_PROFILE_NO_UPDATE_CHECK=1 %q cli %q "$@"\n' \
    "$source_calibration_codex_profile" "$profile_name" > "$launcher"
  chmod 700 "$launcher"
  source_calibration_codex_launchers+=("$launcher")
  source_calibration_codex_reports+=("$source_calibration_root/codex-$profile_index-report.json")
done
unset profile_name profile_home launcher requested_codex_profiles seen_codex_profiles

if [[ "$source_calibration_mode" != claude ]]; then
  cp "$script_root/codex-calibration.mjs" "$source_calibration_root/harness/"
fi
cp "$script_root/verify-reports.mjs" "$source_calibration_root/harness/"
chmod 600 "$source_calibration_root/harness/"*.mjs

if [[ "$source_calibration_mode" != codex ]]; then
  source_calibration_claude_report_a="$source_calibration_root/claude-A-report.jsonl"
  source_calibration_claude_report_b="$source_calibration_root/claude-B-report.jsonl"
  source_calibration_claude_work_a="$source_calibration_root/claude-a-work"
  source_calibration_claude_work_b="$source_calibration_root/claude-b-work"
  source_calibration_claude_session_a="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  source_calibration_claude_session_b="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  source_calibration_real_claude_settings="$HOME/.claude/settings.json"
  source_calibration_claude_history="$HOME/.claude/history.jsonl"
  mkdir -p \
    "$source_calibration_root/claude-state" \
    "$source_calibration_claude_work_a" \
    "$source_calibration_claude_work_b"
  chmod 700 \
    "$source_calibration_root/claude-state" \
    "$source_calibration_claude_work_a" \
    "$source_calibration_claude_work_b"
  cp "$script_root/claude-recorder.mjs" "$source_calibration_root/harness/"
  chmod 600 "$source_calibration_root/harness/claude-recorder.mjs"

if [[ -f "$source_calibration_real_claude_settings" ]]; then
  source_calibration_settings_state='present'
  source_calibration_settings_before="$(
    shasum -a 256 "$source_calibration_real_claude_settings" | awk '{print $1}'
  )"
else
  source_calibration_settings_state='absent'
  source_calibration_settings_before='absent'
fi

if [[ -f "$source_calibration_claude_history" ]]; then
  source_calibration_history_state='present'
  source_calibration_history_size="$(stat -f '%z' "$source_calibration_claude_history")"
  source_calibration_history_checksum="$(
    shasum -a 256 "$source_calibration_claude_history" | awk '{print $1}'
  )"
else
  source_calibration_history_state='absent'
  source_calibration_history_size='0'
  source_calibration_history_checksum='absent'
fi

if find "$HOME/.claude" \( \
  -path "*$source_calibration_claude_session_a*" -o \
  -path "*$source_calibration_claude_session_b*" \
\) -print -quit 2>/dev/null | grep -q .; then
  print -u2 -- "A generated calibration UUID unexpectedly already exists under ~/.claude."
  exit 1
fi

for label in A B; do
  lower_label="${(L)label}"
  wrapper="$source_calibration_root/claude-$lower_label-statusline"
  settings="$source_calibration_root/claude-$lower_label-settings.json"
  cat > "$wrapper" <<EOF
#!/bin/zsh
exec "$source_calibration_node" "$source_calibration_root/harness/claude-recorder.mjs" --root "$source_calibration_root" --label "$label"
EOF
  chmod 700 "$wrapper"
  "$source_calibration_node" -e '
    const fs = require("node:fs");
    fs.writeFileSync(
      process.argv[1],
      JSON.stringify({
        statusLine: {
          type: "command",
          command: process.argv[2],
          refreshInterval: 30,
        },
      }, null, 2) + "\n",
      { mode: 0o600 },
    );
  ' "$settings" "$wrapper"
done
fi

typeset -p \
  source_calibration_mode \
  source_calibration_revision \
  source_calibration_root \
  source_calibration_node \
  source_calibration_repo_root \
  source_calibration_repo_status_before \
  > "$source_calibration_root/session.zsh"
if [[ "$source_calibration_mode" != claude ]]; then
  typeset -p \
  source_calibration_codex_profile \
  source_calibration_codex_launchers \
  source_calibration_codex_reports \
  >> "$source_calibration_root/session.zsh"
fi
if [[ "$source_calibration_mode" != codex ]]; then
  typeset -p \
  source_calibration_claude \
  source_calibration_claude_report_a \
  source_calibration_claude_report_b \
  source_calibration_claude_work_a \
  source_calibration_claude_work_b \
  source_calibration_claude_session_a \
  source_calibration_claude_session_b \
  source_calibration_real_claude_settings \
  source_calibration_settings_state \
  source_calibration_settings_before \
  source_calibration_claude_history \
  source_calibration_history_state \
  source_calibration_history_size \
  source_calibration_history_checksum \
  >> "$source_calibration_root/session.zsh"
fi
chmod 600 "$source_calibration_root/session.zsh"

print -- "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
print -- "Node.js: $("$source_calibration_node" --version)"
if [[ "$source_calibration_mode" != claude ]]; then
  print -- "codex-profile: $("$source_calibration_codex_profile" version 2>/dev/null)"
  for (( profile_index = 1; profile_index <= ${#source_calibration_codex_launchers}; profile_index += 1 )); do
    print -- "Codex profile $profile_index: $("${source_calibration_codex_launchers[$profile_index]}" --version 2>/dev/null)"
  done
fi
if [[ "$source_calibration_mode" != codex ]]; then
  print -- "Claude Code: $("$source_calibration_claude" --version)"
fi
print -- "Disposable directory: $source_calibration_root"
print -- "In every calibration terminal, run:"
printf "source %q\n" "$source_calibration_root/session.zsh"

preparation_complete=true
trap - EXIT

