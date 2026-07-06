#!/usr/bin/env bash
# assert-hardening.sh - Bucket 1 (Stage 1a): on-box hardening assertions.
# Runbook: CHARTER.md Bucket 1; executed over SSH by .github/workflows/hardening-smoke.yml
# (CI-as-hands, CHARTER.md decision 2). Runs as the deploy user (NOPASSWD sudo).
# Exit 0 only if every assertion passes.

set -u

total=0
fails=0
check() {
    local name="$1" cmd="$2"
    total=$((total + 1))
    if bash -c "$cmd" >/dev/null 2>&1; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

echo "== $(hostname -f 2>/dev/null || hostname) | $(uname -r) | up $(uptime -p 2>/dev/null || true)"

# first boot may still be configuring - wait for cloud-init to settle (10 min cap)
timeout 600 cloud-init status --wait >/dev/null 2>&1 || true
echo "== cloud-init: $(cloud-init status 2>/dev/null | tr '\n' ' ')"

# sshd effective config (sshd -T = post-include truth, not file contents)
check "sshd: password auth off"        "sudo sshd -T | grep -qx 'passwordauthentication no'"
check "sshd: keyboard-interactive off" "sudo sshd -T | grep -qx 'kbdinteractiveauthentication no'"
check "sshd: root login off"           "sudo sshd -T | grep -qx 'permitrootlogin no'"
check "sshd: only deploy allowed"      "sudo sshd -T | grep -qx 'allowusers deploy'"

# firewall
check "ufw: active"                    "sudo ufw status verbose | grep -q 'Status: active'"
check "ufw: default deny incoming"     "sudo ufw status verbose | grep -q 'deny (incoming)'"
check "ufw: allows 22/tcp"             "sudo ufw status | grep -Eq '^22/tcp\s+ALLOW'"
check "ufw: allows 80/tcp"             "sudo ufw status | grep -Eq '^80/tcp\s+ALLOW'"
check "ufw: allows 443/tcp"            "sudo ufw status | grep -Eq '^443/tcp\s+ALLOW'"

# intrusion + patching
check "fail2ban: service active"       "systemctl is-active --quiet fail2ban"
check "fail2ban: sshd jail up"         "sudo fail2ban-client status sshd"
check "unattended-upgrades: enabled"   "systemctl is-enabled --quiet unattended-upgrades"
check "apt periodic: unattended=1"     "apt-config dump APT::Periodic::Unattended-Upgrade | grep -q '\"1\"'"

# container runtime (Bucket 2 prereq)
check "docker: engine responds"        "docker ps"
check "docker: compose plugin"         "docker compose version"
check "docker: deploy in group"        "id -nG deploy | grep -qw docker"

echo "== $((total - fails))/$total assertions pass"
[ "$fails" -eq 0 ]
