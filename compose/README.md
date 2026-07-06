# compose/ — stack templates

Per-box baseline + per-workload Docker Compose templates:

- **Baseline (every box):** Traefik (auto-TLS via Let's Encrypt) + tecnativa **docker-socket-proxy** (nothing ever mounts the bare Docker socket) + **Dokploy** (the control plane — locked by the vault's ADR; deploy-playbook Phases 3–8 run through it) + monitoring agents (Beszel · Uptime Kuma).
- **Workloads:** one folder per workload. Images are **digest-pinned** to GHCR (built by CI — never on a laptop); secrets ship as compose secret-files (gitignored), never env-baked into images.

The production image bar (multi-stage · minimal pinned base · non-root · HEALTHCHECK) is defined in the vault's Docker standard; CI enforces what it can.
