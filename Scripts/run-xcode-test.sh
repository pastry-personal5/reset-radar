#!/bin/zsh
# Finalize results in a unique local directory; keep failed runs for diagnosis.
set -euo pipefail

if (( $# < 2 )); then
  print -u2 "usage: $0 SECONDS XCODEBUILD [ARG ...]"
  exit 64
fi

timeout_seconds=$1
shift
workdir=$(mktemp -d /private/tmp/reset-radar-xcode-test.XXXXXX)
command_status=1
cleanup() {
  if (( command_status == 0 )); then
    rm -rf "$workdir"
  else
    print -u2 "Xcode action failed; diagnostic artifacts retained at $workdir"
  fi
}
trap cleanup EXIT

# Preserve the command's status through tee, including timeout (124). Never infer success
# from individual passing tests: xcodebuild must finalize and return success itself.
set +e
python3 -I "${0:A:h}/run-with-timeout.py" "$timeout_seconds" -- \
  "$@" -collect-test-diagnostics never -resultBundlePath "$workdir/result.xcresult" \
  2>&1 | tee "$workdir/xcodebuild.log"
command_status=$?
exit "$command_status"
