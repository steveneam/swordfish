#!/usr/bin/env bash
set -euo pipefail

# install-hermes-syd3.sh - Hermes pilot, E0 posture (see README.md alongside).
# Idempotent; first live run 2026-07-11 (hermes-agent 0.18.2) - actuals folded
# back in: the upstream installer creates ~/.hermes/config.yaml and .env from
# ITS templates, so posture/identity are applied AFTER install as marker-
# guarded APPENDS (top-level posture keys are absent from their template;
# python-dotenv and ruamel take the later value). Service unit runs
# `hermes gateway run` (foreground) - `gateway start` targets hermes's OWN
# installed service, which we deliberately do not use (root-managed system
# unit instead; the non-sudo hermes user cannot control its own supervision).

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
  # non-interactive: installer skips sudo-needing extras (ffmpeg - fine, E0
  # needs none of them) and creates config.yaml/.env/SOUL.md from templates
  sudo -u hermes bash /tmp/hermes-install.sh
  rm -f /tmp/hermes-install.sh
  changed=1
fi

# --- telegram adapter deps: the curated install does NOT ship them, and the
#     runtime error hint names a nonexistent extra ('hermes-agent[telegram]');
#     the real extra is [messaging] (python-telegram-bot et al). uv, not pip -
#     uv-created venvs carry no pip. (lesson 2026-07-11) ---------------------
if ! sudo -u hermes /home/hermes/.hermes/hermes-agent/venv/bin/python -c 'import telegram' 2>/dev/null; then
  sudo -u hermes bash -lc 'cd ~/.hermes/hermes-agent && ~/.hermes/bin/uv pip install --python ./venv/bin/python ".[messaging]"'
  changed=1
fi

# --- E0 toolset: disable everything execution-capable (idempotent) -----------
# survivors = web, todo, memory, session_search, clarify, cronjob
# PER PLATFORM: `hermes tools disable` defaults to --platform cli only, while
# each gateway platform resolves its own list (telegram's default composite
# `hermes-telegram` = EVERYTHING). Found live 2026-07-13: telegram-side hermes
# ran nslookup/uname and attempted sudo with the cli platform "disabled" -
# `hermes tools list` (no flag) shows cli and says nothing about the gateway.
for _plat in cli telegram; do
  if sudo -u hermes bash -lc "hermes tools list --platform $_plat" | grep -E '✓ enabled +(terminal|code_execution|computer_use|browser|file|skills|delegation|image_gen|tts|vision) ' >/dev/null; then
    sudo -u hermes bash -lc "hermes tools disable --platform $_plat terminal code_execution computer_use browser file skills delegation image_gen tts vision"
    changed=1
  fi
done

# --- posture: marker-guarded append (never clobber the upstream template) ----
if ! sudo grep -q 'swordfish E0 posture' /home/hermes/.hermes/config.yaml; then
  sudo -u hermes tee -a /home/hermes/.hermes/config.yaml >/dev/null <<'CFG'

# ============================================================================
# swordfish E0 posture (provisioning/hermes/README.md is the authority;
# these top-level keys are absent from the upstream template)
# ============================================================================
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

# --- identity: staged with placeholders; real values are applied by the
#     operator (agent pipes them from inventory/secrets/, never tracked) ------
if ! sudo grep -q 'swordfish E0 identity' /home/hermes/.hermes/.env; then
  sudo tee -a /home/hermes/.hermes/.env >/dev/null <<'ENV'

# swordfish E0 identity - fill via operator, service gates on REPLACE_ME.
# HERMES bot = a DIFFERENT BotFather bot from the fleet alerts bot.
TELEGRAM_BOT_TOKEN=REPLACE_ME
TELEGRAM_ALLOWED_USERS=REPLACE_ME_FOUNDER_TELEGRAM_ID
TELEGRAM_HOME_CHANNEL=REPLACE_ME_FOUNDER_TELEGRAM_ID
TELEGRAM_HOME_CHANNEL_NAME=Steven
# LLM: Vercel AI Gateway (OpenAI-compatible; chartered US$10/mo cap).
# Wire as model.provider "custom" + model.base_url in config.yaml, key below
# (exact key name verified at enable time - see README VERIFY).
OPENROUTER_API_KEY=REPLACE_ME_GATEWAY_KEY
ENV
  changed=1
fi
sudo chown hermes:hermes /home/hermes/.hermes/.env
sudo chmod 600 /home/hermes/.hermes/.env

# --- model wiring via `hermes config set` ONLY (lesson 2026-07-11: the CLI
#     normalizes/rewrites config.yaml on every tools/config command, so sed
#     against template text silently matches nothing). Actuals from first
#     enable: llama-3.3-70b FAILS Hermes's tool schema (Groq failed_generation)
#     -> gpt-oss-120b (price-equivalent, strong function calling); max_tokens
#     must sit under the provider's output cap; api_key MUST be set in config
#     (the gateway runtime does not honor the env fallback for custom). -------
if ! sudo grep -q 'base_url: https://ai-gateway.vercel.sh/v1' /home/hermes/.hermes/config.yaml; then
  sudo -u hermes bash -lc '
    hermes config set model.provider custom
    hermes config set model.base_url https://ai-gateway.vercel.sh/v1
    hermes config set model.default openai/gpt-oss-120b
    hermes config set model.max_tokens 2048'
  changed=1
fi
if ! sudo grep -q REPLACE_ME /home/hermes/.hermes/.env && ! sudo grep -q 'api_key:' /home/hermes/.hermes/config.yaml; then
  sudo -u hermes bash -lc 'hermes config set model.api_key "$(grep ^OPENROUTER_API_KEY= ~/.hermes/.env | cut -d= -f2-)"' >/dev/null
  sudo chmod 600 /home/hermes/.hermes/config.yaml
  changed=1
fi

# --- systemd unit (system-level, root-managed, runs as hermes) ---------------
if [ ! -f /etc/systemd/system/hermes-gateway.service ] || \
   ! grep -q 'hermes gateway run' /etc/systemd/system/hermes-gateway.service; then
  sudo tee /etc/systemd/system/hermes-gateway.service >/dev/null <<'UNIT'
[Unit]
Description=Hermes agent gateway (E0 posture - provisioning/hermes/README.md)
After=network-online.target
Wants=network-online.target

[Service]
User=hermes
WorkingDirectory=/home/hermes
ExecStart=/home/hermes/.local/bin/hermes gateway run
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
