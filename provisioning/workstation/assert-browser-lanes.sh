#!/usr/bin/env bash
# assert-browser-lanes.sh - every agent that drives a browser owns its own Chrome.
#
# WHY (the trap, 2026-07-17): chrome-devtools-mcp defaults to a SHARED Chrome
# user-data-dir ($HOME/.cache/chrome-devtools-mcp/chrome-profile). Chrome takes
# a SingletonLock on a profile dir, so the SECOND agent to launch a browser
# against the default profile cannot start until the first one closes - which
# is exactly the "two projects can't browser-verify at once" symptom. The fix
# is per-agent isolation: --isolated (temp dir, auto-cleaned) or a distinct
# --userDataDir. This asserts it, because the default is the broken one and a
# new project inherits the break silently just by not configuring anything.
#
# Companion trap, NOT checked here (it lives in the project repos): two Next.js
# apps both running bare `next dev` both want :3000. See dev-lanes.md.
#
# Exit 0 only if every chrome-devtools config on the box is lane-isolated.

set -u

python3 - <<'PY'
import glob, json, os, re, sys

home = os.path.expanduser('~')
findings = []   # (source, name, verdict, detail)


def verdict(args):
    """A chrome-devtools arg list is safe if it opts out of the shared profile."""
    joined = ' '.join(args)
    if '--isolated' in args or re.search(r'--isolated[= ]true', joined):
        return 'isolated', 'temp profile, auto-cleaned'
    m = re.search(r'--user-?[Dd]ata-?[Dd]ir[= ]+(\S+)', joined)
    if m:
        return 'userDataDir', m.group(1)
    return 'SHARED', '$HOME/.cache/chrome-devtools-mcp/chrome-profile (default)'


def scan_mcp_servers(servers, source):
    for name, cfg in (servers or {}).items():
        if 'chrome-devtools' not in name:
            continue
        args = cfg.get('args', []) or []
        kind, detail = verdict(args)
        findings.append((source, name, kind, detail))


# 1. Claude: global config + any per-project override block
claude_json = os.path.join(home, '.claude.json')
if os.path.exists(claude_json):
    try:
        d = json.load(open(claude_json))
    except Exception as e:
        print(f'FAIL: {claude_json} is not parseable JSON ({e})')
        sys.exit(1)
    scan_mcp_servers(d.get('mcpServers'), '~/.claude.json (global)')
    for proj, pcfg in (d.get('projects') or {}).items():
        scan_mcp_servers(pcfg.get('mcpServers'), f'~/.claude.json [{proj}]')

# 2. Claude: per-repo .mcp.json (these are the PROJECTS' own tracked files -
#    swordfish reads them to assert fleet health, it never edits them)
for f in sorted(glob.glob(os.path.join(home, 'work', '*', '.mcp.json'))):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    scan_mcp_servers(d.get('mcpServers'), f.replace(home, '~'))

# 3. Codex: TOML, [mcp_servers.chrome-devtools] with an args = [...] line
codex = os.path.join(home, '.codex', 'config.toml')
if os.path.exists(codex):
    txt = open(codex, encoding='utf-8', errors='replace').read()
    m = re.search(r'^\[mcp_servers\.chrome-devtools\]\s*$(.*?)(?=^\[|\Z)',
                  txt, re.M | re.S)
    if m:
        a = re.search(r'^\s*args\s*=\s*\[(.*?)\]', m.group(1), re.M | re.S)
        args = re.findall(r'"([^"]*)"', a.group(1)) if a else []
        kind, detail = verdict(args)
        findings.append(('~/.codex/config.toml', 'chrome-devtools', kind, detail))

if not findings:
    print('PASS: no chrome-devtools MCP configs on this box (nothing to isolate).')
    sys.exit(0)

shared = [f for f in findings if f[2] == 'SHARED']
for source, name, kind, detail in findings:
    tag = 'FAIL' if kind == 'SHARED' else 'PASS'
    print(f'{tag}: {source} :: {name} -> {kind} ({detail})')

# Two explicit userDataDirs that are the SAME dir collide just as hard as the
# default does - a distinct path per agent is the whole point.
dirs = {}
for source, name, kind, detail in findings:
    if kind == 'userDataDir':
        dirs.setdefault(detail, []).append(source)
clashes = {d: s for d, s in dirs.items() if len(s) > 1}
for d, srcs in clashes.items():
    print(f'FAIL: userDataDir {d} is claimed by {len(srcs)} agents: {", ".join(srcs)}')

bad = len(shared) + len(clashes)
print(f'== browser lanes: {len(findings) - len(shared)}/{len(findings)} isolated'
      f'{", " + str(len(clashes)) + " userDataDir clash(es)" if clashes else ""}')
sys.exit(1 if bad else 0)
PY
