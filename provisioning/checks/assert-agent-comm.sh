#!/usr/bin/env bash
set -uo pipefail

# assert-agent-comm.sh - proves agent-comm's refusal invariants and send
# mechanics on a THROWAWAY tmux server (-L socket) with stub "claude" panes.
# The production agent server is never touched. Verdicts are captured then
# tested - never piped through grep chains (verification-exit-codes lesson).

AC=${AC:-/home/deploy/work/swordfish/provisioning/workstation/agent-comm.sh}
SOCK="ac-assert-$$"
tmp=$(mktemp -d)
pass=0; fail=0

cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

ok()   { echo "  ok   - $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL - $1"; fail=$((fail+1)); }

# hermetic env: outside any tmux (identity paths deterministic), test ledger
run() { env -u TMUX -u TMUX_PANE AGENT_COMM_SOCKET="$SOCK" AGENT_COMM_LEDGER="$tmp/ledger.log" "$AC" "$@"; }

# --- 1 · classify() unit table (the mirage-vs-draft edge) --------------------
v=$("$AC" _classify "❯ " "❯ " x);                    [ "$v" = empty ]   && ok "classify: bare prompts = empty"          || bad "classify bare: got $v"
v=$("$AC" _classify "❯ old submitted msg" "❯ x" x);  [ "$v" = empty ]   && ok "classify: probe replaced = mirage/empty" || bad "classify mirage: got $v"
v=$("$AC" _classify "❯ parked" "❯ parkedx" x);       [ "$v" = draft ]   && ok "classify: probe appended = real draft"   || bad "classify draft: got $v"
v=$("$AC" _classify "❯ parked" "❯ something else" x);[ "$v" = unclear ] && ok "classify: mutation = unclear"            || bad "classify unclear: got $v"

# --- 2 · stub sessions on the throwaway server -------------------------------
# fake claude: comm becomes the script basename, so pane_current_command=claude
# pane_current_command = basename of cmdline[0], NOT comm - so the stub must
# be an EXECUTABLE named claude (a bash copy), with the logic in -c and only
# builtins inside (an exec'd cat/sleep would rename the pane's command)
cp /bin/bash "$tmp/claude"
tmux -L "$SOCK" new-session -d -s alpha \
  "$tmp/claude -c 'while IFS= read -r l; do printf \"%s\\n\" \"\$l\"; done'"
tmux -L "$SOCK" new-session -d -s parked \
  "$tmp/claude -c 'printf \"❯ parked draft\"; while :; do read -r -t 300 _ || :; done'"
tmux -L "$SOCK" new-session -d -s bare bash
# wrapper shape: relay-style `bash -c 'claude; ...'` - pane cmd stays bash,
# claude is a CHILD; the descendant-aware matcher must still find this pane
tmux -L "$SOCK" new-session -d -s wrapped \
  "bash -c '\"$tmp/claude\" -c \"while IFS= read -r l; do printf \\\"%s\\\\n\\\" \\\"\\\$l\\\"; done\"; sleep 5'"
sleep 1

# --- 3 · refusals ------------------------------------------------------------
run send --from tester ghost "hello" >/dev/null 2>&1;  [ $? -eq 2 ] && ok "unknown session refused (2)"        || bad "unknown session not refused"
run send --from tester bare "hello" >/dev/null 2>&1;   [ $? -eq 2 ] && ok "no-claude-pane refused (2)"         || bad "bare session not refused"
run send alpha "hello" >/dev/null 2>&1;                [ $? -eq 2 ] && ok "anonymous (no tmux, no --from) refused (2)" || bad "anonymous send not refused"
run send --from tester parked "hello" >/dev/null 2>&1; [ $? -eq 3 ] && ok "parked real draft refused (3)"      || bad "parked draft not refused"
long=$(printf 'a%.0s' $(seq 1 2001))
run send --from tester alpha "$long" >/dev/null 2>&1;  [ $? -eq 2 ] && ok "overlong body refused (2)"          || bad "overlong body not refused"

# --- 4 · send mechanics: prefix, newline collapse, single line, ledger -------
out=$(run send --from Steven --channel dashboard alpha $'line one\nline two' 2>&1); rc=$?
pane=$(tmux -L "$SOCK" capture-pane -t alpha -p)
hits=$(grep -cF '[Steven via dashboard] line one line two' <<<"$pane")
[ "$rc" -eq 0 ] || [ "$rc" -eq 5 ]        && ok "send returned ($rc)"                    || bad "send rc=$rc: $out"
[ "$hits" -ge 1 ]                          && ok "prefixed + newline-collapsed one-liner landed" || bad "expected line not in pane"
multi=$(grep -cF 'line two' <<<"$pane"); single=$(grep -cF 'line one line two' <<<"$pane")
[ "$multi" -eq "$single" ]                 && ok "no second turn from the newline"        || bad "newline produced a split line"
lrow=$(tail -1 "$tmp/ledger.log" 2>/dev/null)
case "$lrow" in *"Steven -> alpha"*"line one line two"*) ok "ledger row written" ;; *) bad "ledger row missing/wrong: $lrow" ;; esac

# --- 5 · sessions roster sees the stubs; wrapper shape resolves --------------
roster=$(run sessions)
case "$roster" in *alpha*parked*|*parked*alpha*) ok "roster lists stub sessions" ;; *) bad "roster incomplete: $roster" ;; esac
case "$roster" in *"bare"*"no live claude pane"*) ok "roster flags claude-less session" ;; *) bad "bare not flagged" ;; esac
out=$(run send --from tester wrapped "wrapper ping" 2>&1); rc=$?
wpane=$(tmux -L "$SOCK" capture-pane -t wrapped -p)
wany=$(grep -cF '[tester via agent-comm] wrapper ping' <<<"$wpane")
{ [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ]; } && [ "$wany" -ge 1 ] \
  && ok "wrapper-shape pane (bash -c claude child) found + reached" \
  || bad "wrapper shape failed rc=$rc hits=$wany: $out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
