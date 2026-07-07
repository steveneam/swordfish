# syd2 purchase step-card (founder, single touch) — BinaryLane

_Bucket-5 opener. ⛔ This purchase is the Bucket-5 Approval Gate — pre-approved at the
Bucket-4 checkpoint (CHARTER.md ruling 2), re-confirmed by you executing this card.
After this one form + one token, everything else is scripted._

## Before you start

- [ ] Open `provisioning/cloud-init/syd2.yaml` and copy the **entire file** to the
      clipboard (first line must be `#cloud-config`).
- [ ] Log in to BinaryLane (account created 2026-07-08).

## The purchase form (exact values)

Field names may differ slightly from the wizard's wording; these five values are the
invariants:

| Field | Value | Why it matters |
|---|---|---|
| Location | **Sydney (SYD)** | Latency + data residency; matches syd1 |
| Operating system | **Ubuntu 24.04 LTS** — NOT the 26.04 default | The user-data pins Docker's apt suite to `noble` and fail2ban assumes 24.04 images; 26.04 boots un-hardened Docker-less |
| Plan | **Standard 4 vCPU / 8 GB / 100 GB NVMe / 4 TB** — AUD $39.20/mo (≈US$26) | The checkpoint-approved plan, inside the $30 ceiling |
| Hostname / server name | `syd2.swordfish.cfd` | Neutral naming rule; DNS + TLS derive from it |
| Cloud-init user data (under Advanced/options) | **Paste syd2.yaml** | The whole hardening story lands at first boot; without it the box is a naked default image |

Also, while in the form:

- If it offers to add an **SSH key**, pick/upload `swordfish-ops` (harmless either way —
  the user-data bakes both keys into the `deploy` user and disables password auth).
- **Decline provider add-ons** (provider backups, licensed software): restic→B2 is the
  backup plane; extras breach the pinned budget.
- Double-check the user-data field really has content and starts with `#cloud-config`
  before you hit purchase.

## Immediately after purchase (still in the console)

1. **Record the box IP** (just note it — do NOT wire DNS; the A-record is scripted).
2. **Create the API token**: Developer API / API tokens section → new token (full
   access, name it `swordfish-agent`) → copy it once.
3. On the laptop, add to `E:\swordfish\.env` (gitignored — never anywhere else):

   ```
   BINARYLANE_API_TOKEN=<paste>
   ```

4. **Do not** log in via the emailed root password or web console — the box is key-only,
   root-refused from first boot (that's the point). Emailed password = break-glass only.

## Then hand back to the agent

Say: **"syd2 purchased, IP = x.x.x.x, token in .env"** — the scripted path takes over:
`provisioning/binarylane/` adapter → A-record `syd2` → hardening-smoke vs syd2 → edge →
backups + tested restore → dogfood replay (the portability drill) → verify-deadman on
syd2 → DNS cutover + soak. **The Vultr instance is destroyed only after the full
verification set passes** (parallel-run protocol, CHARTER.md ruling 2); the Vultr account
+ credit stay as fallback.
