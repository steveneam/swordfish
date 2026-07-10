#!/usr/bin/env bash
set -euo pipefail

# enable-ssh-443.sh - the chartered SSH-on-443 fallback (AGENTS.md operating
# rule 2), founder-approved 2026-07-11: BinaryLane blocks ALL outbound port-22
# from syd4, so the syd4->syd3 break-glass channel rides 443 instead.
# sshd gains a second listener via drop-in; the drop-in lists BOTH ports
# because any Port directive overrides sshd's implicit default of 22.
# ufw allows 443 only from the approved break-glass source (default: syd4).
# The provider-firewall twin of that rule is applied via the Vultr API,
# outside this script. Idempotent - safe to re-run.

SRC_ALLOW="${1:-66.226.147.123}"
DROPIN=/etc/ssh/sshd_config.d/10-swordfish-ssh443.conf
changed=0

if [ ! -f "$DROPIN" ]; then
  printf 'Port 22\nPort 443\n' | sudo tee "$DROPIN" >/dev/null
  sudo chmod 644 "$DROPIN"
  changed=1
fi

# never restart into a broken config
sudo sshd -t

if [ "$changed" -eq 1 ]; then
  sudo systemctl restart ssh
fi

if ! sudo ufw status | grep -E "443/tcp.*ALLOW.*${SRC_ALLOW}" >/dev/null; then
  sudo ufw allow from "$SRC_ALLOW" to any port 443 proto tcp comment 'swordfish: ssh-on-443 break-glass'
  changed=1
fi

ss -ltn | grep -q ':443 ' || { echo "FAIL: sshd is not listening on 443"; exit 1; }
ss -ltn | grep -q ':22 '  || { echo "FAIL: sshd lost its 22 listener"; exit 1; }

if [ "$changed" -eq 0 ]; then
  echo "== converged: no changes"
else
  echo "== converged: changes applied (sshd on 22+443, ufw 443 from ${SRC_ALLOW})"
fi
