#!/bin/zsh

set -euo pipefail
umask 077

source_script_root="${0:A:h:h}"
test_root="$(mktemp -d /private/tmp/reset-radar-source-calibration-prepare.test.XXXXXX)"
prepared_root=''
cleanup() {
  if [[ "$prepared_root" == /private/tmp/reset-radar-source-calibration.* ]]; then
    rm -rf -- "$prepared_root"
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p \
  "$test_root/bin" \
  "$test_root/home-one" \
  "$test_root/home-two" \
  "$test_root/repo/spikes/provider-source-calibration"
cp \
  "$source_script_root/prepare.zsh" \
  "$source_script_root/cleanup.zsh" \
  "$source_script_root/codex-calibration.mjs" \
  "$source_script_root/claude-recorder.mjs" \
  "$source_script_root/verify-reports.mjs" \
  "$test_root/repo/spikes/provider-source-calibration/"
git -C "$test_root/repo" init -q
git -C "$test_root/repo" add .
git -C "$test_root/repo" -c user.name=Test -c user.email=test.invalid commit -qm baseline
script_root="$test_root/repo/spikes/provider-source-calibration"
expected_revision="$(git -C "$test_root/repo" rev-parse HEAD)"
ln -s "$(command -v node)" "$test_root/bin/node"

cat > "$test_root/bin/codex-profile" <<'EOF'
#!/bin/zsh
case "$1" in
  path)
    case "$2" in
      synthetic-one) print -r -- "$SYNTHETIC_PROFILE_HOME_ONE" ;;
      synthetic-two) print -r -- "$SYNTHETIC_PROFILE_HOME_TWO" ;;
      *) exit 1 ;;
    esac
    ;;
  version)
    print -- 'codex-profiles test'
    ;;
  cli)
    [[ "$3" == --version ]]
    print -- 'codex test'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 700 "$test_root/bin/codex-profile"

export SYNTHETIC_PROFILE_HOME_ONE="$test_root/home-one"
export SYNTHETIC_PROFILE_HOME_TWO="$test_root/home-two"
output="$({
  printf '%s\n' synthetic-one synthetic-two
} | PATH="$test_root/bin:$PATH" zsh "$script_root/prepare.zsh" \
  --mode codex \
  --codex-profile-count 2 \
  --expected-revision "$expected_revision")"

prepared_root="$(print -r -- "$output" | sed -n 's/^Disposable directory: //p')"
[[ "$prepared_root" == /private/tmp/reset-radar-source-calibration.* ]]
[[ -f "$prepared_root/session.zsh" ]]
source "$prepared_root/session.zsh"
(( ${#source_calibration_codex_launchers} == 2 ))
(( ${#source_calibration_codex_reports} == 2 ))
[[ "$source_calibration_mode" == codex ]]
[[ "$source_calibration_revision" == "$expected_revision" ]]
[[ "${source_calibration_codex_reports[1]}" == "$prepared_root/codex-1-report.json" ]]
[[ "${source_calibration_codex_reports[2]}" == "$prepared_root/codex-2-report.json" ]]
! grep -Fq synthetic-one "$prepared_root/session.zsh"
! grep -Fq synthetic-two "$prepared_root/session.zsh"
! print -r -- "$output" | grep -Fq synthetic-one
! print -r -- "$output" | grep -Fq synthetic-two
grep -Fq 'cli synthetic-one' "${source_calibration_codex_launchers[1]}"
grep -Fq 'cli synthetic-two' "${source_calibration_codex_launchers[2]}"
[[ ! -e "$prepared_root/claude-state" ]]
[[ ! -e "$prepared_root/claude-a-settings.json" ]]

if printf '%s\n' synthetic-one | PATH="$test_root/bin:$PATH" zsh "$script_root/prepare.zsh" \
    --mode codex --codex-profile-count 1 --expected-revision deadbeef >/dev/null 2>&1; then
  print -u2 -- "prepare unexpectedly accepted the wrong revision"
  exit 1
fi

touch "$test_root/repo/dirty"
if printf '%s\n' synthetic-one | PATH="$test_root/bin:$PATH" zsh "$script_root/prepare.zsh" \
    --mode codex --codex-profile-count 1 --expected-revision "$expected_revision" >/dev/null 2>&1; then
  print -u2 -- "prepare unexpectedly accepted a dirty worktree"
  exit 1
fi
rm "$test_root/repo/dirty"
zsh "$script_root/cleanup.zsh" --mode codex "$prepared_root/session.zsh" >/dev/null
[[ ! -e "$prepared_root" ]]
prepared_root=''

print -- 'codex-profile preparation isolation: PASS'

# Claude Code-only mode needs no codex-profile, creates no Codex state, and cleans up exactly.
mkdir -p "$test_root/claude-home/.claude" "$test_root/claude-bin"
print -r -- '{}' > "$test_root/claude-home/.claude/settings.json"
ln -s "$(command -v node)" "$test_root/claude-bin/node"
printf '#!/bin/zsh\nprint -- "2.0.0 (Claude Code)"\n' > "$test_root/claude-bin/claude"
chmod 700 "$test_root/claude-bin/claude"
printf '#!/bin/zsh\nexit 1\n' > "$test_root/claude-bin/pgrep"
chmod 700 "$test_root/claude-bin/pgrep"
mkdir -p "$test_root/busy-bin"
printf '#!/bin/zsh\nexit 0\n' > "$test_root/busy-bin/pgrep"
chmod 700 "$test_root/busy-bin/pgrep"
settings_sum_before="$(shasum -a 256 "$test_root/claude-home/.claude/settings.json" | awk '{print $1}')"
output="$(HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/prepare.zsh" \
  --mode claude --expected-revision "$expected_revision")"
prepared_root="$(print -r -- "$output" | sed -n 's/^Disposable directory: //p')"
[[ "$prepared_root" == /private/tmp/reset-radar-source-calibration.* ]]
source "$prepared_root/session.zsh"
[[ "$source_calibration_mode" == claude ]]
! grep -Fq source_calibration_codex "$prepared_root/session.zsh"
[[ ! -e "$prepared_root/harness/codex-calibration.mjs" ]]
[[ -f "$prepared_root/harness/claude-recorder.mjs" ]]
[[ -f "$prepared_root/claude-a-settings.json" && -f "$prepared_root/claude-b-settings.json" ]]
[[ "$source_calibration_claude_session_a" != "$source_calibration_claude_session_b" ]]
! print -r -- "$output" | grep -Fq codex-profile
[[ "$(shasum -a 256 "$test_root/claude-home/.claude/settings.json" | awk '{print $1}')" == "$settings_sum_before" ]]

# Cleanup refuses a mismatched mode and requires the explicit confirmation flag.
if HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/cleanup.zsh" --mode codex "$prepared_root/session.zsh" >/dev/null 2>&1; then
  print -u2 -- "cleanup unexpectedly accepted the wrong mode"
  exit 1
fi
if HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/cleanup.zsh" --mode claude "$prepared_root/session.zsh" >/dev/null 2>&1; then
  print -u2 -- "cleanup unexpectedly ran without confirmation"
  exit 1
fi
[[ -d "$prepared_root" ]]
HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/cleanup.zsh" --mode claude \
  --confirm-delete-calibration-sessions "$prepared_root/session.zsh" >/dev/null
[[ ! -e "$prepared_root" ]]
prepared_root=''

# A running Claude Code process is refused, so the harness never attaches to the owner's session.
if HOME="$test_root/claude-home" PATH="$test_root/busy-bin:$test_root/claude-bin:/usr/bin:/bin" \
    zsh "$script_root/prepare.zsh" --mode claude --expected-revision "$expected_revision" >/dev/null 2>&1; then
  print -u2 -- "claude prepare unexpectedly ran beside a Claude Code process"
  exit 1
fi

# Wrong revision and dirty worktree stay refused in Claude Code-only mode.
if HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/prepare.zsh" \
    --mode claude --expected-revision deadbeef >/dev/null 2>&1; then
  print -u2 -- "claude prepare unexpectedly accepted the wrong revision"
  exit 1
fi
touch "$test_root/repo/dirty"
if HOME="$test_root/claude-home" PATH="$test_root/claude-bin:/usr/bin:/bin" zsh "$script_root/prepare.zsh" \
    --mode claude --expected-revision "$expected_revision" >/dev/null 2>&1; then
  print -u2 -- "claude prepare unexpectedly accepted a dirty worktree"
  exit 1
fi
rm "$test_root/repo/dirty"
# An invalid argument shape is a usage error.
if zsh "$script_root/prepare.zsh" --mode claude --codex-profile-count 1 --expected-revision x >/dev/null 2>&1; then
  print -u2 -- "claude prepare unexpectedly accepted a profile count"
  exit 1
fi

print -- 'claude-only preparation and cleanup: PASS'
