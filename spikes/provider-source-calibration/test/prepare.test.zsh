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
