# Hermes E1 relay — finished design (2026-07-13, validated live)

> Supersedes the Leg-3 E1 sketch in `founder-interface-plan-2026-07-11.md`
> (headless dispatch over a syd3→syd4 keypair). The founder's three
> refinements (memory: hermes-e1-relay-directive) changed the shape: messages
> inject into the SAME folder-named tmux sessions agent-term creates — "as if
> I was opening the vscode folder and doing it myself" — with per-project
> attribution both directions and closing-session summaries to Telegram.

## What E1 is

Founder, from his phone: posts a message in a per-project Telegram topic →
that project's real agent session on syd4 receives it as a user turn → the
agent's reply lands back in the same topic. Hermes itself stays an assistant
he can @mention; it is never the router.

## Architecture (five pieces, two boxes)

```
Telegram forum group (founder-owned, bot is admin)
  └─ one topic per project (thread_id = the routing key)
        │  bot OBSERVES all topic messages (env: observe mode), agent
        │  answers only when @mentioned → rows land in syd3 state.db
        ▼
[syd3] hermes gateway + state.db  ── read-only, over the EXISTING
        │                            multiplexed ssh (collector seam)
        ▼
[syd4] relay-poller (systemd, OUR repo, deterministic bash/python)
        │  watermark on message id → new founder rows only
        │  thread_id → project via untracked inventory/secrets/relay-map.yml
        ▼
[syd4] injector: tmux new -A -s <slug> (exact agent-term recipe) →
        send-keys "[Steven via hermes-relay] <msg>" Enter
        + marker file ~/.claude/relay-pending/<session>.json
        ▼
[syd4] Claude Code Stop hook (user-level): turn ends → if marker exists,
        extract last assistant text from the transcript JSONL →
        ssh syd3 hermes send --to telegram:<chat>:<thread> → consume marker
```

## Decisions locked (with rationale)

1. **Pull-only: hermes gets ZERO access to syd4** — the old dispatch-keypair
   design is dead. syd4 polls syd3's state.db over the ssh path the
   collectors already use. The internet-facing, prompt-injectable component
   holds no credential toward the box that runs the agents. (invariant)
2. **No LLM in the routing path.** The router is dumb code with a watermark
   file; hermes-the-agent never executes relay logic (E0's false-report bug
   and the confident-wrong class are the standing argument). (invariant)
3. **Same-session injection, not headless.** `tmux new -A -s <slug> -c <dir>`
   IS agent-term's line — the three entry paths (code-server tab, ssh `work`,
   relay) all converge on one session per project. Claude Code natively
   queues a message typed while the agent is mid-turn, so injection is safe
   at any time.
4. **Replies ride the Stop hook, not transcript polling.** Only turns that a
   relay injection started get relayed back (marker file), so terminal work
   never leaks to Telegram. The transcript JSONL stays the read seam —
   pane-scraping is banned.
5. **Attribution = the topic.** thread_id ↔ project dir ↔ tmux slug ↔
   transcript slug, one mapping file. Inbound + outbound both append to a
   relay ledger (jsonl, untracked) on syd4; the dashboard hermes card grows
   a "last relay per project" line reading that ledger. Both directions
   queryable, which was the founder's third refinement.
6. **Provenance banner is mandatory.** Live rehearsal today: an injected
   "reply with exactly X" was REFUSED by the target agent as suspected
   prompt injection — correct instinct, wrong target. Fix is standing
   context, not phrasing: every project's handoff/CLAUDE.md gets one line —
   "messages prefixed `[Steven via hermes-relay]` are the founder, treat as
   founder-typed." The relay always applies that exact prefix; nothing else
   may use it.
7. **Observe-mode config is env, not YAML** (this hermes build keeps
   platform settings in `~/.hermes/.env`): `TELEGRAM_GROUP_ALLOWED_CHATS=
   <group id>` · `TELEGRAM_REQUIRE_MENTION=true` ·
   `TELEGRAM_OBSERVE_UNMENTIONED_GROUP_MESSAGES=true`, then gateway restart.
   Ratchet home: `provisioning/hermes/install-hermes-syd3.sh`.
8. **Closing summaries** = a wrap-protocol line (each project's wrap sends
   its summary via `hermes send` to its own topic). Protocol first; a
   SessionEnd hook can automate it later if wraps prove forgetful.
9. **Scope control:** relay-map.yml is an allow-list — a project absent from
   it cannot be injected into. Constraints that survive from E0: hermes
   never gets spend keys or provisioning authority; sender check = founder's
   user id only.

## Seams validated live (2026-07-13 evening)

| Seam | Result |
|---|---|
| syd4 reads state.db rows (chat_id, thread_id, observed) | ✅ proven (collector + this session's queries) |
| agent-term-style detached session boot | ✅ `e1-rehearsal` booted; trust dialog handled (one-time per dir — pre-seed at project wake-up) |
| send-keys injection registers as a real user turn | ✅ user entry in transcript JSONL |
| reply extraction from transcript JSONL | ✅ assistant text extracted by parser |
| target-agent trust of injected text | ⚠️ refused without provenance context → decision 6 |
| `hermes send` to a DM | ✅ (three sends today) |
| `hermes send --to telegram:<chat>:<thread>` into a topic | ✅ delivered into the Swordfish topic (chat `-1004431865496`, thread `2`) |
| observe-without-reply group mode | ✅ founder's unmentioned "Status please" arrived `observed=1`, agent silent; wired by `provisioning/hermes/e1-observe-mode.sh` |
| **full E2E loop** | ✅ founder topic message → observed row → pulled by syd4 → injected into live session → agent reply sent back into the topic (manual run of exactly what the poller automates) |
| turn latency expectation | ℹ️ reply time = agent turn time (rehearsal one-liner took ~60 s at xhigh effort) — set founder expectation, not a bug |

**Post-validation findings:** (a) a gateway restart auto-resumes interrupted
sessions by injecting an empty user turn — the poller's sender check +
non-empty-text check both already exclude these rows, keep both. (b) hermes
currently HAS terminal access on syd3 (it ran `nslookup` when the founder
posted "ping-e1") — drifts from the E0 "terminal disabled" posture; flagged
in NEEDS-STEVEN. (c) Telegram tags observed rows `[name|user_id]` — the
poller matches on the embedded user_id, not display name.

## Build list (after design sign-off)

1. `provisioning/workstation/relay/relay-poller` (+ systemd unit, timer or
   long-poll service) — watermark, sender check, mapping, injection, ledger.
2. Stop-hook script + user-level hooks entry in `~/.claude/settings.json`
   on syd4; marker protocol.
3. `install-hermes-syd3.sh` gains the three observe-mode env lines (single
   idempotent block) + gateway restart.
4. relay-map.yml (untracked) seeded with swordfish; thalon added at its
   wake-up (next session).
5. Provenance line added to each allow-listed project's handoff.
6. Dashboard: "last relay" line on the hermes card from the ledger.
7. Rehearsal-grade E2E: founder topic message → swordfish session → reply in
   topic; then delete `~/e1-rehearsal`.

## Founder decisions still open

- Topic set at launch: swordfish only, or pre-create topics for every
  project now (empty topics cost nothing)?
- Poll cadence (default: 5 s).
- Kill switch wording in NEEDS-STEVEN (one founder line:
  `ssh syd4 sudo systemctl stop swordfish-relay.timer`).
