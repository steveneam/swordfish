#!/usr/bin/env bash
# film-import.sh - run thalon's video-project importer against STAGING on syd2.
#
# Why this exists: thalon's own command card says to run
#   npm run videos:import -w @thalon/web ...
# "from the deployed web workdir". That CANNOT WORK. The staging image is a
# pruned Next standalone bundle: apps/web/scripts/import-video-project.ts ships
# in it, but @thalon/contracts, @thalon/engine and @thalon/platform exist
# nowhere in the image (/app/packages holds only db; /app/node_modules holds 32
# traced runtime deps and no @thalon scope). The script is an orphan there and
# dies on its first import. Thalon has since corrected their script header too.
#
# The working procedure has now been derived by hand TWICE - once on 2026-07-19
# and again on 2026-07-29 - which is exactly the signal that it should be
# executable rather than a runbook line (rule 8: a runbook is the grade below a
# script that runs). Landed at thalon's explicit request, their s85 note (5).
#
# What it does: git archive of a NAMED commit -> temp dir on syd2 -> npm ci in a
# container off the DEPLOYED image -> run the importer with thalon-data mounted,
# dokploy-network attached, and the app's own env -> report row counts -> always
# clean up the temp dir.
#
#   usage: film-import.sh <deployed-commit> [--apply] [--name NAME] [--media-root PATH]
#
#   Dry-run is the DEFAULT and writes nothing (their ask 1): the failure mode
#   here is a duplicate video_projects row in a live tenant, which is silent and
#   annoying to unpick. --apply is the only thing that writes.
#
#   <deployed-commit> is REQUIRED and is never resolved to "latest" (their ask
#   2): the importer writes through the schema its checkout expects, so a drift
#   between that checkout and the running app is a real corruption risk. NOTE:
#   the staging image carries NO commit label, so this script CANNOT verify the
#   commit against what is actually running - it prints the running image digest
#   and makes you assert the commit yourself. Get it from the build that pushed
#   the digest shown.

set -euo pipefail
cd "$(dirname "$0")/../.."

THALON_REPO=${THALON_REPO:-/home/deploy/work/thalon}
SYD2=${SYD2:-deploy@syd2.swordfish.cfd}
KEYFILE=${KEYFILE:-inventory/secrets/ci_ed25519}
APP=jh_UI2lErDwykJG6FcFBD
PROJECT_NAME="thalon-concept-film"
MEDIA_ROOT=/data/film-storyboard-s41
APPLY=0

COMMIT=${1:-}; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)      APPLY=1 ;;
    --name)       PROJECT_NAME=$2; shift ;;
    --media-root) MEDIA_ROOT=$2; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$COMMIT" ]; then
  sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

ssh_syd2() { ssh -i "$KEYFILE" -o BatchMode=yes -o ConnectTimeout=20 "$SYD2" "$@"; }

# --- 1. the commit must exist, and must be named rather than inferred ----------
git -C "$THALON_REPO" cat-file -e "${COMMIT}^{commit}" 2>/dev/null \
  || { echo "FAIL: $COMMIT is not a commit in $THALON_REPO"; exit 1; }
SHA=$(git -C "$THALON_REPO" rev-parse "$COMMIT")
echo "== checkout commit : $SHA"

# The image carries no commit label (checked 2026-07-29), so this is an
# assertion the operator makes, not one this script can verify. Print the digest
# the operator should have matched it against.
RUNNING=$(ssh_syd2 "sudo docker inspect -f '{{.Image}}' \
  \$(sudo docker ps --format '{{.ID}} {{.Names}}' | grep -i thalon-web | head -1 | awk '{print \$1}')")
echo "== running image   : $RUNNING"
echo "   (no commit label on the image - verify $SHA built THIS digest yourself)"

# --- 2. duplicate guard - the failure mode their ask 1 is about ---------------
# The DB role is whatever the container was built with ($POSTGRES_USER), not
# "postgres" - hence the inner single quotes, which defer expansion to the
# container. The project name goes in as a psql VARIABLE rather than as string
# interpolation, so a name containing a quote cannot break out of the literal.
# NB the SQL arrives on STDIN, not via -c: psql only interpolates :'var' while
# lexing its input, so the -c form dies with `syntax error at or near ":"`.
existing=$(ssh_syd2 "PNAME='$PROJECT_NAME' bash -s" <<'EOS' 2>/dev/null | tr -d '[:space:]'
pg=$(sudo docker ps --format '{{.Names}}' | grep -i '^tenant-pg' | head -1)
printf "SELECT count(*) FROM video_projects WHERE name = :'pname';\n" \
  | sudo docker exec -i -e PNAME="$PNAME" "$pg" \
      sh -c 'psql -U "$POSTGRES_USER" -d thalon -tA -v pname="$PNAME"' \
  2>/dev/null | tail -1
EOS
)
echo "== existing '$PROJECT_NAME' rows: ${existing:-?}"
if [ "${existing:-0}" != "0" ] && [ "$APPLY" = 1 ]; then
  cat >&2 <<'WARN'
REFUSING: a project with this name already exists in the staging tenant.
Re-running the importer would risk a SECOND project row (or a partial one) in
tenant #0 - silent, and annoying to unpick. If you genuinely mean to re-import,
delete the existing rows deliberately first, then re-run.
WARN
  exit 1
fi

# --- 3. source checkout -> syd2 temp -----------------------------------------
# git archive ships TRACKED files only, so .env.local and every other gitignored
# secret are excluded by construction rather than by an --exclude list I might
# get wrong.
DEST=/home/deploy/.thalon-import-$$
cleanup() { ssh_syd2 "rm -rf '$DEST'" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

echo "== shipping tracked source @ $SHA -> $SYD2:$DEST"
ssh_syd2 "mkdir -p '$DEST'"
git -C "$THALON_REPO" archive --format=tar "$SHA" | ssh_syd2 "tar -x -C '$DEST'"

# --- 4. install + run inside a container off the DEPLOYED image ---------------
MODE_ARGS="--dry-run"; MODE="DRY RUN (writes nothing)"
[ "$APPLY" = 1 ] && { MODE_ARGS=""; MODE="APPLY (writes rows + objects)"; }
echo "== mode: $MODE"

ssh_syd2 "bash -s" <<EOS
set -uo pipefail
D='$DEST'
cid=\$(sudo docker ps --format '{{.ID}} {{.Names}}' | grep -i 'thalon-web' | head -1 | awk '{print \$1}')
IMG=\$(sudo docker inspect -f '{{.Config.Image}}' "\$cid")
NET=\$(sudo docker inspect -f '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}{{end}}' "\$cid")

# env from the live app, deploy-owned 700 - tenant secrets never cross the wire
TMP=\$(mktemp -d /home/deploy/.imptmp.XXXX); chmod 700 "\$TMP"
trap 'rm -rf "\$TMP"' EXIT
sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "\$cid" \
  | grep -vE '^(PATH|HOSTNAME|NODE_VERSION|YARN_VERSION|HOME|TERM)=' > "\$TMP/env"
chmod 600 "\$TMP/env"

echo "-- npm ci (workspace install) --"
sudo docker run --rm --network "\$NET" --user "\$(id -u):\$(id -g)" -e HOME=/work/.npmhome \
  -v "\$D":/work -w /work "\$IMG" \
  sh -c 'mkdir -p /work/.npmhome && npm ci --no-audit --no-fund >/dev/null 2>&1; echo "npm ci exit=\$?"'
[ -d "\$D/node_modules/@thalon" ] && echo "workspace links: \$(ls \$D/node_modules/@thalon | tr '\n' ' ')" \
                                  || { echo "FAIL: no @thalon workspace links after npm ci"; exit 1; }

echo "-- importer --"
# tsx via npx: npm blocks esbuild's postinstall under allow-scripts, so the
# hoisted .bin/tsx is not usable; npx fetches a self-contained one.
# NB sidecar paths resolve against CWD, not --root (thalon runbook note, 07-19),
# so they are passed absolute.
sudo docker run --rm --network "\$NET" --env-file "\$TMP/env" \
  --user "\$(id -u):\$(id -g)" -e HOME=/work/.npmhome \
  -v thalon-data:/data -v "\$D":/work -w /work/apps/web "\$IMG" \
  sh -c 'npx --yes tsx scripts/import-video-project.ts \
      --root $MEDIA_ROOT \
      --name "$PROJECT_NAME" \
      --reasons $MEDIA_ROOT/thalon-import/reasons.json \
      --provenance $MEDIA_ROOT/thalon-import/provenance.json \
      --cuts $MEDIA_ROOT/thalon-import/cuts.json \
      --exclude v1-reference $MODE_ARGS' 2>&1 | grep -vE '^\s*skip ' | tail -20
EOS

# --- 5. report the end state, not the exit code ------------------------------
echo "== row counts now (the verdict is the DB, not the run) =="
ssh_syd2 "bash -s" <<'EOS' 2>&1 | grep -v 'WARNING:\|^DETAIL\|^HINT'
pg=$(sudo docker ps --format '{{.Names}}' | grep -i '^tenant-pg' | head -1)
q() { sudo docker exec "$pg" sh -c "psql -U \"\$POSTGRES_USER\" -d thalon -tA -c \"$1\"" 2>&1; }
q "SELECT 'projects='||count(*) FROM video_projects"
q "SELECT 'takes='||count(*)||' (keeper '||count(*) FILTER (WHERE disposition='keeper')||' / reject '||count(*) FILTER (WHERE disposition='reject')||')' FROM video_takes"
q "SELECT 'rejects_without_reason='||count(*) FROM video_takes WHERE disposition='reject' AND (reason IS NULL OR reason='')"
q "SELECT 'cuts='||count(*) FROM video_cuts"
EOS

echo "== temp workspace removed; the live container was never touched =="
