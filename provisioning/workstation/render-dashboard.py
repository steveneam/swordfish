#!/usr/bin/env python3
"""render-dashboard.py - compose ~/dashboard/index.html from the collector
JSON in ~/dashboard/data/ (dashboard-cockpit-plan-2026-07-13.md).

Rules this renderer enforces:
  - it NEVER invents state: a missing/erroring data file renders a visible
    UNAVAILABLE badge, a null metric renders an em-dash;
  - no secret ever reaches the HTML (collectors already guarantee their JSON
    is token-free; this file adds nothing but what is in the JSON);
  - the OUTPUT is untracked BY DESIGN - project/folder names on this box can
    include guarded portfolio names. Only this generic renderer is tracked.
  - every section header carries the age of its data (JS-ticked, amber after
    ~2 missed 15-min cycles), so staleness is visible without a refresh.
"""

import html
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
DATA = HOME / "dashboard" / "data"
OUT = HOME / "dashboard" / "index.html"
NEEDS_FILE = HOME / "work" / "swordfish" / "agent_handoff" / "NEEDS-STEVEN.md"
NOW = int(time.time())

def load(name):
    try:
        return json.loads((DATA / f"{name}.json").read_text())
    except Exception as e:
        return {"error": f"no data: {e.__class__.__name__}"}

def esc(s):
    return html.escape(str(s), quote=True)

def rel(epoch):
    if not epoch:
        return "never"
    s = max(0, NOW - int(epoch))
    if s < 3600:
        return f"{s // 60}m ago"
    if s < 86400:
        return f"{s // 3600}h ago"
    return f"{s // 86400}d ago"

def rel_any(v):
    """epoch number OR iso string -> relative age (hermes mixes both)"""
    if isinstance(v, (int, float)):
        return rel(v)
    try:
        d = datetime.fromisoformat(str(v).replace("Z", "+00:00"))
        return rel(d.timestamp())
    except Exception:
        return "?"

def human_bytes(n):
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "—"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.1f} PB"

def dash(v, suffix=""):
    return "—" if v is None else f"{v}{suffix}"

def badge(text, cls):
    return f'<span class="badge {cls}">{esc(text)}</span>'

def section(sid, title, data, body):
    """section wrapper; header carries data age + UNAVAILABLE on error"""
    age = ""
    if isinstance(data, dict):
        ts = data.get("generated_at")
        if ts:
            age = f'<span class="age" data-ts="{ts}">{rel(ts)}</span>'
        if data.get("error"):
            age = badge("UNAVAILABLE", "bad") + f'<span class="age">{esc(data["error"])}</span>'
    return (f'<section id="{sid}"><h2>{esc(title)}{age}</h2>{body}</section>')

# --- NEEDS STEVEN -------------------------------------------------------------

def needs_items(projects, security, money):
    items = []  # (sort_key_epoch, html)
    try:
        for line in NEEDS_FILE.read_text().splitlines():
            m = re.match(r"^- \[(\d{4}-\d{2}-\d{2})\]\s+(.*)", line)
            if m:
                d, text = m.group(1), m.group(2)
                ep = int(datetime.strptime(d, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp())
                items.append((ep, f'<li><span class="tag">queue</span>{esc(text)}'
                                  f'<span class="when">{rel(ep)}</span></li>'))
    except Exception as e:
        items.append((NOW, f'<li>{badge("queue file unreadable", "bad")} {esc(e)}</li>'))

    for ask in (projects.get("asks") or []):
        items.append((NOW, f'<li><span class="tag">agent ask</span>'
                           f'<b>{esc(ask.get("project"))}</b>: {esc(ask.get("text"))}</li>'))

    for t in (security.get("tls") or []):
        if t.get("days_left") is not None and t["days_left"] < 30:
            items.append((NOW, f'<li><span class="tag">tls</span>cert for '
                               f'<b>{esc(t["host"])}</b> expires in {t["days_left"]} days</li>'))
    for d in (security.get("domains") or []):
        if d.get("days_left") is not None and d["days_left"] < 30:
            items.append((NOW, f'<li><span class="tag">domain</span><b>{esc(d["domain"])}</b> '
                               f'expires in {d["days_left"]} days</li>'))

    for s in (money.get("subscriptions") or []):
        du = s.get("days_until")
        if du is not None and du <= 7:
            word = "OVERDUE" if du < 0 else f"due in {du}d"
            items.append((NOW, f'<li><span class="tag">money</span><b>{esc(s["name"])}</b> '
                               f'{esc(s.get("currency", ""))} {esc(s.get("amount"))} {word}</li>'))

    items.sort(key=lambda x: -x[0])
    if not items:
        return '<p class="allclear">Nothing needs you. ✓</p>'
    return "<ul class='needs'>" + "".join(h for _, h in items) + "</ul>"

# --- PROJECTS -----------------------------------------------------------------

def projects_html(p):
    if p.get("error"):
        return ""
    out = []
    for prj in (p.get("projects") or []):
        g = prj.get("git") or {}
        if not g.get("is_repo"):
            state = "not a git repo"
        elif g.get("dirty", 0) == 0 and g.get("unpushed", 0) == 0:
            state = '<span class="ok">clean · all pushed</span>'
        else:
            unp = g.get("unpushed")
            state = (f'<span class="warn">{g.get("dirty", "?")} uncommitted · '
                     f'{"?" if unp is None or unp < 0 else unp} unpushed</span>')
        gitline = (f'branch {esc(g.get("branch", "?"))} · last commit '
                   f'{esc(g.get("last_commit_rel", "?"))}<br>{state}') if g.get("is_repo") else state
        extra = f' · {prj["notes"]} notes' if prj.get("kind") == "vault" else ""
        out.append(
            f'<a class="btn" href="http://localhost:8080/?folder={esc(prj["path"])}">'
            f'<div class="name">{esc(prj["name"])}</div>'
            f'<div class="sub">files touched {rel(prj.get("touched"))} · '
            f'agent session {rel(prj.get("session"))}{extra}<br>{gitline}</div></a>')
    return '<div class="btns">' + "".join(out) + "</div>"

# --- FLEET --------------------------------------------------------------------

def pct_cell(v, warn=80, bad=92):
    if v is None:
        return "<td>—</td>"
    cls = "bad" if v >= bad else ("warn" if v >= warn else "")
    return f'<td class="{cls}">{v:.0f}%</td>'

def backup_cell(b):
    if not b:
        return "<td>—</td>"
    if b.get("kind") == "restic-unit":
        last, res = b.get("last_run"), b.get("result")
        stale = last is None or (NOW - last) > 36 * 3600
        cls = "bad" if (stale or res != "success") else "ok"
        return f'<td class="{cls}">{esc(res or "?")} · {rel(last)}</td>'
    ok = b.get("ok")
    if ok is None:
        return "<td>dead-man: —</td>"
    return f'<td class="{"ok" if ok else "bad"}">dead-man {"OK" if ok else "LATE"}</td>'

def services_cell(svcs):
    chips = []
    for s in (svcs or []):
        good = s.get("state") in ("active", "up")
        chips.append(f'<span class="chip {"ok" if good else "bad"}">{esc(s["name"])}</span>')
    return "<td>" + (" ".join(chips) or "—") + "</td>"

def uptime_h(s):
    if s is None:
        return "—"
    d = int(s) // 86400
    return f"{d}d {(int(s) % 86400) // 3600}h" if d else f"{int(s) // 3600}h"

# founder-facing role, one phrase per box (founder ask 2026-07-14: the card
# showed health but assumed he remembers what each box is FOR)
BOX_ROLES = {
    "syd1": "old prod · soak/rollback only",
    "syd2": "production · public edge + workloads",
    "syd3": "cockpit · hermes + founder terminal",
    "syd4": "workspace · repos, vault, agents",
}

def fleet_html(f):
    if f.get("error"):
        return f"<p>{esc(f['error'])}</p>"
    rows = []
    for b in (f.get("boxes") or []):
        up = b.get("up")
        upb = badge("UP", "ok") if up else (badge("?", "warn") if up is None else badge("DOWN", "bad"))
        cpu = b.get("cpu_pct")
        cpu_c = f"<td>{cpu:.1f}%</td>" if cpu is not None else (
            f'<td>load {esc(b["load1"])}</td>' if b.get("load1") is not None else "<td>—</td>")
        rr = ' <span class="chip warn">reboot pending</span>' if b.get("reboot_required") else ""
        rows.append(
            f'<tr><td><b>{esc(b["name"])}</b>{rr}<br><span class="dim">'
            f'{esc(BOX_ROLES.get(b["name"], ""))}'
            f'<br>via {esc(b.get("source", ""))}</span></td>'
            f"<td>{upb}</td>{cpu_c}{pct_cell(b.get('mem_pct'))}{pct_cell(b.get('disk_pct'))}"
            f"<td>{uptime_h(b.get('uptime_s'))}</td>{backup_cell(b.get('backup'))}"
            f"{services_cell(b.get('services'))}</tr>")
    return ('<table><tr><th>box</th><th>state</th><th>cpu/load</th><th>mem</th>'
            "<th>disk</th><th>uptime</th><th>backup</th><th>services</th></tr>"
            + "".join(rows) + "</table>")

# --- SECURITY -------------------------------------------------------------

def security_html(s):
    if s.get("error"):
        return f"<p>{esc(s['error'])}</p>"
    parts = []

    post = []
    for a in (s.get("auth") or []):
        if a.get("unreachable"):
            post.append(f'<tr><td>{esc(a["box"])}</td><td colspan="4">{badge("unreachable", "bad")}</td></tr>')
            continue
        ufw_ok = a.get("ufw") == "active"
        pw_ok = a.get("sshd_password_auth") == "no"
        post.append(
            f'<tr><td><b>{esc(a["box"])}</b></td>'
            f'<td>{badge("ufw " + a.get("ufw", "?"), "ok" if ufw_ok else "bad")}</td>'
            f'<td>{badge("key-only ssh" if pw_ok else "PASSWORD AUTH ON", "ok" if pw_ok else "bad")}</td>'
            f'<td class="{"warn" if a.get("fails_24h", 0) > 50 else ""}">{a.get("fails_24h", "?")} failed auth / 24h</td>'
            f'<td>{a.get("bans_24h", "?")} bans / 24h</td></tr>')
    parts.append("<table>" + "".join(post) + "</table>")

    rt = s.get("relay_tag") or {}
    if rt:
        st = rt.get("status", "unknown")
        cls = {"ok": "ok", "drift": "bad"}.get(st, "warn")
        label = {
            "ok": f'relay founder-id gate OK ({rt.get("checked", "?")} msgs, no tag drift)',
            "drift": f'relay founder-id gate DRIFT ({rt.get("drift", "?")}/{rt.get("checked", "?")} - founder may be unheard)',
            "unreachable": "relay founder-id gate: hermes unreachable",
            "unknown": "relay founder-id gate: unknown",
        }.get(st, f"relay founder-id gate: {esc(st)}")
        parts.append(f"<h3>relay {badge(label, cls)}</h3>")
        if st == "drift" and rt.get("sample"):
            parts.append(f'<p class="mono bad">{esc(rt["sample"])}</p>')

    logins = s.get("logins") or []
    def login_key(e):
        m = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2})Z", e.get("line", ""))
        return m.group(1) if m else ""
    logins = sorted(logins, key=login_key, reverse=True)[:10]
    sus = [e for e in logins if e.get("suspicious")]
    head = badge(f"{len(sus)} unrecognized", "bad") if sus else badge("all keys recognized", "ok")
    rows = "".join(
        f'<li class="{"bad" if e.get("suspicious") else ""}">{esc(e.get("line", ""))}</li>'
        for e in logins) or "<li>no logins in the journal window</li>"
    parts.append(f"<h3>ssh logins (last 10) {head}</h3><ul class='mono'>{rows}</ul>"
                 f'<p class="dim">{esc(s.get("note", ""))}</p>')

    tls_rows, dom_rows = [], []
    for t in (s.get("tls") or []):
        d = t.get("days_left")
        cls = "bad" if (d is None or d < 14) else ("warn" if d < 30 else "")
        tls_rows.append(f'<tr><td>{esc(t["host"])}</td><td class="{cls}">{dash(d, " days")}</td></tr>')
    for t in (s.get("domains") or []):
        d = t.get("days_left")
        cls = "bad" if (d is None or d < 30) else ("warn" if d < 60 else "")
        dom_rows.append(f'<tr><td><b>{esc(t["domain"])}</b></td><td class="{cls}">{dash(d, " days")}</td></tr>')
    parts.append('<div class="cols"><div><h3>TLS certs</h3><table>' + "".join(tls_rows)
                 + '</table></div><div><h3>domains</h3><table>' + "".join(dom_rows)
                 + "</table></div></div>")
    return "".join(parts)

# --- MONEY / CALENDAR / HERMES / MIGRATION ----------------------------------

def money_html(m):
    if m.get("error"):
        return f"<p>{esc(m['error'])}</p>"
    parts = []

    api = m.get("api") or {}
    rows = []
    bl = api.get("binarylane") or {}
    if bl.get("error"):
        rows.append(f'<tr><td>BinaryLane</td><td colspan="2">{badge(bl["error"], "bad")}</td></tr>')
    else:
        chips = " ".join(f'<span class="chip">{esc(s.get("name", "?"))} '
                         f'{s.get("total", "?")}</span>' for s in (bl.get("servers") or []))
        rows.append(f'<tr><td>BinaryLane</td><td>unbilled AUD <b>{esc(bl.get("unbilled_total", "?"))}'
                    f"</b></td><td>{chips}</td></tr>")
    vu = api.get("vultr") or {}
    if vu.get("error"):
        rows.append(f'<tr><td>Vultr</td><td colspan="2">{badge(vu["error"], "bad")}</td></tr>')
    else:
        bal = vu.get("balance")
        credit = f"credit USD <b>{-bal:.2f}</b>" if isinstance(bal, (int, float)) and bal < 0 \
                 else f"balance USD {esc(bal)}"
        rows.append(f'<tr><td>Vultr</td><td>{credit}</td>'
                    f'<td>pending {esc(vu.get("pending_charges", "?"))}</td></tr>')
    pb = api.get("porkbun") or {}
    if pb.get("error"):
        rows.append(f'<tr><td>Porkbun</td><td colspan="2">{badge(pb["error"], "bad")}</td></tr>')
    else:
        doms = pb.get("domains") or []
        auto = all(d.get("auto_renew") for d in doms)
        nearest = doms[0] if doms else None
        near = (f'nearest <b>{esc(nearest["domain"])}</b> in {nearest.get("days_left", "?")}d'
                if nearest else "no domains")
        rows.append(f'<tr><td>Porkbun</td><td>{len(doms)} domains'
                    f'{" · all auto-renew" if auto and doms else ""}</td><td>{near}</td></tr>')
    b2 = api.get("b2") or {}
    rows.append(f'<tr><td>Backblaze B2</td><td colspan="2" class="dim">{esc(b2.get("note", "—"))}</td></tr>')
    parts.append("<table>" + "".join(rows) + "</table>")

    if m.get("subscriptions_missing"):
        parts.append('<p class="dim">subscriptions.yml missing — SaaS spend not tracked</p>')
    else:
        srows = []
        for s in (m.get("subscriptions") or []):
            du = s.get("days_until")
            cls = "bad" if (du is not None and du <= 3) else ("warn" if du is not None and du <= 7 else "")
            srows.append(f'<tr><td>{esc(s.get("name"))}</td>'
                         f'<td>{esc(s.get("currency", ""))} {esc(s.get("amount", "?"))}</td>'
                         f'<td>{esc(s.get("cycle", ""))}</td>'
                         f'<td class="{cls}">{esc(s.get("next_charge") or "—")}'
                         f'{f" ({du}d)" if du is not None else ""}</td>'
                         f'<td class="dim">{esc(s.get("card") or "")}</td></tr>')
        parts.append("<h3>SaaS (founder-maintained)</h3>"
                     "<table><tr><th>what</th><th>amount</th><th>cycle</th><th>next charge</th><th>note</th></tr>"
                     + "".join(srows)
                     + f'</table><p class="dim">SaaS monthly run-rate ≈ {esc(m.get("monthly_run_rate", "?"))} '
                     "(placeholder amounts until the one-time correction pass)</p>")
    return "".join(parts)

def calendar_html(c):
    if c.get("error"):
        return f"<p>{esc(c['error'])}</p>"
    items = []
    for e in (c.get("events") or [])[:5]:
        try:
            d = datetime.fromisoformat(e["start"])
            when = d.strftime("%a %d %b") if e.get("all_day") else d.strftime("%a %d %b %H:%M")
        except Exception:
            when = "?"
        items.append(f'<li><span class="when">{esc(when)}</span>{esc(e.get("summary", ""))}</li>')
    if not items:
        n = c.get("vevents")
        why = f" ({n} events in the feed, all in the past)" if n else ""
        return f"<ul class='cal'><li>nothing in the next 60 days{esc(why)}</li></ul>"
    return "<ul class='cal'>" + "".join(items) + "</ul>"

def hermes_html(h):
    if h.get("error"):
        return f"<p>{esc(h['error'])}</p>"
    g = h.get("gateway") or {}
    chips = [
        badge(f'service {h.get("service", "?")}', "ok" if h.get("service") == "active" else "bad"),
        badge(f'gateway {g.get("state", "?")}', "ok" if g.get("state") == "running" else "bad"),
        badge(f'telegram {g.get("telegram", "?")}', "ok" if g.get("telegram") == "connected" else "bad"),
    ]
    parts = ["<p>" + " ".join(chips) + f' <span class="dim">{esc(h.get("note", ""))}</span></p>']

    jobs = h.get("jobs")
    if jobs is None:
        parts.append(f'<p>{badge("jobs unreadable", "bad")} {esc(h.get("jobs_error", ""))}</p>')
    else:
        rows = []
        for j in jobs:
            st = j.get("state", "?")
            stb = badge(st.upper(), "ok" if st == "scheduled" or j.get("enabled") else "warn")
            ok = j.get("last_status")
            rows.append(f'<tr><td>{esc(j.get("name"))}</td><td class="mono">{esc(j.get("schedule_display"))}</td>'
                        f"<td>{stb}</td><td>{rel_any(j.get('last_run_at'))} · "
                        f'<span class="{"ok" if ok == "ok" else "bad"}">{esc(ok or "—")}</span></td>'
                        f"<td>{esc((j.get('next_run_at') or '—')[:16])}</td></tr>")
        parts.append("<table><tr><th>cron job</th><th>schedule</th><th>state</th>"
                     "<th>last run</th><th>next run</th></tr>" + "".join(rows) + "</table>"
                     '<p class="dim">read from cron/jobs.json — `hermes cron list` hides paused jobs</p>')

    relay = h.get("relay") or []
    if relay:
        lines = "".join(
            f'<li><b>{esc(r.get("project", "?"))}</b> '
            f'<span class="tag">{esc(r.get("dir", "?"))}</span>'
            f'{esc(r.get("head", ""))} '
            f'<span class="when">{rel(r.get("ts"))}</span></li>'
            for r in sorted(relay, key=lambda r: -(r.get("ts") or 0)))
        parts.append(f"<h3>last relay per project</h3><ul class='needs'>{lines}</ul>")

    for key, label in (("last_in", "founder → hermes"), ("last_out", "hermes → founder")):
        m = h.get(key)
        if m:
            parts.append(f'<p><b>{label}</b> <span class="dim">{rel_any(m.get("ts"))}</span><br>'
                         f'<span class="mono">{esc(m.get("snippet", ""))}</span></p>')
    o = h.get("last_cron_output")
    if o:
        parts.append(f'<h3>last cron output <span class="dim">{esc(o.get("file"))} · {rel(o.get("mtime"))}'
                     "</span></h3><pre>" + esc(o.get("head", "")) +
                     '</pre><p class="dim">delivery-green ≠ content-true: check this against what Telegram showed</p>')
    return "".join(parts)

def migration_html(m):
    if m.get("error"):
        return f"<p>{esc(m['error'])}</p>"
    rows = "".join(f'<tr><td>{esc(a["name"])}</td><td>{a["files"]}</td><td>{human_bytes(a["bytes"])}</td></tr>'
                   for a in (m.get("areas") or []))
    placed = " ".join(f'<span class="chip ok">{esc(p)}</span>' for p in (m.get("placed") or []))
    return ("<table><tr><th>staging area</th><th>files</th><th>size</th></tr>" + rows + "</table>"
            + (f"<p>placed by the box agent: {placed}</p>" if placed else "")
            + f'<p class="dim">census: {dash(m.get("census_rows"))} rows · {esc(m.get("note", ""))}</p>')

# --- page ---------------------------------------------------------------------

CSS = """
  *{box-sizing:border-box}
  body{background:#0e1116;color:#e6e6e6;font-family:-apple-system,'Helvetica Neue',sans-serif;
       margin:0;padding:1.2rem;display:flex;flex-direction:column;align-items:center}
  main{width:min(72rem,96vw)}
  header{display:flex;justify-content:space-between;align-items:baseline;flex-wrap:wrap;
         border-bottom:1px solid #2c3c50;padding-bottom:.6rem;margin-bottom:1rem}
  h1{font-weight:300;letter-spacing:.12em;font-size:1.4rem;color:#9db4c8;margin:0}
  .clock{font-size:.9rem;color:#7b8fa3;text-align:right}
  .clock b{color:#cfe0ee;font-size:1.05rem;font-variant-numeric:tabular-nums}
  section{background:#141a22;border:1px solid #22303f;border-radius:.7rem;
          padding:.9rem 1.1rem;margin:.8rem 0}
  h2{font-size:.8rem;letter-spacing:.18em;text-transform:uppercase;color:#9db4c8;
     margin:.1rem 0 .6rem;display:flex;align-items:center;gap:.6rem}
  h3{font-size:.85rem;color:#a9bccd;margin:.8rem 0 .3rem}
  .age{font-weight:400;letter-spacing:0;text-transform:none;color:#5c7186;font-size:.75rem;margin-left:auto}
  .age.stale{color:#e0b060}
  table{border-collapse:collapse;width:100%;font-size:.85rem}
  th{color:#7b8fa3;font-weight:500;text-align:left;padding:.25rem .5rem}
  td{border-top:1px solid #1e2a37;padding:.35rem .5rem;vertical-align:top}
  ul{margin:.2rem 0;padding-left:1.1rem}
  li{margin:.25rem 0;line-height:1.45}
  .needs li{list-style:none;margin-left:-1.1rem}
  #needs-steven{border-color:#5a3a3a;background:#191114}
  .allclear{color:#6fae7f;margin:.2rem 0}
  .tag{display:inline-block;background:#232f3d;color:#9db4c8;border-radius:.4rem;
       font-size:.68rem;padding:.05rem .45rem;margin-right:.5rem;vertical-align:middle}
  .when{color:#7b8fa3;margin:0 .5rem;font-size:.8rem}
  .badge{display:inline-block;border-radius:.4rem;font-size:.7rem;padding:.1rem .45rem;font-weight:600}
  .badge.ok{background:#15301e;color:#6fae7f}.badge.warn{background:#33270f;color:#e0b060}
  .badge.bad{background:#3a1515;color:#e07a6a}
  .chip{display:inline-block;border-radius:.4rem;font-size:.72rem;padding:.05rem .4rem;margin:.06rem .12rem}
  .chip.ok{background:#15301e;color:#6fae7f}.chip.warn{background:#33270f;color:#e0b060}
  .chip.bad{background:#3a1515;color:#e07a6a}
  .ok{color:#6fae7f}.warn{color:#e0b060}.bad{color:#e07a6a}.dim{color:#5c7186;font-size:.8rem}
  .mono{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:.78rem}
  pre{background:#0e1116;border:1px solid #1e2a37;border-radius:.4rem;padding:.6rem;
      font-size:.75rem;white-space:pre-wrap;max-height:12rem;overflow-y:auto}
  .btns{display:grid;grid-template-columns:repeat(auto-fill,minmax(20rem,1fr));gap:.6rem}
  a.btn{display:block;padding:.8rem 1rem;background:#1a2330;color:#e6e6e6;text-decoration:none;
        border-radius:.7rem;border:1px solid #2c3c50}
  a.btn:hover{background:#24344a;border-color:#3d5470}
  .name{font-size:1.15rem}
  .sub{font-size:.76rem;color:#7b8fa3;margin-top:.35rem;line-height:1.5}
  /* hermes card wears the hermes-agent brand (founder ask 2026-07-13):
     gold #FFD700/#8B6508 from the project's own docusaurus theme, logo
     fetched once by collect-hermes.sh into assets/ (untracked, served
     same-origin - never inlined) */
  #hermes{border-color:#8B6508;background:#171307}
  #hermes h2{color:#FFD700}
  #hermes h2::before{content:"";width:1.5rem;height:1.5rem;flex:none;border-radius:.35rem;
    background:#fff url(assets/hermes-logo.png) center/cover no-repeat}
  #hermes th{color:#c89222}
  #hermes .age{color:#8a7a4a}
  #hermes .age.stale{color:#e0b060}
  .cols{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
  .cal .when{display:inline-block;min-width:9rem;color:#9db4c8;margin:0 .4rem 0 0}
  .cal li{list-style:none;margin-left:-1.1rem}
  footer{color:#5c7186;font-size:.75rem;text-align:center;margin:1rem 0}
  @media (max-width:44rem){.cols{grid-template-columns:1fr}}
"""

JS = """
  function tick(){
    const now = new Date();
    const f = (tz) => new Intl.DateTimeFormat('en-AU',
      {timeZone: tz, hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false}).format(now);
    const d = new Intl.DateTimeFormat('en-AU',
      {timeZone: 'Australia/Sydney', weekday: 'short', day: 'numeric', month: 'short'}).format(now);
    document.getElementById('clk').innerHTML =
      d + ' · <b>' + f('Australia/Sydney') + '</b> syd · ' + f('UTC') + ' utc';
  }
  function ages(){
    const now = Date.now() / 1000;
    document.querySelectorAll('.age[data-ts]').forEach(el => {
      const s = now - Number(el.dataset.ts);
      el.textContent = 'data ' + (s < 90 ? 'live' :
        s < 3600 ? Math.round(s / 60) + 'm old' :
        s < 172800 ? Math.round(s / 360) / 10 + 'h old' : Math.round(s / 86400) + 'd old');
      el.classList.toggle('stale', s > 2400);
    });
  }
  setInterval(tick, 1000); setInterval(ages, 30000); tick(); ages();
"""

def main():
    projects = load("projects")
    fleet = load("fleet")
    security = load("security")
    money = load("money")
    calendar = load("calendar")
    hermes = load("hermes")
    migration = load("migration")

    up4 = next((b.get("uptime_s") for b in fleet.get("boxes", [])
                if isinstance(b, dict) and b.get("name") == "syd4"), None)

    # the needs queue draws on three data files - its age is the OLDEST of
    # them, so the top card carries a staleness signal like every other
    needs_ts = [d.get("generated_at") for d in (projects, security, money)
                if isinstance(d.get("generated_at"), int)]
    needs_meta = {"generated_at": min(needs_ts)} if needs_ts else {"error": "no source data"}

    def safe(fn, data, name):
        try:
            return fn(data)
        except Exception as e:
            return f"<p>{badge('render error', 'bad')} {esc(name)}: {esc(e)}</p>"

    body = f"""<meta charset="utf-8"><meta http-equiv="refresh" content="300">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>syd4 cockpit</title>
<style>{CSS}</style>
<main>
<header><h1>syd4 · infrastructure cockpit</h1>
<div class="clock"><span id="clk">…</span><br>
<span class="dim">box up {uptime_h(up4)} · page regenerates every 15 min</span></div></header>
{section("needs-steven", "Needs Steven", needs_meta, safe(lambda _: needs_items(projects, security, money), None, "needs"))}
{section("projects", "Projects", projects, safe(projects_html, projects, "projects"))}
{section("fleet", "Fleet health", fleet, safe(fleet_html, fleet, "fleet"))}
{section("security", "Security", security, safe(security_html, security, "security"))}
{section("money", "Money", money, safe(money_html, money, "money"))}
{section("calendar", "Calendar", calendar, safe(calendar_html, calendar, "calendar"))}
{section("hermes", "Hermes", hermes, safe(hermes_html, hermes, "hermes"))}
{section("migration", "Migration", migration, safe(migration_html, migration, "migration"))}
<footer>rendered {datetime.now(timezone.utc).strftime("%F %H:%M")} UTC ·
localhost:8080/proxy/8090 · blank page? the ssh tunnel is down — it restarts itself within ~10 s</footer>
</main>
<script>{JS}</script>
"""
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text("<!doctype html>\n<html><body>" + body + "</body></html>\n")
    tmp.replace(OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
