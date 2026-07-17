#!/usr/bin/env bash
set -uo pipefail

# who-is-live.sh - WHO WILL I KILL? Pre-flight for any box-mutating action.
#
# WHY THIS EXISTS - swordfish crashed live agents TWICE, same root cause:
#   2026-07-16  `systemctl restart code-server`      -> killed every agent
#   2026-07-17  `apt-get install postgresql-17`      -> needrestart restarted
#               code-server -> killed a tenant agent mid-run, detached another
#
# The mechanisms differ (direct restart, then apt's needrestart; next time it
# will be something else), so guarding each vector is whack-a-mole. What both
# share is an agent taking a box action WITHOUT CHECKING ITS BLAST RADIUS. The
# 07-16 remediation (agent-tmux.service) was right and it WORKED on 07-17 -
# everything inside it survived. The only casualty was the one agent outside it,
# and its exposure was written in swordfish's own handoff file, unread.
#
# So: this answers the question that was never asked, mechanically, in one line.
# It is a GATE, not a report - call it before you touch the box:
#
#     provisioning/checks/who-is-live.sh --gate || { echo "agents exposed"; exit 1; }
#
# EXIT: 0 = every agent is sheltered (or none running). 1 = at least one agent
# would die if code-server restarts. Use --gate in scripts; bare for a listing.
#
# THE SHELTER: agent-tmux.service runs the tmux server in its OWN systemd cgroup,
# so its sessions do not die with code-server. An agent in a code-server terminal
# that is NOT inside tmux lives in code-server's cgroup and dies with it. PPID=1
# does NOT mean escaped - check the cgroup, which is the only truth here.

GATE=0
[ "${1:-}" = "--gate" ] && GATE=1

exposed=0; sheltered=0
rows=""

for p in $(pgrep -x claude 2>/dev/null; pgrep -f 'bin/codex$' 2>/dev/null); do
    [ -r "/proc/$p/cgroup" ] || continue
    cg=$(cut -d: -f3 "/proc/$p/cgroup" 2>/dev/null | head -1)
    cwd=$(readlink "/proc/$p/cwd" 2>/dev/null | sed 's|^/home/deploy/work/||')
    et=$(ps -p "$p" -o etime= 2>/dev/null | tr -d ' ')
    case "$cg" in
        */agent-tmux.service)
            sheltered=$((sheltered+1))
            rows="$rows$(printf '  OK       %-8s %-12s up %-10s sheltered (agent-tmux.service)\n' "$p" "${cwd:-?}" "$et")\n" ;;
        *)
            exposed=$((exposed+1))
            rows="$rows$(printf '  EXPOSED  %-8s %-12s up %-10s %s\n' "$p" "${cwd:-?}" "$et" "$cg")\n" ;;
    esac
done

printf '== agents on %s: %d sheltered, %d EXPOSED\n' "$(hostname -s)" "$sheltered" "$exposed"
[ -n "$rows" ] && printf '%b' "$rows"

if [ "$exposed" -gt 0 ]; then
    cat <<'WARN'

  ^ These die if code-server restarts - and apt can restart it for you
    (needrestart). setup-needrestart-guard.sh blocks the default path, but do
    not lean on it: pass NEEDRESTART_MODE=l on any apt call, and prefer to wait.

  To shelter one: re-open its terminal via the agent-term profile (which runs
  `tmux new -A -s <folder>`), or from inside its session: `tmux new -A -s <name>`.
  A DETACHED tmux session is NOT dead - reattaching restores it intact.
WARN
    [ "$GATE" -eq 1 ] && exit 1
fi

if [ "$GATE" -eq 1 ]; then
    if [ "$sheltered" -gt 0 ]; then
        echo "== GATE: all $sheltered agent(s) sheltered - a code-server restart is survivable"
    else
        echo "== GATE: no agents running - box action is free"
    fi
fi
exit 0
