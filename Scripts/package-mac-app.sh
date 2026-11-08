#!/bin/zsh
# Archive the owner's signed Release Mac app and preserve an existing install package.
set -euo pipefail
cd "${0:A:h}/.."

package_path=${1:-.build/mac/ResetRadarMac.zip}
if [[ -e $package_path ]]; then
  print "Mac package already exists: $package_path"
  exit 0
fi

workdir=$(mktemp -d /private/tmp/reset-radar-mac-package.XXXXXX)
staged_package=""
trap 'rm -rf "$workdir"; [[ -z $staged_package ]] || rm -f "$staged_package"' EXIT

python3 -I Scripts/run-with-timeout.py "${COMMAND_TIMEOUT_SECONDS:-600}" -- \
  xcodebuild -quiet archive \
    -project ResetRadar.xcodeproj -scheme ResetRadarMac -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath .build/derived-data/mac-package \
    -archivePath "$workdir/ResetRadarMac.xcarchive" -allowProvisioningUpdates

check_app() {
  local app=$1 binary architectures candidate description checked=0
  CONFIGURATION=Release Scripts/check-mac-signing.sh "$app"
  codesign --verify --deep --strict "$app"
  python3 -I Scripts/check-app-icons.py --mac-app "$app"
  for binary in "$app/Contents/MacOS/ResetRadarMac" \
    "$app/Contents/Helpers/ResetRadarStatusLine"; do
    [[ -f $binary ]] || { print -u2 "Mac package: missing executable in app bundle."; return 1; }
  done
  while IFS= read -r -d '' candidate; do
    description=$(/usr/bin/file -b "$candidate")
    [[ $description == *"Mach-O"* ]] || continue
    architectures=$(xcrun lipo -archs "$candidate")
    [[ $architectures == arm64 ]] || {
      print -u2 "Mac package: found non-arm64 Mach-O in app bundle: $candidate";
      return 1
    }
    (( checked += 1 ))
  done < <(/usr/bin/find "$app" -type f -print0)
  (( checked >= 2 )) || { print -u2 "Mac package: expected both app and helper executables."; return 1; }
}

app="$workdir/ResetRadarMac.xcarchive/Products/Applications/ResetRadarMac.app"
[[ -d $app ]] || { print -u2 "Mac package: archive is missing ResetRadarMac.app."; exit 1; }
check_app "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$workdir/ResetRadarMac.zip"
mkdir "$workdir/unpacked"
ditto -x -k "$workdir/ResetRadarMac.zip" "$workdir/unpacked"
check_app "$workdir/unpacked/ResetRadarMac.app"

mkdir -p "${package_path:h}"
staged_package="${package_path:h}/.ResetRadarMac.zip.$$.tmp"
cp "$workdir/ResetRadarMac.zip" "$staged_package"
ln "$staged_package" "$package_path"
print "Created Mac package: $package_path"
