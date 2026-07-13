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

fail() { # $1 = name, $2 = message
  jq -n --arg e "$2" --argjson t "$(date +%s)" \
    '{generated_at: $t, error: $e}' > "$DATA_DIR/$1.json"
}

# secret files synced from the Windows laptop carry CRLF line endings; a bare
# $(cat f) keeps the \r and every API rejects the credential (found live
# 2026-07-13: both Beszel hubs 400'd until the \r was stripped).
secret() { tr -d '\r\n' < "$1"; }

# ssh multiplexing for every collector ssh call: each NEW ssh session fires
# the pam login alert to the founder's Telegram, and the 15-min timer would
# turn that into ~96 pings/day. One persistent master = one pam session,
# refreshed on every run (ControlPersist outlives the 15-min gap).
SSH_CM=(-o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm-%r@%h-%p" -o ControlPersist=1800)
