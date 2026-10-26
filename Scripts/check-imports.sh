#!/bin/zsh
# Rejects a ResetRadarKit import that the "Target imports" table does not allow, in both the
# Swift package (SwiftPM's explicit dependency import check) and the Xcode targets' sources.
set -euo pipefail
cd "${0:A:h}/.."

(cd ResetRadarKit && swift build --build-tests --explicit-target-dependency-import-check=error 2>&1 | tail -3)

failed=0
section=main
while IFS= read -r line; do
  [[ -z $line || $line == \#* ]] && continue
  if [[ $line == \[scoped-symbols\] ]]; then section=scoped; break; fi
  dir=${line%%:*}
  allowed=(${=line#*:})
  [[ -d $dir ]] || continue
  imports=$(grep -rhE '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*import[[:space:]]+(struct|class|enum|protocol|typealias|func|var|let[[:space:]]+)?[[:space:]]*ResetRadar' "$dir" --include='*.swift' || true)
  while IFS= read -r imp; do
    [[ -z $imp ]] && continue
    spec=$(print -r -- "$imp" | sed -E 's/^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?//; s/[[:space:]].*$//')
    if [[ ${spec%%.*} == ResetRadar ]]; then
      module=App
    else
      module=${${spec%%.*}#ResetRadar}
    fi
    scoped=0; [[ $spec == *.* ]] && scoped=1
    if (( ${allowed[(Ie)$module]} )); then continue; fi
    if (( ${allowed[(Ie)$module(scoped)]} )); then
      symbol=${spec#*.}
      if (( scoped )) && grep -qE "^$dir/ResetRadar$module:.*\\b$symbol\\b" Config/import-boundaries.txt; then continue; fi
      print -u2 "$dir: import of ResetRadar$module must be scoped to a listed symbol: $imp"
    else
      print -u2 "$dir: ResetRadar$module is not an allowed import: $imp"
    fi
    failed=1
  done <<< "$imports"
done < Config/import-boundaries.txt
exit $failed
