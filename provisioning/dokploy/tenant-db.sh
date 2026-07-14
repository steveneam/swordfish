#!/usr/bin/env bash
# tenant-db.sh - syd4-side DRIVER for tenant database provisioning on syd2.
# Generates (or reuses) the tenant's DB credential locally, hands the password
# to CI via the TENANT_DB_PASSWORD repo secret, dispatches the
# tenant-db-apply workflow (the box side of this pair), and watches it green.
#
#   usage: tenant-db.sh                 # baseline/canary converge only
#          tenant-db.sh <tenant-slug>   # + provision that tenant's DB + role
#
# The credential's source of truth is inventory/secrets/pg-tenant-<slug>.env
# (gitignored, restic-backed nightly): password + a ready DATABASE_URL built
# from PG_HOST in pg-syd2.env. Re-running re-asserts the same password on the
# box (idempotent). Handoff to the tenant's agent = that env file, per the
# tenant-credential.sh pattern. Slugs are runtime args - guarded names never
# enter tracked files. Secrets ride --body/stdin, never argv (PS 5.1 lesson
# generalized; gh reads --body from the variable without a process boundary).

set -euo pipefail
cd "$(dirname "$0")/../.."

SLUG=${1:-}
WORKFLOW=tenant-db-apply.yml
HOST=${HOST:-syd2.swordfish.cfd}

if [ -n "$SLUG" ]; then
    [[ "$SLUG" =~ ^[a-z][a-z0-9_]{1,30}$ ]] \
        || { echo "FAIL: slug '$SLUG' must match ^[a-z][a-z0-9_]{1,30}\$"; exit 1; }
    SECFILE="inventory/secrets/pg-tenant-$SLUG.env"

    PG_HOST=$(grep '^PG_HOST=' inventory/secrets/pg-syd2.env | cut -d= -f2- | tr -d '[:space:]')
    [ -n "$PG_HOST" ] || { echo "FAIL: PG_HOST missing from pg-syd2.env - run tenant-pg.sh first"; exit 1; }

    if [ -f "$SECFILE" ]; then
        PW=$(grep '^PGPASSWORD=' "$SECFILE" | cut -d= -f2- | tr -d '[:space:]')
        [ -n "$PW" ] || { echo "FAIL: $SECFILE exists but has no PGPASSWORD"; exit 1; }
        echo "OK: reusing stored credential for '$SLUG' (re-run re-asserts it on the box)"
    else
        PW=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
        umask 077
        { echo "# tenant DB credential for '$SLUG' (tenant-pg on syd2; internal docker network only)"
          echo "PGHOST=$PG_HOST"
          echo "PGPORT=5432"
          echo "PGDATABASE=$SLUG"
          echo "PGUSER=$SLUG"
          echo "PGPASSWORD=$PW"
          echo "DATABASE_URL=postgresql://$SLUG:$PW@$PG_HOST:5432/$SLUG"; } > "$SECFILE"
        echo "CHANGED: credential generated -> $SECFILE"
    fi

    # the secret is transport, not storage: consumed by the dispatched run;
    # next tenant's dispatch overwrites it
    gh secret set TENANT_DB_PASSWORD --body "$PW"
    echo "OK: TENANT_DB_PASSWORD staged as repo secret"
fi

gh workflow run "$WORKFLOW" -f host="$HOST" ${SLUG:+-f slug="$SLUG"}
echo "OK: dispatched $WORKFLOW (host=$HOST${SLUG:+, slug=$SLUG}) - waiting for the run to register"
sleep 8
RUN_ID=$(gh run list --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')
[ -n "$RUN_ID" ] || { echo "FAIL: could not find the dispatched run"; exit 1; }
gh run watch "$RUN_ID" --exit-status
echo "== converged: $WORKFLOW run $RUN_ID green${SLUG:+ - handoff file: inventory/secrets/pg-tenant-$SLUG.env}"
