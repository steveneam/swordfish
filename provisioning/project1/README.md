# Project 1 (= Eamos) landing zone + tenant pack (Phase 0 of the migration plan)

> **Unmasked by founder call 2026-07-15:** Project 1 = **Eamos** (repo
> `~/work/eamos` on syd4); its guard token is removed. The `project1` slug
> stays in every provisioned artifact (paths, workflow, Dokploy project,
> credential) — it is burned into live box state and a rename is churn
> without safety value. Plan + sequencing:
> `research/project1-asset-migration-plan-2026-07-15.md`. Economics + safety:
> `research/capacity-and-data-plan-2026-07-13.md`.

## What lives here

| file | role |
|---|---|
| `setup-landing-zone.sh` | idempotent converge of the syd2 landing tree + harness + drill canaries; ships via `project1-apply.yml` (CI-as-hands — syd2's port 22 answers CI only) |
| `asset-manifest.sh` | the deterministic verification harness, installed box-wide as `/usr/local/bin/asset-manifest` |

## The landing zone (on syd2)

```
/srv/project1/            root:root      bind-mount root for the tenant container
/srv/project1/assets/     deploy:deploy  ~41 GB reference corpus lands here at
                                         Phase 3 (owner/mode = wake-up DEFAULT,
                                         confirm container uid with their agent)
/srv/project1/manifests/  deploy:deploy  seed manifests + checksums (restic-covered)
```

**Backup posture (invariant: backups before workloads — satisfied BEFORE any
data lands):** `manifests/` is in the syd2 restic set; `assets/**` is a
**recorded exclusion** — the corpus is reproducible public reference data and
its restore path IS the re-seed from the managed source bucket. The exception
is *verified, not just recorded*: `setup-landing-zone.sh` seeds a covered
manifest + an excluded canary, and `backup-restore-drill.yml` asserts the
manifest restores while zero files under `assets/` do.

## The harness (what their agent calls)

```sh
asset-manifest manifest /srv/project1/assets            > manifests/seed-YYYY-MM-DD.manifest
asset-manifest diff     manifests/source.manifest  /srv/project1/assets   # exit 0 iff identical
asset-manifest self-test                                                   # standing proof
```

Line format `sha256  size  relpath`, bytewise-sorted, fully deterministic —
two identical trees manifest to identical bytes, so manifests are themselves
diffable/checksummable. Diff classes: `MISSING` / `EXTRA` / `MISMATCH`; any
line = exit 1. This is the Phase 1 **nothing-lives-ONLY-on-Render proof** tool
(source-bucket manifest vs live Render-disk manifest) and the Phase 3
**7/7-green re-seed check** (source manifest vs box tree).

## The tenant pack (Dokploy)

Same pattern as Thalon, born deploy-only (`STRICT_SCOPE=1` standard since
2026-07-15): Dokploy project `project1` + member `dokploy-project1-ci@` whose
key can deploy + read its own project and nothing else. Minted by
`../dokploy/tenant-credential.sh project1 project1` from syd4; credential file
= `inventory/secrets/dokploy-tenant-project1.env` (gitignored, handed off at
wake-up via their own channel, never through git). **No tenant database** —
Project 1's data plane is Supabase and stays managed (keep-managed invariant).

## What is deliberately NOT here

- No corpus seeding — bulk data waits for Phase 2 (⛔ resize gate) + Phase 3
  (their agent drives the re-seed; swordfish never reaches into their app).
- No app/service definition — their agent brings the container spec at
  wake-up; swordfish pre-creates the Dokploy shell then, not before.
