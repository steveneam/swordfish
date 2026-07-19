#!/usr/bin/env bash
set -uo pipefail

# assert-dashboard-reset.sh - the reset-terminals refusal invariant, proven
# with a stub process tree BEFORE the button is trusted (plan requirement,
# research/dashboard-terminal-controls-plan-2026-07-17.md: "endpoint refuses
# to kill a shell with children").
#
# Method: launch a THROWAWAY dashboard-server instance on a test port whose
# PANEL_CGROUP_SUFFIX is this script's OWN cgroup, so two stub bashes started
# here look exactly like panel shells to the scanner:
#   stub A: childless bash (blocks opening a fifo - the open happens in the
#           read builtin, no child process, comm stays "bash")
#   stub B: bash with a sleep child (a live agent's shape)
# Then POST the reset and assert: A is HUP'd and dies; B and its child SURVIVE
# and are reported refused. The production instance is never touched.
#
# Verdicts are captured then tested - never piped through head/grep chains
# (verification-exit-codes lesson).

SERVER=${SERVER:-/home/deploy/work/swordfish/provisioning/workstation/dashboard-server.py}
PORT=${TEST_PORT:-8091}

fail() { echo "FAIL: $1"; cleanup; exit 1; }

tmpdir=$(mktemp -d)
fifo="$tmpdir/block.fifo"
mkfifo "$fifo"

cleanup() {
    [ -n "${srv_pid:-}" ] && kill "$srv_pid" 2>/dev/null
    [ -n "${stub_a:-}" ] && kill -9 "$stub_a" 2>/dev/null
    [ -n "${stub_b:-}" ] && kill -9 "$stub_b" 2>/dev/null
    rm -rf "$tmpdir"
}

my_cgroup=$(cut -d: -f3 "/proc/$$/cgroup" | head -1)
[ -n "$my_cgroup" ] || { echo "SKIP: no readable cgroup for the test harness"; exit 0; }

# stub A: childless panel-shaped bash (read builtin blocks on the fifo open)
bash -c "read -t 60 _ < \"$fifo\"" & stub_a=$!
# stub B: panel-shaped bash sheltering a child (the live-agent shape)
bash -c "sleep 60 & wait" & stub_b=$!
sleep 0.3
kill -0 "$stub_a" 2>/dev/null || fail "stub A did not start"
kill -0 "$stub_b" 2>/dev/null || fail "stub B did not start"

DASH_PORT=$PORT DASH_DIR="$tmpdir" PANEL_CGROUP_SUFFIX="$my_cgroup" \
    python3 "$SERVER" >"$tmpdir/server.log" 2>&1 & srv_pid=$!
for _ in $(seq 1 20); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
    sleep 0.25
done

preview=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/reset-terminals/preview")
case "$preview" in
    *"$stub_a"*) : ;;
    *) fail "preview does not list the childless stub (got: $preview)" ;;
esac
case "$preview" in
    *"$stub_b"*) : ;;
    *) fail "preview does not list the with-children stub as refused (got: $preview)" ;;
esac

result=$(curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/api/reset-terminals")
sleep 0.5

# the childless stub must be gone (SIGHUP terminates a non-exec'd bash)
if kill -0 "$stub_a" 2>/dev/null; then
    fail "childless stub survived the reset (result: $result)"
fi
# the with-children stub and its child must BOTH survive, and be reported
kill -0 "$stub_b" 2>/dev/null || fail "REFUSAL INVARIANT BROKEN: shell with children was killed (result: $result)"
sleep_child=$(pgrep -P "$stub_b" | head -1)
[ -n "$sleep_child" ] || fail "REFUSAL INVARIANT BROKEN: the stub's child is gone (result: $result)"
case "$result" in
    *refused_live*"$stub_b"*) : ;;
    *) fail "with-children stub not reported as refused (result: $result)" ;;
esac
case "$result" in
    *hupped*"$stub_a"*) : ;;
    *) fail "childless stub not reported as hupped (result: $result)" ;;
esac

cleanup
echo "OK: reset-terminals HUPs childless panels and refuses live ones (stub tree proven)"
