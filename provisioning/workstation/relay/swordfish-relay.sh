#!/usr/bin/env bash
set -uo pipefail

# swordfish-relay.sh - the E1 relay poller (design:
# agent_handoff/hermes-e1-relay-design-2026-07-13.md, decisions 1-2, 10-11).
# Deterministic daemon on syd4: pulls the founder's unmentioned Telegram
# forum-topic messages out of hermes's state.db on syd3 (read-only, over the
# collectors' multiplexed ssh master - hermes holds ZERO credentials toward
# this box), routes thread_id -> project via the UNTRACKED map (project dir
# names can be guarded), injects into the project's agent-term tmux session,
# and leaves a marker for relay-stop-hook.sh to send the reply back.
# Messages starting with '!' are consumed HERE (never injected): !status,
# !stop, !kill - the escape hatch that works even when the LLM is wedged.
#
# Reads ALL rows since the watermark, every topic, every cycle - never
# filters to an expected thread, never stops after an expected message
# (decision 11: exactly how the manual validation missed a General-topic
# question).

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/../collectors/lib.sh"

MAP_FILE="$HOME/work/swordfish/inventory/secrets/relay-map"
STATE_DIR="$HOME/.local/state/swordfish-relay"
MARKER_DIR="$HOME/.claude/relay-pending"
LEDGER="$DATA_DIR/relay-ledger.jsonl"
mkdir -p "$STATE_DIR" "$MARKER_DIR"

declare -A map
GROUP_ID="" FOUNDER_ID="" POLL_S=5
. "$MAP_FILE"   # sets GROUP_ID, FOUNDER_ID, map[<thread>]=<project dir>
[ -n "$GROUP_ID" ] && [ -n "$FOUNDER_ID" ] || { echo "relay-map incomplete"; exit 1; }

wm_file="$STATE_DIR/watermark"
[ -f "$wm_file" ] || { echo "no watermark - run setup-relay.sh first"; exit 1; }

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }

ledger() { # $1 dir(in|out|cmd) $2 project $3 thread $4 msgid $5 head
  jq -cn --arg d "$1" --arg p "$2" --arg t "$3" --arg m "$4" --arg h "$5" \
    --argjson ts "$(date +%s)" \
    '{ts:$ts,dir:$d,project:$p,thread:$t,msg_id:$m,head:$h}' >> "$LEDGER"
}

send() { # $1 thread, stdin body
  # alerts-bot voice with hermes-send fallback (finding-e resolution): a
  # founder reply to an alerts-bot message never trips hermes's reply-to-bot
  # dispatch, so hermes stays silent in topics without config we don't have.
  "$DIR/relay-send.sh" "$GROUP_ID" "$1"
}

prime_master() {
  ssh -O check "${SSH_CM[@]}" syd3 2>/dev/null \
    || ssh "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes -fN syd3 2>/dev/null \
    || return 1
}

fetch_rows() { # rows since watermark as JSON lines: {id, thread, content}
  # RATCHET (finding e): no observed=1 filter. Hermes classifies a message
  # as reply-to-bot/mention and dispatches its own agent on rules we do not
  # control (topic-starter replies, replies to relay notices...). The relay
  # takes EVERY founder user-row in the group - a message can never be
  # eaten. The companion ratchet is relay-send.sh: outbound rides the
  # ALERTS bot, so replies to relayed messages never look reply-to-hermes.
  ssh_syd3_stdin 'sudo -n python3 -' <<PY
import json, sqlite3
db = sqlite3.connect("file:/home/hermes/.hermes/state.db?mode=ro", uri=True)
for r in db.execute(
    "select m.id, s.thread_id, m.content from messages m "
    "join sessions s on s.id=m.session_id "
    "where s.source='telegram' and s.chat_id='${GROUP_ID}' "
    "and m.role='user' and m.id > $(cat "$wm_file") "
    "order by m.id"):
    print(json.dumps({"id": r[0], "thread": str(r[1] or ""), "content": r[2] or ""}))
PY
}

ensure_session() { # $1 slug $2 dir -> 0 when composer ready
  tmux has-session -t "$1" 2>/dev/null || tmux new-session -d -s "$1" -c "$2" \
    'claude; echo; echo "[claude exited - type claude to relaunch, or claude --continue to resume]"; exec bash'
  for _ in $(seq 1 40); do
    local pane; pane=$(tmux capture-pane -t "$1" -p 2>/dev/null || true)
    grep -q 'trust this folder' <<<"$pane" && { tmux send-keys -t "$1" Enter; sleep 2; continue; }
    grep -q '❯' <<<"$pane" && return 0
    sleep 3
  done
  return 1
}

handle_cmd() { # $1 cmd $2 slug $3 dir $4 thread
  case "$1" in
    '!status')
      local st="no session"
      if tmux has-session -t "$2" 2>/dev/null; then
        st="session up"
        tmux capture-pane -t "$2" -p 2>/dev/null | grep -q 'esc to interrupt' \
          && st="$st, agent mid-turn" || st="$st, agent idle"
      fi
      local last; last=$(grep "\"project\":\"$2\"" "$LEDGER" 2>/dev/null | tail -1 \
        | jq -r '"last \(.dir) \((now - .ts | floor))s ago"' 2>/dev/null || true)
      printf '%s: %s%s\n' "$2" "$st" "${last:+ · $last}" | send "$4" ;;
    '!stop')
      tmux send-keys -t "$2" Escape 2>/dev/null \
        && echo "$2: sent interrupt (Escape)" | send "$4" \
        || echo "$2: no session to interrupt" | send "$4" ;;
    '!kill')
      rm -f "$MARKER_DIR/$2.json"
      tmux kill-session -t "$2" 2>/dev/null \
        && echo "$2: session killed - your next plain message starts a fresh one" | send "$4" \
        || echo "$2: no session to kill" | send "$4" ;;
    *) echo "unknown command $1 - know: !status !stop !kill" | send "$4" ;;
  esac
}

process_row() { # $1 id $2 thread $3 content
  local id="$1" thread="$2" content="$3" dir slug sender text
  dir="${map[$thread]:-}"
  if [ -z "$dir" ]; then
    echo "topic $thread is not mapped to a project - add it to relay-map on syd4" | send "$thread"
    ledger cmd unmapped "$thread" "$id" "unmapped topic notice"
    return
  fi
  slug=$(basename "$dir")
  # first line is the gateway's "[Name|user_id]" tag; the rest is the message
  sender=$(sed -n '1s/^\[[^|]*|\([0-9]*\)\].*$/\1/p' <<<"$content")
  text=$(sed '1d' <<<"$content")
  [ "$sender" = "$FOUNDER_ID" ] || { log "drop msg $id: sender '$sender' != founder"; return; }
  [ -n "$(tr -d '[:space:]' <<<"$text")" ] || { log "drop msg $id: empty (restart auto-resume artifact)"; return; }

  if [[ "$text" == !* ]]; then
    handle_cmd "${text%%[[:space:]]*}" "$slug" "$dir" "$thread"
    ledger cmd "$slug" "$thread" "$id" "${text:0:80}"
    return
  fi

  if ! ensure_session "$slug" "$dir"; then
    echo "$slug: session failed to become ready - try !kill then resend" | send "$thread"
    ledger cmd "$slug" "$thread" "$id" "ensure_session failed"
    return
  fi
  jq -cn --arg c "$GROUP_ID" --arg t "$thread" --arg m "$id" --arg d "$dir" --argjson ts "$(date +%s)" \
    '{chat:$c,thread:$t,msg_id:$m,dir:$d,injected_at:$ts}' > "$MARKER_DIR/$slug.json"
  tmux send-keys -t "$slug" "[Steven via hermes-relay] $text"
  sleep 1
  tmux send-keys -t "$slug" Enter
  ledger in "$slug" "$thread" "$id" "${text:0:80}"
  log "injected msg $id -> $slug"
}

# fallback reply sweep: the Stop hook is the primary reply path, but a
# session started before the hook was installed (or any hook failure) would
# leave the founder in silence. A marker older than 120s whose session is
# idle gets its reply extracted from the transcript right here - replies are
# deterministic no matter what the hook does.
sweep_markers() {
  local m slug dir thread age reply tfile
  for m in "$MARKER_DIR"/*.json; do
    [ -f "$m" ] || continue
    slug=$(basename "$m" .json)
    age=$(( $(date +%s) - $(jq -r '.injected_at // 0' "$m") ))
    [ "$age" -gt 120 ] || continue
    tmux capture-pane -t "$slug" -p 2>/dev/null | grep -q 'esc to interrupt' && continue  # still working
    dir=$(jq -r '.dir // empty' "$m"); thread=$(jq -r '.thread' "$m")
    [ -n "$dir" ] || { rm -f "$m"; continue; }
    tfile=$(ls -t "$HOME/.claude/projects/$(printf '%s' "$dir" | tr '/.' '--')"/*.jsonl 2>/dev/null | head -1)
    [ -n "$tfile" ] || continue
    reply=$(python3 - "$tfile" <<'PY'
import json, sys
last_u, last_a = None, None
for line in open(sys.argv[1], errors="replace"):
    try: e = json.loads(line)
    except Exception: continue
    c = (e.get("message") or {}).get("content")
    t = ""
    if isinstance(c, list):
        t = " ".join(b.get("text","") for b in c if isinstance(b,dict) and b.get("type")=="text").strip()
    elif isinstance(c, str): t = c.strip()
    if not t: continue
    if e.get("type") == "user": last_u = t
    elif e.get("type") == "assistant": last_a = t
print((last_a or "")[:3500] if last_u and last_u.startswith("[Steven via hermes-relay]") else "")
PY
)
    [ -n "$reply" ] || continue
    rm -f "$m"
    printf '%s\n' "$reply" | send "$thread"
    ledger out "$slug" "$thread" "$(jq -r '.msg_id' "$m" 2>/dev/null || echo '?')" "${reply:0:80} (fallback)"
    log "fallback reply sent for $slug"
  done
}

log "relay up: group $GROUP_ID, $(( ${#map[@]} )) mapped topics, watermark $(cat "$wm_file")"
while :; do
  . "$MAP_FILE"   # hot-reload: a new topic mapping needs no service restart
  if prime_master; then
    rows=$(fetch_rows 2>/dev/null || true)
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      id=$(jq -r '.id' <<<"$row") || continue
      thread=$(jq -r '.thread' <<<"$row")
      content=$(jq -r '.content' <<<"$row")
      process_row "$id" "$thread" "$content"
      echo "$id" > "$wm_file"      # per-row advance: crash-safe, no replay
    done <<<"$rows"
  else
    log "ssh master unavailable - retrying"
  fi
  sleep "$POLL_S"
done
