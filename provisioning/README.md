# provisioning/ — reproducible box builds (the moat)

Every box must be re-creatable from code in this folder. The ratchet ladder:

1. **Box #1 (dogfood):** cloud-init + idempotent bash — captured live as the box is built. Every command that works lands here **in the same session**.
2. **Box #2:** promote to **Ansible + the dev-sec hardening collection** (the bash scripts become the reference implementation).
3. **Box #3+:** **OpenTofu** for provider resources (box · DNS · firewall · block storage); Ansible for configuration.

Rules: **idempotent** (re-running on a healthy box is a no-op — this is also the rebuild proof; boxes are never destroyed to prove it) · **no secrets** (parameters arrive via env / secret files) · **no local Docker** anywhere in the flow · every script names the runbook it belongs to.

## Layout (Bucket 1 →)

- `cloud-init/` — per-box first-boot user-data (hardening lands before the box is reachable).
- `vultr/` — provider API scripts (`create-box.ps1` — dry-run by default; `-Approve` = the spend gate).
- `dns/` — registrar records (`set-a-record.ps1` — idempotent Porkbun upsert).
- `host/` — idempotent host-layer converge scripts, applied over SSH by the `host-apply` workflow (Bucket 2 →). Anything here must also be mirrored into `cloud-init/` so rebuilds land converged.
- `checks/` — assertions CI runs against live boxes (`assert-hardening.sh`, driven by the `hardening-smoke` workflow).
