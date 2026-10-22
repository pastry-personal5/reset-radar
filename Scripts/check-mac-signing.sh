#!/bin/zsh
# Release-only check: fails when the built Mac app (or its helper) is ad-hoc signed or has no
# team identifier, so a build that could trigger a Keychain dialog never ships.
# Runs as the ResetRadarMac scheme's build post-action, after code signing.
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  print "Mac signing check skipped for ${CONFIGURATION:-unknown} configuration."
  exit 0
fi

app="${TARGET_BUILD_DIR:?}/${FULL_PRODUCT_NAME:?}"
for item in "$app" "$app/Contents/Helpers/ResetRadarStatusLine"; do
  [[ -e $item ]] || { print -u2 "Mac signing check: missing $item"; exit 1; }
  details=$(codesign --display --verbose=4 "$item" 2>&1) || {
    print -u2 "Mac signing check: $item is not signed."; exit 1; }
  team=$(print -r -- "$details" | sed -n 's/^TeamIdentifier=//p')
  if print -r -- "$details" | grep -q 'Signature=adhoc' || [[ -z $team || $team == "not set" ]]; then
    print -u2 "Mac signing check: $item is ad-hoc signed or has no team identifier."
    exit 1
  fi
done
print "Mac signing check passed."
