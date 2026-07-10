#!/usr/bin/env bash
# assert-cockpit.sh - cockpit-box hardening + toolchain assertions (syd3 profile).
# Runbook: executed over SSH by .github/workflows/cockpit-smoke.yml (CI-as-hands).
# The cockpit runs NO workloads: no Docker, no edge, ufw 22-only - so the fleet
# assert-hardening.sh deliberately does NOT apply; this is its cockpit twin.
# Keep in lockstep with provisioning/cloud-init/syd3.yaml.
# Runs as the deploy user (NOPASSWD sudo). Exit 0 only if every assertion passes.

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
echo "== mem: $(free -m | awk '/^Mem:/{print $3 "M used / " $2 "M total, " $7 "M avail"}') | swap: $(free -m | awk '/^Swap:/{print $3 "M used / " $2 "M total"}')"

# first boot may still be configuring - wait for cloud-init to settle (10 min cap)
timeout 600 cloud-init status --wait >/dev/null 2>&1 || true
echo "== cloud-init: $(cloud-init status 2>/dev/null | tr '\n' ' ')"

# sshd effective config (sshd -T = post-include truth, not file contents)
check "sshd: password auth off"        "sudo sshd -T | grep -qx 'passwordauthentication no'"
check "sshd: keyboard-interactive off" "sudo sshd -T | grep -qx 'kbdinteractiveauthentication no'"
check "sshd: root login off"           "sudo sshd -T | grep -qx 'permitrootlogin no'"
check "sshd: only deploy allowed"      "sudo sshd -T | grep -qx 'allowusers deploy'"
check "sshd: curve25519/sntrup kex"    "sudo sshd -T | grep -qx 'kexalgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org'"
check "sshd: no hmac-sha1 macs"        "sudo sshd -T | grep -qx 'macs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com'"

# firewall: 22 only - the cockpit publishes nothing (80/443 allowed = drift)
check "ufw: active"                    "sudo ufw status verbose | grep -q 'Status: active'"
check "ufw: default deny incoming"     "sudo ufw status verbose | grep -q 'deny (incoming)'"
check "ufw: allows 22/tcp"             "sudo ufw status | grep -Eq '^22/tcp\s+ALLOW'"
check "ufw: no 80/tcp rule"            "! sudo ufw status | grep -Eq '^80/tcp\s+ALLOW'"
check "ufw: no 443/tcp rule"           "! sudo ufw status | grep -Eq '^443/tcp\s+ALLOW'"

# intrusion + patching
check "fail2ban: service active"       "systemctl is-active --quiet fail2ban"
check "fail2ban: sshd jail up"         "sudo fail2ban-client status sshd"
check "unattended-upgrades: enabled"   "systemctl is-enabled --quiet unattended-upgrades"
check "apt periodic: unattended=1"     "apt-config dump APT::Periodic::Unattended-Upgrade | grep -q '\"1\"'"
check "unattended-upgrades: reboot on" "apt-config dump Unattended-Upgrade::Automatic-Reboot | grep -q '\"true\"'"
check "unattended-upgrades: 18:30 UTC" "apt-config dump Unattended-Upgrade::Automatic-Reboot-Time | grep -q '\"18:30\"'"

# host layer
check "clock: UTC"                     "[ \"\$(date +%Z)\" = UTC ]"
check "swap: /swapfile active"         "sudo swapon --show=NAME --noheadings | grep -qx /swapfile"
check "swap: fstab entry"              "grep -q '^/swapfile ' /etc/fstab"
check "swap: swappiness=10"            "sysctl -n vm.swappiness | grep -qx 10"

# no container runtime, by design (deltas doc'd in cloud-init/syd3.yaml header)
check "cockpit: no docker engine"      "! command -v docker"

# dev toolchain - the reason this box exists
check "toolchain: git"                 "git --version"
check "toolchain: gh"                  "gh --version"
check "toolchain: tmux"                "tmux -V"
check "toolchain: node >= 20"          "node -e 'process.exit(parseInt(process.versions.node)>=20?0:1)'"
check "toolchain: claude code"         "command -v claude"
check "toolchain: ripgrep"             "rg --version"
check "toolchain: jq"                  "jq --version"

echo "== $((total - fails))/$total assertions passed"
[ "$fails" -eq 0 ] || exit 1
exit 0
