#!/bin/zsh
# Builds the unsigned Release Mac product in isolation and rejects every Mach-O slice except arm64.
# This architecture-only build does not replace the signed Release scheme check.
set -euo pipefail
cd "${0:A:h}/.."

workdir=$(mktemp -d /private/tmp/reset-radar-mac-architecture.XXXXXX)
trap 'rm -rf "$workdir"' EXIT

mac_targets=(ResetRadarMac ResetRadarStatusLine ResetRadarMacTests)
for configuration in Development Release; do
  for target in $mac_targets; do
    settings=$(xcodebuild \
      -project ResetRadar.xcodeproj \
      -target "$target" \
      -configuration "$configuration" \
      -sdk macosx \
      -showBuildSettings)
    architectures=$(print -r -- "$settings" | sed -n 's/^[[:space:]]*ARCHS = //p' | head -n 1)
    excluded_architectures=$(print -r -- "$settings" \
      | sed -n 's/^[[:space:]]*EXCLUDED_ARCHS = //p' \
      | head -n 1)
    if [[ $architectures != "arm64" ]]; then
      print -u2 "Mac architecture check: $target $configuration resolves ARCHS='$architectures'."
      exit 1
    fi
    if [[ " $excluded_architectures " != *" x86_64 "* ]]; then
      print -u2 \
        "Mac architecture check: $target $configuration does not exclude x86_64."
      exit 1
    fi
  done
done

xcodebuild -quiet build \
  -project ResetRadar.xcodeproj \
  -target ResetRadarMac \
  -configuration Release \
  -sdk macosx \
  SYMROOT="$workdir/Products" \
  OBJROOT="$workdir/Intermediates" \
  SHARED_PRECOMPS_DIR="$workdir/PrecompiledHeaders" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

app="$workdir/Products/Release/ResetRadarMac.app"
expected_binaries=(
  "$app/Contents/MacOS/ResetRadarMac"
  "$app/Contents/Helpers/ResetRadarStatusLine"
)
for binary in $expected_binaries; do
  [[ -f $binary ]] || { print -u2 "Mac architecture check: missing $binary"; exit 1; }
done

checked=0
while IFS= read -r -d '' candidate; do
  description=$(/usr/bin/file -b "$candidate")
  [[ $description == *"Mach-O"* ]] || continue
  architectures=$(xcrun lipo -archs "$candidate")
  if [[ $architectures != "arm64" ]]; then
    print -u2 "Mac architecture check: $candidate contains '$architectures'; expected arm64 only."
    exit 1
  fi
  (( checked += 1 ))
done < <(/usr/bin/find "$app" -type f -print0)

(( checked >= ${#expected_binaries} )) || {
  print -u2 "Mac architecture check: expected at least ${#expected_binaries} Mach-O executables; found $checked."
  exit 1
}
print "Mac architecture check passed: all Mac target settings and $checked Release Mach-O executables are arm64 only."
