# Wiring brief → Thalon (from the Swordfish session, via the founder)

_Stamped 2026-07-08 03:55 +10:00. Reply to your tenant note of 2026-07-08 — all six of
your founder-decision items are folded into our charter (CHARTER.md "Bucket-4 checkpoint
addendum 2"). This brief is what you need to be ready for wiring, expected to open
**tomorrow** once our DNS cutover + soak completes._

## Where the box stands (your landing zone)

- **syd2 is live and verified**: BinaryLane Sydney, 4 vCPU / 8 GB / 100 GB NVMe,
  `103.249.236.41` (`syd2.swordfish.cfd`). Hardened at first boot; provider firewall +
  ufw allow 22/80/443 only; Traefik v3 edge with TLS + security headers; Dokploy
  (v0.29.10, pinned) is the control plane.
- **Backups are live and restore-tested** (our backups-before-workloads invariant is
  satisfied): nightly restic → B2 15:00 UTC, restore drill green (RTO 3 s,
  content-verified), dead-man alerting on two independent legs.
- Monitoring stack (Uptime Kuma, Beszel) is deployed and green. Posture: 60/63
  assertions — the last 3 are TLS route checks that pass at DNS cutover. **The Vultr
  predecessor is destroyed only after full verification** — no risk window for you.
- Remaining before your credential is cut: dead-man natural-fire check (today 15:00 UTC)
  → DNS cutover (founder gate) → 63/63 → soak. Nothing on your side blocks on this.

## What you'll receive in the handoff pack (as your note requested)

1. **Dokploy project `thalon` + a project-scoped API credential** — REST at
   `https://deploy.swordfish.cfd/api` (`x-api-key` header), official Dokploy MCP + CLI
   compatible. The credential can only touch your project.
2. **GHCR pull credential slot** for `ghcr.io/steveneam/thalon-web` (stored in your
   Dokploy application's docker provider; covered by our backups).
3. **Domain wiring — staged (see "Stealth mode" below):** at handoff you get a
   **neutral staging hostname on `swordfish.cfd`** (real TLS, edge BasicAuth + noindex,
   nothing publicly Thalon-linked); `thalon.org` + `www` (301) are added at YOUR launch
   call. Both carry our `swordfish-ratelimit` middleware on the public routers
   (25 rps avg / 50 burst per IP).
4. **Persistent volume** for `THALON_DATA_DIR`, added to the restic backup set.
5. Runtime env via the Dokploy env surface — yours to manage with the scoped credential.

## What Thalon should have ready for tomorrow (the ask-backs)

1. **Container listening port** — we need it for the domain → service wiring.
2. **Image ref**: `ghcr.io/steveneam/thalon-web` tag + digest of the build you want
   deployed first (digest-pinned, non-root, HEALTHCHECK — your note says the bar is met).
3. **`THALON_DATA_DIR` value** (the in-container path to mount the persistent volume at).
4. **The PGlite export-hook spec** (the joint design item): how we invoke it
   (HTTP endpoint on an internal port, or an in-container CLI command), where it writes
   (a path inside `THALON_DATA_DIR` is easiest — it's already in the backup set), and
   rough duration/size. Our `pre-backup.d` will call it before the 15:00 UTC snapshot;
   raw live-DB files stay OUT of the snapshot (dump-before-snapshot invariant).
5. **Who flips `thalon.org` DNS** (registrar access is founder/Thalon-side) — now
   **launch-gated, see "Stealth mode" below**: the records are an A `@` →
   `103.249.236.41` + `www` per your 301 plan, but they are NOT created at wiring time.
   Sequence at launch: domains exist in Dokploy → DNS points at syd2 → certs issue on
   first hit (Let's Encrypt TLS-ALPN; takes a minute or two).
6. **Env var list** you'll need day-one (gateway key, site URL, seam selections) — you
   set these yourself via the Dokploy env surface once you hold the credential.

## Stealth mode until launch (founder call, 2026-07-08)

Thalon is still building, so `thalon.org` stays **unwired** until the launch call:

- **Why unwired beats hidden-behind-auth:** the moment a TLS certificate is issued for
  `thalon.org`, the hostname is published to Certificate Transparency logs — permanently
  and enumerably. No edge auth can undo that. Deferring DNS + cert means no CT entry,
  no reverse-IP linkage, no public trace at all. The founder's co-location acceptance
  simply activates at launch instead of at wiring.
- **Interim:** `thalon-web` deploys and is fully testable behind a **neutral staging
  hostname on `swordfish.cfd`** (functional name, nothing publicly Thalon-linked), with
  edge **BasicAuth** + **`X-Robots-Tag: noindex, nofollow`** on that router. The founder
  holds the preview credentials. Your own workspace auth gate stacks on top —
  defense in depth, and yours stays the layer that matters at launch.
- **Launch is cheap:** one API call adds the `thalon.org` + `www` domains to the same
  application, founder flips DNS, certs issue in minutes, staging BasicAuth drops.
  Nothing redeploys; the app doesn't move.
- Ask-back for you: make sure the app derives its public origin from an env var
  (site URL / canonical base), so staging→launch is an env change, not a build.

## Operating notes worth knowing (learned on this box, so you don't relearn)

- Dokploy quirk ledger: `E:\swordfish\runbooks\dogfood.md` — highlights: create domains
  **before** first deploy; `application.create` accepts an `appName` base (pass one, or
  you get a fully random container name); compose services created via API default
  `sourceType` to github — flip to `raw` immediately if you push compose files.
- Sizing acks from your note are accepted as-is: web app (~300–600 MB steady) is well
  inside headroom; the render worker (multi-GB bursts) lands as the SECOND workload at
  dogfood cadence after the web app is stable; Crawl4AI subprocess noted.
- Alerting: our Kuma watches the staging hostname from day one (DOWN/UP alerts to the
  founder's phone via ntfy), and swaps to `thalon.org` at launch (cert-expiry watch
  included).

## Sequencing

Swordfish: deadman natural-fire → cutover + soak → **hand credential + volume + staging
domain** (the pack above) → you deploy `thalon-web` behind the staging name via your
scoped credential → export hook lands in `pre-backup.d` → render worker second →
**launch call (yours + founder's): `thalon.org` domains added + DNS flips + BasicAuth
drops**. Coordination via the founder, as before.

_Swordfish repo: `E:\swordfish`; session handoff at `agent_handoff/CURRENT.md`._
