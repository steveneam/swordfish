# lib.sh - shared by the collect-*.sh dashboard collectors (sourced, not run).
# Contract (dashboard-cockpit-plan-2026-07-13.md): every collector writes ONE
# JSON file to ~/dashboard/data/<name>.json, always with a generated_at epoch.
# A collector that fails writes {"generated_at":..., "error":"..."} so the
# renderer shows a visible UNAVAILABLE card - never a silently blank panel.

DATA_DIR="$HOME/dashboard/data"
SEC_DIR="$HOME/work/swordfish/inventory/secrets"
mkdir -p "$DATA_DIR"

# atomic write: JSON on stdin, validated before it replaces the previous file,
# so a half-written or garbage payload can never blank a card that had data.
emit() { # $1 = name
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$DATA_DIR/$1.json"
  else
    rm -f "$tmp"
    return 1
  fi
}

# failure contract (two modes, stated honestly): a CRASH lands here and the
# error stub replaces the old payload -> UNAVAILABLE card; a TIMEOUT KILL
# (orchestrator's `timeout 120`) writes nothing -> the previous JSON stays
# and its age display goes amber. Known hole: a `set -u` abort exits without
# taking the `main || fail` branch - keep collectors free of unbound vars.
fail() { # $1 = name, $2 = message (atomic, like emit)
  local tmp
  tmp=$(mktemp)
  jq -n --arg e "$2" --argjson t "$(date +%s)" \
    '{generated_at: $t, error: $e}' > "$tmp" && mv "$tmp" "$DATA_DIR/$1.json"
}

# secret files synced from the Windows laptop carry CRLF line endings; a bare
# $(cat f) keeps the \r and every API rejects the credential (found live
# 2026-07-13: both Beszel hubs 400'd until the \r was stripped).
secret() { tr -d '\r\n' < "$1"; }

# same CRLF story for KEY=value lines in the laptop-synced .env, PLUS some
# values carry a leading space after the '=' (Porkbun keys rejected as
# "Invalid API key" until trimmed, found live 2026-07-13).
envval() { # $1 = var name, $2 = env file (default: repo .env)
  grep "^${1}[[:space:]]*=" "${2:-$HOME/work/swordfish/.env}" | head -1 \
    | cut -d= -f2- | tr -d '\r"' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# ssh multiplexing for every collector ssh call: each NEW ssh session fires
# the pam login alert to the founder's Telegram, and the 15-min timer would
# turn that into ~96 pings/day. One persistent master = one pam session,
# refreshed on every run (ControlPersist outlives the 15-min gap). The
# orchestrator PRIMES the master before forking collectors - three parallel
# cold starts would otherwise race ControlMaster=auto and the losers open
# their own pam sessions (code review 2026-07-13).
SSH_CM=(-o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm-%r@%h-%p" -o ControlPersist=1800)

# the one home for the syd3 call shape (5 call sites once lived in 3 files;
# remote-quoting bugs breed in copies - keep journalctl/systemd args here
# space-free, e.g. --since=-24h, never --since \"24 hours ago\")
ssh_syd3() { ssh -n "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes syd3 "$@"; }
ssh_syd3_stdin() { ssh "${SSH_CM[@]}" -o ConnectTimeout=8 -o BatchMode=yes syd3 "$@"; }

# public TLS surfaces per box - edit ONCE here (cutover 2026-07-13: real names
# moved to syd2, syd1 left the board at the same gate; the *2 temp names retire
# at soak end and are deliberately NOT probed)
# (cross-refs: kuma/bootstrap.py HTTP_MONITORS, beszel/bootstrap.py BASE)
SYD2_HOSTS=(deploy.swordfish.cfd status.swordfish.cfd metrics.swordfish.cfd hello.swordfish.cfd)
