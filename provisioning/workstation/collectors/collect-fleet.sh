#!/usr/bin/env bash
set -uo pipefail

# collect-fleet.sh - one row per box (plan §3).
#   syd4: local reads.
#   syd3: one ssh call (cockpit peer; break-glass rides 443, see ~/.ssh/config).
#   syd2: Beszel hub + Uptime Kuma read APIs ONLY - syd2's inbound 22
#     answers CI runners alone and the cockpit never weakens that. A metric the
#     APIs can't provide stays null - a blank is honest, a guess is not.
# syd1 left the board at the cutover gate (2026-07-13); it stays live off-board
# through the 72 h soak, then its destroy decision presents separately.

. "$(dirname "$0")/lib.sh"

ts_to_epoch() { # systemd timestamp -> epoch, or null
  local e
  e=$(date -d "$1" +%s 2>/dev/null) && echo "$e" || echo null
}

local_box() { # $1 = box name; local /proc + systemctl reads
  local name=$1 uptime_s load1 mem_pct disk_pct disk_free rr result lastrun svc_json
  uptime_s=$(cut -d. -f1 /proc/uptime)
  load1=$(awk '{print $1}' /proc/loadavg)
  mem_pct=$(free | awk '/^Mem:/{printf "%.1f", $3/$2*100}')
  read -r disk_pct disk_free < <(df -B1 --output=pcent,avail / | tail -1 | tr -d '%')
  rr=false; [ -f /var/run/reboot-required ] && rr=true
  result=$(systemctl show "resticprofile-backup@profile-${name}.service" -p Result --value 2>/dev/null)
  lastrun=$(ts_to_epoch "$(systemctl show "resticprofile-backup@profile-${name}.service" -p ExecMainExitTimestamp --value 2>/dev/null)")
  svc_json='[]'
  local s state
  for s in "${@:2}"; do
    state=$(systemctl is-active "$s" 2>/dev/null || true)
    svc_json=$(jq --arg n "$s" --arg st "${state:-unknown}" '. + [{name: $n, state: $st}]' <<<"$svc_json")
  done
  jq -n --arg name "$name" --argjson up true --argjson u "$uptime_s" \
        --argjson load "$load1" --argjson mem "$mem_pct" --argjson disk "$disk_pct" \
        --argjson free "$disk_free" --argjson rr "$rr" \
        --arg res "${result:-unknown}" --argjson lr "$lastrun" --argjson svc "$svc_json" \
    '{name: $name, source: "local", up: $up, uptime_s: $u, load1: $load,
      mem_pct: $mem, disk_pct: $disk, disk_free_bytes: $free,
      reboot_required: $rr, backup: {kind: "restic-unit", result: $res, last_run: $lr},
      services: $svc}'
}

syd3_box() {
  local out
  out=$(ssh_syd3 '
    echo "uptime_s=$(cut -d. -f1 /proc/uptime)"
    echo "load1=$(awk "{print \$1}" /proc/loadavg)"
    echo "mem_pct=$(free | awk "/^Mem:/{printf \"%.1f\", \$3/\$2*100}")"
    echo "disk=$(df -B1 --output=pcent,avail / | tail -1 | tr -d "%" | tr -s " " ",")"
    [ -f /var/run/reboot-required ] && echo "rr=true" || echo "rr=false"
    echo "restic_result=$(systemctl show resticprofile-backup@profile-syd3.service -p Result --value 2>/dev/null)"
    echo "restic_last=$(systemctl show resticprofile-backup@profile-syd3.service -p ExecMainExitTimestamp --value 2>/dev/null)"
    for s in ssh fail2ban hermes-gateway; do
      echo "svc_${s}=$(systemctl is-active $s 2>/dev/null)"
    done' 2>/dev/null) || { jq -n '{name: "syd3", source: "ssh", up: false}'; return; }
  # numeric fields from the remote box are UNTRUSTED (a compromised syd3
  # could emit a JSON string through --argjson and reach the page): anything
  # that isn't a plain number becomes null (security review 2026-07-13)
  num() { grep "^${1}=" <<<"$out" | cut -d= -f2 | grep -xE '[0-9]+(\.[0-9]+)?' || echo null; }
  local uptime_s load1 mem_pct disk rr rres rlast
  uptime_s=$(num uptime_s)
  load1=$(num load1)
  mem_pct=$(num mem_pct)
  disk=$(grep '^disk=' <<<"$out" | cut -d= -f2 | sed 's/^,//' \
         | grep -xE '[0-9]+,[0-9]+' || echo 'null,null')
  rr=$(grep '^rr=' <<<"$out" | cut -d= -f2)
  rres=$(grep '^restic_result=' <<<"$out" | cut -d= -f2)
  rlast=$(ts_to_epoch "$(grep '^restic_last=' <<<"$out" | cut -d= -f2-)")
  local svc_json='[]' s
  for s in ssh fail2ban hermes-gateway; do
    svc_json=$(jq --arg n "$s" --arg st "$(grep "^svc_${s}=" <<<"$out" | cut -d= -f2)" \
      '. + [{name: $n, state: (if $st == "" then "unknown" else $st end)}]' <<<"$svc_json")
  done
  jq -n --argjson u "${uptime_s:-null}" --argjson load "${load1:-null}" \
        --argjson mem "${mem_pct:-null}" \
        --argjson disk "${disk%%,*}" --argjson free "${disk##*,}" \
        --argjson rr "${rr:-false}" --arg res "${rres:-unknown}" --argjson lr "$rlast" \
        --argjson svc "$svc_json" \
    '{name: "syd3", source: "ssh", up: true, uptime_s: $u, load1: $load,
      mem_pct: $mem, disk_pct: $disk, disk_free_bytes: $free,
      reboot_required: $rr, backup: {kind: "restic-unit", result: $res, last_run: $lr},
      services: $svc}'
}

probe() { # $1 = url -> "up"/"down" (any HTTP answer < 500 = the edge is serving)
  local code
  code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$1" 2>/dev/null)
  if [ -n "$code" ] && [ "$code" -ge 100 ] && [ "$code" -lt 500 ]; then echo up; else echo down; fi
}

api_box() { # $1=name $2=beszel-base $3=kuma-base $4=deadman-monitor $5...=probe hosts
  local name=$1 bbase=$2 kbase=$3 monitor=$4; shift 4
  local bpw kpw tok sys deadman=null svc_json='[]' host
  bpw=$(secret "$SEC_DIR/beszel-admin.password")
  kpw=$(secret "$SEC_DIR/kuma-admin.password")

  # secrets travel via stdin/@-files, never argv - /proc/<pid>/cmdline is
  # world-readable while curl runs (security review 2026-07-13)
  tok=$(printf 'identity=%s&password=%s' "ops@swordfish.cfd" "$bpw" \
        | curl -s -m 10 "$bbase/api/collections/users/auth-with-password" \
               --data @- | jq -r '.token // empty')
  sys=null
  if [ -n "$tok" ]; then
    sys=$(curl -s -m 10 "$bbase/api/collections/systems/records" \
               -H @<(printf 'Authorization: %s\n' "$tok") \
          | jq --arg n "$name" '[.items[] | select(.name == $n)][0] // null')
  fi

  # dead-man: the box's own Kuma push monitor - up means the backup pinged
  # inside its 30 h window (24 h period + 6 h grace), which IS snapshot-age-OK
  local mval
  mval=$(curl -s -m 10 -K <(printf 'user = "swordfish:%s"\n' "$kpw") "$kbase/metrics" 2>/dev/null \
         | awk -v m="monitor_name=\"$monitor\"" '/^monitor_status/ && index($0, m) {print $NF}')
  [ -n "$mval" ] && deadman=$mval

  for host in "$@"; do
    svc_json=$(jq --arg n "$host" --arg st "$(probe "https://$host")" \
      '. + [{name: $n, state: $st}]' <<<"$svc_json")
  done

  jq -n --arg name "$name" --argjson sys "$sys" --argjson dm "$deadman" \
        --arg monitor "$monitor" --argjson svc "$svc_json" \
    '{name: $name, source: "beszel+kuma",
      up: (if $sys == null then null else ($sys.status == "up") end),
      uptime_s: ($sys.info.u // null), cpu_pct: ($sys.info.cpu // null),
      mem_pct: ($sys.info.mp // null), disk_pct: ($sys.info.dp // null),
      backup: {kind: "kuma-deadman", monitor: $monitor,
               ok: (if $dm == null then null else ($dm == 1) end)},
      services: $svc}'
}

main() {
  local b4 b3 b2
  b4=$(local_box syd4 ssh fail2ban code-server swordfish-dashboard-web)
  b3=$(syd3_box)
  b2=$(api_box syd2 https://metrics.swordfish.cfd https://status.swordfish.cfd \
       swordfish-syd2-backup "${SYD2_HOSTS[@]}")
  jq -n --argjson t "$(date +%s)" \
        --argjson b4 "$b4" --argjson b3 "$b3" --argjson b2 "$b2" \
    '{generated_at: $t, boxes: [$b4, $b3, $b2]}' \
    | emit fleet
}

main || fail fleet "fleet collector crashed"
