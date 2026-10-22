#!/bin/zsh

set -euo pipefail

script_root="${0:A:h}"
node_path="$(command -v node)"

for script in \
  "$script_root/codex-calibration.mjs" \
  "$script_root/claude-recorder.mjs" \
  "$script_root/verify-reports.mjs" \
  "$script_root/test/mock-codex.mjs" \
  "$script_root/test/synthetic.test.mjs"; do
  "$node_path" --check "$script"
done

for script in \
  "$script_root/prepare.zsh" \
  "$script_root/preflight-codex.zsh" \
  "$script_root/cleanup.zsh" \
  "$script_root/test/prepare.test.zsh" \
  "$script_root/test.zsh"; do
  zsh -n "$script"
done

"$node_path" --test "$script_root/test/synthetic.test.mjs"
zsh "$script_root/test/prepare.test.zsh"

