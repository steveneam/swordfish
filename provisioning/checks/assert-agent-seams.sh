#!/usr/bin/env bash
set -euo pipefail

# assert-agent-seams.sh - the 2026-07-16 incident, encoded as executable
# checks (rule 8: executable beats documentary). Run on syd4 (workstation);
# safe anytime - read-only except an ephemeral localhost listener.
#
# What it guards:
#   1. the tmux server belongs to agent-tmux.service, NOT any other unit's
#      cgroup (a code-server restart once killed every agent on the box)
#   2. the code-server unit carries the dual --proxy-domain form (portless
#      Ports-tab links were dead on the founder's Mac; port-carrying Hosts
#      did not match the proxy at all)
#   3. end-to-end: an app on an arbitrary port is reachable through the
#      preview proxy for BOTH Host shapes a client can send
#
# Part of the monthly documented-commands pass. Exit 0 = all seams hold.

fail() { echo "FAIL: $*"; exit 1; }

# --- 1. tmux server cgroup ----------------------------------------------------
systemctl is-active --quiet agent-tmux || fail "agent-tmux.service not active"
pid=$(systemctl show -p MainPID --value agent-tmux)
[ "${pid:-0}" != 0 ] || fail "agent-tmux has no MainPID"
cg=$(cat "/proc/$pid/cgroup" 2>/dev/null) || fail "cannot read tmux server cgroup"
case "$cg" in *agent-tmux.service*) ;; *) fail "tmux server not in agent-tmux.service cgroup" ;; esac
case "$cg" in *code-server*) fail "tmux server inside code-server's cgroup (the 06:43 incident shape)" ;; esac

# --- 2. code-server unit shape ------------------------------------------------
u=/etc/systemd/system/code-server.service
[ -f "$u" ] || fail "code-server unit missing at $u"
grep -q -- '--proxy-domain localhost:8080' "$u" \
  || fail "unit missing '--proxy-domain localhost:8080' (browser Hosts won't proxy; Ports-tab links lose :8080)"
grep -Eq -- '--proxy-domain localhost( |$)' "$u" \
  || fail "unit missing portless '--proxy-domain localhost' (compat net)"
# the port-carrying domain must come FIRST - it is what VSCODE_PROXY_URI uses
first=$(grep -o -- '--proxy-domain [^ ]*' "$u" | head -1)
[ "$first" = "--proxy-domain localhost:8080" ] \
  || fail "proxy-domain order wrong ('$first' first) - links would drop :8080"

# --- 3. end-to-end preview proxy ----------------------------------------------
port=39999
python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
lp=$!
trap 'kill "$lp" 2>/dev/null || true' EXIT
sleep 1
c_with=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -H "Host: $port.localhost:8080" http://127.0.0.1:8080/ || true)
c_bare=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -H "Host: $port.localhost" http://127.0.0.1:8080/ || true)
[ "$c_with" = 200 ] || fail "preview proxy broken for browser-shaped Host with :8080 (got ${c_with:-none})"
[ "$c_bare" = 200 ] || fail "preview proxy broken for portless Host (got ${c_bare:-none})"

echo "OK: agent-tmux owns the tmux server; preview proxy green for both Host shapes"
