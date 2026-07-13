#!/usr/bin/env bash
set -uo pipefail

# relay-send.sh - the relay's outbound VOICE (finding-e resolution; dated note
# in agent_handoff/hermes-e1-relay-design-2026-07-13.md). Sends stdin into a
# forum topic AS THE ALERTS BOT via the Bot API, so a founder reply to a
# relayed message can never match hermes's reply-to-bot dispatch trigger:
# the adapter compares the replied-to author id against HERMES's own bot id,
# and v0.18.2 (latest) offers no config to disable that trigger - while
# dropping the group from TELEGRAM_ALLOWED_CHATS would ALSO kill observation
# (observe allowlist = group_allowed_chats INTERSECT allowed_chats), eating
# founder messages entirely. Different sender identity is the ratchet config
# cannot provide. Alerts-bot messages are invisible to hermes itself (its
# user-auth gate drops non-founder senders before observe/dispatch).
#
# Until the founder adds the alerts bot to the group, Telegram answers
# "chat not found"; we then FALL BACK to `hermes send` (today's voice) and
# say so on stderr - delivery never depends on the migration being done.
#
# usage: relay-send.sh <chat_id> <thread_id> < body
#   thread_id "1" or "" = the General topic: the Bot API wants the
#   message_thread_id parameter OMITTED there, not set to 1.

CHAT="${1:?usage: relay-send.sh <chat_id> <thread_id> < body}"
THREAD="${2-}"
ENV_FILE="$HOME/work/swordfish/inventory/secrets/telegram.env"

body=$(cat)
body="${body:0:4000}"   # Telegram sendMessage cap is 4096
[ -n "$(tr -d '[:space:]' <<<"$body")" ] || exit 0

# laptop-synced secrets carry \r and stray spaces - strip ALL whitespace
TOK=$(grep '^ALERTS_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"')

if [ -n "$TOK" ]; then
  args=(-d "chat_id=${CHAT}")
  [ -n "$THREAD" ] && [ "$THREAD" != "1" ] && args+=(-d "message_thread_id=${THREAD}")
  if curl -fsS -m 10 "https://api.telegram.org/bot${TOK}/sendMessage" \
       "${args[@]}" --data-urlencode "text=${body}" >/dev/null 2>&1; then
    exit 0
  fi
  echo "relay-send: alerts-bot voice failed for ${CHAT}:${THREAD:-general}" \
       "(bot not in group yet?) - falling back to hermes send" >&2
else
  echo "relay-send: no ALERTS_BOT_TOKEN in $ENV_FILE - falling back to hermes send" >&2
fi

SSH_CM=(-o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm-%r@%h-%p" -o ControlPersist=1800)
printf '%s\n' "$body" | ssh "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes syd3 \
  "sudo -n -u hermes /home/hermes/.local/bin/hermes send --to telegram:${CHAT}:${THREAD:-1} -q -f -"
