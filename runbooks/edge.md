# Edge + control plane (Bucket 2)

The edge is **repo-managed**: `compose/edge/` (Traefik v3 + docker-socket-proxy) +
`provisioning/host/phase3-edge.sh`, applied by the dispatch-only `edge-apply` workflow.
Dokploy is the control plane behind it at `deploy.swordfish.cfd`, **version-pinned**
(pin lives in `phase3-edge.sh`; asserted by `assert-hardening.sh` — keep in lockstep).

## Rules (why they exist)

- **Never use Dokploy's UI Traefik actions** (restart/reload/env/ports on the Traefik
  screen). They (re)create a stock `dokploy-traefik` container with the raw Docker
  socket; it will crash-loop on the taken 80/443 and `assert-hardening.sh` flags it.
  The converge removes it. Edge changes = edit the repo → run `edge-apply`.
- **Never change the Let's Encrypt email in the UI** — it round-trips
  `/etc/dokploy/traefik/traefik.yml`, and the next converge reverts it. Change it in
  `compose/edge/traefik/traefik.yml`.
- **Never upgrade Dokploy before Bucket-3 backups** cover `/etc/dokploy` (2026 failure
  mode on record: updates removed the managed Traefik — issue Dokploy/dokploy#4245).
  Upgrade protocol (post-Bucket-3): re-read upstream `install.sh` at the new tag,
  re-derive the vendored steps in `phase3-edge.sh`, bump the pin there **and** in
  `assert-hardening.sh`, run `edge-apply`, verify, only then `docker service update`.

## How the pieces meet Dokploy's contract

Traefik keeps Dokploy's entrypoint names (`web`/`websecure`), resolver name
(`letsencrypt`), and dynamic dir (`/etc/dokploy/traefik/dynamic`) — Dokploy writes
per-app routers there and they route through our Traefik unchanged. The
`dokploy.yml` bootstrap route (written by the converge until Dokploy owns the file)
mirrors Dokploy's own shape, so setting *Server Domain* in the UI is a no-op handover.

## Access + break-glass

- UI: `https://deploy.swordfish.cfd` only. Port 3000 is **not published** (delta from
  upstream install; the provider firewall blocks it anyway and the published-ports
  assertion stays clean).
- If the TLS route is broken and the UI is needed anyway: republish temporarily via
  `docker service update --publish-add mode=host,published=3000,target=3000 dokploy`,
  reach it through an SSH tunnel (hotspot break-glass), then `--publish-rm` it again.
- Edge down hard: `cd /opt/swordfish/edge && docker compose up -d` (or re-run
  `edge-apply`, which is the same thing plus the converge).

## Watch-items on record

- `/etc/dokploy` is `chmod 777` — upstream install.sh behavior, kept to avoid fighting
  Dokploy's build workloads. Revisit at Bucket 6 (Ansible graduation).
- 2 GB RAM tier: record headroom at the Bucket-2 checkpoint (`free -m`,
  `docker stats --no-stream`); resize path is the Bucket-5 gate.
- ssh-audit `[warn]` findings are recorded by the smoke run, not gated; tightening
  sshd crypto is a future hardening pass.
