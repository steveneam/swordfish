#!/usr/bin/env bash
set -uo pipefail

# collect-migration.sh - drive-transfer state (plan §8; fades out once the
# drive retires - delete this collector + card at that session). What crossed,
# per staging area; what the box agent already placed (incoming/.placed); the
# census row count. Folder names appear only in the untracked JSON/HTML.

. "$(dirname "$0")/lib.sh"

MIG="$HOME/migration"

main() {
  [ -d "$MIG" ] || { fail migration "no ~/migration on this box"; return; }

  local areas='[]' d name bytes files
  for d in "$MIG"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; name=$(basename "$d")
    case "$name" in browsers|claude-home|gh|ssh) continue ;; esac
    bytes=$(du -sb "$d" 2>/dev/null | cut -f1)
    files=$(find "$d" -type f 2>/dev/null | wc -l)
    areas=$(jq --arg n "$name" --argjson b "${bytes:-0}" --argjson f "$files" \
      '. + [{name: $n, bytes: $b, files: $f}]' <<<"$areas")
  done

  local placed='[]' census=null
  if [ -f "$MIG/incoming/.placed" ]; then
    placed=$(jq -R -s '[split("\n")[] | select(length > 0)]' < "$MIG/incoming/.placed")
  fi
  if [ -f "$MIG/incoming/census/Steven.tsv" ]; then
    census=$(wc -l < "$MIG/incoming/census/Steven.tsv")
  fi

  jq -n --argjson t "$(date +%s)" --argjson a "$areas" \
        --argjson p "$placed" --argjson c "$census" \
    '{generated_at: $t, areas: $a, placed: $p, census_rows: $c,
      note: "census re-scan on the Mac is the final check before the drive retires (see NEEDS STEVEN)"}' \
    | emit migration
}

main || fail migration "migration collector crashed"
