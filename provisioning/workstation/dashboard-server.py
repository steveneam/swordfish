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

Second action (founder call 2026-07-19, "build 1 and 2"): the live-comms
compose box. POST /api/agent-send delegates ENTIRELY to agent-comm - one
enforcement path for the safety rules (draft-refusal, claude-pane targeting,
newline collapse, ledger); this server only validates shape, pins the
provenance to "[Steven via dashboard]", and maps agent-comm's exit codes to
JSON the page can render. GET /api/agent-roster and /api/agent-ledger are
thin reads over the same tool.

Env seams (for the check script's stub instance; production uses defaults):
  DASH_PORT / DASH_DIR / PANEL_CGROUP_SUFFIX / AGENT_COMM_BIN
"""
import http.server
import json
import os
import re
import signal
import subprocess

DASH_DIR = os.environ.get("DASH_DIR", "/home/deploy/dashboard")
PORT = int(os.environ.get("DASH_PORT", "8090"))
# panel shells live in code-server's cgroup; agent-tmux.service (the shelter)
# never matches this suffix, so sheltered sessions are structurally out of reach
CGROUP_SUFFIX = os.environ.get("PANEL_CGROUP_SUFFIX", "/code-server.service")
AGENT_COMM = os.environ.get("AGENT_COMM_BIN", "/usr/local/bin/agent-comm")

# agent-comm send exit codes -> what the page shows (keep in step with the tool)
SEND_CODE = {
    0: ("ok", "sent"),
    2: ("bad-request", "refused: bad target/usage"),
    3: ("refused-draft", "refused: a draft is parked in that composer"),
    4: ("refused-unclear", "refused: composer state unclear - retry shortly"),
    5: ("sent-unverified", "sent, but composer still shows text - peek to verify"),
}


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
        if self.path == "/api/agent-roster":
            try:
                out = subprocess.run([AGENT_COMM, "sessions", "--json"],
                                     capture_output=True, text=True, timeout=20)
                self._json({"agents": json.loads(out.stdout or "[]")})
            except Exception as e:
                self._json({"error": str(e)})
            return
        if self.path == "/api/agent-ledger":
            try:
                out = subprocess.run([AGENT_COMM, "ledger", "8"],
                                     capture_output=True, text=True, timeout=10)
                self._json({"rows": out.stdout.splitlines()})
            except Exception as e:
                self._json({"error": str(e)})
            return
        super().do_GET()

    def _agent_send(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n)) if 0 < n <= 8192 else {}
        except (ValueError, json.JSONDecodeError):
            body = {}
        target = (body.get("target") or "").strip()
        text = (body.get("text") or "").strip()
        with_raw = body.get("with") or []
        # same safe charset as the relay's resolve_project: a typo or crafted
        # name must never reach tmux as a target
        if (not target or not text or len(text) > 2000
                or not re.fullmatch(r"[a-z0-9_-]+", target)):
            self._json({"status": "bad-request",
                        "detail": "need a known target and 1..2000 chars of text"})
            return
        # optional coordination partners: the founder pairs two (or more)
        # agents; the standard clause is appended SERVER-side so every pairing
        # carries the same rules pointer. Partners get the same charset gate,
        # and target-as-partner is a user mistake worth refusing loudly.
        if not isinstance(with_raw, list):
            self._json({"status": "bad-request", "detail": "'with' must be a list"})
            return
        partners = []
        for w in with_raw:
            w = (w or "").strip() if isinstance(w, str) else ""
            if not re.fullmatch(r"[a-z0-9_-]+", w):
                self._json({"status": "bad-request",
                            "detail": f"bad partner name: {w!r}"})
                return
            if w == target:
                self._json({"status": "bad-request",
                            "detail": "target cannot be its own coordination partner"})
                return
            if w not in partners:
                partners.append(w)
        if partners:
            text += (" — coordinate LIVE with " + ", ".join(partners)
                     + " on this via agent-comm (you lead the loop; signals"
                       " not task grants; wrap the outcome in your channel)")
        if len(text) > 2000:
            self._json({"status": "bad-request",
                        "detail": "message too long once the coordination"
                                  " clause is added - trim it"})
            return
        try:
            r = subprocess.run(
                [AGENT_COMM, "send", "--from", "Steven", "--channel", "dashboard",
                 target, text],
                capture_output=True, text=True, timeout=60,
                env={**os.environ, "TMUX": "", "TMUX_PANE": ""})
        except subprocess.TimeoutExpired:
            self._json({"status": "error", "detail": "agent-comm timed out"})
            return
        status, human = SEND_CODE.get(r.returncode,
                                      ("error", f"agent-comm exit {r.returncode}"))
        detail = (r.stderr or r.stdout).strip().splitlines()
        print(f"agent-send: {target} <- Steven(dashboard): {status}", flush=True)
        self._json({"status": status, "human": human,
                    "detail": detail[-1] if detail else ""})

    def do_POST(self):
        if self.path == "/api/agent-send":
            self._agent_send()
            return
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
