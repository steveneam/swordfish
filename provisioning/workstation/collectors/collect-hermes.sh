#!/usr/bin/env bash
set -uo pipefail

# collect-hermes.sh - the Hermes card (plan §7). One ssh to syd3; python3
# (stdlib sqlite3) reads Hermes's own state files as root:
#   - cron/jobs.json, NEVER `hermes cron list`: cron list HIDES paused jobs,
#     so a paused job and a deleted job look identical there (trap, 2026-07-13)
#   - gateway_state.json: gateway + telegram connection state
#   - state.db messages: last founder->Hermes and Hermes->founder message
#   - cron/output/: newest output file + head, because delivery-green does not
#     mean content-true (the 2026-07-13 false-PROBLEM briefing) - the founder
#     eyeballs the snippet against what Telegram showed
# Per-project Hermes threads are an E1 feature; E0 is one channel and the card
# says so rather than faking attribution.

. "$(dirname "$0")/lib.sh"

main() {
  local svc out
  # is-active prints inactive/failed AND exits non-zero: keep the captured
  # truth, "unreachable" only when nothing came back (code review 2026-07-13
  # - a stopped gateway and a dead tunnel need OPPOSITE founder actions)
  svc=$(ssh_syd3 'systemctl is-active hermes-gateway.service' 2>/dev/null) || true
  [ -n "$svc" ] || svc=unreachable

  out=$(ssh_syd3_stdin 'sudo -n python3 -' <<'PY' 2>/dev/null
import json, os, glob, sqlite3, time
H = "/home/hermes/.hermes"
r = {}

try:
    jobs = json.load(open(f"{H}/cron/jobs.json"))["jobs"]
    r["jobs"] = [{k: j.get(k) for k in
                  ("id", "name", "state", "enabled", "schedule_display",
                   "last_run_at", "last_status", "last_error", "next_run_at")}
                 for j in jobs]
except Exception as e:
    r["jobs_error"] = str(e)

try:
    g = json.load(open(f"{H}/gateway_state.json"))
    r["gateway"] = {"state": g.get("gateway_state"),
                    "telegram": g.get("platforms", {}).get("telegram", {}).get("state"),
                    "active_agents": g.get("active_agents"),
                    "updated_at": g.get("updated_at")}
except Exception as e:
    r["gateway_error"] = str(e)

try:
    db = sqlite3.connect(f"file:{H}/state.db?mode=ro", uri=True)
    # join sessions: cron runs inject prompts as role=user in their own
    # sessions - only source='telegram' rows are the real founder channel
    q = ("select m.content, m.timestamp from messages m "
         "join sessions s on m.session_id = s.id "
         "where s.source = 'telegram' and m.role = ? and m.content != '' "
         "order by m.timestamp desc limit 1")
    for role, key in (("user", "last_in"), ("assistant", "last_out")):
        row = db.execute(q, (role,)).fetchone()
        if row:
            r[key] = {"ts": row[1], "snippet": (row[0] or "")[:160]}
except Exception as e:
    r["messages_error"] = str(e)

try:
    # outputs nest as output/<job-id>/<timestamp>.md; symlink guard because
    # this runs as root - a planted link must not surface an arbitrary
    # file's head on the dashboard (security review 2026-07-13)
    outs = [p for p in glob.glob(f"{H}/cron/output/*") + glob.glob(f"{H}/cron/output/*/*")
            if os.path.isfile(p) and not os.path.islink(p)]
    if outs:
        newest = max(outs, key=os.path.getmtime)
        r["last_cron_output"] = {"file": os.path.basename(newest),
                                 "mtime": int(os.path.getmtime(newest)),
                                 "head": open(newest, errors="replace").read(400)}
except Exception as e:
    r["output_error"] = str(e)

print(json.dumps(r))
PY
  ) || out='{}'
  [ -n "$out" ] || out='{}'

  jq -n --argjson t "$(date +%s)" --arg svc "$svc" --argjson d "$out" \
    '{generated_at: $t, service: $svc,
      note: "single-channel E0 bot; per-project threads land at E1"} + $d' \
    | emit hermes
}

main || fail hermes "hermes collector crashed"
