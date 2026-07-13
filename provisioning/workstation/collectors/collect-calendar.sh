#!/usr/bin/env bash
set -uo pipefail

# collect-calendar.sh - next founder events (plan §6). Fetches the Google
# Calendar SECRET .ics address (one founder paste, stored 2026-07-13 in
# inventory/secrets/google-calendar-founder.ics.url, gitignored - the URL is
# the credential and never enters JSON/HTML). No OAuth, no Google API project.
# Parser is python3 stdlib only; recurring events get a bounded, simple
# RRULE expansion (DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL/BYDAY/COUNT/UNTIL,
# EXDATE honored). Times render in Australia/Sydney.

. "$(dirname "$0")/lib.sh"

URL_FILE="$SEC_DIR/google-calendar-founder.ics.url"

main() {
  [ -f "$URL_FILE" ] || { fail calendar "no calendar url file (one founder paste sets it up)"; return; }
  local url ics
  url=$(secret "$URL_FILE")
  ics=$(mktemp)
  if ! curl -fsS -m 20 -o "$ics" "$url"; then
    rm -f "$ics"; fail calendar "ics fetch failed"; return
  fi
  python3 - "$ics" <<'PY' | emit calendar
import sys, json, time, datetime as dt
from zoneinfo import ZoneInfo

SYD = ZoneInfo("Australia/Sydney")
UTC = ZoneInfo("UTC")
now = dt.datetime.now(SYD)
horizon = now + dt.timedelta(days=60)

# unfold RFC5545 continuation lines
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
lines = []
for l in raw:
    if l[:1] in (" ", "\t") and lines:
        lines[-1] += l[1:]
    else:
        lines.append(l)

def parse_dt(prop, val):
    params = dict(p.split("=", 1) for p in prop.split(";")[1:] if "=" in p)
    if params.get("VALUE") == "DATE" or (len(val) == 8 and val.isdigit()):
        d = dt.datetime.strptime(val, "%Y%m%d")
        return d.replace(tzinfo=SYD), True
    tz = ZoneInfo(params["TZID"]) if "TZID" in params else (UTC if val.endswith("Z") else SYD)
    d = dt.datetime.strptime(val.rstrip("Z"), "%Y%m%dT%H%M%S")
    return d.replace(tzinfo=tz), False

WD = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

def expand(start, rrule, exdates, all_day):
    """bounded simple expansion; yields occurrence starts inside the window"""
    if not rrule:
        if now - dt.timedelta(days=1) <= start <= horizon:
            yield start
        return
    r = dict(p.split("=", 1) for p in rrule.split(";") if "=" in p)
    freq, interval = r.get("FREQ"), int(r.get("INTERVAL", 1))
    count = int(r["COUNT"]) if "COUNT" in r else None
    until = None
    if "UNTIL" in r:
        u = r["UNTIL"]
        until = (dt.datetime.strptime(u.rstrip("Z"), "%Y%m%dT%H%M%S").replace(tzinfo=UTC)
                 if "T" in u else dt.datetime.strptime(u, "%Y%m%d").replace(tzinfo=SYD))
    bydays = [WD[d[-2:]] for d in r.get("BYDAY", "").split(",") if d[-2:] in WD] if freq == "WEEKLY" else []
    cur, emitted = start, 0
    for _ in range(1000):
        if until and cur > until:
            return
        if count is not None and emitted >= count:
            return
        occs = [cur]
        if bydays:  # expand the week of `cur` over BYDAY
            monday = cur - dt.timedelta(days=cur.weekday())
            occs = [monday + dt.timedelta(days=d) for d in sorted(bydays)]
        for o in occs:
            if o < start or (until and o > until):
                continue
            emitted += 1
            if count is not None and emitted > count:
                return
            if o > horizon:
                return
            if o >= now - dt.timedelta(days=1) and o.date() not in exdates:
                yield o
        if freq == "DAILY":
            cur += dt.timedelta(days=interval)
        elif freq == "WEEKLY":
            cur += dt.timedelta(weeks=interval)
        elif freq == "MONTHLY":
            m = cur.month - 1 + interval
            try:
                cur = cur.replace(year=cur.year + m // 12, month=m % 12 + 1)
            except ValueError:
                return
        elif freq == "YEARLY":
            try:
                cur = cur.replace(year=cur.year + interval)
            except ValueError:
                return
        else:
            return

events, cur, vevents = [], None, 0
for l in lines:
    if l.startswith("BEGIN:VEVENT"):
        cur = {"exdates": set()}
        vevents += 1
    elif l.startswith("END:VEVENT") and cur is not None:
        if "start" in cur:
            for occ in expand(cur["start"], cur.get("rrule"), cur["exdates"], cur.get("all_day")):
                events.append({"start": occ.astimezone(SYD).isoformat(),
                               "summary": cur.get("summary", "(no title)"),
                               "all_day": cur.get("all_day", False)})
        cur = None
    elif cur is not None and ":" in l:
        prop, val = l.split(":", 1)
        key = prop.split(";")[0]
        try:
            if key == "DTSTART":
                cur["start"], cur["all_day"] = parse_dt(prop, val)
            elif key == "SUMMARY":
                cur["summary"] = val.replace("\\,", ",").replace("\\;", ";").strip()
            elif key == "RRULE":
                cur["rrule"] = val
            elif key == "EXDATE":
                for v in val.split(","):
                    cur["exdates"].add(parse_dt(prop, v)[0].date())
        except Exception:
            pass  # one bad property never kills the feed

events.sort(key=lambda e: e["start"])
upcoming = [e for e in events if dt.datetime.fromisoformat(e["start"]) >= now - dt.timedelta(hours=6)]
print(json.dumps({"generated_at": int(time.time()), "vevents": vevents,
                  "in_window": len(events), "events": upcoming[:8]}))
PY
  local rc=$?
  rm -f "$ics"
  return $rc
}

main || fail calendar "calendar collector crashed"
