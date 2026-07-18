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

# --- TMUX AUTO-LAND (founder ask 2026-07-17) ----------------------------------
# A code-server panel must land in the agent tmux, never sit as a bare shell:
# when code-server died today (13:56, "a socket was left hanging", NRestarts=1),
# the recreated panels came back as PLAIN bash - and because code-server
# focuses the last-active terminal, those dead panels hijacked every dashboard
# project button until killed by hand. Redirect instead of warn: an interactive
# vscode panel not already in tmux execs into agent-term (the same session the
# button's agent profile attaches - tmux new -A dedupes, never two agents).
# The "bash" dropdown profile sets PLAIN_SHELL=1: the deliberate plain-shell
# escape hatch, which falls through to the UNSHELTERED banner below instead.
# Inert off the workstation: fires only in vscode panels with agent-term on disk.
# AGENT_TERM override exists so tests can stub the exec target.
if [ -n "${PS1:-}" ] && [ "${TERM_PROGRAM:-}" = "vscode" ] && [ -z "${TMUX:-}" ] \
   && [ -z "${PLAIN_SHELL:-}" ] && [ -x "${AGENT_TERM:-/usr/local/bin/agent-term}" ]; then
  exec "${AGENT_TERM:-/usr/local/bin/agent-term}"
fi

# --- SHELTER INDICATOR (founder ask 2026-07-17) -------------------------------
# The problem it solves: a terminal in code-server gives no hint whether it is
# inside tmux. Inside = the agent survives a code-server restart (agent-tmux.service
# owns the tmux server's cgroup). Outside = the agent DIES with code-server - and
# apt can restart code-server for you via needrestart. That is exactly how a live
# agent was killed mid-run on 2026-07-17; the difference was invisible.
# In tmux the green SHELTERED badge in the status bar says so. Out here, nothing
# said anything - so say it loudly, in the two places that survive an agent TUI
# taking over the screen: the shell banner (printed before the agent starts) and
# the prompt (visible whenever you are back at a shell).
# _SWORDFISH_SHELTER_WARNED is deliberately NOT exported: this file is sourced
# twice in one shell (profile.d for login + bash.bashrc for non-login), which
# would double the banner AND double-prefix PS1. Unexported = deduped within a
# shell, but a CHILD shell re-evaluates and warns again - correct, because a
# child of an unsheltered shell is equally unsheltered.
if [ -n "${PS1:-}" ] && [ -z "${TMUX:-}" ] && [ -t 1 ] && [ -z "${_SWORDFISH_SHELTER_WARNED:-}" ]; then
  _SWORDFISH_SHELTER_WARNED=1
  printf '\033[41;97;1m  UNSHELTERED SHELL  \033[0m \033[91mnot in tmux — an agent started here DIES if code-server restarts\033[0m\n'
  printf '  \033[93mrun\033[0m \033[1mwork\033[0m\033[93m (swordfish) or\033[0m \033[1mtmux new -A -s <project>\033[0m\033[93m before starting an agent.\033[0m\n'
  printf '  \033[90m(a DETACHED tmux session is not dead — reattaching restores it intact)\033[0m\n'
  PS1='\[\033[41;97;1m\]UNSHELTERED\[\033[0m\] '"$PS1"
fi
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
# SHELTER INDICATOR (founder ask 2026-07-17, after apt restarted code-server and
# killed an agent that was NOT in tmux). A status bar merely EXISTING meant
# "you're in tmux" only to someone who already knew that - the dangerous state
# looked like nothing at all. Now the safe state SAYS so, in green, permanently,
# and it is visible even while an agent's TUI owns the pane (the status line
# lives outside it). Its absence is the tell for a plain shell, reinforced by
# the red banner+prompt that /etc/profile.d/swordfish-qol.sh prints there.
set -g status-left "#[bg=colour28,fg=colour231,bold] SHELTERED #[bg=colour22,fg=colour231] #S #[default] "
set -g status-left-length 40
set -g status-right "#[fg=colour245]survives code-server restart · #H | %H:%M UTC"
set -g status-right-length 60
# clipboard: let OSC52 escape from inside tmux to the outer terminal, so the
# `copy` QoL command lands content in the founder's Mac clipboard (2026-07-13)
set -g allow-passthrough on
set -s set-clipboard external
TMUXCONF

# code-server unit: CONVERGED here since 2026-07-16 (cloud-init lockstep) -
# it used to live only in cloud-init and had drifted by hand-edit on the live
# box, which is how the 06:43 incident restart happened outside provisioning.
# Workstation boxes only (guarded on the binary).
# Dual --proxy-domain, ORDER MATTERS:
#   1. localhost:8080 - browsers send Host WITH the port
#      ("3005.localhost:8080"), and code-server matches the Host verbatim
#      (getHost never strips ports), so this entry is what makes real
#      browser requests proxy at all. Being FIRST it also becomes
#      VSCODE_PROXY_URI, so Ports-tab links carry :8080 - portless links
#      were "refused to connect" on the founder's Mac (port 80).
#   2. localhost - keeps portless Host shapes working (curl, header-rewriting
#      proxies). Works for ANY app port on ANY future project - the URL
#      pattern is http://<port>.localhost:8080 through the tunnel.
# NOTE: converging this file NEVER auto-restarts code-server - a restart
# kills plain-shell terminals (codex). Restart deliberately at clean points;
# tmux agents survive it once agent-tmux (below) owns the server.
if command -v code-server >/dev/null 2>&1; then
  pre_cs=$changed
  install_if_changed 0644 /etc/systemd/system/code-server.service <<'CSUNIT'
[Unit]
Description=code-server (VS Code in the browser) - SSH-tunnel-only
After=network.target

[Service]
User=deploy
ExecStart=/usr/bin/code-server --bind-addr 127.0.0.1:8080 --auth none --proxy-domain localhost:8080 --proxy-domain localhost
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CSUNIT
  if [ "$changed" -ne "$pre_cs" ]; then
    sudo systemctl daemon-reload
    echo "NOTE: code-server.service converged - restart it DELIBERATELY (kills plain-shell terminals)"
  fi
fi

# agent-tmux.service: the tmux server as its OWN unit, outside every other
# service's cgroup. Learned the hard way 2026-07-16: agent-term used to let
# the first terminal spawn the tmux server, which parked it inside
# code-server.service's cgroup - `systemctl restart code-server` then killed
# the server and EVERY agent session in it (swordfish, thalon mid-work,
# eamos's codex, the founder's dev server). systemd kills by cgroup;
# PPID=1 reparenting does NOT mean a process escaped it.
# `tmux -D` = foreground server (systemd owns the lifecycle) and implies
# exit-empty off, so the server idles fine with zero sessions.
install_if_changed 0644 /etc/systemd/system/agent-tmux.service <<'UNIT'
[Unit]
Description=agent tmux server - persistent seam for all agent sessions
# invariant: must NEVER be merged into / made dependent on code-server -
# surviving code-server restarts is this unit's entire reason to exist
After=network.target

[Service]
User=deploy
Type=simple
ExecStart=/usr/bin/tmux -D
# sessions inherit the SERVER's env: ~/.local/bin carries the self-updating
# claude build that agent-term auto-starts
Environment=PATH=/home/deploy/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Restart=always
RestartSec=5
# OOMPolicy=stop (systemd's service default) turned one hungry agent into a
# fleet kill on 2026-07-17: the kernel OOM-killed thalon's 3.7GiB claude and
# systemd then stopped the WHOLE unit - tmux server + every agent session.
# continue = the kernel's single-process kill stands; everyone else survives.
OOMPolicy=continue

[Install]
WantedBy=multi-user.target
UNIT

if ! systemctl is-enabled --quiet agent-tmux 2>/dev/null; then
  sudo systemctl daemon-reload
  sudo systemctl enable agent-tmux >/dev/null
  changed=1
fi
# adopt the socket only when nothing is serving it - NEVER kill a live server
# here (that is agent-tmux-cutover's job, run at an agreed founder moment)
if ! systemctl is-active --quiet agent-tmux && ! tmux has-session 2>/dev/null; then
  sudo systemctl start agent-tmux
  changed=1
fi

# agent-tmux-cutover: ONE-SHOT migration of a live in-cgroup tmux server to
# agent-tmux.service. Kills every current tmux session, so agents wrap first
# and it runs DETACHED (the caller usually dies with the server):
#   sudo systemd-run --unit=agent-tmux-cutover --on-active=5 /usr/local/bin/agent-tmux-cutover
install_if_changed 0755 /usr/local/bin/agent-tmux-cutover <<'CUTOVER'
#!/bin/bash
# root-only, deliberate: swaps the agent tmux server under agent-tmux.service
set -u
runuser -u deploy -- tmux kill-server 2>/dev/null || true
sleep 1
systemctl daemon-reload
systemctl enable agent-tmux >/dev/null 2>&1
systemctl restart agent-tmux
sleep 1
pid=$(systemctl show -p MainPID --value agent-tmux)
ok="OK"
[ "${pid:-0}" != 0 ] || ok="FAIL: agent-tmux has no main pid"
if [ "$ok" = OK ]; then
  cg=$(cat /proc/"$pid"/cgroup 2>/dev/null)
  case "$cg" in *agent-tmux.service*) ;; *) ok="FAIL: server not in unit cgroup" ;; esac
fi
msg="🤖 [$(hostname -s)] agent-tmux cutover: $ok (expected - planned fix). Agent sessions were ended cleanly; reopen project tabs + gogogo."
logger -t swordfish-alerts "$msg"
if [ -r /etc/swordfish/alerts.env ]; then
  . /etc/swordfish/alerts.env
  [ -n "${ALERTS_BOT_TOKEN:-}" ] && [ -n "${ALERTS_CHAT_ID:-}" ] && \
    curl -fsS -m 10 "https://api.telegram.org/bot${ALERTS_BOT_TOKEN}/sendMessage" \
      -d chat_id="${ALERTS_CHAT_ID}" --data-urlencode text="$msg" >/dev/null 2>&1
fi
echo "$ok"
[ "$ok" = OK ]
CUTOVER

# agent-term: code-server's DEFAULT terminal profile (wired in the box's
# code-server settings.json - see cloud-init). Every integrated terminal lands
# in a tmux session named after the workspace folder, so a browser/window
# crash never kills the agent - reopening the terminal reattaches to the same
# live session (a bare-terminal claude died with its pty on 2026-07-13, taking
# uncommitted work with it). The tmux server itself must belong to
# agent-tmux.service (see above), which agent-term ensures before attaching.
# First open auto-starts claude; when claude exits you land in a shell inside
# tmux. A plain shell is the "bash" profile in the terminal dropdown - that is
# also the deliberate home for CODEX (founder call 2026-07-16: he reads codex
# via native terminal scrollback, which tmux would capture; `codex resume`
# is its crash recovery). A second tab on the same project MIRRORS the
# first - that is tmux, not a bug.
install_if_changed 0755 /usr/local/bin/agent-term <<'AGENTTERM'
#!/bin/bash
d="$PWD"
# protocol: never launch the agent at $HOME (empty memory slug)
[ "$d" = "$HOME" ] && [ -d "$HOME/work/swordfish" ] && d="$HOME/work/swordfish"
s=$(printf '%s' "$(basename "$d")" | tr -cs 'A-Za-z0-9_-' '-')
s=${s#-}; s=${s%-}; [ -n "$s" ] || s=agent
# the shared tmux server must run under agent-tmux.service, never this
# terminal's cgroup (a code-server restart killed every agent 2026-07-16)
systemctl is-active --quiet agent-tmux || sudo -n systemctl start agent-tmux 2>/dev/null || true
exec tmux new-session -A -s "$s" -c "$d" \
  'claude; echo; echo "[claude exited - type claude to relaunch, or claude --continue to resume the last conversation]"; exec bash'
AGENTTERM

if ! grep -qF '/etc/profile.d/swordfish-qol.sh' /etc/bash.bashrc; then
  printf '\n# swordfish: profile.d only reaches login shells; code-server terminals are\n# interactive non-login (2026-07-13). QoL stays in one file, hooked in here.\n[ -f /etc/profile.d/swordfish-qol.sh ] && . /etc/profile.d/swordfish-qol.sh\n' \
    | sudo tee -a /etc/bash.bashrc >/dev/null
  changed=1
fi

# --- syd4 swap headroom: +4G /swapfile2 on top of the fleet 2G baseline -------
# Founder call 2026-07-18: thalon runs multi-lane agent work on this 8GiB box
# until the 16GB resize lands; ONE lane alone peaked at 3.7GiB (the 07-17 OOM).
# Swap is survival headroom, not speed: simultaneous lane peaks degrade to
# swapping instead of OOM kills (OOMPolicy=continue above caps any kill to one
# process). The fleet 2G baseline stays phase2-host.sh's; this is syd4-only.
if [ "$(hostname -s)" = syd4 ]; then
  if sudo swapon --show=NAME --noheadings | grep -qx /swapfile2; then
    echo "OK: /swapfile2 already active"
  else
    if [ ! -f /swapfile2 ]; then
      sudo fallocate -l 4G /swapfile2 || sudo dd if=/dev/zero of=/swapfile2 bs=1M count=4096 status=none
    fi
    sudo chmod 600 /swapfile2
    sudo mkswap /swapfile2 >/dev/null
    sudo swapon /swapfile2
    echo "CHANGED: 4G /swapfile2 activated (6G swap total)"
    changed=1
  fi
  if ! grep -q '^/swapfile2 ' /etc/fstab; then
    echo '/swapfile2 none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    changed=1
  fi
fi

# --- verify ------------------------------------------------------------------
# env -u TERM_PROGRAM: probe as a NON-vscode shell - converging from a
# code-server terminal leaks TERM_PROGRAM=vscode into the probe, the auto-land
# guard execs the probe into agent-term and false-fails the check (2026-07-17)
env -u TERM_PROGRAM bash -ic 'type work' >/dev/null 2>&1 || { echo "FAIL: work invisible to non-login interactive shells"; exit 1; }
env -u TERM_PROGRAM bash -lc 'type work' >/dev/null 2>&1 || { echo "FAIL: work invisible to login shells"; exit 1; }
# auto-land guard: a vscode-shaped interactive shell must exec into agent-term
# (stubbed via AGENT_TERM); the PLAIN_SHELL=1 dropdown profile must fall through
stub=$(mktemp); printf '#!/bin/bash\necho GUARD-FIRED\n' > "$stub"; chmod +x "$stub"
out=$(env -u TMUX TERM_PROGRAM=vscode AGENT_TERM="$stub" bash -ic 'echo REACHED-BODY' 2>/dev/null)
case "$out" in *GUARD-FIRED*) ;; *) echo "FAIL: auto-land guard did not fire in a vscode shell"; exit 1;; esac
case "$out" in *REACHED-BODY*) echo "FAIL: auto-land guard fired but the shell body still ran"; exit 1;; esac
out=$(env -u TMUX TERM_PROGRAM=vscode PLAIN_SHELL=1 AGENT_TERM="$stub" bash -ic 'echo REACHED-BODY' 2>/dev/null)
case "$out" in *REACHED-BODY*) ;; *) echo "FAIL: PLAIN_SHELL escape hatch broken"; exit 1;; esac
rm -f "$stub"
[ -x /usr/local/bin/agent-term ] || { echo "FAIL: agent-term missing or not executable"; exit 1; }
bash -n /usr/local/bin/agent-term || { echo "FAIL: agent-term does not parse"; exit 1; }
[ -x /usr/local/bin/agent-tmux-cutover ] || { echo "FAIL: cutover script missing"; exit 1; }
bash -n /usr/local/bin/agent-tmux-cutover || { echo "FAIL: cutover script does not parse"; exit 1; }
systemctl is-enabled --quiet agent-tmux || { echo "FAIL: agent-tmux not enabled"; exit 1; }
# the unit must parse; capture-then-check (verdicts never through pipes)
out=$(systemd-analyze verify /etc/systemd/system/agent-tmux.service 2>&1) || { echo "FAIL: agent-tmux unit invalid: $out"; exit 1; }
if [ "$(hostname -s)" = syd4 ]; then
  sudo swapon --show=NAME --noheadings | grep -qx /swapfile2 || { echo "FAIL: /swapfile2 not active (syd4 swap headroom)"; exit 1; }
fi

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (QoL file + non-login hook)"
fi
