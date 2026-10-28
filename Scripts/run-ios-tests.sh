#!/bin/zsh
# One complete iOS suite per destination. A failed or timed-out run is never retried silently.
set -euo pipefail
cd "${0:A:h}/.."

if (( $# != 3 )); then
  print -u2 "usage: $0 SECONDS DESTINATION DERIVED_DATA_PATH"
  exit 64
fi

print "Testing the complete iOS suite on $2"
exec Scripts/run-xcode-test.sh "$1" \
  xcodebuild -quiet test -enableCodeCoverage NO -scheme ResetRadar \
  -destination "$2" -destination-timeout 30 -derivedDataPath "$3" \
  -parallel-testing-enabled NO
