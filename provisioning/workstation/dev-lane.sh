#!/usr/bin/env bash
# dev-lane.sh - give every project its own dev-server port, with no central registry.
#
# THE TRAP (founder report 2026-07-17, seen with two projects the night before):
# every Next.js/Vite app defaults to :3000. Two projects browser-verifying at
# once therefore fight over one port. The failure is NOT merely "the second one
# can't start" - Next 15+/16 SILENTLY auto-increments to the next free port, so
# the second app comes up on :3001 while its agent happily browser-verifies
# http://localhost:3000 and validates THE OTHER PROJECT'S APP. That is a
# correctness bug wearing an ergonomics costume, and it gets worse with every
# project added to the box.
#
# THE FIX, made project-agnostic on purpose: a project's port is DERIVED from
# its directory name, not assigned from a list. A new project gets a stable
# private lane the moment it exists - nobody edits a registry, nobody allocates
# anything, and no two projects can drift onto the same number without `doctor`
# saying so.
#
#   port = 3100 + (crc32(project-dir-name) % 700)   ->  3100..3799
#
# Why derived beats a table: a table is a documentary ratchet (AGENTS.md rule 8)
# - it rots the first time someone adds a project and forgets to edit it. A pure
# function of the directory name cannot rot, has no merge conflicts, and gives
# the same answer on every box and in every agent's head.
#
# :3000 is deliberately left OUTSIDE the range and unallocated. Nothing should
# ever be there; if something is, it is a project that has not adopted a lane.
#
# USAGE
#   dev-lane.sh port [dir]     # print this project's port (default: $PWD)
#   dev-lane.sh doctor         # every project's lane + live listeners + clashes
#   dev-lane.sh env [dir]      # print `PORT=<n>` for eval/export
#
# ADOPTION (one line, in each project's own repo - swordfish never edits it):
#   "dev": "next dev -p 3xxx"          <- the number `dev-lane.sh port` prints
# Hardcoding the derived number is correct and preferred: it is explicit, it
# survives any shell, and it does not make the repo depend on this script.
# Ambient PORT= env was considered and REJECTED - it covers only the sessions
# that happen to export it, and partial coverage on a wrong-app-verification bug
# is worse than none, because it fails unpredictably.

set -euo pipefail

RANGE_BASE=3100
RANGE_SPAN=700
WORK_ROOT="${WORK_ROOT:-$HOME/work}"

# Stable across machines and shells: cksum is POSIX CRC32 of the name only.
# (printf, not echo/here-string: no trailing newline in the hashed bytes.)
lane_port() {
    local name="$1" crc
    crc="$(printf '%s' "$name" | cksum | awk '{print $1}')"
    echo $(( RANGE_BASE + (crc % RANGE_SPAN) ))
}

project_name_from_dir() {
    local d="${1:-$PWD}"
    # Walk up to the repo root so `dev-lane port` works from any subdirectory
    # (apps/web, app/web, packages/*) and still names the PROJECT, not the leaf.
    local root
    root="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
    basename "${root:-$d}"
}

cmd_port() {
    lane_port "$(project_name_from_dir "${1:-$PWD}")"
}

cmd_env() {
    echo "PORT=$(cmd_port "${1:-$PWD}")"
}

cmd_doctor() {
    local -a names=() ports=()
    local d name port
    printf '%-18s %-7s %-9s %s\n' PROJECT PORT LISTENING NOTE
    for d in "$WORK_ROOT"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        port="$(lane_port "$name")"
        names+=("$name"); ports+=("$port")

        local live='-' note=''
        if ss -ltn 2>/dev/null | grep -qE "[:.]${port}\b"; then live='yes'; fi

        # Only projects that actually serve something can collide. Look for a
        # `dev` script anywhere in the workspace (root or per-app package.json,
        # excluding node_modules) before judging adoption - otherwise a repo
        # with no web app at all (this one, for instance) gets nagged forever
        # and the signal drowns in noise.
        local -a pkgs=()
        mapfile -t pkgs < <(find "$d" -maxdepth 3 -name package.json \
            -not -path '*/node_modules/*' 2>/dev/null || true)
        local has_dev=0 adopted=0 f
        for f in "${pkgs[@]:-}"; do
            [ -n "$f" ] || continue
            grep -qsE '"dev"[[:space:]]*:' "$f" || continue
            has_dev=1
            grep -qsE "\"dev\"[[:space:]]*:[^\"]*\"[^\"]*(-p +${port}|--port[= ]+${port})" "$f" && adopted=1
        done
        if grep -qsE "^PORT=${port}\b" "$d.env" "$d.env.local" 2>/dev/null; then adopted=1; fi

        if [ "$has_dev" -eq 0 ]; then
            note='no dev server - nothing to lane'
        elif [ "$adopted" -eq 1 ]; then
            note='adopted'
        else
            note="NOT adopted - bare dev script, will take :3000"
        fi
        printf '%-18s %-7s %-9s %s\n' "$name" "$port" "$live" "$note"
    done

    # Derived ports are collision-RESISTANT, not collision-proof: ~700 slots, so
    # a handful of projects is very unlikely to clash, but "unlikely" is not
    # "never" and a silent clash would recreate the exact bug this replaces.
    local i j clash=0
    for ((i = 0; i < ${#ports[@]}; i++)); do
        for ((j = i + 1; j < ${#ports[@]}; j++)); do
            if [ "${ports[i]}" = "${ports[j]}" ]; then
                echo "CLASH: ${names[i]} and ${names[j]} both derive ${ports[i]}"
                echo "       -> pin one of them to any free port in ${RANGE_BASE}-$((RANGE_BASE + RANGE_SPAN - 1)) in its own repo."
                clash=1
            fi
        done
    done

    # :3000 must stay empty - anything there has not adopted a lane.
    if ss -ltn 2>/dev/null | grep -qE '[:.]3000\b'; then
        echo 'WARN: something is listening on :3000 - that is the unallocated'
        echo '      collision slot. A project has not adopted its lane.'
    fi
    [ "$clash" -eq 0 ] || return 1
    return 0
}

case "${1:-doctor}" in
    port)   shift; cmd_port "${1:-$PWD}" ;;
    env)    shift; cmd_env  "${1:-$PWD}" ;;
    doctor) cmd_doctor ;;
    *) echo "usage: dev-lane.sh {port|env|doctor} [dir]" >&2; exit 2 ;;
esac
