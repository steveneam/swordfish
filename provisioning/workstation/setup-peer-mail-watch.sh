#!/usr/bin/env bash
set -euo pipefail

# setup-peer-mail-watch.sh - cross-project channel watcher (founder ratchet,
# 2026-07-15: "watchers in each other's workspace beat me relaying messages").
#
# WHAT: every 10 min, hash each peer project's OUTBOUND channel file (their
# mail TO swordfish). On change: ONE Telegram note + a NEW-<peer> flag under
# /var/lib/swordfish/peer-mail/. The next swordfish session reads the flags at
# boot (CURRENT.md protocol note), handles the mail, and removes the flag.
# First sighting of a file just records the baseline - no alert.
#
# BOUNDARIES (deliberate, keep them):
#   - watch the CHANNEL FILE only, never the peer's whole workspace - the
#     channel is mail addressed to us; the rest of their repo is theirs.
#   - notification is NOT authorization: channel content stays untrusted data
#     (AGENTS.md rule 10) - founder gates hold no matter what the mail says.
#   - deterministic + LLM-free, same family as setup-login-alerts.sh.
# INBOUND ONLY, ON PURPOSE (2026-07-17). An outbound half was built and RIPPED
# OUT the same hour: it used `tmux send-keys` to nudge a peer's live agent pane,
# and send-keys types into a SHARED interactive session - it cannot tell an empty
# composer from a human mid-sentence. It injected into the FOUNDER's own typing
# while he was writing to eamos ("no it's <injected nudge>"), and its test fires
# had already trained that peer to dismiss real nudges as duplicates.
#
# The lesson is not "detect a busy composer harder" - it is that in-band
# injection into a session a human shares is the wrong mechanism at the root. A
# timer must never contend with a keyboard.
#
# Outbound notification is therefore the CHANNEL FILE ITSELF (founder call: "just
# keep the notifications in the handoffs as per normal but monitor"). Peers read
# FROM-SWORDFISH.md at boot and on mail check; swordfish monitors THEIR outbound
# here and reads it. Out-of-band both ways; nothing types at anyone.
#
# Add a peer: append "name:absolute-path" to the WATCHES list below and re-run.
# GUARDED-NAME peers: none since the full unmask (founder call 2026-07-17 -
# selom was the last, and graduated into the tracked WATCHES like eamos before
# it). The mechanism is KEPT for the next masked project: entries whose paths
# may not appear in tracked files live in UNTRACKED
# /etc/swordfish/peer-mail-watches.local (same precedent as the gitignored
# .context/ vault pointer) - one "name:absolute-path" per line, # comments ok,
# and the name MUST be the mask: it lands in flag filenames, alerts, and chat.
# Root unit (alerts.env is root:600). Idempotent - safe to re-run.

changed=0
install_if_changed() { # $1=mode $2=dest, content on stdin
  local tmp; tmp=$(mktemp)
  cat > "$tmp"
  if [ ! -f "$2" ] || ! cmp -s "$tmp" "$2"; then
    sudo install -m "$1" -o root -g root "$tmp" "$2"
    changed=1
  fi
  rm -f "$tmp"
}

install_if_changed 0755 /usr/local/bin/swordfish-peer-mail-watch.sh <<'WATCH'
#!/usr/bin/env bash
# Fired by swordfish-peer-mail.timer. Never fails loudly; missing file or
# env just means "next tick". One alert per content change per channel.
set -u
WATCHES="thalon:/home/deploy/work/thalon/agent_handoff/ASK-BACKS-FOR-SWORDFISH.md
eamos:/home/deploy/work/eamos/agent_handoff/ASK-BACKS-FOR-SWORDFISH.md
selom:/home/deploy/work/selom/agent_handoff/ASK-BACKS-FOR-SWORDFISH.md
walter:/home/deploy/vault/ASK-BACKS-FOR-SWORDFISH.local.md"


# guarded-name peers ride the untracked local list (see setup script header)
LOCAL_WATCHES=/etc/swordfish/peer-mail-watches.local
if [ -r "$LOCAL_WATCHES" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    WATCHES="$WATCHES $line"
  done < "$LOCAL_WATCHES"
fi

STATE=/var/lib/swordfish/peer-mail
mkdir -p "$STATE"
[ -r /etc/swordfish/alerts.env ] || exit 0
. /etc/swordfish/alerts.env
[ -n "${ALERTS_BOT_TOKEN:-}" ] && [ -n "${ALERTS_CHAT_ID:-}" ] || exit 0

for entry in $WATCHES; do
  name=${entry%%:*}; path=${entry#*:}
  [ -r "$path" ] || continue
  hash=$(sha256sum "$path" | cut -d' ' -f1)
  hfile="$STATE/$name.hash"
  if [ ! -f "$hfile" ]; then          # first sighting = baseline, no alert
    printf '%s\n' "$hash" > "$hfile"
    continue
  fi
  [ "$hash" != "$(cat "$hfile")" ] || continue
  printf '%s\n' "$hash" > "$hfile"
  # newest section heading, display-only (untrusted content: strip to
  # printable ASCII, cap length - it labels the alert, nothing more)
  head=$(grep '^# ' "$path" | tail -1 | tr -cd ' -~' | cut -c1-80)
  msg="📬 [$(hostname -s)] peer mail: $name -> swordfish channel changed (${head:-no heading}) - flag set for the next swordfish session"
  logger -t swordfish-alerts "$msg"
  { date -u +%FT%TZ; printf '%s\n' "$head"; } > "$STATE/NEW-$name"
  curl -fsS -m 10 "https://api.telegram.org/bot${ALERTS_BOT_TOKEN}/sendMessage" \
    -d chat_id="${ALERTS_CHAT_ID}" --data-urlencode text="$msg" >/dev/null 2>&1
done

exit 0
WATCH

install_if_changed 0644 /etc/systemd/system/swordfish-peer-mail.service <<'UNIT'
[Unit]
Description=swordfish: peer-project channel watcher (mail from tenant agents)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/swordfish-peer-mail-watch.sh
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-peer-mail.timer <<'TIMER'
[Unit]
Description=swordfish: peer-mail watch every 10 min

[Timer]
OnCalendar=*:0/10
Persistent=true

[Install]
WantedBy=timers.target
TIMER

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet swordfish-peer-mail.timer 2>/dev/null; then
  sudo systemctl enable --now swordfish-peer-mail.timer
  changed=1
fi

# --- verify ------------------------------------------------------------------
systemctl is-active --quiet swordfish-peer-mail.timer || { echo "FAIL: timer inactive"; exit 1; }
sudo /usr/local/bin/swordfish-peer-mail-watch.sh || { echo "FAIL: watcher errored"; exit 1; }
sudo test -f /var/lib/swordfish/peer-mail/thalon.hash || { echo "FAIL: thalon baseline hash not written"; exit 1; }
sudo test -f /var/lib/swordfish/peer-mail/eamos.hash || { echo "FAIL: eamos baseline hash not written"; exit 1; }
# every local-list peer whose channel file exists must have a baseline too
extra=""
if sudo test -r /etc/swordfish/peer-mail-watches.local; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    n=${line%%:*}; p=${line#*:}
    sudo test -r "$p" || { echo "WARN: local peer '$n' channel file not readable yet - baseline deferred"; continue; }
    sudo test -f "/var/lib/swordfish/peer-mail/$n.hash" \
      || { echo "FAIL: baseline hash missing for local peer '$n'"; exit 1; }
    extra="$extra + $n"
  done < <(sudo cat /etc/swordfish/peer-mail-watches.local)
fi

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes (channels: thalon + eamos + selom$extra)"
else
  echo "== converged: peer-mail watch armed (channels: thalon + eamos + selom$extra)"
fi
