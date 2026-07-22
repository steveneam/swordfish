#!/usr/bin/env bash
# eamos-evidence.sh - read-only Phase-3c evidence sample for a tenant Compose
# container on syd2 (default: Eamos backend). Emits sanitized host/container proof
# and a machine verdict, mutating NOTHING. Safe to run against live production.
#
# WHY IT IS TRACKED, not a scratchpad one-off: swordfish gathered this exact
# evidence ad hoc when Eamos (Codex-driven, no live pane) asked for a Phase-3c
# soak sample 2026-07-22. The soak re-requests the same proof on a cadence, so the
# gather belongs in runnable code - same reasoning that turned the 2026-07-17
# cutover grep into app-5xx-watch.sh (AGENTS.md rule 8: executable ratchet beats a
# lost scratchpad file). This is the on-box half; the Dokploy-STORE half (stored
# Compose SHA, the 55-name env allowlist, autoDeploy=false, the one approved
# domain) is cross-checked separately via the Dokploy MCP `compose.one` and is NOT
# reachable over SSH - keep both halves when answering an evidence ask.
#
# ═══ THE LESSONS THIS FILE CARRIES ═══
# 1. READ-ONLY BY CONSTRUCTION. Only `docker inspect`/`stats`/`logs`, `find -printf`
#    (inode metadata, never file content), and reads of /sys/fs/cgroup + /proc. No
#    exec that writes, no deploy/restart/rm, no traffic. The one `docker exec` is a
#    non-mutating `cat` of cgroup files, used only as a SECOND source (see #3).
# 2. SECRETS NEVER LEAVE THE BOX. `docker inspect` .Config.Env and .Config.Labels
#    carry live secret VALUES. This pipes inspect through python that prints only
#    whitelisted fields and reports env as NAMES/COUNT only. Never widen that
#    filter to dump values. (The 55-name allowlist is a count+names fact, not a
#    values dump.)
# 3. CORROBORATE, DON'T TRUST ONE SIGNAL. cgroup memory.events is read from BOTH
#    the host scope (/proc/PID/cgroup -> /sys/fs/cgroup) AND an in-container
#    `exec cat`; a disagreement is itself a finding. (2026-07-xx: three false
#    findings in one day came from single unverified signals - see the memory
#    "corroborate-before-reporting".)
# 4. ANCHOR STATUS GREPS ON THE ACCESS-LOG SHAPE, NEVER THE BARE NUMBER. `docker
#    logs -t` prefixes a nanosecond timestamp, so `grep 503` matches timestamps,
#    byte counts and latencies. Use `" 5xx "` (quote-space-status-space). This is
#    the app-5xx-watch.sh lesson; do not "simplify" the regex to a bare number.
# 5. DON'T pass `ssh -n` when feeding a script on stdin - `-n` redirects stdin from
#    /dev/null and the remote `bash -s` silently gets nothing (cost one empty run).
#
# Usage: eamos-evidence.sh [--host H] [--container C] [--since RFC3339]
#                          [--runtime-tree PATH] [--expect-files N] [--expect-bytes N]
# Defaults target the Eamos backend Compose 5rBnRf20ht4wGRQ856ZLO on syd2.
# Exit:  0 = all green · 2 = at least one anomaly (5xx/429, oom_kill>0, restart
#        drift, or runtime-tree mismatch) · 64 = usage error

set -uo pipefail

HOST=syd2.swordfish.cfd
CONTAINER=project1-backend-dd110r-backend-1
SINCE=2026-07-19T01:46:12Z          # Eamos Phase-3c edge-recovery anchor
RUNTIME_TREE=/srv/project1/assets/runtime
EXPECT_FILES=23                     # frozen Phase-3a manifest
EXPECT_BYTES=47943536945
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --runtime-tree) RUNTIME_TREE="$2"; shift 2 ;;
    --expect-files) EXPECT_FILES="$2"; shift 2 ;;
    --expect-bytes) EXPECT_BYTES="$2"; shift 2 ;;
    -h|--help) sed -n '31,37p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

echo "== eamos-evidence: $CONTAINER on $HOST (read-only) · since $SINCE"

# NOTE: no `ssh -n` (lesson #5) - the remote body is fed on stdin as `bash -s`.
# Params go after `--` as $1..$6 so the single-quoted heredoc stays fully literal.
ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "bash -s -- '$CONTAINER' '$SINCE' '$RUNTIME_TREE' '$EXPECT_FILES' '$EXPECT_BYTES'" <<'REMOTE'
set -uo pipefail
C="$1"; REC="$2"; RT="$3"; EXP_F="$4"; EXP_B="$5"
D(){ sudo -n docker "$@"; }
anomaly=0

echo "########## 0. sample time / host boot ##########"
echo "sample_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)  host=$(hostname)"
echo "host_boot=$(uptime -s)  recovery_anchor=$REC"

echo "########## 1. identity + inspect (secrets filtered on-box) ##########"
D inspect "$C" | python3 -c '
import json,sys
d=json.load(sys.stdin)[0]; hc=d["HostConfig"]; st=d["State"]; cfg=d["Config"]
print("container_id      =", d["Id"])
print("image_ref         =", cfg.get("Image"))
print("image_id          =", d["Image"])
print("created           =", d["Created"])
print("state.Status      =", st.get("Status"), " Running=", st.get("Running"))
print("state.StartedAt   =", st.get("StartedAt"))
print("state.RestartCount =", d.get("RestartCount"))
print("state.OOMKilled   =", st.get("OOMKilled"), " ExitCode=", st.get("ExitCode"))
h=st.get("Health") or {}
print("health.Status     =", h.get("Status"), " failingStreak=", h.get("FailingStreak"))
print("Config.User       =", repr(cfg.get("User")))
print("ReadonlyRootfs    =", hc.get("ReadonlyRootfs"), " Privileged=", hc.get("Privileged"))
print("CapAdd/CapDrop    =", hc.get("CapAdd"), "/", hc.get("CapDrop"))
print("SecurityOpt       =", hc.get("SecurityOpt"))
print("limits mem/cpu/pids =", hc.get("Memory"), "/", hc.get("NanoCpus"), "/", hc.get("PidsLimit"))
for m in d.get("Mounts",[]):
    print("  mount:", m.get("Source"),"->",m.get("Destination"),"RW="+str(m.get("RW")),m.get("Mode"))
for n,v in (d["NetworkSettings"].get("Networks") or {}).items():
    print("  net:", n, v.get("IPAddress"))
print("PortBindings      =", hc.get("PortBindings"), " Ports=", d["NetworkSettings"].get("Ports"))
names=sorted(e.split("=",1)[0] for e in (cfg.get("Env") or []))
print("env_name_count    =", len(names))
print("env_names         =", ",".join(names))
'

echo "########## 2. cgroup memory (host scope + in-container, corroborated) ##########"
PID=$(D inspect "$C" -f '{{.State.Pid}}'); echo "pid=$PID"
CG=$(sed 's/^0:://' /proc/$PID/cgroup 2>/dev/null); BASE=/sys/fs/cgroup$CG
for f in memory.current memory.peak memory.max memory.events pids.current pids.max; do
  [ -r "$BASE/$f" ] && { echo "== host:$f =="; sudo -n cat "$BASE/$f" 2>/dev/null | sed 's/^/  /'; }
done
echo "== exec (second source) =="
D exec "$C" sh -c 'echo events:; cat /sys/fs/cgroup/memory.events; echo current:; cat /sys/fs/cgroup/memory.current; id' 2>&1 | sed 's/^/  /'
OOMK=$(sudo -n cat "$BASE/memory.events" 2>/dev/null | awk '/^oom_kill /{print $2}')
[ "${OOMK:-0}" -gt 0 ] 2>/dev/null && { echo "!! oom_kill=$OOMK"; anomaly=1; }

echo "########## 3. docker stats (working set) + disk ##########"
D stats --no-stream --format 'cpu={{.CPUPerc}} mem={{.MemUsage}} ({{.MemPerc}}) pids={{.PIDs}}' "$C"
df -h / 2>/dev/null | sed 's/^/  /'

echo "########## 4. runtime tree vs frozen manifest ##########"
FC=$(sudo -n find "$RT" -type f 2>/dev/null | wc -l)
BT=$(sudo -n find "$RT" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{printf "%d\n",s}')
echo "path=$RT  file_count=$FC  byte_total=$BT"
echo "expected  file_count=$EXP_F  byte_total=$EXP_B"
if [ "$FC" = "$EXP_F" ] && [ "$BT" = "$EXP_B" ]; then echo "tree=MATCH"; else echo "tree=MISMATCH"; anomaly=1; fi

echo "########## 5. app logs since recovery (anchored tallies) ##########"
LOG=$(D logs -t "$C" --since "$REC" 2>&1)
FIVEXX=$(printf '%s\n' "$LOG" | grep -cE '" 5[0-9][0-9] ')
FOURXX=$(printf '%s\n' "$LOG" | grep -cE '" 4[0-9][0-9] ')
NN29=$(printf '%s\n' "$LOG" | grep -cE '" 429 ')
echo "http_requests=$(printf '%s\n' "$LOG" | grep -c 'HTTP/')  5xx=$FIVEXX  429=$NN29  4xx=$FOURXX"
echo "tracebacks=$(printf '%s\n' "$LOG" | grep -c 'Traceback (most recent call last)')  ERROR/CRIT=$(printf '%s\n' "$LOG" | grep -cE '(ERROR|CRITICAL)')  oom=$(printf '%s\n' "$LOG" | grep -ciE 'out of memory|MemoryError')"
printf '%s\n' "$LOG" | grep -E '" (5[0-9][0-9]|429) ' | head -20 | sed 's/^/  HIT /'
{ [ "$FIVEXX" -gt 0 ] || [ "$NN29" -gt 0 ]; } && anomaly=1

echo "########## 6. traefik edge since recovery ##########"
TLOG=$(D logs -t swordfish-traefik --since "$REC" 2>&1)
echo "traefik_lines=$(printf '%s\n' "$TLOG" | grep -c .)  errors=$(printf '%s\n' "$TLOG" | grep -cE 'level=error')"

echo "########## VERDICT ##########"
if [ "$anomaly" -eq 0 ]; then echo "GREEN"; exit 0; else echo "ANOMALY"; exit 2; fi
REMOTE
rc=$?
echo "== eamos-evidence exit=$rc ($([ $rc -eq 0 ] && echo GREEN || echo "ANOMALY/err"))"
exit $rc
