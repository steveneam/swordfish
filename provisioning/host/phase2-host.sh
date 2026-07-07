#!/usr/bin/env bash
# phase2-host.sh - Bucket 2 host layer (pre-steps from the Checkpoint-1 research
# pass + the sshd crypto floor the ssh-audit smoke gate requires):
#   1. Docker daemon.json: json-file log caps (a chatty container cannot fill the
#      disk) + live-restore (daemon restarts/upgrades do not kill containers).
#   2. unattended-upgrades reboot window: kernel/libc updates actually take effect
#      unattended (no Ubuntu Pro attach - personal-use terms judged grey).
#      18:30 UTC = 04:30 AEST / 05:30 AEDT - pre-dawn Sydney; box clock stays UTC.
#   3. 2 GB swapfile + swappiness=10: on a 2 GB box the OOM killer is the real
#      enemy; swap buys graceful degradation instead (RAM headroom watch-item).
#   4. sshd crypto restriction: stock OpenSSH offers NIST-curve kex + hmac-sha1,
#      which ssh-audit grades [fail] - the smoke workflow gates on those.
# Runbook: CHARTER.md Bucket 2; executed over SSH by
# .github/workflows/host-apply.yml / edge-apply.yml (CI-as-hands). Runs as deploy
# (NOPASSWD sudo). Idempotent: re-running on a converged box is a no-op; only
# changes restart docker/sshd.

set -euo pipefail

changed=0
note() { echo "$1"; }

# --- 1. Docker daemon.json ---------------------------------------------------
desired_daemon_json='{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}'

if [ -f /etc/docker/daemon.json ] && echo "$desired_daemon_json" | sudo cmp -s /etc/docker/daemon.json -; then
    note "OK: /etc/docker/daemon.json already converged"
else
    if [ -f /etc/docker/daemon.json ]; then
        sudo cp /etc/docker/daemon.json "/tmp/daemon.json.bak.$(date +%s)"
        note "CHANGED: existing daemon.json backed up to /tmp before overwrite"
    fi
    echo "$desired_daemon_json" | sudo tee /etc/docker/daemon.json >/dev/null
    sudo systemctl restart docker
    # docker must come back and agree live-restore is on, else fail loudly
    for i in $(seq 1 12); do
        if sudo docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null | grep -qx true; then break; fi
        [ "$i" -eq 12 ] && { echo "FAIL: docker did not come back with live-restore after restart"; exit 1; }
        sleep 5
    done
    note "CHANGED: daemon.json written, docker restarted, live-restore confirmed"
    changed=1
fi

# --- 2. unattended-upgrades reboot window ------------------------------------
reboot_conf=/etc/apt/apt.conf.d/52-swordfish-reboot
desired_reboot_conf='Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "18:30";'

if [ -f "$reboot_conf" ] && echo "$desired_reboot_conf" | sudo cmp -s "$reboot_conf" -; then
    note "OK: reboot window already converged ($reboot_conf)"
else
    echo "$desired_reboot_conf" | sudo tee "$reboot_conf" >/dev/null
    # apt-config parses the whole conf.d tree - a syntax error here would break apt
    apt-config dump Unattended-Upgrade::Automatic-Reboot >/dev/null
    note "CHANGED: reboot window set (18:30 UTC = pre-dawn Sydney)"
    changed=1
fi

# --- 3. swap: 2 GB file + conservative swappiness -----------------------------
if sudo swapon --show=NAME --noheadings | grep -qx /swapfile; then
    note "OK: /swapfile already active ($(sudo swapon --show=SIZE --noheadings | head -1 | tr -d ' '))"
else
    if [ ! -f /swapfile ]; then
        sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
    sudo swapon /swapfile
    note "CHANGED: 2 GB swapfile created and activated"
    changed=1
fi

if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    note "CHANGED: /swapfile added to fstab (survives reboot)"
    changed=1
else
    note "OK: /swapfile already in fstab"
fi

swappiness_conf=/etc/sysctl.d/99-swordfish-swap.conf
if [ -f "$swappiness_conf" ] && grep -qx 'vm.swappiness=10' "$swappiness_conf"; then
    note "OK: swappiness already converged"
else
    echo 'vm.swappiness=10' | sudo tee "$swappiness_conf" >/dev/null
    sudo sysctl -q vm.swappiness=10
    note "CHANGED: vm.swappiness=10 (swap is a safety net, not a working set)"
    changed=1
fi

# --- 4. sshd crypto restriction (ssh-audit [fail]-clean) -----------------------
# curve25519/sntrup kex + ed25519/rsa-sha2 host keys + AEAD/etm only. Every real
# client (GitHub runners, founder laptop + phone, Vultr-adjacent tooling) speaks
# these; the file is validated with sshd -t BEFORE restart so a typo can never
# lock the box (validation failure removes the drop-in and aborts loudly).
crypto_conf=/etc/ssh/sshd_config.d/01-swordfish-crypto.conf
desired_crypto_conf='KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com'

if [ -f "$crypto_conf" ] && echo "$desired_crypto_conf" | sudo cmp -s "$crypto_conf" -; then
    note "OK: sshd crypto already converged ($crypto_conf)"
else
    echo "$desired_crypto_conf" | sudo tee "$crypto_conf" >/dev/null
    if ! sudo sshd -t; then
        sudo rm -f "$crypto_conf"
        echo "FAIL: sshd rejected the crypto drop-in - removed it, sshd untouched"
        exit 1
    fi
    sudo systemctl restart ssh
    note "CHANGED: sshd crypto restricted (validated with sshd -t before restart)"
    changed=1
fi

# ------------------------------------------------------------------------------
if [ "$changed" -eq 0 ]; then
    echo "== converged: no changes (idempotent re-run clean)"
else
    echo "== applied: box now carries the Bucket-2 host layer"
fi
