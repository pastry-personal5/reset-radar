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
# A successful action that recorded no passing test means a broken scheme or plan, not a pass.
if (( command_status == 0 )) && ! xcrun xcresulttool get test-results summary --compact \
  --path "$workdir/result.xcresult" | python3 -I -c '
import json, sys
s = json.load(sys.stdin)
print("Tests: {totalTestCount} total, {passedTests} passed, {skippedTests} skipped, {failedTests} failed".format(**s))
sys.exit(0 if s["passedTests"] > 0 and s["failedTests"] == 0 else 1)'; then
  print -u2 "Result bundle recorded no passing tests or reported failures."
  command_status=65
fi
exit "$command_status"
