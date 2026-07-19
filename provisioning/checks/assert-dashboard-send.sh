#!/usr/bin/env bash
set -uo pipefail

# assert-dashboard-send.sh - proves /api/agent-send on a THROWAWAY server
# instance with a STUB agent-comm: the endpoint must pass exactly the pinned
# provenance (--from Steven --channel dashboard), refuse malformed input
# server-side, and map agent-comm's exit codes faithfully. The production
# server and the real agent-comm are never touched.

SERVER=${SERVER:-/home/deploy/work/swordfish/provisioning/workstation/dashboard-server.py}
PORT=${TEST_PORT:-8092}
tmp=$(mktemp -d)
pass=0; fail=0
ok()  { echo "  ok   - $1"; pass=$((pass+1)); }
bad() { echo "  FAIL - $1"; fail=$((fail+1)); }
cleanup() { [ -n "${srv_pid:-}" ] && kill "$srv_pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

# stub agent-comm: records argv; exit code keyed by target name
cat > "$tmp/agent-comm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$1" in
  sessions) echo '[{"session":"alpha","claude":true,"state":"idle","activity":"","composer":""}]'; exit 0 ;;
  ledger)   echo "row1"; exit 0 ;;
esac
for a in "$@"; do case "$a" in parked) exit 3 ;; unclear) exit 4 ;; esac; done
exit 0
EOF
chmod +x "$tmp/agent-comm"

DASH_DIR="$tmp" DASH_PORT="$PORT" AGENT_COMM_BIN="$tmp/agent-comm" STUB_LOG="$tmp/argv.log" \
  python3 "$SERVER" >"$tmp/server.log" 2>&1 &
srv_pid=$!
for _ in $(seq 1 20); do curl -fsS -m 2 "http://127.0.0.1:$PORT/api/agent-roster" >/dev/null 2>&1 && break; sleep 0.5; done

post() { curl -fsS -m 30 -X POST "http://127.0.0.1:$PORT/api/agent-send" \
           -H 'Content-Type: application/json' -d "$1"; }

# 1 · happy path: provenance pinned, code 0 -> ok
r=$(post '{"target":"alpha","text":"hello there"}')
case "$r" in *'"status": "ok"'*|*'"status":"ok"'*) ok "valid send -> ok" ;; *) bad "valid send: $r" ;; esac
argv=$(tail -1 "$tmp/argv.log" 2>/dev/null)
case "$argv" in "send --from Steven --channel dashboard alpha hello there") ok "provenance pinned server-side" ;; *) bad "argv wrong: $argv" ;; esac

# 2 · exit-code mapping: parked draft (3) and unclear (4)
r=$(post '{"target":"parked","text":"x"}')
case "$r" in *refused-draft*) ok "exit 3 -> refused-draft" ;; *) bad "parked mapping: $r" ;; esac
r=$(post '{"target":"unclear","text":"x"}')
case "$r" in *refused-unclear*) ok "exit 4 -> refused-unclear" ;; *) bad "unclear mapping: $r" ;; esac

# 2b · coordination pairing: clause appended server-side; bad partners refused
r=$(post '{"target":"alpha","text":"do the thing","with":["bravo","charlie"]}')
argv=$(tail -1 "$tmp/argv.log" 2>/dev/null)
case "$argv" in *"do the thing — coordinate LIVE with bravo, charlie"*) ok "pairing clause appended" ;; *) bad "pairing argv: $argv" ;; esac
r=$(post '{"target":"alpha","text":"x","with":["../evil"]}')
case "$r" in *bad-request*) ok "bad partner charset refused" ;; *) bad "bad partner: $r" ;; esac
r=$(post '{"target":"alpha","text":"x","with":["alpha"]}')
case "$r" in *bad-request*) ok "target-as-partner refused" ;; *) bad "self partner: $r" ;; esac

# 3 · server-side input refusals (stub must NOT be invoked for these)
n_before=$(wc -l < "$tmp/argv.log")
r=$(post '{"target":"alpha","text":""}')
case "$r" in *bad-request*) ok "empty text refused" ;; *) bad "empty text: $r" ;; esac
r=$(post '{"target":"../evil","text":"x"}')
case "$r" in *bad-request*) ok "bad-charset target refused" ;; *) bad "bad target: $r" ;; esac
long=$(printf 'a%.0s' $(seq 1 2001))
r=$(post "{\"target\":\"alpha\",\"text\":\"$long\"}")
case "$r" in *bad-request*) ok "overlong text refused" ;; *) bad "overlong: $r" ;; esac
n_after=$(wc -l < "$tmp/argv.log")
[ "$n_before" -eq "$n_after" ] && ok "refused inputs never reached agent-comm" || bad "stub invoked on refused input"

# 4 · roster + ledger pass-throughs
r=$(curl -fsS -m 5 "http://127.0.0.1:$PORT/api/agent-roster")
case "$r" in *'"session": "alpha"'*|*'"session":"alpha"'*) ok "roster pass-through" ;; *) bad "roster: $r" ;; esac
r=$(curl -fsS -m 5 "http://127.0.0.1:$PORT/api/agent-ledger")
case "$r" in *row1*) ok "ledger pass-through" ;; *) bad "ledger: $r" ;; esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
