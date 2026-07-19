#!/usr/bin/env bash
set -uo pipefail

# collect-needs.sh - the founder queue files, as JSON. The old renderer read
# ~/work/*/agent_handoff/NEEDS-STEVEN.md server-side at render time; the
# client-side app cannot, so this collector emits the same parse as
# data/needs.json. Every other Needs-Steven derivation (blocked agents, TLS,
# B2 cap, subscriptions) is computed client-side from JSON the page already
# fetches - this file carries ONLY the queue lines.
#
# Line contract (unchanged from render-dashboard.py): `- [YYYY-MM-DD] text`.

. "$(dirname "$0")/lib.sh"

main() {
  local items='[]' missing=true qf proj
  [ -f "$HOME/work/swordfish/agent_handoff/NEEDS-STEVEN.md" ] && missing=false
  for qf in "$HOME"/work/*/agent_handoff/NEEDS-STEVEN.md; do
    [ -f "$qf" ] || continue
    proj=$(basename "$(dirname "$(dirname "$qf")")")
    items=$(jq --arg p "$proj" --slurpfile new <(
      grep -E '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "$qf" | while IFS= read -r line; do
        d=${line:3:10}
        jq -n --arg d "$d" --arg t "${line:15}" \
          --argjson e "$(date -u -d "$d" +%s 2>/dev/null || echo 0)" \
          '{date: $d, epoch: $e, text: ($t | ltrimstr(" "))}'
      done | jq -s .
    ) '. + ($new[0] | map(. + {project: $p}))' <<<"$items")
  done
  jq -n --argjson t "$(date +%s)" --argjson items "$items" \
        --argjson missing "$missing" \
    '{generated_at: $t, items: $items, missing_swordfish_queue: $missing}' \
    | emit needs
}

main || fail needs "needs collector crashed"
