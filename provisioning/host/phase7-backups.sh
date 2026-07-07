#!/usr/bin/env bash
# phase7-backups.sh - Bucket 3 (Stage 1c): backups BEFORE workloads (invariant).
#   restic + resticprofile land as sha256-verified pinned release binaries -
#   never a piped installer (Bucket-1.5 supply-chain lesson), and resticprofile
#   is the no_self_update build: upgrades arrive by moving the pin HERE, not by
#   a binary updating itself. Config + hooks sync from provisioning/backup/
#   (shipped to /opt/swordfish/backup by backups-apply.yml) into
#   /etc/resticprofile/; nightly backup / weekly check / weekly prune register
#   as systemd system timers via `resticprofile schedule`.
# Secrets are installed by backups-apply BEFORE this converge (0600 root):
#   password.txt (repo password) - b2.env (bucket-scoped key) - hc-url (dead-man).
# Runbook: runbooks/backup-restore.md. Runs as deploy (NOPASSWD sudo), piped
# over SSH by backups-apply.yml. Idempotent: re-run on a converged box = no-op.

set -euo pipefail

RESTIC_VERSION=0.19.1
RESTIC_SHA256=f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c
RESTICPROFILE_VERSION=0.33.1
RESTICPROFILE_SHA256=1d7027d15e3e2456e585a210f811d0f72ec40f6b3388f00425642ed579165d70  # no_self_update build
BACKUP_DIR=/opt/swordfish/backup
ETC=/etc/resticprofile
PROFILE_NAME=syd1

changed=0
note() { echo "$1"; }

[ -f "$BACKUP_DIR/profiles.yaml" ] || { echo "FAIL: $BACKUP_DIR missing - backups-apply must ship provisioning/backup first"; exit 1; }

# --- 0. secrets must already be on the box (they never ride in the repo) --------
for f in password.txt b2.env; do
    sudo test -s "$ETC/$f" || { echo "FAIL: $ETC/$f missing/empty - backups-apply writes it from repo secrets before converging"; exit 1; }
done

# --- 1. restic at pin (sha256-verified release binary) ---------------------------
if command -v restic >/dev/null && restic version | grep -q "restic $RESTIC_VERSION "; then
    note "OK: restic at pin ($RESTIC_VERSION)"
else
    command -v bunzip2 >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bzip2 >/dev/null
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/restic.bz2" "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2"
    echo "$RESTIC_SHA256  $tmp/restic.bz2" | sha256sum -c - >/dev/null
    bunzip2 "$tmp/restic.bz2"
    sudo install -m 755 "$tmp/restic" /usr/local/bin/restic
    rm -rf "$tmp"
    note "CHANGED: restic $RESTIC_VERSION installed (sha256 verified)"
    changed=1
fi

# --- 2. resticprofile at pin ------------------------------------------------------
if command -v resticprofile >/dev/null && resticprofile version 2>/dev/null | grep -q "version $RESTICPROFILE_VERSION"; then
    note "OK: resticprofile at pin ($RESTICPROFILE_VERSION)"
else
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/rp.tar.gz" "https://github.com/creativeprojects/resticprofile/releases/download/v${RESTICPROFILE_VERSION}/resticprofile_no_self_update_${RESTICPROFILE_VERSION}_linux_amd64.tar.gz"
    echo "$RESTICPROFILE_SHA256  $tmp/rp.tar.gz" | sha256sum -c - >/dev/null
    tar -C "$tmp" -xzf "$tmp/rp.tar.gz" resticprofile
    sudo install -m 755 "$tmp/resticprofile" /usr/local/bin/resticprofile
    rm -rf "$tmp"
    note "CHANGED: resticprofile $RESTICPROFILE_VERSION installed (sha256 verified, no-self-update build)"
    changed=1
fi

# --- 3. config + hooks from the shipped repo copy ---------------------------------
sudo install -d -m 700 "$ETC" "$ETC/pre-backup.d"
sudo install -d -m 700 /var/backups/swordfish

profiles_changed=0
sync_file() { # src dst mode
    if sudo test -f "$2" && sudo cmp -s "$1" "$2"; then
        note "OK: $2 converged"
    else
        sudo install -m "$3" "$1" "$2"
        note "CHANGED: $2 updated from repo"
        changed=1
        # plain if, not `[ ] &&` - set -e kills the converge on a false test
        # as a function's last command (phase3 lesson, 2026-07-07)
        if [ "$2" = "$ETC/profiles.yaml" ]; then profiles_changed=1; fi
    fi
}
sync_file "$BACKUP_DIR/profiles.yaml" "$ETC/profiles.yaml" 644
sync_file "$BACKUP_DIR/hc-ping.sh" "$ETC/hc-ping.sh" 755
for hook in "$BACKUP_DIR"/pre-backup.d/*; do
    sync_file "$hook" "$ETC/pre-backup.d/$(basename "$hook")" 755
done

# --- 4. systemd timers (schedules live inside the units, so re-register on drift) --
need_schedule=$profiles_changed
for cmd in backup check prune; do
    if ! systemctl is-enabled --quiet "resticprofile-$cmd@profile-$PROFILE_NAME.timer" 2>/dev/null; then
        need_schedule=1
    fi
done
if [ "$need_schedule" -eq 1 ]; then
    sudo resticprofile -c "$ETC/profiles.yaml" --name "$PROFILE_NAME" schedule >/dev/null
    note "CHANGED: systemd timers (re)registered (nightly backup / weekly check / weekly prune)"
    changed=1
else
    note "OK: backup/check/prune timers enabled"
fi

# -----------------------------------------------------------------------------------
if [ "$changed" -eq 0 ]; then
    echo "== converged: no changes (idempotent re-run clean)"
else
    echo "== applied: box now carries the Bucket-3 backup layer"
fi
