#!/usr/bin/env bash
set -euo pipefail

# install-hermes-syd3.sh - Hermes pilot, E0 posture (see README.md alongside).
# Idempotent skeleton: deterministic parts are scripted; VERIFY items in the
# README get confirmed on first install and corrected here same-session.
# Safe ordering: nothing is enabled until the founder inputs replace the
# REPLACE_ME placeholders in /home/hermes/.hermes/.env.

changed=0

# --- dedicated non-sudo user -------------------------------------------------
if ! id hermes >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash hermes
  changed=1
fi
id -nG hermes | grep -qw sudo && { echo "FAIL: hermes must never hold sudo"; exit 1; }

# --- fetch installer: download-then-execute with retries (NodeSource lesson
#     2026-07-10: piped curl|bash fails SILENTLY - empty pipe = bash success) --
if ! sudo -u hermes test -x /home/hermes/.local/bin/hermes; then
  curl -fL --retry 5 --retry-delay 3 -o /tmp/hermes-install.sh \
    https://hermes-agent.nousresearch.com/install.sh
  [ -s /tmp/hermes-install.sh ] || { echo "FAIL: empty installer download"; exit 1; }
  sudo -u hermes bash /tmp/hermes-install.sh
  rm -f /tmp/hermes-install.sh
  changed=1
fi

# --- config: E0 posture, written only if absent (never clobber on-box edits) --
if ! sudo -u hermes test -f /home/hermes/.hermes/config.yaml; then
  sudo -u hermes mkdir -p /home/hermes/.hermes
  sudo -u hermes tee /home/hermes/.hermes/config.yaml >/dev/null <<'CFG'
# E0 posture - provisioning/hermes/README.md is the authority on these knobs
unauthorized_dm_behavior: ignore
approvals:
  mode: manual
  timeout: 60
  cron_mode: deny
  mcp_reload_confirm: true
  destructive_slash_confirm: true
security:
  allow_lazy_installs: false
  allow_private_urls: false
CFG
  changed=1
fi

if ! sudo -u hermes test -f /home/hermes/.hermes/.env; then
  sudo -u hermes tee /home/hermes/.hermes/.env >/dev/null <<'ENV'
# founder inputs - service will not enable while REPLACE_ME remains.
# HERMES bot = a DIFFERENT BotFather bot from the fleet alerts bot.
TELEGRAM_BOT_TOKEN=REPLACE_ME
TELEGRAM_ALLOWED_USERS=REPLACE_ME_FOUNDER_TELEGRAM_ID
# Vercel AI Gateway (OpenAI-compatible; chartered US$10/mo cap) - VERIFY keys
OPENAI_API_KEY=REPLACE_ME_GATEWAY_KEY
OPENAI_BASE_URL=https://ai-gateway.vercel.sh/v1
ENV
  sudo chmod 600 /home/hermes/.hermes/.env
  changed=1
fi

# --- systemd unit (system-level, runs as hermes) ------------------------------
if [ ! -f /etc/systemd/system/hermes-gateway.service ]; then
  sudo tee /etc/systemd/system/hermes-gateway.service >/dev/null <<'UNIT'
[Unit]
Description=Hermes agent gateway (E0 posture - provisioning/hermes/README.md)
After=network-online.target
Wants=network-online.target

[Service]
User=hermes
WorkingDirectory=/home/hermes
ExecStart=/home/hermes/.local/bin/hermes gateway start
Restart=always
RestartSec=10
NoNewPrivileges=true
SyslogIdentifier=hermes-gateway

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  changed=1
fi

# --- gate: never enable with placeholder secrets ------------------------------
if sudo grep -q REPLACE_ME /home/hermes/.hermes/.env; then
  echo "== staged, NOT enabled: fill /home/hermes/.hermes/.env (bot token,"
  echo "   founder Telegram ID, gateway key) then:"
  echo "   sudo systemctl enable --now hermes-gateway.service"
  exit 0
fi

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (enable the service when ready)"
fi
