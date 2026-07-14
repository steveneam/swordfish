#!/usr/bin/env bash
set -uo pipefail

# relay-tag-canary.sh - format-drift alarm for the relay's founder-id gate
# (security review 2026-07-14, prompt-injection lens).
#
# The relay authenticates the founder by parsing hermes's "[name|user_id]" tag
# (parse_sender in swordfish-relay.sh); the id is the trailing |<digits>] hermes
# appends, and the parse is anchored so an attacker-controlled display name
# cannot forge it. That safety has ONE moving dependency we do not own: hermes's
# tag format. If a hermes upgrade changes that shape - or the founder's Telegram
# display name gains a | [ ] that breaks the anchor - real founder messages would
# be SILENTLY DROPPED (fail closed: safe, but the founder goes unheard).
#
# This canary reads recent group user-messages read-only (same path as the relay,
# hermes holds zero credentials toward this box) and alerts when a message that
# still LOOKS like a hermes tag no longer parses to an id - i.e. drift, a display
# name that broke the parse, or a spoof attempt. It reuses parse_sender /
# is_tag_shaped from the relay (one source of truth) via the relay's test seam.
#
#   usage: relay-tag-canary.sh [--alert]
#     --alert  push to the founder's Telegram (General) on a status CHANGE only
#              (edge-triggered: ok->drift and drift->ok; never spams a stuck state)
#     env: CANARY_SAMPLE (default 25) - how many recent user rows to inspect
#   exit 0 = no drift · 1 = drift · 2 = could not check (hermes unreachable)
#
# Also emitted (without --alert) into the cockpit security card by
# collect-security.sh; JSON on the LAST stdout line for machine consumers.

DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/swordfish-relay.sh"   # parse_sender + is_tag_shaped + GROUP_ID + SSH helpers
                              # (the test seam skips the daemon loop on source)

N=${CANARY_SAMPLE:-25}
ALERT=0; [ "${1:-}" = "--alert" ] && ALERT=1
STATE_FILE="$HOME/.local/state/swordfish-relay/canary-status"

emit_json() { # $1 status $2 checked $3 shaped $4 drift $5 sample
  jq -cn --arg s "$1" --argjson c "$2" --argjson t "$3" --argjson d "$4" --arg x "$5" \
    '{status:$s, checked:$c, tag_shaped:$t, drift:$d, sample:$x}'
}

prime_master || { echo "canary: ssh master to syd3 unavailable - cannot check"; emit_json unreachable 0 0 0 ""; exit 2; }

rows=$(ssh_syd3_stdin 'sudo -n python3 -' <<PY
import json, sqlite3
db = sqlite3.connect("file:/home/hermes/.hermes/state.db?mode=ro", uri=True)
for r in db.execute(
    "select m.content from messages m join sessions s on s.id=m.session_id "
    "where s.source='telegram' and s.chat_id='${GROUP_ID}' and m.role='user' "
    "order by m.id desc limit ${N}"):
    print(json.dumps((r[0] or "").split(chr(10))[0]))   # line 1 (the tag) only
PY
) || { echo "canary: fetch from hermes failed"; emit_json unreachable 0 0 0 ""; exit 2; }

checked=0 shaped=0 drift=0 sample=""
while IFS= read -r j; do
  [ -n "$j" ] || continue
  line=$(jq -r '.' <<<"$j") || continue
  checked=$((checked+1))
  is_tag_shaped "$line" || continue
  shaped=$((shaped+1))
  if [ -z "$(parse_sender "$line")" ]; then
    drift=$((drift+1)); [ -n "$sample" ] || sample="${line:0:48}"
  fi
done <<<"$rows"

# drift = a tag-shaped line the strict parse rejects, OR: we saw messages but not
# one carried a tag at all (hermes stopped tagging = total format change).
status=ok
if [ "$drift" -gt 0 ] || { [ "$checked" -gt 0 ] && [ "$shaped" -eq 0 ]; }; then
  status=drift
  [ -n "$sample" ] || sample="(no tag-shaped messages in last $checked)"
fi

if [ "$status" = drift ]; then
  echo "DRIFT: $drift/$checked recent messages look like a hermes tag but fail the founder-id parse (sample: $sample). Cause = hermes tag-format change, a founder display name that grew a | [ ], or a spoof attempt. The relay may be silently dropping founder messages - re-check parse_sender vs the live tag in swordfish-relay.sh + rerun test-relay-map.sh."
else
  echo "OK: $checked recent messages, $shaped tag-shaped, all parse to an id - no drift."
fi

# edge-triggered alert: only on a status change, so a stuck state never spams.
if [ "$ALERT" = 1 ]; then
  prev=$(cat "$STATE_FILE" 2>/dev/null || echo unknown)
  if [ "$status" != "$prev" ]; then
    if [ "$status" = drift ]; then
      printf '%s\n' "relay tag-format canary - DRIFT: $drift/$checked recent group messages look like a hermes tag but the founder-id parse now rejects them. The relay may be dropping your messages (or it blocked a spoof). Sample: $sample. Fix: check parse_sender vs the live tag in swordfish-relay.sh, then rerun test-relay-map.sh." \
        | "$DIR/relay-send.sh" "$GROUP_ID" 1 || true
    else
      printf '%s\n' "relay tag-format canary - recovered: $checked recent messages all parse cleanly again." \
        | "$DIR/relay-send.sh" "$GROUP_ID" 1 || true
    fi
    printf '%s' "$status" > "$STATE_FILE" 2>/dev/null || true
  fi
fi

emit_json "$status" "$checked" "$shaped" "$drift" "$sample"
[ "$status" = ok ]
