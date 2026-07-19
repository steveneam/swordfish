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

Third addition (dashboard redesign 2026-07-19): the tracked static app +
live read-only terminal mirrors.
  - DASH_APP_DIR set -> `/` serves the repo's dashboard-app/ while /data/ and
    /assets/ re-root into DASH_DIR (two roots, no copies: a copy step is the
    sha-drift bug class setup-dashboard.sh already fought once). Default
    empty = the old single-root behavior, so stub instances are untouched.
  - GET /api/term/list + /api/term/capture mirror tmux panes via
    `tmux capture-pane` ONLY - never attach (a second client would resize the
    agent's window), never any key-injection subcommand (agent-comm is the
    single send path; assert-dashboard-term.sh asserts this server's tmux
    argv surface stays read-only, including a literal grep for the injection
    subcommand's name - which is why this comment paraphrases it).
  - GET /api/hermes/journal tails hermes-gateway on syd3 as a ControlMaster
    PASSENGER: `ssh -O check` first, and no master = honest stale answer,
    never a fresh dial (each new ssh session fires a pam Telegram ping).

Env seams (for the check script's stub instance; production uses defaults):
  DASH_PORT / DASH_DIR / PANEL_CGROUP_SUFFIX / AGENT_COMM_BIN
  DASH_APP_DIR / TMUX_BIN / SSH_BIN
"""
import hashlib
import http.server
import json
import os
import re
import signal
import subprocess
import threading
import time
import urllib.parse

DASH_DIR = os.environ.get("DASH_DIR", "/home/deploy/dashboard")
APP_DIR = os.environ.get("DASH_APP_DIR", "")
PORT = int(os.environ.get("DASH_PORT", "8090"))
# panel shells live in code-server's cgroup; agent-tmux.service (the shelter)
# never matches this suffix, so sheltered sessions are structurally out of reach
CGROUP_SUFFIX = os.environ.get("PANEL_CGROUP_SUFFIX", "/code-server.service")
AGENT_COMM = os.environ.get("AGENT_COMM_BIN", "/usr/local/bin/agent-comm")
# tmux socket note: this unit runs without TMUX in env, landing on the default
# deploy socket - the same one collect-agents.sh and the agent sessions use.
# If agents ever move to a dedicated-socket service, add the matching -S here.
TMUX = os.environ.get("TMUX_BIN", "tmux")
SSH = os.environ.get("SSH_BIN", "ssh")
# same ControlPath pattern as collectors/lib.sh - ssh expands the % tokens
CM_OPTS = ["-o", "ControlMaster=no",
           "-o", f"ControlPath={os.path.expanduser('~')}/.ssh/cm-%r@%h-%p",
           "-o", "BatchMode=yes"]

_sessions_lock = threading.Lock()
_sessions_cache = {"ts": 0.0, "rows": []}
SESSIONS_TTL = 3

_hermes_lock = threading.Lock()
_hermes_cache = {"ts": 0, "lines": [], "error": None}
HERMES_TTL = 8


def tmux_sessions():
    """[{name, activity, cmd}] with a short TTL cache - the capture endpoint
    validates membership on every hit, and N polling cards must not mean N
    tmux invocations per tick.

    TRAP: cmd is #{pane_current_command} = basename(cmdline[0]) and reports
    the wrapper `bash` for relay-launched sessions while claude runs beneath
    (bit the relay, agent-comm AND collect-agents on 2026-07-19). It is
    display metadata ONLY - never decide agent liveness on it; that decision
    lives in collect-agents.sh's has_agent_desc."""
    with _sessions_lock:
        if time.time() - _sessions_cache["ts"] < SESSIONS_TTL:
            return _sessions_cache["rows"]
        rows = []
        try:
            r = subprocess.run(
                [TMUX, "list-sessions", "-F",
                 "#{session_name}|#{session_activity}|#{pane_current_command}"],
                capture_output=True, text=True, timeout=5)
            for line in r.stdout.splitlines():
                parts = line.split("|")
                if len(parts) == 3:
                    rows.append({"name": parts[0],
                                 "activity": int(parts[1]) if parts[1].isdigit() else None,
                                 "cmd": parts[2]})
        except (OSError, subprocess.TimeoutExpired):
            pass  # no tmux server / wedged -> empty list, card says so
        _sessions_cache.update(ts=time.time(), rows=rows)
        return rows

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
        super().__init__(*args, directory=(APP_DIR or DASH_DIR), **kwargs)

    def translate_path(self, path):
        # two-root serving: app files from the repo, data/assets from DASH_DIR.
        # stdlib translate_path keeps its traversal safety; we only swap the
        # root it resolves against for the data prefixes.
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if APP_DIR and (clean.startswith("/data/") or clean.startswith("/assets/")):
            saved, self.directory = self.directory, DASH_DIR
            try:
                return super().translate_path(path)
            finally:
                self.directory = saved
        return super().translate_path(path)

    def end_headers(self):
        # the founder must never be stuck on a stale app.js or cached JSON -
        # the code-server proxy and the browser both honor no-cache
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *args):
        pass  # static hits are noise; actions log via _json below

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _term_capture(self, q):
        name = (q.get("session") or [""])[0]
        # both gates, always: the charset rule (same as _agent_send) AND live
        # membership - a crafted-but-clean name must never reach tmux either
        if not re.fullmatch(r"[a-z0-9_-]{1,32}", name):
            self._json({"error": "bad session name"}, 400)
            return
        if name not in {s["name"] for s in tmux_sessions()}:
            self._json({"error": "no such session"}, 404)
            return
        try:
            n = max(10, min(int((q.get("lines") or ["200"])[0]), 2000))
        except ValueError:
            n = 200
        try:
            # capture-pane: read-only by construction - no attach (attaching
            # would resize the agent's window), no input path of any kind.
            # target "=name:" = exact session match, its active pane (a bare
            # "=name" is a valid target-window but NOT a valid target-pane)
            r = subprocess.run(
                [TMUX, "capture-pane", "-p", "-e", "-t", "=" + name + ":", "-S", f"-{n}"],
                capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired) as e:
            self._json({"error": f"capture failed: {e.__class__.__name__}"}, 500)
            return
        if r.returncode != 0:
            self._json({"error": (r.stderr.strip() or "capture failed")}, 500)
            return
        digest = hashlib.sha1(r.stdout.encode()).hexdigest()[:16]
        if (q.get("h") or [""])[0] == digest:
            self._json({"session": name, "hash": digest, "unchanged": True})
            return
        self._json({"session": name, "hash": digest, "text": r.stdout,
                    "ts": int(time.time())})

    def _hermes_journal(self, q):
        try:
            n = max(20, min(int((q.get("lines") or ["150"])[0]), 500))
        except ValueError:
            n = 150
        with _hermes_lock:  # single-flight: N polling tabs = one ssh per TTL
            if time.time() - _hermes_cache["ts"] < HERMES_TTL:
                self._json({**_hermes_cache, "cached": True})
                return
            # ControlMaster PASSENGER: -O check fails fast when no master is
            # up, and we answer stale rather than dial - a fresh ssh session
            # fires a pam Telegram ping (the 15-min collector timer re-primes)
            try:
                chk = subprocess.run([SSH] + CM_OPTS + ["-O", "check", "syd3"],
                                     capture_output=True, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                chk = None
            if chk is None or chk.returncode != 0:
                self._json({**_hermes_cache, "stale": True,
                            "error": "syd3 ssh master not primed - live tail "
                                     "resumes with the next 15-min collector cycle"})
                return
            try:
                # remote args deliberately space-free (lib.sh quoting lesson)
                r = subprocess.run(
                    [SSH, "-n"] + CM_OPTS
                    + ["syd3", "sudo", "-n", "journalctl",
                       "-u", "hermes-gateway.service", f"-n{n}",
                       "--no-pager", "-o", "short-iso"],
                    capture_output=True, text=True, timeout=10)
                _hermes_cache.update(ts=int(time.time()),
                                     lines=r.stdout.splitlines()[-n:], error=None)
                self._json(_hermes_cache)
            except (OSError, subprocess.TimeoutExpired):
                self._json({**_hermes_cache, "stale": True,
                            "error": "journal fetch timed out"})

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(url.query)
        if url.path == "/api/reset-terminals/preview":
            childless, live = scan_panels()
            self._json({"stale": childless, "refused_live": live})
            return
        if url.path == "/api/term/list":
            self._json({"sessions": tmux_sessions()})
            return
        if url.path == "/api/term/capture":
            self._term_capture(q)
            return
        if url.path == "/api/hermes/journal":
            self._hermes_journal(q)
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
