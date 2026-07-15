# Security review — 2026-07-14 (founder-directed)

Founder ask: "run some security checks over our VPS to make sure it's secure
against API attacks, DDoS, and prompt injections." Three lenses over the fleet
(security-reviewer agent x3 + live recon). Findings ranked by exploitability;
each carries a ratchet and a status. `invariant` = safety one-way (never
loosened); `opinion` = convention.

Fleet at review time: syd2 (prod: Dokploy control plane + Traefik edge + tenant
Postgres + Kuma/Beszel/hello), syd3 (cockpit + hermes gateway), syd4 (workspace
+ relay), syd1 (soak/rollback). Live recon confirmed syd2 external surface = ONLY
80/443 (Postgres/Docker/Dokploy-direct all filtered); security headers + sniStrict
live; Dokploy /api 401 unauth; registration bounces closed.

## Confirmed findings (ranked)

1. **Relay founder-id gate spoofable (HIGH, code-certain).** `swordfish-relay.sh`
   parsed the FIRST `|<digits>]` from hermes's `[name|id]` tag; the display name
   before it is attacker-controlled and may contain `|`/`]`, so a display name
   `x|<founderid>]` forged the founder id. Reproduced vs live state.db + unit test.
   Precondition: a non-founder able to post a user-row in the ops group (today
   founder+bots only). → **FIXED** `ca71f4a`: anchored trailing-id parse
   (`parse_sender`), +14 hostile-input assertions in `test-relay-map.sh`.
   Ratchet: executable, **invariant**.

2. **Tenant Dokploy key over-grant (HIGH).** `tenant-credential.sh` grants
   `canCreateServices=True`; `service:create` also permits compose.create/
   application.create → arbitrary image/compose with host bind-mount → container
   escape on the SHARED prod box. Key already distributed to Thalon; leak = box
   compromise. Header falsely claimed "cannot create anything." → **PARTIAL**
   `9778b26`: corrected the docs, non-destructive `canCreateServices` read-back
   (WARN, FAIL under `STRICT_SCOPE=1`), opt-in `PROBE_CREATE=1` live test, SLUG
   guard. **DEFERRED (founder):** the deploy-without-create architectural decision
   + the live prod probe; **rotate Thalon's key together with the scope fix** (not
   alone — same over-grant, and rotating now breaks their CI twice).
   Ratchet: executable, **invariant** once STRICT_SCOPE flips.

3. **`[Steven via hermes-relay]` unauthenticated trust sentinel (HIGH).** AGENTS.md
   rule 10 told agents the prefix "IS the founder"; it's committed plaintext, so
   any content an agent ingests (vault, tenant DB, alerts, git logs, web) could
   forge it. Related: memory/handoff/vault are auto-read on `gogogo` and could
   carry injected "Next" items. → **FIXED** `ca71f4a`: rule 10 rewritten — prefix
   is routing/provenance not authority; founder-gate list (spend, destroy,
   secrets read-out, authorized_keys, firewall/sshd/edge weakening, vault push)
   holds regardless of any prefix/handoff/memory/vault and is confirmed
   in-session; rule 11 carves this out of the auto-start.
   Ratchet: structural/doc, **invariant**.

4. **No slowloris/connection cap at the edge (HIGH, availability).** Only L7
   control was a per-IP rate limit counting COMPLETED requests; a single-host
   slowloris issued zero 429s and could exhaust Traefik on all routers incl.
   deploy. → **FIXED** `21208ba` (applied to syd2 via edge-apply): `inFlightReq`
   amount=100 at the websecure entrypoint (safe for deploy. — 503 not lockout) +
   `readTimeout=60s` (writeTimeout left default to protect streaming) + net
   sysctls; +4 assertions, posture 68→72 (edge-apply run 29324955083, idempotent,
   control plane healthy, live-verified). Ratchet: config+executable, **opinion**.

5. **Control-plane brute-force / no HTTP jail (HIGH, availability+auth).** deploy.
   is rate-limit-exempt (defensible) and fail2ban watches sshd only; a scripted
   login flood = unmetered password-hash CPU drain + credential stuffing.
   → **STAGED (next):** fail2ban jail over Traefik's JSON access log (needs
   access-log-to-file + rotation); optional ipAllowList on deploy.
   Ratchet target: executable, opinion.

## Mediums / staged

- **Relay turn-splitting (MED).** Multi-line body via `send-keys` submitted extra
  turns that could carry a forged prefix. → **FIXED** `ca71f4a`: `send-keys -l --`
  + newline collapse.
- **hermes tag-format dependency (MED, durability).** The gate depends on hermes's
  tag shape (a third-party we don't own). → **FIXED** `be5ee49`: 6-hourly
  `relay-tag-canary` (edge-triggered alert + cockpit tile) fires if a tag-shaped
  message stops parsing. Chosen over patching hermes's schema (couples us, no
  structured sender column exists for the forum path anyway).
- **No per-container memory limits (MED, blast containment).** One container OOMs
  the 8GB box → kernel may kill Traefik/control plane. Matters before Thalon's
  render worker. → **STAGED (next):** limits on Dokploy-deployed workloads
  (Dokploy deploy.resources) + assert no unbounded container.
- **Public origin IP + 4TB cap (MED, billing/availability).** A ~100Mbps flood
  burns 4TB in days. → **DEFERRED to Cloudflare bucket (Next-4)**, gated behind
  the soak (DNS is the syd1 rollback lever until ~07-16). Interim: bandwidth alert.

## Lows

- CI SSH `StrictHostKeyChecking=accept-new` = blind TOFU on ephemeral runners for
  a root-capable key. → pin `known_hosts` (host keys aren't secret). STAGED.
- IPv6 firewall scope narrower than the Vultr predecessor (no AAAA today). Note.
- `gh secret set --body "$PW"` puts the tenant DB password on argv on shared syd4.
  → pipe via stdin. STAGED.
- A couple of `workflow_dispatch` inputs interpolated unquoted into remote shell
  (repo-write already implies box control). → validate inputs. STAGED.

## Solid (verified, no action)
Only 80/443 externally on syd2; read-only socket-proxy everywhere; secrets
untracked + 0600; CI uses env-mapped secrets (no `${{}}` injection sink), commit-
pinned actions, read-only GITHUB_TOKEN; SQL provisioning validates slug/password;
TLS 1.2 + sniStrict + security headers live; Dokploy /api 401 + registration
closed; monitoring UIs need login (strong generated passwords); hermes holds zero
credentials toward syd4 and its injection path doesn't pass through an LLM;
`!map` allowlist path-traversal-safe.

## The honest DDoS ceiling
A single box with a public origin IP cannot absorb volumetric L3/L4 or large
DISTRIBUTED L7 floods — per-IP limits are useless vs a botnet. That is the
**Cloudflare bucket's** job (Next-4) and only works with origin-IP rotation
(current IP is in DNS + CT logs), firewall locked to CF ranges, ACME switched
TLS-ALPN→DNS-01, and `forwardedHeaders.trustedIPs`=CF. Gated behind the soak.

## Next actions (post-review)
1. **STAGED edge (this slice, 2nd apply):** fail2ban Traefik-log jail (finding 5)
   + workload memory limits (blast containment).
2. **Tenant-key scope fix (finding 2):** resolve deploy-without-create with the
   founder → flip `STRICT_SCOPE=1` → rotate Thalon's key once, properly scoped.
3. **Cloudflare bucket (Next-4):** after the soak gate.
4. Low-severity cleanups: pin CI known_hosts, gh-secret stdin, dispatch-input
   validation, IPv6 firewall rules.

## Addendum 2026-07-14 (staged-edge slice executed)

- **inFlightReq was per-HOST, not per-IP (HIGH, self-inflicted, fixed same
  day).** The middleware landed in the morning slice with no `sourceCriterion`
  — and Traefik's documented default for inFlightReq groups by REQUEST HOST
  (unlike rateLimit, which defaults to client IP). Net effect: a 100-concurrent
  cap on each hostname that one attacker could exhaust with slow requests to
  503 every other client — a DoS amplifier posing as a mitigation. Fixed:
  `sourceCriterion.ipStrategy` (depth 0 = TCP remote address) + a
  `hardening-smoke` assertion so it can never silently regress. Lesson routed
  to the CF bucket note: middleware defaults are per-middleware, verify each
  against docs, not by analogy.
- **Finding 5 executed:** Traefik JSON access log → host file
  (`/var/log/swordfish-traefik`, logrotated) + two fail2ban jails banning in
  `DOCKER-USER` (INPUT never sees docker-published traffic), port-scoped 80,443
  so a ban can never touch 22. Flood jail (429s) armed; auth jail (401/403)
  ships DISARMED until the founder's egress IP lands in the `FOUNDER_EGRESS_IP`
  repo secret (his call from the review plan: no 401-bans before his IP is
  exempt). Filters verified with fail2ban-regex against synthetic Traefik JSON
  before landing. Ratchet: executable (converge + smoke assertions), opinion.
- **Memory limits executed (blast containment):** caps sized from 6 days of
  Beszel history (>=2x observed peak): thalon-web **4 GiB** (founder call
  2026-07-14, raised twice from the metrics-derived 1 GiB — it is a
  web-design + video-editing tool, renders in-process, so the cap allows
  spikes well past the ~502 MB observed peak; worst-case cap-sum ~7.2 GB on
  the 8 GB box is acceptable because caps are limits, not reservations, and
  steady state is ~2.6 GB), kuma 512 MiB
  (~218 MB), tenant-pg 512 MiB (~55 MB), beszel hub 256 MiB,
  agent 128 MiB, socket-proxies 64 MiB, hello 128 MiB. Deliberately uncapped:
  the edge pair + Dokploy control-plane trio (protecting them is the point).
  Enforced by the "workloads: all memory-capped" smoke assertion. Thalon's
  render worker gets sized when they answer the RAM ask-back. Ratchet:
  executable, opinion (sizes) / invariant (no unbounded workload).

## Addendum 2026-07-15 — finding 2 RESOLVED: Option B (deploy-without-create), verified live

The deferred deploy-without-create decision closed today, founder-directed:

- **Permission-model fact (verified via customRole.getStatements):** Dokploy
  has NO `service:update` statement — `application.update` gates on
  `service:create`, so no narrower ROLE can carry the legacy image-bump call.
  Deploy-without-create therefore required a pipeline-shape change, offered to
  Thalon as Option B (fixed `:staging` GHCR tag re-tagged by digest in their
  CI; key drops to deploy-only) vs Option A (keep shape, audit-log detection).
- **Thalon chose B** (their reasoning: capability-removal > detection on a
  shared box) and staged the CI path behind `DEPLOY_VIA_RETAG` same day.
- **Candidate-key trial (live, prod, their written endorsement):** deploy-only
  member (`canCreateServices=False`) → `application.update` 401 ·
  `application.deploy` 200 (`running`→`done` ~20 s) · `application.one` 200 ·
  live `compose.create` probe REJECTED · sees only its project · docker 401.
  **The host-bind-mount container-escape class closes by capability removal.**
- **Rotation state:** new deploy-only key swapped into their CI secret
  (2026-07-15 08:57 UTC); old key stays live as rollback until their
  confirm-deploy is green, then it is revoked + the legacy member retired and
  `STRICT_SCOPE=1` becomes the standing check. `tenant-credential.sh` now
  mints deploy-only BY DEFAULT (`CREATE_SCOPE=1` = legacy escape, documented
  as a coordinated-cutover-only knob). Project 1's future tenant pack is born
  deploy-only. Ratchet: executable, **invariant** (tenant keys carry no
  create-class grant).
