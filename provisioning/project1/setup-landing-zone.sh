#!/usr/bin/env bash
# setup-landing-zone.sh - converge the Project 1 asset landing zone on syd2
# (migration plan Phase 0.1-0.2, research/project1-asset-migration-plan-2026-07-15.md).
# Idempotent; runs as root via project1-apply.yml (CI-as-hands; syd2's port 22
# answers CI only). "project1" is the guard mask, never the real name - slugs
# and paths stay masked in every tracked file (AGENTS.md hard constraint).
#
# Converges:
#   /srv/project1/            root:root  - the tenant's bind-mount root
#   /srv/project1/assets/     deploy:deploy - ~41 GB reference corpus lands
#                             here at Phase 3 (owner/mode is the PROPOSAL the
#                             plan says their agent confirms at wake-up; the
#                             container uid mapping may adjust it)
#   /srv/project1/manifests/  deploy:deploy - seed manifests + checksums;
#                             restic-covered (assets are the recorded
#                             exclusion - see profiles.yaml syd2)
#   /usr/local/bin/asset-manifest - the verification harness, box-wide
#
# Plus the two drill canaries that turn the recorded exclusion into a
# VERIFIABLE one (backup-restore-drill.yml asserts both, opposite ways):
#   manifests/landing-drill.manifest       MUST appear in a restore
#   assets/.drill/exclusion-canary.bin     MUST NOT appear in a restore

set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

changed=0
mark() { echo "CHANGED: $1"; changed=1; }

# --- 1. the tree -------------------------------------------------------------
[ -d /srv/project1 ] || { install -d -o root -g root -m 755 /srv/project1; mark "created /srv/project1"; }
for d in assets manifests; do
    [ -d "/srv/project1/$d" ] \
        || { install -d -o deploy -g deploy -m 755 "/srv/project1/$d"; mark "created /srv/project1/$d (deploy:deploy - wake-up default, confirm with their agent)"; }
done
# Phase-1 subtrees (contract frozen with Project 1's agent 2026-07-16): the two
# bind-mount targets are pre-created deploy-owned so a container can never
# root-own them at first mount. Both sit under the recorded assets/** restic
# exclusion; diffs scope to the subtree, never the assets root (the .drill
# canary lives there and would always read EXTRA).
#   assets/runtime         <-> container /var/data/eamos/bio_assets
#   assets/phase1-dry-run  <-> container /var/data/eamos/phase1-dry-run
for d in runtime phase1-dry-run; do
    [ -d "/srv/project1/assets/$d" ] \
        || { install -d -o deploy -g deploy -m 755 "/srv/project1/assets/$d"; mark "created /srv/project1/assets/$d (Phase-1 mount target, deploy:deploy)"; }
done
echo "OK: landing tree present ($(stat -c '%U:%G %a' /srv/project1/assets) assets; $(stat -c '%U:%G %a' /srv/project1/manifests) manifests)"

# --- 2. the harness ----------------------------------------------------------
if ! cmp -s "$HERE/asset-manifest.sh" /usr/local/bin/asset-manifest 2>/dev/null; then
    install -o root -g root -m 755 "$HERE/asset-manifest.sh" /usr/local/bin/asset-manifest
    mark "installed /usr/local/bin/asset-manifest"
fi
/usr/local/bin/asset-manifest self-test
echo "OK: harness installed + self-test green"

# --- 3. the drill canaries ---------------------------------------------------
# fixed content on purpose: the drill compares restored bytes, and an
# idempotent converge must not churn the snapshot between runs
canary=/srv/project1/assets/.drill/exclusion-canary.bin
if [ ! -f "$canary" ]; then
    install -d -o deploy -g deploy -m 755 /srv/project1/assets/.drill
    printf 'swordfish landing-zone exclusion canary - this file must NEVER appear in a restic restore\n' > "$canary"
    chown deploy:deploy "$canary"
    mark "seeded exclusion canary ($canary)"
fi
manifest=/srv/project1/manifests/landing-drill.manifest
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
/usr/local/bin/asset-manifest manifest /srv/project1/assets/.drill > "$tmp"
if ! cmp -s "$tmp" "$manifest" 2>/dev/null; then
    install -o deploy -g deploy -m 644 "$tmp" "$manifest"
    mark "wrote $manifest"
fi
# the harness proves its own seed: the covered manifest must describe the
# excluded canary exactly (this is the same call their agent makes at Phase 1)
/usr/local/bin/asset-manifest diff "$manifest" /srv/project1/assets/.drill
echo "OK: drill canaries in place (manifest covered, canary excluded)"

# --- 4. Phase-1 preflight (fail-closed; their agent's frozen contract) --------
# numeric 1000:1000 is the deployment identity their hardened image runs as -
# assert it BEFORE any container writes here, and halt on any mismatch.
pf_fail=0
for p in /srv/project1/assets /srv/project1/assets/runtime /srv/project1/assets/phase1-dry-run; do
    own=$(stat -c '%u:%g' "$p")
    [ "$own" = "1000:1000" ] || { echo "PREFLIGHT-FAIL: $p is $own, expected 1000:1000"; pf_fail=1; }
done
# the drill canary must be byte-identical (its manifest above already proves
# content; this asserts the subtree was never disturbed by mount work)
[ -f /srv/project1/assets/.drill/exclusion-canary.bin ] \
    || { echo "PREFLIGHT-FAIL: drill canary missing"; pf_fail=1; }
# free space: the ClinGen dry-run payload is 527,925,248 bytes; require 2 GB
avail=$(df -B1 --output=avail /srv/project1/assets | tail -1)
[ "$avail" -ge 2147483648 ] || { echo "PREFLIGHT-FAIL: only $avail bytes free under /srv/project1/assets"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "== PREFLIGHT FAILED - no writes may proceed"; exit 1; }
echo "OK: preflight green (1000:1000 on assets + both mount targets; canary intact; $(( avail / 1024 / 1024 / 1024 )) GiB free)"

[ "$changed" = 1 ] || echo "OK: nothing to change"
echo "== converged: project1 landing zone (assets excluded from restic BY profiles.yaml - dispatch backups-apply after any profile edit)"
