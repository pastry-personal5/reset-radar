#!/bin/zsh

set -euo pipefail
umask 077

script_root="${0:A:h:h}"
test_root="$(mktemp -d /private/tmp/reset-radar-source-calibration-prepare.test.XXXXXX)"
prepared_root=''
cleanup() {
  if [[ "$prepared_root" == /private/tmp/reset-radar-source-calibration.* ]]; then
    rm -rf -- "$prepared_root"
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_root/bin" "$test_root/home-one" "$test_root/home-two"
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

cat > "$test_root/bin/claude" <<'EOF'
#!/bin/zsh
[[ "$1" == --version ]]
print -- 'claude test'
EOF
chmod 700 "$test_root/bin/claude"

export SYNTHETIC_PROFILE_HOME_ONE="$test_root/home-one"
export SYNTHETIC_PROFILE_HOME_TWO="$test_root/home-two"
output="$({
  printf '%s\n' synthetic-one synthetic-two
} | PATH="$test_root/bin:$PATH" zsh "$script_root/prepare.zsh" --codex-profile-count 2)"

prepared_root="${${(M)${(f)output}:#Disposable directory: *}#Disposable directory: }"
[[ "$prepared_root" == /private/tmp/reset-radar-source-calibration.* ]]
[[ -f "$prepared_root/session.zsh" ]]
source "$prepared_root/session.zsh"
(( ${#source_calibration_codex_launchers} == 2 ))
(( ${#source_calibration_codex_reports} == 2 ))
[[ "${source_calibration_codex_reports[1]}" == "$prepared_root/codex-1-report.json" ]]
[[ "${source_calibration_codex_reports[2]}" == "$prepared_root/codex-2-report.json" ]]
! grep -Fq synthetic-one "$prepared_root/session.zsh"
! grep -Fq synthetic-two "$prepared_root/session.zsh"
! print -r -- "$output" | grep -Fq synthetic-one
! print -r -- "$output" | grep -Fq synthetic-two
grep -Fq 'cli synthetic-one' "${source_calibration_codex_launchers[1]}"
grep -Fq 'cli synthetic-two' "${source_calibration_codex_launchers[2]}"

print -- 'codex-profile preparation isolation: PASS'
