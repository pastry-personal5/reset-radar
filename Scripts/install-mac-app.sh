#!/bin/zsh
# Install the signed Release Mac app and its command-line launcher.
set -euo pipefail

cd "${0:A:h}/.."

package_path=${MAC_PACKAGE_PATH:-.build/mac/ResetRadarMac.zip}
applications_dir=${MAC_APPLICATIONS_DIR:-/Applications}
rr_dir=${RR_INSTALL_DIR:-/usr/local/bin}
app_name=ResetRadarMac.app
app_path="$applications_dir/$app_name"
rr_path="$rr_dir/rr"

[[ -f $package_path ]] || {
  print -u2 "Mac install: missing package: $package_path"
  print -u2 "Run make mac-package first."
  exit 1
}

case "$applications_dir" in
  /Applications|*/Applications) ;;
  *) print -u2 "Mac install: refusing unexpected applications directory: $applications_dir"; exit 1 ;;
esac
case "$rr_dir" in
  /usr/local/bin|/opt/homebrew/bin|*/bin) ;;
  *) print -u2 "Mac install: refusing unexpected launcher directory: $rr_dir"; exit 1 ;;
esac

run_as_owner_or_root() {
  local destination=$1
  shift
  if [[ -w ${destination:h} ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

workdir=$(mktemp -d /private/tmp/reset-radar-mac-install.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
ditto -x -k "$package_path" "$workdir"
staged_app="$workdir/$app_name"
[[ -d $staged_app ]] || { print -u2 "Mac install: package is missing $app_name"; exit 1; }
CONFIGURATION=Release Scripts/check-mac-signing.sh "$staged_app"
codesign --verify --deep --strict "$staged_app"
python3 -I Scripts/check-app-icons.py --mac-app "$staged_app"

if pgrep -x ResetRadarMac >/dev/null 2>&1; then
  osascript -e 'tell application id "com.unidentifiedstealthstartup.ResetRadarMac" to quit' >/dev/null
  for _ in {1..20}; do
    pgrep -x ResetRadarMac >/dev/null 2>&1 || break
    sleep 0.25
  done
  if pgrep -x ResetRadarMac >/dev/null 2>&1; then
    print -u2 "Mac install: Reset Radar is still running. Quit every Mac copy and retry."
    exit 1
  fi
fi

# Remove only the previously installed application bundle. Application Support and Keychain
# state are deliberately retained so an update keeps the configured collector identity.
if [[ -e $app_path ]]; then
  run_as_owner_or_root "$app_path" rm -rf -- "$app_path"
fi
run_as_owner_or_root "$app_path" mkdir -p -- "$applications_dir"
run_as_owner_or_root "$app_path" ditto "$staged_app" "$app_path"

launcher="$workdir/rr"
cat > "$launcher" <<EOF
#!/bin/sh
exec open -a "$app_path" --args "\$@"
EOF
if [[ ! -x $rr_path ]] || ! cmp -s "$launcher" "$rr_path"; then
  run_as_owner_or_root "$rr_path" mkdir -p -- "$rr_dir"
  run_as_owner_or_root "$rr_path" install -m 755 "$launcher" "$rr_path"
fi

print "Installed $app_path"
print "Installed launcher: $rr_path"
print "Run: rr"
