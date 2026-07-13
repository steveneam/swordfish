#!/usr/bin/env bash
set -euo pipefail

# setup-qol.sh - fleet quality-of-life shell setup, converged over SSH
# (qol-apply workflow) or run directly on a box. This file is the CANONICAL
# home of the QoL content; the cloud-inits carry a lockstep copy so fresh
# boxes are right at first boot.
#
# Why /etc/bash.bashrc AND /etc/profile.d: profile.d is sourced by LOGIN
# shells only - code-server / VS Code integrated terminals are interactive
# NON-login shells and never saw `work` (founder hit this 2026-07-13).
# bash.bashrc is the non-login hook; both now source the same one file.
#
# Idempotent - safe to re-run. Second run prints "== converged: no changes".

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

# tmux is what `work` runs - workload boxes (syd2) don't ship it via cloud-init
if ! dpkg -s tmux >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null
  changed=1
fi

install_if_changed 0644 /etc/profile.d/swordfish-qol.sh <<'QOL'
# swordfish fleet quality-of-life. CANONICAL: provisioning/host/setup-qol.sh
# (cloud-init carries a lockstep copy for first boot). Non-login shells get
# this file via the /etc/bash.bashrc hook the same script installs.
# self-updating user-space tools (claude native build) live in ~/.local/bin
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;;
esac
# protocol: sessions launch inside the swordfish repo (the memory slug
# attaches to the launch dir - a $HOME launch comes up empty).
# Session named after the FOLDER so `work` over ssh and a code-server
# terminal tab (agent-term) converge on the same session, never two agents.
work() {
  local d="$HOME/work/swordfish"; [ -d "$d" ] || d="$HOME"
  tmux new -A -s "$(basename "$d")" -c "$d"
}
qr() { qrencode -t ANSIUTF8 "$1"; }
# copy: put a file's (or piped) content into the FOUNDER'S MAC CLIPBOARD
# through the browser terminal (OSC52; code-server forwards it, tmux needs
# the passthrough wrap + allow-passthrough in tmux.conf). Box->Mac copy via
# text selection is unreliable in a live TUI (redraws drop the selection) -
# this is the mechanical path. Big content (>~50KB) still goes via a file
# opened in the editor. `copytest` = 3-second founder verification.
copy() {
  local data
  if [ $# -ge 1 ]; then data=$(base64 -w0 < "$1") || return 1
  else data=$(base64 -w0); fi
  if [ -n "${TMUX:-}" ]; then
    printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$data"
  else
    printf '\033]52;c;%s\007' "$data"
  fi
}
copytest() {
  printf 'clipboard works: %s' "$(date '+%H:%M:%S')" | copy
  echo "sent - now paste (Cmd+V) into any Mac app; you should get 'clipboard works: <time>'"
}
alias snapshots='sudo resticprofile -c /etc/resticprofile/profiles.yaml --name "$(hostname -s)" snapshots'
alias backup-now='sudo resticprofile -c /etc/resticprofile/profiles.yaml --name "$(hostname -s)" backup'
QOL

# tmux.conf: mouse policy + clipboard passthrough. Canonical HERE (cloud-init
# lockstep). allow-passthrough + set-clipboard are what let `copy` (OSC52)
# reach the founder's Mac clipboard from inside the agent-term sessions.
install_if_changed 0644 /etc/tmux.conf <<'TMUXCONF'
# mouse OFF by default: tmux mouse mode captures the terminal's mouse,
# which kills native macOS Terminal selection/copy (rehearsal lesson
# 2026-07-11 - an OAuth URL could not be copied). prefix+m toggles it
# for wheel scrolling; native selection is the primary copy path.
set -g mouse off
bind m set -g mouse \; display 'tmux mouse: #{?mouse,ON (wheel scroll; selection captured),off (native selection works)}'
set -g history-limit 50000
set -g status-interval 5
set -g status-right "#H | %H:%M UTC"
# clipboard: let OSC52 escape from inside tmux to the outer terminal, so the
# `copy` QoL command lands content in the founder's Mac clipboard (2026-07-13)
set -g allow-passthrough on
set -s set-clipboard external
TMUXCONF

# agent-term: code-server's DEFAULT terminal profile (wired in the box's
# code-server settings.json - see cloud-init). Every integrated terminal lands
# in a tmux session named after the workspace folder, so a browser/window
# crash never kills the agent - reopening the terminal reattaches to the same
# live session (a bare-terminal claude died with its pty on 2026-07-13, taking
# uncommitted work with it). First open auto-starts claude; when claude exits
# you land in a shell inside tmux. A plain shell is the "bash" profile in the
# terminal dropdown. A second tab on the same project MIRRORS the first -
# that is tmux, not a bug.
install_if_changed 0755 /usr/local/bin/agent-term <<'AGENTTERM'
#!/bin/bash
d="$PWD"
# protocol: never launch the agent at $HOME (empty memory slug)
[ "$d" = "$HOME" ] && [ -d "$HOME/work/swordfish" ] && d="$HOME/work/swordfish"
s=$(printf '%s' "$(basename "$d")" | tr -cs 'A-Za-z0-9_-' '-')
s=${s#-}; s=${s%-}; [ -n "$s" ] || s=agent
exec tmux new-session -A -s "$s" -c "$d" \
  'claude; echo; echo "[claude exited - type claude to relaunch, or claude --continue to resume the last conversation]"; exec bash'
AGENTTERM

if ! grep -qF '/etc/profile.d/swordfish-qol.sh' /etc/bash.bashrc; then
  printf '\n# swordfish: profile.d only reaches login shells; code-server terminals are\n# interactive non-login (2026-07-13). QoL stays in one file, hooked in here.\n[ -f /etc/profile.d/swordfish-qol.sh ] && . /etc/profile.d/swordfish-qol.sh\n' \
    | sudo tee -a /etc/bash.bashrc >/dev/null
  changed=1
fi

# --- verify ------------------------------------------------------------------
bash -ic 'type work' >/dev/null 2>&1 || { echo "FAIL: work invisible to non-login interactive shells"; exit 1; }
bash -lc 'type work' >/dev/null 2>&1 || { echo "FAIL: work invisible to login shells"; exit 1; }
[ -x /usr/local/bin/agent-term ] || { echo "FAIL: agent-term missing or not executable"; exit 1; }
bash -n /usr/local/bin/agent-term || { echo "FAIL: agent-term does not parse"; exit 1; }

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (QoL file + non-login hook)"
fi
