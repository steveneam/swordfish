# Dashboard terminal controls — future plan (parked)

Founder ask 2026-07-17, parked by his call the same day ("save it as a future
plan"). Context: the 13:56 code-server death left plain-bash panels hijacking
the project buttons; the founder asked whether he could do the cleanup and the
tmux-vs-shell choice himself from the dashboard.

## What made this mostly unnecessary (build only if the itch returns)

- **TMUX AUTO-LAND guard** (`provisioning/host/setup-qol.sh`, commit b5b52ee):
  every vscode panel now execs into agent-term unless PLAIN_SHELL=1 — the
  stale-panel class this would clean up can no longer form.
- **Already-clickable self-service in the terminal panel:** trash icon = kill
  that panel's pty server-side; `+` = tmux (default profile); `˅` dropdown →
  bash = plain shell (PLAIN_SHELL=1, gets the UNSHELTERED banner).

## Hard constraint discovered

The dashboard buttons are `?folder=` links. A code-server URL cannot create,
target, or choose a profile for a terminal — so "open as tmux / open as shell"
can never live on the button itself. Any dashboard-side control has to be a
box-side action endpoint, not a link parameter.

## If/when built

- **Where:** the cockpit static server (`swordfish-dashboard-web.service`,
  127.0.0.1:8090) is a bare `python3 -m http.server` — static only. Replace
  with a ~30-line handler (still localhost-only; the SSH tunnel stays the auth,
  8090 never in ufw) or a separate socket-activated oneshot. Provisioning home:
  `provisioning/workstation/setup-dashboard.sh`.
- **Button 1 — "reset terminals":** SIGHUP (not SIGTERM — interactive bash
  ignores it) every code-server panel shell that is childless. NEVER touch a
  shell with children: that is a live agent, and killing one is a founder
  decision per panel (today's duplicate codex proved why).
- **Button 2 — tmux/shell chooser:** infeasible as a link (above); the
  in-panel dropdown already is this. Drop unless code-server grows URL-driven
  terminal profiles.
- **Verify ratchet:** endpoint refuses to kill a shell with children; check
  script asserts that with a stub process tree before the button ships.

Related: `research/hermes-e1-relay-design-2026-07-13.md` (same tunnel-is-auth
posture), memory `dashboard-button-terminal-focus`.
