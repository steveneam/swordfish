#!/usr/bin/env bash
set -uo pipefail

# relay-stop-hook.sh - Claude Code user-level Stop hook (E1 design decision
# 4). Fires at the end of EVERY agent turn on this box, so the no-marker
# path must be instant and silent: only turns that swordfish-relay.sh
# injected (marker file present for this project) relay their reply back to
# the founder's Telegram topic. Normal terminal work never leaves the box.

MARKER_DIR="$HOME/.claude/relay-pending"
[ -d "$MARKER_DIR" ] || exit 0
ls "$MARKER_DIR"/*.json >/dev/null 2>&1 || exit 0   # fast path: no relays pending

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
[ -n "$cwd" ] && [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# match the marker whose project dir contains this session's cwd
marker="" dir=""
for m in "$MARKER_DIR"/*.json; do
  slug=$(basename "$m" .json)
  for base in "$HOME/work/$slug" "$HOME/$slug"; do
    case "$cwd/" in "$base"/*|"$base") marker="$m"; dir="$base"; break 2 ;; esac
  done
done
[ -n "$marker" ] || exit 0

# two sessions can share a project dir (a legacy terminal tab + the relay's
# tmux session): only the turn the relay actually started may consume the
# marker - its transcript's last user message carries the relay prefix.
python3 - "$transcript" <<'PY' || exit 0
import json, sys
last = None
for line in open(sys.argv[1], errors="replace"):
    try: e = json.loads(line)
    except Exception: continue
    if e.get("type") == "user":
        c = (e.get("message") or {}).get("content")
        if isinstance(c, list):
            t = " ".join(b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text")
        else:
            t = c if isinstance(c, str) else ""
        if t.strip(): last = t.strip()
sys.exit(0 if last and last.startswith("[Steven via hermes-relay]") else 1)
PY

chat=$(jq -r '.chat' "$marker"); thread=$(jq -r '.thread' "$marker")
msg_id=$(jq -r '.msg_id' "$marker")

reply=$(python3 - "$transcript" <<'PY'
import json, sys
last = None
for line in open(sys.argv[1], errors="replace"):
    try: e = json.loads(line)
    except Exception: continue
    if e.get("type") == "assistant":
        c = (e.get("message") or {}).get("content")
        if isinstance(c, list):
            t = " ".join(b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text").strip()
        else:
            t = (c or "").strip() if isinstance(c, str) else ""
        if t: last = t
print((last or "")[:3500])
PY
)
# a session can fire an early Stop before any assistant text exists (seen
# live: fresh session's init turn ate the marker and the real reply had no
# ride home). No text -> leave the marker for the next Stop / the poller's
# fallback sweep; consume only once there is a real reply to send.
[ -n "$reply" ] || exit 0
rm -f "$marker"   # consume before sending: a send failure must not re-fire every turn

SSH_CM=(-o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm-%r@%h-%p" -o ControlPersist=1800)
printf '%s\n' "$reply" | ssh "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes syd3 \
  "sudo -n -u hermes /home/hermes/.local/bin/hermes send --to telegram:${chat}:${thread} -q -f -" \
  || exit 0   # never block the session over a send failure

jq -cn --arg p "$(basename "$dir")" --arg t "$thread" --arg m "$msg_id" \
  --arg h "${reply:0:80}" --argjson ts "$(date +%s)" \
  '{ts:$ts,dir:"out",project:$p,thread:$t,msg_id:$m,head:$h}' \
  >> "$HOME/dashboard/data/relay-ledger.jsonl" 2>/dev/null || true
exit 0
