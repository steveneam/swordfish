# compose/ — stack templates

Per-box baseline + per-workload Docker Compose templates:

- **`edge/` (every box, live on syd1):** Traefik v3 (auto-TLS via Let's Encrypt, TLS-ALPN) + tecnativa **docker-socket-proxy** (nothing internet-facing ever mounts the bare Docker socket). **Dokploy** (the control plane — locked by the vault's ADR; deploy-playbook Phases 3–8 run through it) rides behind it, created by `provisioning/host/phase3-edge.sh` as pinned swarm services rather than compose (its own architecture). Monitoring agents (Beszel · Uptime Kuma) arrive in Bucket 4 via Dokploy.
- **Workloads:** one folder per workload. Images are **digest-pinned** to GHCR (built by CI — never on a laptop); secrets ship as compose secret-files (gitignored), never env-baked into images.

The production image bar (multi-stage · minimal pinned base · non-root · HEALTHCHECK) is defined in the vault's Docker standard; CI enforces what it can.
