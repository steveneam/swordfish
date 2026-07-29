#!/usr/bin/env bash
# needs-steven-hygiene.sh - keep the founder's action board honest.
#
# The board (agent_handoff/NEEDS-STEVEN.md, one per project) is maintained BY
# HAND and the dashboard renders it verbatim, never retiring anything itself.
# Both failure modes are silent, and both had actually happened by 2026-07-29:
#
#   1. RESOLVED lines left sitting on the board wearing a checkmark, so the
#      founder re-reads decisions he already made. Three of swordfish's own
#      lines were closed days-to-weeks earlier and still on the board.
#   2. INVISIBLE lines - written `- [2026-07-13->17]` (the raised-then-updated
#      form agents naturally use) when the collector's regex demanded `]`
#      immediately after the date. 21 lines fleet-wide were being dropped,
#      including a SPEND GATE. The collector now parses both forms; this check
#      is the guard that notices if that ever regresses.
#
# A queue that silently drops entries is worse than no queue: it reads as
# "nothing pending". This check is read-only and never edits a board.
#
#   usage: needs-steven-hygiene.sh [--stale-days N]   (default 21)

set -uo pipefail
cd "$(dirname "$0")/../.."

STALE_DAYS=21
[ "${1:-}" = "--stale-days" ] && STALE_DAYS=${2:-21}

today=$(date -u +%s)
warn=0

for qf in "$HOME"/work/*/agent_handoff/NEEDS-STEVEN.md; do
    [ -f "$qf" ] || continue
    proj=$(basename "$(dirname "$(dirname "$qf")")")
    echo "== $proj"

    # -- 1. lines that LOOK like actions but the collector cannot parse --------
    # Mirrors collect-needs.sh exactly; if the two ever disagree, that IS the bug.
    invisible=$(grep -nE '^- \[' "$qf" | grep -vcE '^[0-9]+:- \[[0-9]{4}-[0-9]{2}-[0-9]{2}[^]]*\]' || true)
    if [ "${invisible:-0}" -gt 0 ]; then
        echo "   INVISIBLE: $invisible line(s) start with '- [' but the collector will DROP them"
        grep -nE '^- \[' "$qf" | grep -vE '^[0-9]+:- \[[0-9]{4}-[0-9]{2}-[0-9]{2}[^]]*\]' \
            | cut -c1-100 | sed 's/^/     /'
        warn=$((warn+1))
    fi

    # -- 2. resolved items still on the live board ----------------------------
    # Anything announcing its own doneness belongs in archive/, not here.
    done_lines=$(grep -cE '^- \[[^]]*\][^|]*(✅|accounted, no action|DONE —|COMPLETE)' "$qf" || true)
    if [ "${done_lines:-0}" -gt 0 ]; then
        echo "   RESOLVED-BUT-PRESENT: $done_lines line(s) marked done are still on the board"
        grep -nE '^- \[[^]]*\][^|]*(✅|accounted, no action|DONE —|COMPLETE)' "$qf" \
            | cut -c1-100 | sed 's/^/     /'
        warn=$((warn+1))
    fi

    # -- 3. staleness, as information rather than a failure -------------------
    # Age is not a defect: several of these are deliberately "no rush, your
    # call". This exists so nobody has to eyeball dates to notice a year-old ask.
    while IFS= read -r line; do
        d=${line:3:10}
        e=$(date -u -d "$d" +%s 2>/dev/null) || continue
        age=$(( (today - e) / 86400 ))
        [ "$age" -ge "$STALE_DAYS" ] && printf '   STALE %3sd: %s\n' "$age" "$(printf '%s' "${line#*\]}" | cut -c1-72)"
    done < <(grep -E '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}[^]]*\]' "$qf")

    open=$(grep -cE '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}[^]]*\]' "$qf" || echo 0)
    echo "   open actions: $open"
done

echo
if [ "$warn" -eq 0 ]; then
    echo "== boards clean (no invisible lines, no resolved items left sitting)"
else
    echo "== $warn hygiene issue(s) above - fix before the next wrap"
fi
# Advisory by design: this reports, it does not gate a commit. Exit 0 always.
exit 0
