#!/usr/bin/env bash
set -uo pipefail

# collect-needs.sh - the founder queue files, as JSON. The old renderer read
# ~/work/*/agent_handoff/NEEDS-STEVEN.md server-side at render time; the
# client-side app cannot, so this collector emits the same parse as
# data/needs.json. Every other Needs-Steven derivation (blocked agents, TLS,
# B2 cap, subscriptions) is computed client-side from JSON the page already
# fetches - this file carries ONLY the queue lines.
#
# Line contract: `- [YYYY-MM-DD] text`, and ALSO `- [YYYY-MM-DD→DD] text`.
#
# 2026-07-29 FIX: the original regex demanded `]` immediately after the date, so
# every line written in the date-RANGE form agents actually use - `[2026-07-13→17]`
# for "raised then updated" - silently never reached the founder's dashboard.
# It was not a rendering glitch: those items were invisible to him entirely.
# 21 lines fleet-wide were being dropped when this was found (4 swordfish,
# 17 thalon), including swordfish's syd2 SPEND GATE. A queue that silently
# drops entries is worse than no queue - it reads as "nothing pending".
# The date is still the first 10 chars; the text is now everything after the
# FIRST `]`, so both forms parse and neither depends on a fixed offset.

. "$(dirname "$0")/lib.sh"

main() {
  local items='[]' missing=true qf proj
  [ -f "$HOME/work/swordfish/agent_handoff/NEEDS-STEVEN.md" ] && missing=false
  for qf in "$HOME"/work/*/agent_handoff/NEEDS-STEVEN.md; do
    [ -f "$qf" ] || continue
    proj=$(basename "$(dirname "$(dirname "$qf")")")
    items=$(jq --arg p "$proj" --slurpfile new <(
      grep -E '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}[^]]*\]' "$qf" | while IFS= read -r line; do
        d=${line:3:10}
        jq -n --arg d "$d" --arg t "${line#*\]}" \
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
