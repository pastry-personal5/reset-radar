#!/bin/zsh
# Runs swift-format lint --strict over the maintained Swift roots in Scripts/swift-roots.txt.
# swift-format has no configuration-file exclusions, so generated, external, and spike
# directories are kept out by never listing them.
set -euo pipefail
cd "${0:A:h}/.."
roots=("${(@f)$(<Scripts/swift-roots.txt)}")
for root in $roots; do
  [[ -e $root ]] || { print -u2 "missing maintained root: $root"; exit 1; }
done
exec swift-format lint --strict --recursive $roots
