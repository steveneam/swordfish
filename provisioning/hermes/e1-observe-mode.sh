#!/usr/bin/env bash
set -euo pipefail

# e1-observe-mode.sh — wire the E1 relay's Telegram group observe-mode on
# syd3 (design: agent_handoff/hermes-e1-relay-design-2026-07-13.md, decision
# 7). Run ON syd3 (e.g. from syd4: ssh syd3 'sudo bash -s -- <group_id>' <
# this-file). Idempotent: re-running with the same id prints "converged".
#
# Effect: the hermes bot SEES every message in the allow-listed forum group
# (rows land in state.db for the syd4 relay-poller) but the hermes agent
# only answers when @mentioned. This hermes build keeps platform settings in
# ~/.hermes/.env, not config.yaml — hence env lines, not `hermes config set`.

GROUP_ID="${1:?usage: e1-observe-mode.sh <telegram_group_chat_id (negative number)>}"
case "$GROUP_ID" in
  -*[0-9]) ;;
  *) echo "FAIL: '$GROUP_ID' does not look like a group chat id (negative number)"; exit 1 ;;
esac

ENV=/home/hermes/.hermes/.env
[ -f "$ENV" ] || { echo "FAIL: $ENV missing"; exit 1; }

changed=0
setkey() { # $1=KEY $2=value — append or update in place
  if grep -q "^$1=" "$ENV"; then
    grep -q "^$1=$2\$" "$ENV" || { sed -i "s|^$1=.*|$1=$2|" "$ENV"; changed=1; }
  else
    printf '%s=%s\n' "$1" "$2" >> "$ENV"; changed=1
  fi
}

cp -p "$ENV" "$ENV.bak-e1"   # one rollback point; overwritten per run
setkey TELEGRAM_GROUP_ALLOWED_CHATS "$GROUP_ID"
setkey TELEGRAM_REQUIRE_MENTION true
setkey TELEGRAM_OBSERVE_UNMENTIONED_GROUP_MESSAGES true

if [ "$changed" -eq 0 ]; then
  echo "== converged: observe-mode already set for $GROUP_ID"
  exit 0
fi

systemctl restart hermes-gateway.service
for i in $(seq 1 15); do
  sleep 2
  state=$(python3 -c "
import json
g = json.load(open('/home/hermes/.hermes/gateway_state.json'))
print(g.get('platforms', {}).get('telegram', {}).get('state', '?'))" 2>/dev/null || echo '?')
  [ "$state" = connected ] && { echo "== converged: observe-mode set for $GROUP_ID, telegram reconnected"; exit 0; }
done
echo "FAIL: gateway did not reconnect to telegram within 30s (env backup: $ENV.bak-e1)"
exit 1
