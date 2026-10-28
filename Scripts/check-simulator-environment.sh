#!/bin/zsh
# Detect inaccessible host services before a build or simulator boot can wait on them.
set -euo pipefail
cd "${0:A:h}/.."

workdir=$(mktemp -d /private/tmp/reset-radar-simulator-preflight.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
if ! python3 -I Scripts/run-with-timeout.py 20 -- \
  xcrun simctl list devices available --json > "$workdir/devices.json" 2> "$workdir/error.log"; then
  cat "$workdir/error.log" >&2
  print -u2 'Simulator preflight failed: CoreSimulator must be accessible in the host user session.'
  print -u2 'In a coding-agent sandbox, rerun with approved host access; do not reset devices or rewrite HOME.'
  exit 1
fi
python3 -I - "$workdir/devices.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    devices = json.load(source).get("devices", {})
if not any(devices.values()):
    sys.exit("No available simulators. Install the approved runtimes/models; see docs/contribution-guide.md.")
print("Simulator preflight: host CoreSimulator service is accessible.")
PY
