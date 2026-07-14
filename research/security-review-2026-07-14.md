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
