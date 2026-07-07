#!/usr/bin/env bash
# assert-hardening.sh - Buckets 1+2: on-box hardening + edge assertions.
# Runbook: CHARTER.md Buckets 1-2; executed over SSH by .github/workflows/hardening-smoke.yml
# and re-run after every converge by host-apply.yml / edge-apply.yml
# (CI-as-hands, CHARTER.md decision 2). Runs as the deploy user (NOPASSWD sudo).
# Exit 0 only if every assertion passes.

set -u

# Box-relative parameters (Bucket 5, parallel-run): the control-plane FQDN is
# overridable (successor box carries deploy2. until DNS cutover) and the backup
# profile name follows the box's own short hostname (profile "syd1" on syd1,
# "syd2" on syd2 - keep provisioning/backup/profiles.yaml naming in lockstep).
DEPLOY_FQDN="${DEPLOY_FQDN:-deploy.swordfish.cfd}"
BOX="$(hostname -s)"

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
# headroom record (2 GB tier watch-item, CHARTER Bucket 2 verify): every smoke
# run logs it so the resize call at Bucket 5 has a history, not a guess
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

# host layer (Bucket 2 pre-steps; applied by provisioning/host/phase2-host.sh,
# mirrored in cloud-init for rebuilds - keep all three in lockstep)
check "clock: UTC"                     "[ \"\$(date +%Z)\" = UTC ]"
check "docker: log caps configured"    "sudo grep -q 'max-size' /etc/docker/daemon.json"
check "docker: swarm active"           "docker info --format '{{.Swarm.LocalNodeState}}' | grep -qx active"
check "swap: /swapfile active"         "sudo swapon --show=NAME --noheadings | grep -qx /swapfile"
check "swap: fstab entry"              "grep -q '^/swapfile ' /etc/fstab"
check "swap: swappiness=10"            "sysctl -n vm.swappiness | grep -qx 10"
check "unattended-upgrades: reboot on" "apt-config dump Unattended-Upgrade::Automatic-Reboot | grep -q '\"true\"'"
check "unattended-upgrades: 18:30 UTC" "apt-config dump Unattended-Upgrade::Automatic-Reboot-Time | grep -q '\"18:30\"'"

# edge + control plane (Bucket 2; converged by provisioning/host/phase3-edge.sh
# + compose/edge via edge-apply.yml - keep versions/names in lockstep with both)
check "edge: swordfish-traefik running"  "docker inspect -f '{{.State.Running}}' swordfish-traefik | grep -qx true"
check "edge: socket-proxy running"       "docker inspect -f '{{.State.Running}}' swordfish-socket-proxy | grep -qx true"
check "edge: no stock dokploy-traefik"   "! docker ps -a --format '{{.Names}}' | grep -qx dokploy-traefik"
check "edge: traefik has no raw socket"  "! docker inspect swordfish-traefik -f '{{range .Mounts}}{{.Source}} {{end}}' | grep -q docker.sock"
check "edge: socket-proxy socket is ro"  "docker inspect swordfish-socket-proxy -f '{{range .Mounts}}{{.Source}}={{.RW}} {{end}}' | grep -q 'docker.sock=false'"
check "ports: only traefik on 0.0.0.0"   "! docker ps --format '{{.Names}} {{.Ports}}' | grep -v '^swordfish-traefik ' | grep -E '(0\.0\.0\.0|\[::\]):'"
check "ports: traefik only 80/443"       "! docker ps --filter name=swordfish-traefik --format '{{.Ports}}' | tr ',' '\n' | grep -E '(0\.0\.0\.0|\[::\]):' | grep -vE ':(80|443)->'"
check "edge: 80 redirects to https"      "curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve $DEPLOY_FQDN:80:127.0.0.1 http://$DEPLOY_FQDN | grep -qE '^30(1|8)$'"
check "edge: 443 answers TLS (SNI)"      "curl -sk --max-time 10 --resolve $DEPLOY_FQDN:443:127.0.0.1 https://$DEPLOY_FQDN -o /dev/null"
# accepted 30x includes 307: a FRESH dokploy answers with a 307 to /register
# (observed live on syd2 first boot, 2026-07-08) - the check's intent is
# "app answers through the route", not "already initialized"
check "edge: dokploy route live (no 404)" "curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve $DEPLOY_FQDN:443:127.0.0.1 https://$DEPLOY_FQDN | grep -qE '^(200|30[1278])$'"
check "edge: acme storage 0600"          "sudo stat -c %a /etc/dokploy/traefik/dynamic/acme.json | grep -qx 600"
check "dokploy: service 1/1"             "docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^dokploy 1/1'"
check "dokploy: postgres 1/1"            "docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^dokploy-postgres 1/1'"
check "dokploy: redis 1/1"               "docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^dokploy-redis 1/1'"
check "dokploy: image at pin"            "docker service inspect dokploy --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | grep -q 'dokploy/dokploy:v0.29.10'"

# backups (Bucket 3; converged by provisioning/host/phase7-backups.sh +
# provisioning/backup/ via backups-apply.yml - keep pins/names in lockstep).
# The snapshot check talks to B2 live: this smoke IS the standing verification
# that backups exist, not just that the machinery is installed.
check "restic: binary at pin"            "restic version | grep -q 'restic 0.19.1 '"
check "resticprofile: binary at pin"     "resticprofile version | grep -q 'version 0.33.1'"
check "backups: profiles.yaml present"   "sudo test -s /etc/resticprofile/profiles.yaml"
check "backups: repo password 0600 root" "sudo stat -c '%a %U' /etc/resticprofile/password.txt | grep -qx '600 root'"
check "backups: b2 key 0600 root"        "sudo stat -c '%a %U' /etc/resticprofile/b2.env | grep -qx '600 root'"
check "backups: dokploy-pg dump hook"    "sudo test -x /etc/resticprofile/pre-backup.d/10-dokploy-postgres-dump"
check "backups: nightly backup timer"    "systemctl is-enabled --quiet resticprofile-backup@profile-$BOX.timer"
check "backups: weekly check timer"      "systemctl is-enabled --quiet resticprofile-check@profile-$BOX.timer"
check "backups: weekly prune timer"      "systemctl is-enabled --quiet resticprofile-prune@profile-$BOX.timer"
check "backups: repo live, >=1 snapshot" "sudo resticprofile -c /etc/resticprofile/profiles.yaml --name $BOX snapshots --json | grep -q short_id"

# dogfood workloads (Bucket 4; tracked in compose/status + compose/metrics,
# deployed via the Dokploy MCP - the AI-operability surface). Container names
# carry Dokploy-generated compose-project suffixes, so match by fragment.
check "dogfood: kuma healthy"            "docker ps --filter name=kuma --format '{{.Status}}' | grep -q '(healthy)'"
check "dogfood: beszel hub running"      "docker ps --filter name=beszel-1 --format '{{.Status}}' | grep -q '^Up'"
check "dogfood: beszel agent running"    "docker ps --filter name=agent-1 --format '{{.Status}}' | grep -q '^Up'"
# the box-wide socket invariant: the raw docker socket is mounted ONLY into
# tecnativa socket-proxies and the Dokploy control plane itself - an app
# container holding the socket = a box compromise waiting for an app CVE
check "sockets: proxies+dokploy only"    "! docker ps -q | xargs -r -n1 docker inspect -f '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}' | grep docker.sock | grep -vE 'socket-proxy|^/dokploy\.'"
check "backups: dogfood dump hook"       "sudo test -x /etc/resticprofile/pre-backup.d/20-dogfood-sqlite-dumps"
check "backups: sqlite3 for dump hook"   "command -v sqlite3"
check "backups: kuma-url 0600 root"      "sudo stat -c '%a %U' /etc/resticprofile/kuma-url | grep -qx '600 root'"
check "dogfood: hello running"           "docker ps --filter name=swordfish-hello --format '{{.Status}}' | grep -q '^Up'"
check "dogfood: hello route live"        "curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve hello.swordfish.cfd:443:127.0.0.1 https://hello.swordfish.cfd | grep -qE '^(200|30[1278])$'"
check "dogfood: status route live"       "curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve status.swordfish.cfd:443:127.0.0.1 https://status.swordfish.cfd | grep -qE '^(200|30[1278])$'"
check "dogfood: metrics route live"      "curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve metrics.swordfish.cfd:443:127.0.0.1 https://metrics.swordfish.cfd | grep -qE '^(200|30[1278])$'"
check "edge: ratelimit middleware defined" "sudo grep -q 'swordfish-ratelimit' /etc/dokploy/traefik/dynamic/50-swordfish-hardening.yml"

echo "== $((total - fails))/$total assertions pass"
[ "$fails" -eq 0 ]
