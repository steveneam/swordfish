#!/usr/bin/env bash
set -euo pipefail

# setup-login-alerts.sh - fleet SSH-login alerting to the founder's Telegram
# (founder-interface-plan-2026-07-11, Leg 2). Deterministic and LLM-free by
# design: pam_exec fires on every sshd session open and posts WHO logged in,
# from WHERE, with WHICH KEY (labeled via the authorized_keys comment), over
# outbound 443 only. A daily digest reports failed/invalid auth counts.
#
# Secrets: /etc/swordfish/alerts.env (root, 600) is installed by the
# alerts-apply workflow, NEVER by this script and NEVER from a tracked file.
# Until it exists every hook exits silently - safe on fresh rebuilds.
# The alerts bot is SEND-ONLY and a different bot from Hermes: a compromised
# workload box must never hold a token that can command the cockpit agent.
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

# --- fail2ban -> journald (FIRST block: the restart below keys off $changed
#     still being 0). The digest counts bans with journalctl, but Ubuntu's
#     default logtarget is /var/log/fail2ban.log - the journal never sees
#     ' Ban ' lines, so every digest said "0 fail2ban bans" while fail2ban had
#     really banned (57 lifetime bans on syd4 when found, 2026-07-13). -------
if command -v fail2ban-client >/dev/null 2>&1; then
  install_if_changed 0644 /etc/fail2ban/fail2ban.local <<'F2B'
# swordfish (setup-login-alerts.sh): log to journald so the daily digest can
# count bans the same way it counts sshd failures. The file default keeps
# bans invisible to journalctl.
[Definition]
logtarget = SYSTEMD-JOURNAL
F2B
  if [ "$changed" -eq 1 ]; then
    sudo systemctl restart fail2ban
  fi
fi

# --- the pam_exec hook -------------------------------------------------------
install_if_changed 0755 /usr/local/bin/swordfish-pam-notify.sh <<'HOOK'
#!/usr/bin/env bash
# Fired by pam_exec on sshd session events. MUST never block or fail a login:
# every path exits 0, delivery is backgrounded, and the PAM line is 'optional'.
[ "${PAM_TYPE:-}" = "open_session" ] || exit 0
[ -r /etc/swordfish/alerts.env ] || exit 0
. /etc/swordfish/alerts.env
[ -n "${ALERTS_BOT_TOKEN:-}" ] && [ -n "${ALERTS_CHAT_ID:-}" ] || exit 0

user="${PAM_USER:-?}"; rhost="${PAM_RHOST:-?}"

# label the key: fingerprint SSH_AUTH_INFO_0, match against authorized_keys,
# report the key COMMENT (CI key / founder Mac / break-glass) - the label is
# what makes an unexpected key stand out.
label="no-key-info"
info="${SSH_AUTH_INFO_0:-}"
if [ -n "$info" ]; then
  line=$(printf '%s\n' "$info" | head -n1)
  if [ "${line%% *}" = "publickey" ]; then
    fp=$(printf '%s\n' "${line#publickey }" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')
    label="UNRECOGNIZED-KEY ${fp:-?}"
    home=$(getent passwd "$user" | cut -d: -f6)
    if [ -n "$home" ] && [ -r "$home/.ssh/authorized_keys" ]; then
      while IFS= read -r ak; do
        case "$ak" in ''|\#*) continue ;; esac
        akfp=$(printf '%s\n' "$ak" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}')
        if [ -n "$fp" ] && [ "$akfp" = "$fp" ]; then
          label=$(printf '%s\n' "$ak" | cut -d' ' -f3-)
          [ -n "$label" ] || label="uncommented-key $fp"
          break
        fi
      done < "$home/.ssh/authorized_keys"
    fi
  else
    label="method:${line%% *}"
  fi
fi

# classify the source so a phone alert is one-glance triage (founder ask
# 2026-07-15: "was at work, couldn't tell if the login was expected").
# Fleet + founder IPs mirror inventory/ssh-login-audit.md - update both
# together. FOUNDER_IPS in alerts.env (space-separated) overrides the
# founder defaults when his egress rotates.
marker="" src=""
case "$rhost" in
  103.249.236.41) marker="🔁" src="fleet: syd2 prod" ;;
  139.180.170.11) marker="🔁" src="fleet: syd3 cockpit+hermes" ;;
  66.226.147.123) marker="🔁" src="fleet: syd4 workspace+relay" ;;
  45.63.24.122)   marker="🔁" src="fleet: syd1 soak" ;;
esac
if [ -z "$src" ]; then
  for ip in ${FOUNDER_IPS:-202.128.115.13 49.186.75.98}; do
    if [ "$rhost" = "$ip" ]; then marker="🏠" src="founder egress IP"; break; fi
  done
fi
if [ -z "$src" ]; then
  case "$label" in *swordfish-ci*) marker="🤖" src="CI key (GitHub runner expected)" ;; esac
fi
if [ -z "$src" ]; then marker="⚠️" src="UNKNOWN SOURCE - check inventory/ssh-login-audit.md"; fi

# throttle: CI workflows log in several times per run - one alert per
# user|rhost|label per 2 minutes is signal, ten copies is noise.
tdir=/run/swordfish-alerts
mkdir -p "$tdir"
tkey="$tdir/$(printf '%s|%s|%s' "$user" "$rhost" "$label" | md5sum | cut -d' ' -f1)"
if [ -f "$tkey" ] && [ -n "$(find "$tkey" -mmin -2 2>/dev/null)" ]; then exit 0; fi
touch "$tkey"

msg="${marker} [$(hostname -s)] ssh login: ${user} from ${rhost} (${src}) key: ${label} $(date -u '+%F %H:%MZ')"
logger -t swordfish-alerts "$msg"
curl -fsS -m 10 "https://api.telegram.org/bot${ALERTS_BOT_TOKEN}/sendMessage" \
  -d chat_id="${ALERTS_CHAT_ID}" --data-urlencode text="$msg" >/dev/null 2>&1 &
exit 0
HOOK

# --- daily failed-auth digest ------------------------------------------------
install_if_changed 0755 /usr/local/bin/swordfish-auth-digest.sh <<'DIGEST'
#!/usr/bin/env bash
set -u
[ -r /etc/swordfish/alerts.env ] || exit 0
. /etc/swordfish/alerts.env
[ -n "${ALERTS_BOT_TOKEN:-}" ] && [ -n "${ALERTS_CHAT_ID:-}" ] || exit 0
fails=$(journalctl -u ssh --since "24 hours ago" --no-pager 2>/dev/null \
        | grep -cE 'Invalid user|Failed (publickey|password)|banner exchange.*invalid' || true)
bans=$(journalctl -u fail2ban --since "24 hours ago" --no-pager 2>/dev/null \
       | grep -c ' Ban ' || true)
[ "${fails:-0}" -eq 0 ] && [ "${bans:-0}" -eq 0 ] && exit 0
msg="[$(hostname -s)] auth digest 24h: ${fails} failed/invalid ssh attempts, ${bans} fail2ban bans"
curl -fsS -m 10 "https://api.telegram.org/bot${ALERTS_BOT_TOKEN}/sendMessage" \
  -d chat_id="${ALERTS_CHAT_ID}" --data-urlencode text="$msg" >/dev/null 2>&1
exit 0
DIGEST

install_if_changed 0644 /etc/systemd/system/swordfish-auth-digest.service <<'UNIT'
[Unit]
Description=swordfish: daily failed-auth digest to Telegram

[Service]
Type=oneshot
ExecStart=/usr/local/bin/swordfish-auth-digest.sh
UNIT

install_if_changed 0644 /etc/systemd/system/swordfish-auth-digest.timer <<'TIMER'
[Unit]
Description=swordfish: daily failed-auth digest (21:00 UTC = pre-dawn Sydney)

[Timer]
OnCalendar=*-*-* 21:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# --- wire pam_exec into sshd's session stack ('optional' = a broken or
#     missing hook can NEVER block a login) ---------------------------------
PAMLINE='session optional pam_exec.so quiet /usr/local/bin/swordfish-pam-notify.sh'
if ! sudo grep -qF "$PAMLINE" /etc/pam.d/sshd; then
  printf '%s\n' "$PAMLINE" | sudo tee -a /etc/pam.d/sshd >/dev/null
  changed=1
fi

# --- let sshd hand the auth key to PAM (founder fix 2026-07-15) --------------
# Without ExposeAuthInfo the hook's SSH_AUTH_INFO_0 is always empty, every
# alert says no-key-info, and the dashboard paints EVERY login red - alarm
# fatigue instead of one-glance triage. This is informational plumbing, not an
# auth-surface change: it only exposes the ALREADY-VERIFIED key to PAM so the
# label can resolve against authorized_keys comments. Drop-in wins: no other
# file sets the directive (verified fleet-wide before shipping) and the
# compiled-in default is the only competitor.
EXPOSE_CONF=/etc/ssh/sshd_config.d/20-swordfish-expose-auth-info.conf
if ! sudo grep -qsxF 'ExposeAuthInfo yes' "$EXPOSE_CONF"; then
  printf '# swordfish login alerts: expose the verified key to PAM so alerts can label it\nExposeAuthInfo yes\n' \
    | sudo tee "$EXPOSE_CONF" >/dev/null
  sudo chmod 644 "$EXPOSE_CONF"
  sudo sshd -t || { echo "FAIL: sshd config invalid after ExposeAuthInfo drop-in - removing it"; sudo rm -f "$EXPOSE_CONF"; exit 1; }
  sudo systemctl reload ssh
  changed=1
fi

if [ "$changed" -eq 1 ]; then
  sudo systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet swordfish-auth-digest.timer 2>/dev/null; then
  sudo systemctl enable --now swordfish-auth-digest.timer
  changed=1
fi

# --- verify ------------------------------------------------------------------
sudo grep -qF "$PAMLINE" /etc/pam.d/sshd || { echo "FAIL: pam line missing"; exit 1; }
[ -x /usr/local/bin/swordfish-pam-notify.sh ] || { echo "FAIL: hook missing"; exit 1; }
sudo sshd -T 2>/dev/null | grep -qix 'exposeauthinfo yes' \
  || { echo "FAIL: effective sshd config does not carry ExposeAuthInfo yes (an earlier directive wins?)"; exit 1; }
systemctl is-active --quiet swordfish-auth-digest.timer || { echo "FAIL: digest timer inactive"; exit 1; }
if command -v fail2ban-client >/dev/null 2>&1; then
  systemctl is-active --quiet fail2ban || { echo "FAIL: fail2ban inactive after logtarget change"; exit 1; }
  sudo fail2ban-client get logtarget | grep -q 'SYSTEMD-JOURNAL' \
    || { echo "FAIL: fail2ban logtarget is not journald - digest ban count stays 0"; exit 1; }
fi

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (pam hook + daily digest; env file pending = silent)"
fi
