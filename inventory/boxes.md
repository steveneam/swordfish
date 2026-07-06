# Boxes

| box | provider | region | plan / specs | runs-what | $/mo | provisioned-by | backups (last tested restore) | status |
|-----|----------|--------|--------------|-----------|------|----------------|-------------------------------|--------|
| syd1.swordfish.cfd | Vultr | syd (Sydney) | `vhf-1c-2gb` — 1 vCPU / 2 GB / 64 GB NVMe / 2 TB bw | Swordfish tooling (Dokploy · Kuma · Beszel · hello); Project 2 from Stage 2 | 12 | `provisioning/cloud-init/syd1.yaml` + `provisioning/vultr/create-box.ps1` (2026-07-07, founder-approved gate) | *(Bucket 3 — pending; NO WORKLOADS until then)* | **live** — 45.63.24.122, hardened at first boot, `hardening-smoke` = the standing verification. Bucket-2 pre-steps applied 2026-07-07: provider firewall `swordfish-syd1` (22/80/443 only, `firewall-group.ps1`), daemon.json log caps + live-restore, reboot window 18:30 UTC, swap 6.2G (image-shipped, kept) + swappiness 10 — 23/23 assertions green |

*(purchase approved + executed 2026-07-07 at the Bucket-1 gate; access = CI-as-hands via the `swordfish-ci` key (repo secret `SSH_DEPLOY_KEY`) + founder break-glass key; box billing started — $12/mo against the $250 credit, within the $30/mo Stage-1–2 ceiling)*
