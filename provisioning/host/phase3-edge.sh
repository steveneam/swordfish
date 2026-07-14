#!/usr/bin/env bash
# phase3-edge.sh - Bucket 2 (Stage 1b): edge + control plane converge.
#   Traefik v3 + docker-socket-proxy own the edge (compose/edge, rsynced to
#   /opt/swordfish/edge by edge-apply.yml); Dokploy runs version-pinned behind
#   TLS at deploy.swordfish.cfd. Runbook: runbooks/edge.md.
#
# Why we do NOT pipe dokploy's install.sh (read in full at pin time, 2026-07-07):
#   - destructive on re-run: `docker swarm leave --force` + `network rm -f`
#     would tear down a healthy box - the opposite of a converge;
#   - it aborts if 80/443 are bound, so it could never re-run behind our edge;
#   - it starts a raw-socket dokploy-traefik we replace anyway;
#   - piping remote root shell is the Bucket-1.5 supply-chain lesson.
#   The equivalent steps are vendored below, guarded + idempotent. Re-derive
#   against upstream install.sh whenever the pin moves (upgrade protocol:
#   runbooks/edge.md - blocked until Bucket-3 backups cover /etc/dokploy).
#
# Dokploy contract preserved (dokploy packages/server/src/setup/traefik-setup.ts):
#   entrypoints web/websecure, resolver "letsencrypt", dynamic dir
#   /etc/dokploy/traefik/dynamic (acme.json inside), edge on dokploy-network.
#   Configs land BEFORE the dokploy service first boots - dokploy only writes
#   its defaults if the files are missing, so ours stick. Our container is
#   swordfish-traefik ON PURPOSE: dokploy force-removes any container named
#   dokploy-traefik when it reinitializes its managed edge.
#
# Runs as deploy (docker group, NOPASSWD sudo), piped over SSH by edge-apply.yml.
# Idempotent: re-running on a converged box is a no-op.

set -euo pipefail

DOKPLOY_VERSION=v0.29.10   # pinned (CHARTER Bucket 2); never bump before Bucket-3 restic covers /etc/dokploy
POSTGRES_IMAGE=postgres:16 # vendored from install.sh at the pin
REDIS_IMAGE=redis:7        # vendored from install.sh at the pin
EDGE_DIR=/opt/swordfish/edge
# Overridable for the parallel-run window (Bucket 5): the successor box carries
# a temp neutral FQDN (deploy2.) until DNS cutover, then a re-run with the real
# FQDN re-points the bootstrap route. Default = the production control plane.
DEPLOY_FQDN="${DEPLOY_FQDN:-deploy.swordfish.cfd}"
DYN=/etc/dokploy/traefik/dynamic

changed=0
traefik_restart=0
note() { echo "$1"; }

[ -f "$EDGE_DIR/compose.yaml" ] || { echo "FAIL: $EDGE_DIR missing - edge-apply must ship compose/edge first"; exit 1; }

# --- 0. swarm (dokploy prereq; single-node manager) ---------------------------
if docker info --format '{{.Swarm.LocalNodeState}}' | grep -qx active; then
    note "OK: swarm already active"
else
    # single public-NIC box: advertise the primary address. Swarm mgmt ports
    # (2377/7946/4789) stay unreachable - provider firewall + ufw allow only
    # 22/80/443 in (verified by the Bucket-2 pre-steps).
    addr=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    [ -n "$addr" ] || { echo "FAIL: no primary IPv4 for swarm advertise-addr"; exit 1; }
    docker swarm init --advertise-addr "$addr" >/dev/null
    note "CHANGED: swarm initialized (advertise $addr)"
    changed=1
fi

# --- 1. dokploy-network (attachable overlay: edge + every workload join it) ---
if docker network inspect dokploy-network >/dev/null 2>&1; then
    note "OK: dokploy-network exists"
else
    docker network create --driver overlay --attachable dokploy-network >/dev/null
    note "CHANGED: dokploy-network created"
    changed=1
fi

# --- 2. dokploy secrets (generated on-box, never leave it) ---------------------
for s in dokploy_postgres_password dokploy_auth_secret; do
    if docker secret inspect "$s" >/dev/null 2>&1; then
        note "OK: secret $s exists"
    else
        openssl rand -hex 32 | docker secret create "$s" - >/dev/null
        note "CHANGED: secret $s created"
        changed=1
    fi
done

# --- 3. traefik config BEFORE dokploy first-boot -------------------------------
# (dokploy's defaults ship httpChallenge + api.insecure; landing ours first
#  means dokploy's create-if-missing writers skip)
sudo mkdir -p /etc/dokploy
sudo chmod 777 /etc/dokploy   # upstream install.sh does this (non-root build
                              # workloads write under it); watch-item, not ours to fight yet
sudo install -d -m 755 /etc/dokploy/traefik "$DYN"

sync_file() { # src dst  (644; sets changed + traefik_restart flags on drift)
    if [ -f "$2" ] && sudo cmp -s "$1" "$2"; then
        note "OK: $2 converged"
    else
        sudo install -m 644 "$1" "$2"
        note "CHANGED: $2 updated from repo"
        changed=1
        # plain if, not `[ ] &&`: a false test as a function's last command
        # returns 1 and set -e kills the whole converge (hit live 2026-07-07)
        if [ "$2" = "/etc/dokploy/traefik/traefik.yml" ]; then traefik_restart=1; fi
    fi
}
sync_file "$EDGE_DIR/traefik/traefik.yml" /etc/dokploy/traefik/traefik.yml
sync_file "$EDGE_DIR/traefik/dynamic/50-swordfish-hardening.yml" "$DYN/50-swordfish-hardening.yml"

# --- 3b. traefik access-log landing zone (must exist before compose up mounts it)
# The JSON access log is fail2ban's input (section 8) - it lives on the host at
# /var/log/swordfish-traefik, bind-mounted to /var/log/traefik in the container.
sudo install -d -m 755 /var/log/swordfish-traefik
sudo touch /var/log/swordfish-traefik/access.log   # jail logpath must exist even before traefik's first write

sync_content() { # dest label  (desired content on stdin; 644 root; converges on drift)
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [ -f "$1" ] && sudo cmp -s "$tmp" "$1"; then
        note "OK: $2 converged"
        rm -f "$tmp"
        return 1
    fi
    sudo install -m 644 "$tmp" "$1"
    rm -f "$tmp"
    note "CHANGED: $2 updated"
    changed=1
    return 0
}

# copytruncate: no signal into the container needed; the seconds-wide copy
# window can drop a few lines - acceptable for an access log. maxsize backs
# the daily cadence so a request flood can't fill the disk between runs.
sync_content /etc/logrotate.d/swordfish-traefik "logrotate config" <<'EOF' || true
/var/log/swordfish-traefik/*.log {
    daily
    rotate 7
    maxsize 500M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# middlewares.yml: dokploy's routers reference redirect-to-https by name; dokploy
# creates this file only-if-missing at boot - pre-seeding it (same content as
# upstream createDefaultMiddlewares) keeps the bootstrap router below valid
if [ -f "$DYN/middlewares.yml" ]; then
    note "OK: middlewares.yml present (dokploy-owned)"
else
    sudo tee "$DYN/middlewares.yml" >/dev/null <<'EOF'
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
EOF
    note "CHANGED: middlewares.yml pre-seeded (upstream default shape)"
    changed=1
fi

# --- 4. bootstrap route: deploy.swordfish.cfd -> dokploy:3000 ------------------
# Shape mirrors dokploy's updateServerTraefik() exactly, so when the founder sets
# Server Domain in the UI dokploy rewrites this file to the same content (no-op
# handover). Written when missing, still the stock localhost stub, missing the
# websecure router, OR routed at a different FQDN (the Bucket-5 cutover re-point:
# re-running with the real DEPLOY_FQDN converges the route away from the temp
# name): saving Server Domain with the HTTPS toggle off makes dokploy
# DELETE dokploy-router-app-secure - with 3000 unpublished that 404s the UI with
# no recovery path except this converge (locked the founder out live, 2026-07-07).
# The control plane staying reachable over TLS is an invariant this enforces.
if [ ! -f "$DYN/dokploy.yml" ] || sudo grep -q 'docker.localhost' "$DYN/dokploy.yml" \
   || ! sudo grep -q 'dokploy-router-app-secure' "$DYN/dokploy.yml" \
   || ! sudo grep -qF "Host(\`$DEPLOY_FQDN\`)" "$DYN/dokploy.yml"; then
    sudo tee "$DYN/dokploy.yml" >/dev/null <<EOF
http:
  routers:
    dokploy-router-app:
      rule: Host(\`$DEPLOY_FQDN\`)
      service: dokploy-service-app
      entryPoints:
        - web
      middlewares:
        - redirect-to-https
    dokploy-router-app-secure:
      rule: Host(\`$DEPLOY_FQDN\`)
      service: dokploy-service-app
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
  services:
    dokploy-service-app:
      loadBalancer:
        servers:
          - url: http://dokploy:3000
        passHostHeader: true
EOF
    note "CHANGED: bootstrap route written ($DEPLOY_FQDN -> dokploy:3000)"
    changed=1
else
    note "OK: dokploy.yml route present"
fi

# --- 5. dokploy services (vendored from install.sh at the pin) -----------------
svc_exists() { docker service inspect "$1" >/dev/null 2>&1; }

if svc_exists dokploy-postgres; then
    note "OK: dokploy-postgres service exists"
else
    docker service create \
        --name dokploy-postgres \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --env POSTGRES_USER=dokploy \
        --env POSTGRES_DB=dokploy \
        --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
        --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
        --mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data \
        --detach "$POSTGRES_IMAGE" >/dev/null
    note "CHANGED: dokploy-postgres created ($POSTGRES_IMAGE)"
    changed=1
fi

if svc_exists dokploy-redis; then
    note "OK: dokploy-redis service exists"
else
    docker service create \
        --name dokploy-redis \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --mount type=volume,source=dokploy-redis,target=/data \
        --detach "$REDIS_IMAGE" >/dev/null
    note "CHANGED: dokploy-redis created ($REDIS_IMAGE)"
    changed=1
fi

if svc_exists dokploy; then
    running=$(docker service inspect dokploy --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | cut -d@ -f1)
    if [ "$running" = "dokploy/dokploy:$DOKPLOY_VERSION" ]; then
        note "OK: dokploy service at pin ($DOKPLOY_VERSION)"
    else
        # deliberate: report drift, never auto-upgrade (gated behind Bucket 3)
        note "WARN: dokploy runs $running, pin is $DOKPLOY_VERSION - upgrade is gated (runbooks/edge.md)"
    fi
else
    addr=$(docker info --format '{{.Swarm.NodeAddr}}')
    # deltas vs upstream: image pinned; NO --publish 3000 (UI is reachable only
    # through the TLS route - the provider firewall blocks 3000 anyway and the
    # published-ports CI assertion stays clean); RELEASE_TAG=latest matches
    # upstream's pinned-version branch
    docker service create \
        --name dokploy \
        --replicas 1 \
        --network dokploy-network \
        --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
        --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
        --mount type=volume,source=dokploy,target=/root/.docker \
        --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
        --secret source=dokploy_auth_secret,target=/run/secrets/dokploy_auth_secret \
        --update-parallelism 1 \
        --update-order stop-first \
        --constraint 'node.role == manager' \
        --env RELEASE_TAG=latest \
        --env ADVERTISE_ADDR="$addr" \
        --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
        --env BETTER_AUTH_SECRET_FILE=/run/secrets/dokploy_auth_secret \
        --detach "dokploy/dokploy:$DOKPLOY_VERSION" >/dev/null
    note "CHANGED: dokploy service created (dokploy/dokploy:$DOKPLOY_VERSION, no published ports)"
    changed=1
fi

# --- 6. the edge must be ours: no stock dokploy-traefik ------------------------
# (defensive - this flow never creates one, but a UI 'reload traefik' would)
if docker ps -a --format '{{.Names}}' | grep -qx dokploy-traefik; then
    docker rm -f dokploy-traefik >/dev/null
    note "CHANGED: stock dokploy-traefik removed (swordfish-traefik owns the edge)"
    changed=1
else
    note "OK: no stock dokploy-traefik"
fi

# --- 7. edge stack up -----------------------------------------------------------
out=$(cd "$EDGE_DIR" && docker compose up -d 2>&1)
echo "$out"
if echo "$out" | grep -Eq 'Started|Created|Recreated'; then
    note "CHANGED: edge stack (re)started"
    changed=1
elif [ "$traefik_restart" -eq 1 ]; then
    docker restart swordfish-traefik >/dev/null
    note "CHANGED: swordfish-traefik restarted (static config drift)"
fi

# --- 8. acme storage perms (traefik creates it 600; belt-and-braces) ------------
if [ -f "$DYN/acme.json" ] && [ "$(sudo stat -c %a "$DYN/acme.json")" != "600" ]; then
    sudo chmod 600 "$DYN/acme.json"
    note "CHANGED: acme.json tightened to 0600"
    changed=1
fi

# --- 9. edge abuse jails: fail2ban over traefik's access log --------------------
# Security review 2026-07-14 finding 5: HTTP brute force / ratelimit floods had
# no firewall consequence (fail2ban watched sshd only). Design constraints:
#   - bans land in DOCKER-USER, not INPUT: traffic to docker-published 80/443 is
#     DNAT'd + FORWARDed and never traverses INPUT - an INPUT ban would be
#     cosmetic. DOCKER-USER is the chain docker guarantees for admin rules.
#   - port-scoped 80,443: a ban - even a false positive - can never touch 22,
#     so the founder/CI SSH path onto the box is structurally out of blast radius.
#   - ignoreip: loopback + RFC1918/CGN (kuma on this box probes our own public
#     hostnames - the box must never ban itself or its overlay networks), the
#     box's own public IP, the cockpit/workspace boxes (syd3/syd4: MCP calls +
#     staging asserts), and the founder's egress IP when provided.
#   - the auth (401/403) jail arms ONLY when FOUNDER_EGRESS_IP is set (shipped
#     by edge-apply from the FOUNDER_EGRESS_IP repo secret): founder-agreed
#     plan - no 401-bans before his IP is exempt, a fumbled login must not cost
#     him the web UI. The flood (429) jail arms now: deploy. is ratelimit-exempt
#     so he cannot generate 429s there, and sustained 429s elsewhere are
#     self-inflicted by definition (the rate limit is per-client-IP).
#   - backend = polling (the fleet baseline jail.local sets systemd, which
#     cannot read files); Cloudflare bucket note: once CF fronts the edge,
#     ClientHost becomes a CF address - these jails must move to the
#     X-Forwarded-For strategy in that bucket or they will ban CF's edge.
box_ip=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
fleet_ips=""
for h in syd3.swordfish.cfd syd4.swordfish.cfd; do
    hip=""
    hip=$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}') || hip=""
    if [ -n "$hip" ]; then fleet_ips="$fleet_ips $hip"; fi
done
ignoreip="127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 ${box_ip}${fleet_ips}"
if [ -n "${FOUNDER_EGRESS_IP:-}" ]; then
    ignoreip="$ignoreip $FOUNDER_EGRESS_IP"
    auth_enabled=true
else
    auth_enabled=false
fi

fail2ban_reload=0
# lookahead regex: JSON key order is alphabetical today but the filter must not
# depend on it. Status anchored with the trailing comma (3-digit codes only).
if sync_content /etc/fail2ban/filter.d/swordfish-traefik-auth.conf "fail2ban auth filter" <<'EOF'
[Definition]
failregex = ^(?=.*"DownstreamStatus":40[13],).*"ClientHost":"<HOST>"
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S
EOF
then fail2ban_reload=1; fi

if sync_content /etc/fail2ban/filter.d/swordfish-traefik-flood.conf "fail2ban flood filter" <<'EOF'
[Definition]
failregex = ^(?=.*"DownstreamStatus":429,).*"ClientHost":"<HOST>"
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S
EOF
then fail2ban_reload=1; fi

if sync_content /etc/fail2ban/jail.d/swordfish-traefik.local "fail2ban traefik jails" <<EOF
# generated by phase3-edge.sh - do not hand-edit (converge overwrites)
[swordfish-traefik-auth]
enabled = $auth_enabled
backend = polling
filter = swordfish-traefik-auth
logpath = /var/log/swordfish-traefik/access.log
chain = DOCKER-USER
port = 80,443
banaction = iptables-multiport
maxretry = 12
findtime = 10m
bantime = 1h
ignoreip = $ignoreip

[swordfish-traefik-flood]
enabled = true
backend = polling
filter = swordfish-traefik-flood
logpath = /var/log/swordfish-traefik/access.log
chain = DOCKER-USER
port = 80,443
banaction = iptables-multiport
maxretry = 60
findtime = 5m
bantime = 1h
ignoreip = $ignoreip
EOF
then fail2ban_reload=1; fi

if [ "$fail2ban_reload" -eq 1 ]; then
    sudo fail2ban-client reload >/dev/null
    note "CHANGED: fail2ban reloaded (traefik jails: flood armed, auth $( [ "$auth_enabled" = true ] && echo armed || echo 'DISARMED pending FOUNDER_EGRESS_IP'))"
else
    note "OK: fail2ban traefik jails converged"
fi

# --------------------------------------------------------------------------------
if [ "$changed" -eq 0 ]; then
    echo "== converged: no changes (idempotent re-run clean)"
else
    echo "== applied: edge + control plane converged (Bucket 2)"
fi
