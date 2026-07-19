#!/usr/bin/env python3
"""history-append.py - one time-series sample per FULL collector run.

Called by generate-dashboard.sh after the collectors, full runs only (the
event-driven `projects` fast path must not pollute the 15-min cadence, and a
single writer here avoids parallel-collector append races). Reads the freshly
written ~/dashboard/data/*.json and appends one compact line per domain to
~/dashboard/data/history/<name>.jsonl for the dashboard's charts.

Rules (same honesty contract as the collectors):
  - a domain whose JSON is missing or carries "error" is SKIPPED - history
    never records invented state;
  - a sample lands at most every MIN_GAP seconds (double-run guard);
  - files trim to MAX_LINES (~6 weeks at 15-min cadence) via tmp+os.replace -
    safe against a concurrent reader because replace is atomic, and safe
    against a concurrent writer because generate-dashboard.sh is the only one.
    (Collectors write their JSON via mv - lib.sh emit() - so reads here never
    see a half-written file. Keep that contract.)
"""

import json
import os
import time
from pathlib import Path

DATA = Path.home() / "dashboard" / "data"
HIST = DATA / "history"
NOW = int(time.time())
MIN_GAP = 300
MAX_LINES = 4032

# blocked outranks working outranks idle: for a session with several panes the
# strip chart shows the most founder-urgent state (mirrors render sort order)
STATE_RANK = {"blocked": 0, "working": 1, "idle": 2, "opaque": 3, "exited": 4}


def load(name):
    try:
        d = json.loads((DATA / f"{name}.json").read_text())
        return None if d.get("error") else d
    except Exception:
        return None


def backup_ok(b):
    if not b:
        return None
    if b.get("kind") == "restic-unit":
        last = b.get("last_run")
        return (b.get("result") == "success"
                and last is not None and NOW - last < 36 * 3600)
    return b.get("ok")


def sample_fleet(d):
    return {"boxes": {b["name"]: {
        "up": b.get("up"), "cpu_pct": b.get("cpu_pct"), "load1": b.get("load1"),
        "mem_pct": b.get("mem_pct"), "disk_pct": b.get("disk_pct"),
        "backup_ok": backup_ok(b.get("backup")),
    } for b in d.get("boxes") or [] if b.get("name")}}


def sample_money(d):
    api = d.get("api") or {}
    b2, bl, vu = api.get("b2") or {}, api.get("binarylane") or {}, api.get("vultr") or {}
    return {"b2_bytes": b2.get("total_bytes"), "b2_pct": b2.get("pct_of_cap"),
            "bl_unbilled": bl.get("unbilled_total"), "vultr_balance": vu.get("balance")}


def sample_agents(d):
    states = {}
    for a in d.get("agents") or []:
        n, s = a.get("name"), a.get("state")
        if not n or s not in STATE_RANK:
            continue
        if n not in states or STATE_RANK[s] < STATE_RANK[states[n]]:
            states[n] = s
    return {"states": states}


def sample_security(d):
    fails, bans = {}, {}
    for a in d.get("auth") or []:
        box = a.get("box")
        if box and not a.get("unreachable"):
            fails[box] = a.get("fails_24h")
            bans[box] = a.get("bans_24h")
    return {"fails_24h": fails, "bans_24h": bans}


def append(name, sample):
    path = HIST / f"{name}.jsonl"
    lines = path.read_text().splitlines() if path.exists() else []
    if lines:
        try:
            if NOW - json.loads(lines[-1]).get("ts", 0) < MIN_GAP:
                return
        except Exception:
            pass  # corrupt tail line - overwrite territory, keep appending
    lines.append(json.dumps({"ts": NOW, **sample}, separators=(",", ":")))
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(lines[-MAX_LINES:]) + "\n")
    os.replace(tmp, path)


def main():
    HIST.mkdir(parents=True, exist_ok=True)
    for name, fn in (("fleet", sample_fleet), ("money", sample_money),
                     ("agents", sample_agents), ("security", sample_security)):
        d = load(name)
        if d is not None:
            append(name, fn(d))


if __name__ == "__main__":
    main()
