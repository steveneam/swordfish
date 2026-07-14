#!/usr/bin/env bash
# test-relay-map.sh - executable ratchet for the relay's !map command
# (handle_map / resolve_project in swordfish-relay.sh): allowlist resolution,
# idempotent map-file writes, read-back verification, in-memory liveness.
#
# Pure-local: sources the relay script (its test seam skips the daemon loop),
# stubs send() to capture replies, and writes only to a temp map file. It
# never touches Telegram, tmux, hermes, or the real relay-map. Runs on the
# relay host (needs the real relay-map + watermark present to source cleanly).
#
# Exit 0 = every assertion passed. Any failure exits 1 - never pipe this into
# tail/head (memory: verification-exit-codes).
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)

. "$DIR/swordfish-relay.sh"

TMP_MAP=$(mktemp)
MAP_FILE="$TMP_MAP"
map=()          # start from an empty in-memory map
SENT_FILE=$(mktemp)
trap 'rm -f "$TMP_MAP" "$SENT_FILE"' EXIT
# send() is invoked as a pipeline stage (subshell), so capture via a file,
# not a variable - a variable assignment would die with the subshell.
send() { cat > "$SENT_FILE"; }
reply() { cat "$SENT_FILE"; }

pass=0 fail=0
ok()  { echo "  ok   - $1"; pass=$((pass+1)); }
bad() { echo "  FAIL - $1"; fail=$((fail+1)); }

echo "1. bind a new topic (whitespace + case tolerated)"
handle_map 999 '  Thalon '
grep -qxF "map[999]=$HOME/work/thalon" "$TMP_MAP" \
  && ok "line written" || bad "line missing"
[ "${map[999]:-}" = "$HOME/work/thalon" ] \
  && ok "in-memory map live immediately" || bad "in-memory map not updated"
[[ "$(reply)" == "bound topic 999 -> thalon"* ]] \
  && ok "confirm reply" || bad "confirm reply was: $(reply)"

echo "2. re-map updates in place - never duplicates"
handle_map 999 'swordfish'
[ "$(grep -c '^map\[999\]=' "$TMP_MAP")" = 1 ] \
  && ok "still one line for the topic" || bad "duplicated lines"
grep -qxF "map[999]=$HOME/work/swordfish" "$TMP_MAP" \
  && ok "value replaced" || bad "value not replaced"
[[ "$(reply)" == "rebound topic 999 -> swordfish (was thalon)"* ]] \
  && ok "rebound reply names the old binding" || bad "rebound reply was: $(reply)"

echo "3. same value again stays idempotent"
handle_map 999 'swordfish'
[ "$(grep -c '^map\[999\]=' "$TMP_MAP")" = 1 ] \
  && ok "still one line" || bad "duplicated on same-value re-map"
[[ "$(reply)" == "bound topic 999 -> swordfish"* ]] \
  && ok "same-value reply reads as bound (not rebound)" || bad "reply was: $(reply)"

echo "4. walter and vault both resolve to ~/vault"
handle_map 42 'walter'
grep -qxF "map[42]=$HOME/vault" "$TMP_MAP" \
  && ok "walter -> ~/vault" || bad "walter did not resolve"
handle_map 43 'VAULT'
grep -qxF "map[43]=$HOME/vault" "$TMP_MAP" \
  && ok "vault alias + case fold" || bad "vault alias failed"

echo "5. unknown project rejected, file untouched"
before=$(cat "$TMP_MAP")
handle_map 77 'no-such-project-zz9'
[ "$before" = "$(cat "$TMP_MAP")" ] \
  && ok "file unchanged" || bad "file changed on unknown project"
[[ "$(reply)" == "unknown project 'no-such-project-zz9'"* ]] \
  && ok "rejection reply lists known projects" || bad "reply was: $(reply)"

echo "6. path-shaped and hostile args never resolve"
for evil in '../../etc' '/etc' 'a/b' '.ssh' 'work/../vault' '~root' '$HOME' 'a b'; do
  : > "$SENT_FILE"
  handle_map 78 "$evil"
  [[ "$(reply)" == "unknown project"* ]] \
    && ok "rejected: $evil" || bad "NOT rejected: $evil (reply: $(reply))"
done
grep -q '^map\[78\]=' "$TMP_MAP" \
  && bad "hostile arg reached the map file" || ok "no line written for topic 78"

echo "7. empty argument gets usage"
handle_map 79 '   '
[[ "$(reply)" == "usage: !map <project>"* ]] \
  && ok "usage reply" || bad "reply was: $(reply)"

echo "8. non-numeric / missing topic id refused before any write"
before=$(cat "$TMP_MAP")
handle_map '' 'thalon'
[[ "$(reply)" == "cannot bind here"* ]] \
  && ok "empty thread refused" || bad "reply was: $(reply)"
handle_map 'abc;rm' 'thalon'
[[ "$(reply)" == "cannot bind here"* ]] \
  && ok "non-numeric thread refused" || bad "reply was: $(reply)"
[ "$before" = "$(cat "$TMP_MAP")" ] \
  && ok "file unchanged" || bad "file changed on bad thread id"

echo "9. sender gate: only a real trailing founder-id tag passes (spoof-proof)"
# FID is a stand-in id; parse_sender is id-agnostic, so the real founder id stays
# out of this tracked file (it lives only in the gitignored relay-map). hermes
# emits the tag as line 1, body on line 2+.
FID=111222333
sender_is() { # $1 content $2 expected-id-or-empty $3 label
  local got; got=$(parse_sender "$1")
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (got '$got', want '$2')"
}
sender_is "[Steven|$FID]"$'\n'"hello"       "$FID"  "legit founder tag passes"
sender_is "[x|$FID]|99999]"$'\n'"payload"   ""      "display-name spoof dropped (extra id group breaks anchor)"
sender_is "[$FID|$FID]|99999]"$'\n'"x"      ""      "numeric-name spoof dropped"
sender_is "[a|99999]"$'\n'"hi"              "99999" "legit non-founder tag -> its own id (!= founder)"
sender_is "[Steven]"$'\n'"hi"               ""      "tag with no id dropped"
sender_is "[Steven|$FID] hello"             ""      "id must own the line (trailing text dropped)"
sender_is "[Steven|$FID"                    ""      "unterminated tag dropped"
sender_is "plain text, no tag"              ""      "no tag dropped"
sender_is "[a|1][b|$FID]"                   ""      "stacked tags on one line dropped"
# security invariant: only a clean [name|FID] with FID as the sole trailing id
# yields FID (which requires the real sender id to BE FID); every spoof that
# tries to smuggle FID ahead of a different real id must NOT return FID.
for spoof in "[x|$FID]|99999]" "[$FID|$FID]|99999]" "[ |$FID]x]|7]" "[Steven|9|$FID]" "[a|$FID] evil"; do
  [ "$(parse_sender "$spoof"$'\n'body)" != "$FID" ] \
    && ok "spoof never returns founder id: $spoof" || bad "SPOOF RETURNED FOUNDER: $spoof"
done

echo "10. tag-drift canary logic: is_tag_shaped (loose) vs parse_sender (strict)"
shaped_is() { # $1 line $2 expect-yes|no $3 label
  if is_tag_shaped "$1"; then got=yes; else got=no; fi
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (got '$got', want '$2')"
}
shaped_is "[Steven|$FID]"     yes "legit tag is tag-shaped"
shaped_is "[x|$FID]|99999]"   yes "spoof is still tag-shaped (loose)"
shaped_is "[Steven]"          no  "no-id tag is not tag-shaped"
shaped_is "Steven: hello"     no  "untagged line is not tag-shaped"
shaped_is "plain text"        no  "plain text is not tag-shaped"
# the canary fires when a line is tag-shaped but the strict parse yields nothing
offender() { is_tag_shaped "$1" && [ -z "$(parse_sender "$1")" ]; }
offender "[x|$FID]|99999]" \
  && ok "canary flags a spoof/drift tag (shaped but unparseable)" \
  || bad "canary MISSED a shaped-but-unparseable tag"
offender "[Steven|$FID]" \
  && bad "canary false-positives on a legit tag" \
  || ok "canary does not flag a legit tag"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
