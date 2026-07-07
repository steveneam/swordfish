# CURRENT — session handoff (one file, overwritten each wrap)

_Stamped: 2026-07-07 20:35 +10:00 (Bucket 4 COMPLETE — awaiting the founder CHECKPOINT review)_

## State

**Bucket 4 done against every charter line; Stage-1 definition-of-done met.
The AI-operability test ran clean: all deploys + operations went through the
Dokploy MCP from Claude Code — zero SSH, zero UI.** Posture 62/62 assertions
(run 28859416115). Operating detail: `runbooks/dogfood.md`.

- **hello** live at `hello.swordfish.cfd` — CI→GHCR (scratch/non-root/
  HEALTHCHECK, runner-smoked pre-push), pulled with the founder's
  `read:packages` PAT (in Dokploy's registry store, covered by backups),
  digest-pinned `sha-f57702fe3ce5`. Page shows the build SHA = deploy receipt;
  Kuma flipped its monitor UP on deploy (founder got the ntfy).
- **Uptime Kuma 2.4.0** at `status.` + **Beszel 0.18.7** at `metrics.` (agent
  behind its own socket-proxy; box-wide socket invariant asserted).
- **Dead-man DUAL + proven by a real backup** (healthchecks.io + Kuma push;
  `backup-ok` beat on record). Kuma/Beszel SQLite state rides the nightly set
  as host-side dumps.
- **Alerts verified end-to-end:** Kuma→ntfy→phone (organic DOWN + UP received
  by the founder); **UptimeRobot** v3 checks on `status.` + `deploy.` → email
  (`provisioning/uptimerobot/bootstrap.py`; NOTE: 2025+ accounts are v3-only,
  v2 writes return access_denied). healthchecks.io = dead-man witness.
- **Rate limit** 25avg/50burst on hello/status/metrics routers; `deploy.`
  exempt by design — verified with a live hammer (44×429 vs 80×200).
- **Ratchets:** idempotent bootstraps (kuma / beszel / uptimerobot, all
  re-run-proven) · 62 standing assertions · Renovate active on all repo pins
  (hello's pin lives in Dokploy → agent-operated updates, documented).
- Founder items ALL closed: PAT ✓ ntfy subscribed ✓ UptimeRobot key ✓
  kuma+beszel passwords in the password manager ✓.
- RAM watch: ~71% used with all stacks idle → Bucket-5 resize input.

## Next — Bucket-4 CHECKPOINT (founder review), then Bucket 5

Checkpoint agenda:
1. Definition-of-done walkthrough (everything above is verifiable live).
2. **Record the Dokploy-MCP verdict** — evidence says KEEP: every operation
   needed (project/compose/app create, inline compose, env, domains +
   middleware, deploys, logs/containers, traefik file reads) worked over the
   MCP; quirks documented in `runbooks/dogfood.md`.
3. **Box graduates** (Stage 1 complete per charter Bucket-4 line).
4. Open Bucket-5 fork inputs: resize-in-place vs graduate-by-migrating
   (RAM 71% is the datapoint) · Hermes pilot go/no-go (Checkpoint-1 am. 6).

## Standing

- **Tomorrow AM:** confirm BOTH dead-man legs fresh after tonight's 15:00 UTC
  natural timer fire (healthchecks "Last Ping" + Kuma push beat ~01:00 AEST).
- Traefik 3.7.6 Renovate PR when it opens: edge pin bump = edge-apply protocol.

## Constraints in force

No local Docker (CI + VPS only) · 443 is the reliable channel (22 + 53 blocked
from corp network) · zero guarded tokens in tracked files, extends to public
names (CT logs) · backups before workloads — satisfied incl. dogfood state ·
every spend is an Approval Gate · founder is the sole author.

_All work is committed and pushed — it is safe to clear this session._
