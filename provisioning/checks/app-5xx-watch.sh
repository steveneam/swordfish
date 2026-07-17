#!/usr/bin/env bash
# app-5xx-watch.sh - read-only watch on a tenant container's HTTP access log:
# report 5xx recurrence WITH the infra context needed to tell app faults from
# box faults. Mutates nothing. Safe to run against a live production tenant.
#
# WHY IT IS TRACKED, not a scratchpad one-off: swordfish wrote this ad hoc during
# eamos's 2026-07-17 cutover, put the hard-won lesson in a /tmp file, and would
# have lost it the moment the session ended. A lesson living only in scratchpad
# (or in a memory) is the weakest rung of AGENTS.md rule 8. The lesson belongs in
# code that runs.
#
# ═══ THE LESSON THIS FILE EXISTS TO CARRY ═══
# GREP FOR A STATUS CODE MUST BE ANCHORED ON THE ACCESS-LOG SHAPE, NEVER ON THE
# BARE NUMBER. `docker logs -t` prefixes every line with a nanosecond timestamp:
#
#   2026-07-17T11:57:06.262502936Z INFO: ... "GET / HTTP/1.1" 404 Not Found
#                          ^^^ a bare grep "503" matches THIS
#
# Swordfish grepped "503", found 11 matches, reported a phantom "third 503" as an
# unexplained outlier, and built a whole hypothesis on it. The tenant (eamos)
# caught it by reconciling against Dokploy's own log read. Status-anchored: 2.
#
#   grep -c "503"        -> 11   WRONG (timestamps, byte counts, latencies)
#   grep -cE '" 503 '    ->  2   RIGHT (the quote+space shape of the status field)
#
# The general rule: a number appears in a log line for MANY reasons. Anchor on
# structure. And corroborate a finding with a second method before reporting it -
# that is what caught this one, and it was the tenant who did it, not swordfish.
#
# Usage: app-5xx-watch.sh --host <ssh-host> --container <name> [--route <path>]
#                        [--ticks N] [--interval SEC]
# Exit:  0 = watch completed with no 5xx · 2 = at least one 5xx observed

set -uo pipefail
HOST=""; CONTAINER=""; ROUTE=""; TICKS=240; INTERVAL=60
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --route) ROUTE="$2"; shift 2 ;;
    --ticks) TICKS="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$HOST" ] && [ -n "$CONTAINER" ] || { echo "usage: $0 --host H --container C [--route /api/x]"; exit 64; }

# Anchored on the access-log status field: a literal quote, space, 5xx, space.
# THIS REGEX IS THE POINT OF THE FILE - do not "simplify" it to a bare number.
FIVEXX='" 5[0-9][0-9] '
FILTER=${ROUTE:-HTTP/}
seen=0

echo "== app-5xx-watch: $CONTAINER on $HOST${ROUTE:+ (route $ROUTE)} - read-only, ${TICKS}x${INTERVAL}s"

for _ in $(seq 1 "$TICKS"); do
  OUT=$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "
    L=\$(sudo -n docker logs -t $CONTAINER --since $((INTERVAL*5))s 2>&1 | grep -F '$FILTER')
    REQ=\$(printf '%s\\n' \"\$L\" | grep -c 'HTTP/')
    ERR=\$(printf '%s\\n' \"\$L\" | grep -cE '$FIVEXX')
    MEM=\$(sudo -n docker stats --no-stream --format '{{.MemPerc}}' $CONTAINER 2>/dev/null)
    ST=\$(sudo -n docker inspect $CONTAINER -f '{{.RestartCount}}/{{.State.OOMKilled}}/{{.State.Health.Status}}' 2>/dev/null)
    OK=\$(sudo -n docker exec $CONTAINER sh -c 'grep ^oom_kill /sys/fs/cgroup/memory.events' 2>/dev/null | awk '{print \$2}')
    echo \"req=\${REQ:-0} err5xx=\${ERR:-0} mem=\${MEM:-?} restart/oom/health=\${ST:-?} oom_kill=\${OK:-?}\"
  " 2>/dev/null)

  if [ -z "$OUT" ]; then echo "$(date -u +%H:%M:%SZ) sample failed (ssh) - retrying"; sleep "$INTERVAL"; continue; fi
  E=$(sed -n 's/.*err5xx=\([0-9]*\).*/\1/p' <<<"$OUT")
  TS=$(date -u +%H:%M:%SZ)
  if [ "${E:-0}" -gt 0 ]; then
    # The whole value of this tool: a 5xx reported WITH restart/OOM/cgroup/mem at
    # that instant, so the tenant can rule the box in or out without asking.
    echo "$TS RECURRED-5xx $OUT"
    seen=1
  else
    echo "$TS ok $OUT"
  fi
  sleep "$INTERVAL"
done

[ "$seen" -eq 0 ] && { echo "== no 5xx observed"; exit 0; }
echo "== 5xx observed - see lines above (infra context is attached to each)"
exit 2
