#!/usr/bin/env bash
set -uo pipefail

# generate-dashboard.sh - founder cockpit orchestrator (v3, the collectors ->
# JSON -> renderer split of dashboard-cockpit-plan-2026-07-13.md; v2 was a
# single generator emitting project buttons only).
#
#   collectors/collect-*.sh  each write ~/dashboard/data/<name>.json
#                            (parallel, individually timeboxed, individually
#                            fail-safe: a dead collector = an UNAVAILABLE card
#                            + the previous JSON stays for its age display)
#   render-dashboard.py      composes ~/dashboard/index.html from the JSON
#
# The systemd timer (setup-dashboard.sh) runs THIS file every 15 min; the
# static server on 8090 (localhost-only, the Mac tunnel is the auth) serves
# the result at http://localhost:8080/proxy/8090/ .
#
# The OUTPUT (html + json) is untracked BY DESIGN: folder names on this box
# can include guarded portfolio names - they must never enter this repo.

DIR=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/dashboard/data"
. "$DIR/collectors/lib.sh"

# prime the ssh master BEFORE forking: three collectors hitting a cold
# ControlMaster=auto in parallel race the socket, and every loser opens a
# direct connection = a pam Telegram ping (code review 2026-07-13). One
# check-or-start here makes the "one ping ever" claim structural.
ssh -O check "${SSH_CM[@]}" syd3 2>/dev/null \
  || ssh "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes -fN syd3 2>/dev/null \
  || true

pids=()
for c in "$DIR"/collectors/collect-*.sh; do
  timeout 120 bash "$c" &
  pids+=($!)
done
rc=0
for p in "${pids[@]}"; do
  wait "$p" || rc=1
done
[ "$rc" -ne 0 ] && echo "note: at least one collector failed (its card shows UNAVAILABLE)"

exec python3 "$DIR/render-dashboard.py"
