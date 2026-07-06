# provisioning/ — reproducible box builds (the moat)

Every box must be re-creatable from code in this folder. The ratchet ladder:

1. **Box #1 (dogfood):** cloud-init + idempotent bash — captured live as the box is built. Every command that works lands here **in the same session**.
2. **Box #2:** promote to **Ansible + the dev-sec hardening collection** (the bash scripts become the reference implementation).
3. **Box #3+:** **OpenTofu** for provider resources (box · DNS · firewall · block storage); Ansible for configuration.

Rules: **idempotent** (re-running on a healthy box is a no-op — this is also the rebuild proof; boxes are never destroyed to prove it) · **no secrets** (parameters arrive via env / secret files) · **no local Docker** anywhere in the flow · every script names the runbook it belongs to.
