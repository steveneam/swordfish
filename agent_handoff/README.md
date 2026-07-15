# agent_handoff/ — what lives here (convention, founder-directed 2026-07-15)

**Two live files, nothing else at top level:**

- `CURRENT.md` — the session handoff. One file, overwritten at every wrap;
  the founder's `gogogo` boots from it (AGENTS.md rule 11).
- `NEEDS-STEVEN.md` — the founder action queue; feeds the dashboard card.
  One line per OPEN action; remove only when its source says done.

**`archive/`** — completed plans/briefs, each stamped with an
`ARCHIVED <date>` header saying what it became. History lives in git; the
archive exists so a resolved doc is never mistaken for an open thread.

**Not here:**

- Peer-project mail lives in the PEER's repo
  (`~/work/<peer>/agent_handoff/`: their `ASK-BACKS-FOR-SWORDFISH.md` out,
  `FROM-SWORDFISH.md` in — mirrored two-live-files convention). The
  peer-mail watcher (`provisioning/workstation/setup-peer-mail-watch.sh`)
  flags inbound changes; check `/var/lib/swordfish/peer-mail/NEW-*` at boot.
- Reference docs for LIVE systems live in `research/`
  (e.g. `research/hermes-e1-relay-design-2026-07-13.md`, cited by AGENTS.md
  rule 10).

Housekeeping rule: when a plan here is built or a brief is answered, stamp it
and move it to `archive/` at the same wrap that lands the work — a done doc
left at top level reads as an open thread. (ratchet: documentary, opinion)
