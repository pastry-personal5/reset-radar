#!/bin/zsh

set -euo pipefail
umask 077

if (( $# == 3 )) && [[ "$1" == --mode && "$2" == codex ]]; then
  requested_mode=codex
  session_file="${3:A}"
elif (( $# == 4 )) && [[ "$1" == --mode && "$2" == (combined|claude) \
    && "$3" == --confirm-delete-calibration-sessions ]]; then
  requested_mode="$2"
  session_file="${4:A}"
else
  print -u2 -- "usage: zsh cleanup.zsh --mode codex SESSION_FILE"
  print -u2 -- "   or: zsh cleanup.zsh --mode combined|claude --confirm-delete-calibration-sessions SESSION_FILE"
  exit 2
fi
if [[ "$session_file" != /private/tmp/reset-radar-source-calibration.*/session.zsh || ! -f "$session_file" ]]; then
  print -u2 -- "Refusing an unexpected session file."
  exit 1
fi
source "$session_file"
if [[ "$source_calibration_root" != /private/tmp/reset-radar-source-calibration.* \
    || "$source_calibration_mode" != "$requested_mode" ]]; then
  print -u2 -- "Refusing an unexpected cleanup root."
  exit 1
fi
repo_status_after="$(
  git -C "$source_calibration_repo_root" status --porcelain=v1 -z --untracked-files=all \
    | shasum -a 256 | awk '{print $1}'
)"
[[ "$repo_status_after" == "$source_calibration_repo_status_before" ]]
[[ "$(git -C "$source_calibration_repo_root" rev-parse HEAD)" == "$source_calibration_revision" ]]

if [[ "$source_calibration_mode" != codex ]]; then
if ! print -r -- "$source_calibration_claude_session_a" \
    | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
  || ! print -r -- "$source_calibration_claude_session_b" \
    | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  print -u2 -- "Refusing invalid calibration session UUIDs."
  exit 1
fi
if pgrep -x claude >/dev/null 2>&1; then
  print -u2 -- "Close every Claude Code process before cleanup."
  exit 1
fi

if [[ "$source_calibration_settings_state" == present ]]; then
  [[ -f "$source_calibration_real_claude_settings" ]]
  settings_after="$(shasum -a 256 "$source_calibration_real_claude_settings" | awk '{print $1}')"
else
  [[ ! -e "$source_calibration_real_claude_settings" ]]
  settings_after='absent'
fi
[[ "$settings_after" == "$source_calibration_settings_before" ]]

if [[ "$source_calibration_history_state" == present ]]; then
  [[ -f "$source_calibration_claude_history" ]]
  history_after_size="$(stat -f '%z' "$source_calibration_claude_history")"
  (( history_after_size >= source_calibration_history_size ))
  history_prefix_checksum="$(
    head -c "$source_calibration_history_size" "$source_calibration_claude_history" \
      | shasum -a 256 | awk '{print $1}'
  )"
  if [[ "$history_prefix_checksum" != "$source_calibration_history_checksum" ]]; then
    print -u2 -- "Existing Claude Code history changed; refusing to truncate it."
    exit 1
  fi
  truncate -s "$source_calibration_history_size" "$source_calibration_claude_history"
  [[ "$(shasum -a 256 "$source_calibration_claude_history" | awk '{print $1}')" \
    == "$source_calibration_history_checksum" ]]
elif [[ -e "$source_calibration_claude_history" ]]; then
  rm -- "$source_calibration_claude_history"
fi

for claude_session_root in \
  "$HOME/.claude/projects" \
  "$HOME/.claude/session-env" \
  "$HOME/.claude/tasks"; do
  if [[ -d "$claude_session_root" ]]; then
    find "$claude_session_root" -depth \( \
      -path "*$source_calibration_claude_session_a*" -o \
      -path "*$source_calibration_claude_session_b*" \
    \) -exec rm -rf -- {} +
  fi
done

if rg -l -F \
  -e "$source_calibration_claude_session_a" \
  -e "$source_calibration_claude_session_b" \
  "$HOME/.claude" >/dev/null 2>&1; then
  print -u2 -- "A calibration session UUID remains under ~/.claude; inspect privately."
  exit 1
fi
fi

find "$source_calibration_root" -type f -exec chmod 600 {} +
rm -rf -- "$source_calibration_root"
[[ ! -e "$source_calibration_root" ]]
print -- "$source_calibration_mode calibration disposable files removed and repository unchanged: PASS"

