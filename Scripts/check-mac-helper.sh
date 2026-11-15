#!/bin/zsh
# Prove the embedded status-line helper runs after the app copies it to Application Support
# `bin/`: a helper that needs bundle-relative libraries crashes at launch there.
set -euo pipefail

app=${1:?usage: check-mac-helper.sh <ResetRadarMac.app>}
helper="$app/Contents/Helpers/ResetRadarStatusLine"
[[ -f $helper ]] || { print -u2 "Mac helper check: missing $helper"; exit 1; }

workdir=$(mktemp -d /private/tmp/reset-radar-helper-check.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
mkdir "$workdir/bin"
copy="$workdir/bin/reset-radar-statusline"
cp "$helper" "$copy"

if ! version=$(python3 -I "${0:A:h}/run-with-timeout.py" 10 -- "$copy" --version \
  </dev/null 2>"$workdir/stderr") || [[ -z $version ]]; then
  print -u2 "Mac helper check: the status-line helper does not run outside the app bundle."
  head -c 600 "$workdir/stderr" >&2
  exit 1
fi
