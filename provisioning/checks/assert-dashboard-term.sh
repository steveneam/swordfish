#!/usr/bin/env bash
set -uo pipefail

# assert-dashboard-term.sh - the live-terminal mirror invariants, proven
# against a THROWAWAY dashboard-server instance with a stub tmux/ssh before
# the endpoints are trusted (dashboard redesign 2026-07-19):
#
#   1. the server's tmux argv surface is READ-ONLY: only list-sessions and
#      capture-pane ever reach the binary (send-keys absent from the source,
#      machine-checked - agent-comm stays the single send path);
#   2. a bad-charset session name is refused WITHOUT invoking tmux at all;
#      a charset-clean but unknown name 404s (membership gate);
#   3. the capture round-trip works and the &h= hash short-circuit answers
#      "unchanged" (the idle-pane bandwidth contract);
#   4. the hermes journal endpoint is a cached single-flight: a second hit
#      inside the TTL answers from cache, never a second ssh;
#   5. the ANSI->HTML converter escapes hostile pane text (agents print
#      arbitrary bytes; an <img onerror=...> must come out inert).
#
# Verdicts are captured then tested - never piped through head/grep chains
# (verification-exit-codes lesson).

WS=/home/deploy/work/swordfish/provisioning/workstation
SERVER=${SERVER:-$WS/dashboard-server.py}
ANSI_JS=${ANSI_JS:-$WS/dashboard-app/ansi.js}
PORT=${TEST_PORT:-8092}

fail() { echo "FAIL: $1"; cleanup; exit 1; }
cleanup() { [ -n "${srv_pid:-}" ] && kill "$srv_pid" 2>/dev/null; rm -rf "$tmpdir"; }

tmpdir=$(mktemp -d)

# ---- stub tmux: logs every argv line, answers the two read-only calls ------
cat > "$tmpdir/tmux" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG:?}"
case "$1" in
  list-sessions) printf 'alpha|1784000000|claude\n' ;;
  capture-pane)  printf 'plain \x1b[31mred\x1b[0m <img src=x onerror=alert(1)>\n' ;;
  *) exit 1 ;;
esac
STUB
# ---- stub ssh: -O check succeeds; a journal call emits three lines ---------
cat > "$tmpdir/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${STUB_LOG:?}"
case "$*" in
  *"-O check"*) exit 0 ;;
  *journalctl*) printf 'line1\nline2\nline3\n' ;;
esac
STUB
chmod +x "$tmpdir/tmux" "$tmpdir/ssh"

STUB_LOG="$tmpdir/argv.log" DASH_PORT=$PORT DASH_DIR="$tmpdir" \
  TMUX_BIN="$tmpdir/tmux" SSH_BIN="$tmpdir/ssh" \
  python3 "$SERVER" >"$tmpdir/server.log" 2>&1 & srv_pid=$!
export STUB_LOG="$tmpdir/argv.log"
for _ in $(seq 1 20); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
  sleep 0.25
done

# 1+3. list + capture round-trip + hash short-circuit
listing=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/term/list")
case "$listing" in *alpha*) : ;; *) fail "term/list missing the stub session (got: $listing)" ;; esac

cap=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/term/capture?session=alpha&lines=40")
case "$cap" in *'"text"'*red*) : ;; *) fail "capture did not return pane text (got: $cap)" ;; esac
hash=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["hash"])' "$cap") \
  || fail "capture response not JSON ($cap)"
again=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/term/capture?session=alpha&lines=40&h=$hash")
case "$again" in *'"unchanged": true'*|*'"unchanged":true'*) : ;; *) fail "hash short-circuit broken (got: $again)" ;; esac

# 2. refusals - bad charset (never reaches tmux), unknown name (404)
code=$(curl -s -o "$tmpdir/bad.json" -w '%{http_code}' --max-time 5 \
  "http://127.0.0.1:$PORT/api/term/capture?session=%2e%2e")
[ "$code" = 400 ] || fail "bad-charset name not refused with 400 (got $code)"
if grep -q '\.\.' "$tmpdir/argv.log"; then
  fail "REFUSAL BROKEN: a bad-charset name reached the tmux binary"
fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  "http://127.0.0.1:$PORT/api/term/capture?session=zzznotasession")
[ "$code" = 404 ] || fail "unknown session not refused with 404 (got $code)"
if grep -q 'zzznotasession' "$tmpdir/argv.log"; then
  fail "MEMBERSHIP GATE BROKEN: an unknown name reached the tmux binary"
fi

# 4. hermes journal: live then cached inside the TTL
j1=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/hermes/journal?lines=25")
case "$j1" in *line2*) : ;; *) fail "journal tail did not return lines (got: $j1)" ;; esac
j2=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/api/hermes/journal?lines=25")
case "$j2" in *'"cached": true'*|*'"cached":true'*) : ;; *) fail "journal TTL cache broken - second hit was not cached (got: $j2)" ;; esac
ssh_journal_calls=$(grep -c 'journalctl' "$tmpdir/argv.log")
[ "$ssh_journal_calls" = 1 ] || fail "single-flight broken: $ssh_journal_calls journalctl calls for two requests"

# 1b. the tmux argv surface is exactly the two read-only subcommands
bad_argv=$(grep -v '^ssh ' "$tmpdir/argv.log" | grep -cvE '^(list-sessions|capture-pane) ')
[ "$bad_argv" = 0 ] || fail "tmux argv surface widened beyond list-sessions/capture-pane: $(grep -v '^ssh ' "$tmpdir/argv.log" | grep -vE '^(list-sessions|capture-pane) ')"
sendkeys=$(grep -c 'send-keys' "$SERVER")
[ "$sendkeys" = 0 ] || fail "send-keys appears in dashboard-server.py - the no-keystroke-path invariant"

# 5. hostile pane text comes out inert
xss=$(node -e '
  const A = require(process.argv[1]);
  const out = A.ansiToHtml("x \x1b[31m<img src=x onerror=alert(1)>\x1b[0m <script>y");
  if (out.includes("<img") || out.includes("<script")) { console.log("LEAK"); process.exit(0); }
  console.log("ESCAPED");' "$ANSI_JS")
[ "$xss" = ESCAPED ] || fail "ANSI converter leaked markup from hostile pane text"

cleanup
echo "OK: term endpoints are read-only, gated, hash-cached; journal is single-flight; hostile pane text stays inert"
