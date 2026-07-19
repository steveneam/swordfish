#!/usr/bin/env python3
"""dashboard-server.py - founder dashboard: static files + ONE action endpoint.

Replaces the bare `python3 -m http.server` (plan:
research/dashboard-terminal-controls-plan-2026-07-17.md, un-parked by founder
call 2026-07-19). Same posture as before: binds 127.0.0.1 ONLY, the SSH tunnel
is the auth, 8090 never in ufw. Static serving is unchanged (~/dashboard).

The one action - POST /api/reset-terminals - SIGHUPs every code-server panel
BASH that has NO children (SIGHUP, not SIGTERM: interactive bash ignores TERM).
A shell WITH children is a live agent's home and is REFUSED, per panel, always:
killing one is a founder decision made in that panel, never a button sweep
(2026-07-17: a duplicate codex proved why). The childless check is re-run in a
fresh /proc pass immediately before each kill so a shell that spawned an agent
inside the scan window is not swept (window shrinks to ~ms; the refusal
invariant is asserted by provisioning/checks/assert-dashboard-reset.sh).

GET /api/reset-terminals/preview runs the same scan without signalling - the
page button uses it for its confirm dialog, the check script for its asserts.

Env seams (for the check script's stub instance; production uses defaults):
  DASH_PORT / DASH_DIR / PANEL_CGROUP_SUFFIX
"""
import http.server
import json
import os
import signal

DASH_DIR = os.environ.get("DASH_DIR", "/home/deploy/dashboard")
PORT = int(os.environ.get("DASH_PORT", "8090"))
# panel shells live in code-server's cgroup; agent-tmux.service (the shelter)
# never matches this suffix, so sheltered sessions are structurally out of reach
CGROUP_SUFFIX = os.environ.get("PANEL_CGROUP_SUFFIX", "/code-server.service")


def scan_panels():
    """One /proc pass -> (childless, with_children) bash pids in the panel
    cgroup. comm + ppid come from /proc/<pid>/stat (comm is bracketed by the
    LAST ')' so a comm containing ')' cannot fool the parse)."""
    child_count = {}
    panel_bash = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                st = f.read()
            comm = st[st.index("(") + 1:st.rindex(")")]
            ppid = int(st[st.rindex(")") + 2:].split()[1])
            child_count[ppid] = child_count.get(ppid, 0) + 1
            if comm != "bash":
                continue
            with open(f"/proc/{pid}/cgroup") as f:
                cgroup = f.read().strip().split(":", 2)[-1]
            if cgroup.endswith(CGROUP_SUFFIX):
                panel_bash.append(int(pid))
        except (OSError, ValueError, IndexError):
            continue  # process vanished mid-scan, or unreadable - skip
    childless = [p for p in panel_bash if child_count.get(p, 0) == 0]
    live = [p for p in panel_bash if child_count.get(p, 0) > 0]
    return childless, live


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DASH_DIR, **kwargs)

    def log_message(self, *args):
        pass  # static hits are noise; actions log via _json below

    def _json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/reset-terminals/preview":
            childless, live = scan_panels()
            self._json({"stale": childless, "refused_live": live})
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/reset-terminals":
            self.send_error(404)
            return
        candidates, _ = scan_panels()
        hupped, refused = [], []
        for pid in candidates:
            # fresh pass right before the signal: the refusal invariant beats
            # the race where a candidate just became an agent's home
            still_childless, now_live = scan_panels()
            if pid in still_childless:
                try:
                    os.kill(pid, signal.SIGHUP)
                    hupped.append(pid)
                except OSError:
                    pass  # already gone
            elif pid in now_live:
                refused.append(pid)
        _, live = scan_panels()
        result = {"hupped": hupped, "refused_live": sorted(set(refused + live))}
        print(f"reset-terminals: {result}", flush=True)  # -> journald
        self._json(result)


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"dashboard-server on 127.0.0.1:{PORT} dir={DASH_DIR} "
          f"panel-cgroup=*{CGROUP_SUFFIX}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
