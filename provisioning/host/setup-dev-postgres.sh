#!/usr/bin/env bash
set -uo pipefail

# setup-dev-postgres.sh - native PostgreSQL 17 for a tenant's DEV database on a
# COCKPIT-CLASS box (syd4). Idempotent; safe to re-run.
#
# WHY THIS EXISTS (thalon, 2026-07-17, founder-approved live): thalon's embedded
# PGlite dev DB (single process, Postgres-17-WASM) was killed uncleanly and its
# WAL tore - `could not locate a valid checkpoint record`. Native pg tools cannot
# even read it (WASM 32-bit layout / USE_FLOAT8_BYVAL mismatch), so recovery meant
# a restic snapshot + a rebuild. An embedded single-process DB has no crash story;
# a real server does.
#
# WHY IT DOES NOT BREAK COCKPIT-CLASS (syd4 = NO Docker, port 22 only):
#   - NATIVE apt package, not a container -> the `cockpit: no docker engine`
#     assertion in assert-cockpit.sh stays green.
#   - listen_addresses = localhost ONLY -> nothing new on the wire, ufw stays
#     22-only, no provider-firewall change, no CT-log surface.
#   - It IS the first workload on a box chartered to run none. That is a posture
#     call and it was the founder's, made live 2026-07-17. Do not extend this
#     precedent to a second workload without asking him again.
#
# BACKUPS BEFORE WORKLOADS (rule 3, non-negotiable): a PGDATA under
# /var/lib/postgresql is NOT in syd4's restic set (source = /home/deploy). A
# file-level copy of a live cluster is not consistent anyway - the same lesson
# the fleet already applies to dokploy-postgres and thalon's PGlite. So this
# installs a pre-backup pg_dump hook that lands a consistent dump INSIDE the
# backed-up tree. The dump is the restore path; PGDATA is not.
#
# Usage:  setup-dev-postgres.sh [--role NAME] [--db NAME]
# Verify: it re-asserts and prints a PASS/FAIL block; exit 0 only if all pass.

ROLE=thalon
DB=thalon
while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --db)   DB="$2";   shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

PGVER=17
SECRET_DIR="$HOME/work/swordfish/inventory/secrets"
PWFILE="$SECRET_DIR/pg-dev-${ROLE}.password"
DUMP_DIR="$HOME/pg-dumps"          # inside /home/deploy => inside syd4's restic source
changed=0

log() { echo "== $*"; }

# --- 0. WHO WILL I KILL? (pre-flight, added after the 2026-07-17 10:17 incident) --
# This script's own apt call restarted code-server via needrestart and killed a
# tenant agent mid-run. The guard config now blocks that path, but the DISCIPLINE
# is the point: ask who is live BEFORE touching the box, every time. A warning
# here is not a veto - a sheltered fleet makes box actions survivable, and an
# EXPOSED agent means wait or shelter it first.
PREFLIGHT="$(dirname "$0")/../checks/who-is-live.sh"
if [ -x "$PREFLIGHT" ]; then
  "$PREFLIGHT" || echo "== ^ WARNING: an agent is EXPOSED. This script passes NEEDRESTART_MODE=l,
==   but prefer to shelter it (or wait) before any box mutation."
fi

# --- 1. install PostgreSQL 17 from PGDG (Ubuntu ships 16; thalon's data is 17) ---
if ! dpkg -l "postgresql-$PGVER" 2>/dev/null | grep -q '^ii'; then
  log "installing postgresql-$PGVER from PGDG"
  # download-then-execute, never curl|bash: the NodeSource pipe failed SILENTLY
  # at syd4's first boot and left the toolchain absent (cloud-init lesson)
  sudo -n install -d -m 0755 /usr/share/postgresql-common/pgdg
  sudo -n curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc || { echo "FAIL: PGDG key download"; exit 1; }
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo -n tee /etc/apt/sources.list.d/pgdg.list >/dev/null
  sudo -n apt-get update -qq || { echo "FAIL: apt update"; exit 1; }
  # NEEDRESTART_MODE=l (list, do not restart) - BELT-AND-BRACES over
  # setup-needrestart-guard.sh. Learned the hard way 2026-07-17 10:17:31: this
  # very install pulled libpq5, needrestart (mode 'a') restarted code-server,
  # and every agent in its cgroup died mid-run. apt does not read runbooks.
  sudo -n NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      "postgresql-$PGVER" "postgresql-client-$PGVER" || { echo "FAIL: apt install"; exit 1; }
  changed=1
else
  log "postgresql-$PGVER already installed"
fi

PGCONF="/etc/postgresql/$PGVER/main/postgresql.conf"
[ -f "$PGCONF" ] || { echo "FAIL: $PGCONF missing after install"; exit 1; }

# --- 2. localhost-only (the whole reason this is allowed on a cockpit box) -------
if ! sudo -n grep -qE "^listen_addresses = 'localhost'" "$PGCONF"; then
  log "pinning listen_addresses = localhost"
  sudo -n sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'\t\t# swordfish: cockpit-class - NEVER the wire/" "$PGCONF"
  changed=1
fi

sudo -n systemctl enable --quiet "postgresql@$PGVER-main" 2>/dev/null || true
sudo -n systemctl start "postgresql@$PGVER-main" || { echo "FAIL: service start"; exit 1; }
[ "$changed" -eq 1 ] && sudo -n systemctl reload "postgresql@$PGVER-main" 2>/dev/null

# --- 3. role + database (find-or-create; password persisted ONCE, 0600) ---------
psu() { sudo -n -u postgres psql -tAc "$1" 2>/dev/null; }

if [ -s "$PWFILE" ]; then
  PGPW=$(tr -d '\r\n' < "$PWFILE")
  log "reusing existing password for role $ROLE"
else
  PGPW=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
  umask 077
  install -d -m 700 "$SECRET_DIR"
  printf '%s\n' "$PGPW" > "$PWFILE"
  chmod 600 "$PWFILE"
  log "minted new password for role $ROLE -> $PWFILE (0600, gitignored)"
  changed=1
fi

if [ "$(psu "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'")" != "1" ]; then
  log "creating role $ROLE"
  sudo -n -u postgres psql -qc "CREATE ROLE \"$ROLE\" LOGIN PASSWORD '$PGPW';" >/dev/null \
    || { echo "FAIL: create role"; exit 1; }
  changed=1
else
  # re-assert the password so the stored secret is always the truth
  sudo -n -u postgres psql -qc "ALTER ROLE \"$ROLE\" WITH PASSWORD '$PGPW';" >/dev/null
fi

if [ "$(psu "SELECT 1 FROM pg_database WHERE datname='$DB'")" != "1" ]; then
  log "creating database $DB owned by $ROLE"
  sudo -n -u postgres createdb -O "$ROLE" "$DB" || { echo "FAIL: createdb"; exit 1; }
  changed=1
fi

# --- 4. BACKUPS BEFORE WORKLOADS: dump-before-snapshot hook ---------------------
# PGDATA is not in the restic set and a file copy of a live cluster is not
# consistent. The dump is the restore path. It lands under /home/deploy, which
# IS syd4's backup source, so no profile source change is needed.
install -d -m 700 "$DUMP_DIR"
HOOK=/etc/resticprofile/pre-backup.d/40-dev-postgres-dump
if ! sudo -n test -f "$HOOK" || ! sudo -n grep -q "$DUMP_DIR" "$HOOK" 2>/dev/null; then
  log "installing pre-backup dump hook -> $HOOK"
  sudo -n install -d -m 700 /etc/resticprofile/pre-backup.d
  sudo -n tee "$HOOK" >/dev/null <<HOOKEOF
#!/usr/bin/env bash
# 40-dev-postgres-dump - consistent dump of the native dev cluster BEFORE the
# restic snapshot. PGDATA (/var/lib/postgresql) is deliberately NOT backed up:
# a file-level copy of a live cluster is not consistent. THIS dump is the
# restore path. Lands in $DUMP_DIR, inside syd4's /home/deploy backup source.
set -uo pipefail
install -d -m 700 "$DUMP_DIR"
for db in \$(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datistemplate=false AND datname<>'postgres'"); do
  out="$DUMP_DIR/\${db}.sql.gz"
  tmp="\$out.tmp"
  if sudo -u postgres pg_dump --clean --if-exists "\$db" | gzip -9 > "\$tmp"; then
    mv "\$tmp" "\$out"; chown deploy:deploy "\$out"; chmod 600 "\$out"
  else
    rm -f "\$tmp"; echo "FAIL: pg_dump \$db"; exit 1
  fi
done
exit 0
HOOKEOF
  sudo -n chmod 700 "$HOOK"
  changed=1
fi

# syd4's profile has no run-before; the hook is inert without it. Assert loudly
# rather than silently shipping an un-run hook (a documentary ratchet rots).
PROFILE=/etc/resticprofile/profiles.yaml
RUNBEFORE_OK=0
sudo -n awk '/^syd4:/{f=1} f&&/run-before/{print;exit}' "$PROFILE" 2>/dev/null | grep -q pre-backup.d && RUNBEFORE_OK=1

# --- 5. VERIFY (exit 0 only if every assertion passes) --------------------------
echo
echo "== verify"
fails=0
ck() { if bash -c "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

ck "service active"                "systemctl is-active --quiet postgresql@$PGVER-main"
ck "listens on localhost ONLY"     "ss -ltn | grep -q '127.0.0.1:5432' && ! ss -ltn | grep ':5432' | grep -qv '127.0.0.1\|\[::1\]'"
ck "NOT on the wire"               "! ss -ltn | grep -qE '0\.0\.0\.0:5432|:::5432'"
ck "cockpit-class: still no docker" "! command -v docker"
ck "ufw still 22-only (no 5432)"   "! sudo -n ufw status | grep -q 5432"
ck "role $ROLE exists"             "[ \"\$(sudo -n -u postgres psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$ROLE'\")\" = 1 ]"
ck "db $DB exists"                 "[ \"\$(sudo -n -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB'\")\" = 1 ]"
ck "role can actually connect"     "PGPASSWORD='$PGPW' psql -h 127.0.0.1 -U '$ROLE' -d '$DB' -tAc 'SELECT 1' | grep -q 1"
ck "password file 0600"            "[ \"\$(stat -c %a '$PWFILE')\" = 600 ]"
ck "dump hook installed+executable" "sudo -n test -x '$HOOK'"
ck "dump hook runs clean"          "sudo -n run-parts --exit-on-error /etc/resticprofile/pre-backup.d"
ck "dump landed in the backup tree" "[ -s '$DUMP_DIR/$DB.sql.gz' ]"
ck "dump is restorable (gzip ok)"  "gzip -t '$DUMP_DIR/$DB.sql.gz'"

if [ "$RUNBEFORE_OK" -eq 1 ]; then
  echo "PASS: syd4 profile runs pre-backup.d (hook will fire nightly)"
else
  echo "FAIL: syd4 profile has NO run-before -> the dump hook is INERT."
  echo "      Add to the syd4 profile in provisioning/backup/profiles.yaml:"
  echo "        run-before: \"run-parts --exit-on-error /etc/resticprofile/pre-backup.d\""
  echo "      then converge via cockpit-backups-apply.yml. Until then this DB has NO backup."
  fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "== converged: postgres $PGVER, localhost-only, $ROLE@$DB, dump hook armed ($changed change-set)"
  exit 0
fi
echo "== $fails assertion(s) FAILED"
exit 1
