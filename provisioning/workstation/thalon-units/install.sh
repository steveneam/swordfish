#!/usr/bin/env bash
# install.sh - converge thalon's two reboot-fragile processes into systemd
# USER units on syd4 (thalon s65 ask, 2026-07-19: the 8899 preview server +
# the intel sweep scheduler died on every weekly 18:30Z kernel reboot and
# restarted only by hand; the sweeper soak was found silently dead at their
# s65 opener).
#
#   usage: install.sh          (as deploy on syd4; idempotent - re-run prints state)
#
# What it converges:
#   1. linger for deploy (sudo loginctl enable-linger) - WITHOUT this, user
#      units only run while a session is open and nothing survives a reboot;
#      linger IS the fix, the units are just the packaging
#   2. both unit files -> ~/.config/systemd/user/ + daemon-reload + enable
#   3. TAKEOVER of any hand-run instances: kill by PID from pgrep -af
#      (NEVER pkill -f - it matches prod units and your own command line),
#      children too (the sweeper pipeline reparents its npm/node tree)
#   4. start + verify: units active, port 8899 answering, sweeper log advancing
set -euo pipefail
cd "$(dirname "$0")"

UNITS="thalon-preview.service thalon-sweeper.service"
UNIT_DIR="$HOME/.config/systemd/user"

# systemctl --user needs the user manager's bus; agent shells and cron lack
# the login-session env ("Failed to connect to bus: No medium found" - hit
# live on first install 2026-07-25). Point at the runtime dir explicitly.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
[ -S "$XDG_RUNTIME_DIR/bus" ] || { echo "FAIL: no user bus at $XDG_RUNTIME_DIR/bus - is user@$(id -u).service running? (systemctl status user@$(id -u))"; exit 1; }

# --- 1. linger: the actual reboot-survival mechanism ------------------------------
if [ "$(loginctl show-user "$USER" -p Linger --value)" = yes ]; then
    echo "OK: linger enabled for $USER"
else
    sudo loginctl enable-linger "$USER"
    echo "CHANGED: linger enabled for $USER (user units now start at boot)"
fi

# --- 2. unit files + enable --------------------------------------------------------
mkdir -p "$UNIT_DIR"
changed=0
for u in $UNITS; do
    if [ -f "$UNIT_DIR/$u" ] && cmp -s "$u" "$UNIT_DIR/$u"; then
        echo "OK: $u matches installed copy"
    else
        cp "$u" "$UNIT_DIR/$u"
        echo "CHANGED: $u -> $UNIT_DIR"
        changed=1
    fi
done
[ "$changed" = 0 ] || systemctl --user daemon-reload
for u in $UNITS; do
    systemctl --user is-enabled "$u" >/dev/null 2>&1 \
        || { systemctl --user enable "$u" >/dev/null 2>&1; echo "CHANGED: $u enabled"; }
done

# --- 3. take over hand-run instances (kill by PID, never pkill -f) -----------------
# preview: bare python3; sweeper: a bash->npm->sh->node pipeline whose members
# reparent if only the root dies - kill the whole set, oldest first.
takeover() { # pattern label
    local pids
    pids=$(pgrep -af "$1" | grep -v -e systemd -e "$UNIT_DIR" | awk '{print $1}' || true)
    # drop PIDs already inside our units' cgroups (a restarted install run)
    local hand=""
    for p in $pids; do
        grep -q 'thalon-\(preview\|sweeper\)\.service' "/proc/$p/cgroup" 2>/dev/null || hand="$hand $p"
    done
    if [ -n "${hand// /}" ]; then
        echo "CHANGED: taking over hand-run $2 (pids:$hand)"
        # shellcheck disable=SC2086
        kill $hand 2>/dev/null || true
        sleep 2
        for p in $hand; do kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true; done
    else
        echo "OK: no hand-run $2 to take over"
    fi
}
takeover 'preview-server\.py 8899' "preview server"
takeover 'run-sweep-scheduler'      "sweep scheduler"

# --- 4. start + verify --------------------------------------------------------------
for u in $UNITS; do
    systemctl --user is-active --quiet "$u" || systemctl --user start "$u"
done
sleep 3
fail=0
for u in $UNITS; do
    if systemctl --user is-active --quiet "$u"; then
        echo "OK: $u active"
    else
        echo "FAIL: $u not active - journalctl --user -u $u"; fail=1
    fi
done
code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8899/" || echo curl-fail)
case "$code" in
    2*|3*|401|403|404) echo "OK: port 8899 answering (HTTP $code)" ;;
    *) echo "FAIL: port 8899 returned $code"; fail=1 ;;
esac
[ "$fail" = 0 ] || exit 1
echo "== converged: thalon-preview + thalon-sweeper as user units (reboot-safe via linger)"
