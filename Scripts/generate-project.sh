#!/bin/zsh
# Generates the ignored ResetRadar.xcodeproj from project.yml with the tested XcodeGen version
# and fails if the expected targets, configurations, shared schemes, or test plans are absent.
set -euo pipefail
cd "${0:A:h}/.."

required_version="2.46.0"
actual_version=$(xcodegen --version | sed -n 's/^Version: //p')
if [[ $actual_version != $required_version ]]; then
  print -u2 "XcodeGen $required_version is required; found '${actual_version:-none}'."
  exit 1
fi

xcodegen generate --quiet

expected_targets=(ResetRadar ResetRadarWidgets ResetRadarWatch ResetRadarWatchWidgets ResetRadarMac
  ResetRadarStatusLine ResetRadarTests ResetRadarUITests ResetRadarMacTests ResetRadarWatchTests)
expected_schemes=(ResetRadar ResetRadarMac ResetRadarWatch)
listing=$(xcodebuild -list -json -project ResetRadar.xcodeproj)
actual_targets=("${(@f)$(print -r -- $listing | python3 -I -c 'import json,sys; print("\n".join(json.load(sys.stdin)["project"]["targets"]))')}")
actual_configs=("${(@f)$(print -r -- $listing | python3 -I -c 'import json,sys; print("\n".join(json.load(sys.stdin)["project"]["configurations"]))')}")
shared_schemes=("${(@f)$(ls ResetRadar.xcodeproj/xcshareddata/xcschemes | sed 's/\.xcscheme$//')}")

[[ "${(j: :)${(o)actual_targets}}" == "${(j: :)${(o)expected_targets}}" ]] \
  || { print -u2 "Unexpected target set: $actual_targets"; exit 1; }
[[ "${(j: :)${(o)actual_configs}}" == "Development Release" ]] \
  || { print -u2 "Unexpected configurations: $actual_configs"; exit 1; }
[[ "${(j: :)${(o)shared_schemes}}" == "${(j: :)${(o)expected_schemes}}" ]] \
  || { print -u2 "Unexpected shared schemes: $shared_schemes"; exit 1; }
for scheme in $expected_schemes; do
  [[ -f Config/TestPlans/$scheme.xctestplan ]] \
    || { print -u2 "Missing test plan: Config/TestPlans/$scheme.xctestplan"; exit 1; }
done
print "Generated ResetRadar.xcodeproj with XcodeGen $actual_version."
