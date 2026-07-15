# Hermes pilot on syd3 — E0 (eyes) → E1 (conversational relay)

Chartered: Checkpoint-1 amendment 6 ladder + Bucket-5 in-flight record (LLM =
founder's Vercel AI Gateway, Groq-hosted Llama 3.3-class, **US$10/mo hard cap**,
expected <$1). Pull-forward to syd3 pre-cutover = founder decision 2026-07-11
(charter amendment queued for next checkpoint). Full design:
`agent_handoff/archive/founder-interface-plan-2026-07-11.md`.

Upstream: [nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent)
(MIT — hot-path licensing OK). Own repo assessment: `research/2026-07-07-vps-ops-research.md` §11
— its own docs say *treat it like SSH access*; that is why the posture below exists.

## Posture (invariant at E0 — never loosened without the ladder)

| Knob | Setting | Why |
|---|---|---|
| OS user | `hermes`, NO sudo, own home | agent compromise ≠ box compromise |
| Sender gate | `TELEGRAM_ALLOWED_USERS` = founder ID only | leaked bot token alone grants nothing |
| Strangers | `unauthorized_dm_behavior: ignore` | no pairing offers to randoms |
| Terminal tool | DISABLED at E0 | E0 = eyes: briefings + triage, no shell |
| Approvals | `mode: manual`, `cron_mode: deny` | any future command needs a founder tap |
| Yolo | never (`/yolo` counts as loosening) | hardline blocklist is not a substitute |
| Lazy installs | `allow_lazy_installs: false` | no runtime pip supply-chain surface |
| LLM | gateway key only | no Anthropic key, no spend-capable keys |
| Content | swordfish-cockpit context only | guarded portfolio names never near it |

E1 adds exactly ONE allowlisted command: the relay script that feeds founder
messages into per-project Claude Code sessions on syd4 (see the plan doc — the
approval model lives there). E2 only if E1 earns it.

## Install (run from syd3 as deploy)

    cd ~ && bash /path/to/install-hermes-syd3.sh   # idempotent skeleton

The script stops before enabling the service until the founder inputs are in
`/home/hermes/.hermes/.env`: Telegram bot token (the HERMES bot — a DIFFERENT
bot from the alerts bot, so a compromised workload box never holds a token
that can command the cockpit agent), founder's Telegram user ID, and the
Vercel AI Gateway key. Then:

    sudo systemctl enable --now hermes-gateway.service
    journalctl -u hermes-gateway -f   # watch first contact

## VERIFY — first install actuals (2026-07-11, hermes-agent 0.18.2 on syd3)

- [x] launcher lands at `~/.local/bin/hermes` (assumed path was right)
- [x] service command is **`hermes gateway run`** (foreground) — `gateway
      start` targets hermes's OWN `gateway install` service, which we skip;
      our root-managed system unit supervises `run` instead
- [x] upstream installer CREATES `config.yaml`/`.env`/`SOUL.md` from its
      templates → posture/identity are marker-guarded APPENDS after install
- [x] Telegram gateway is long-polling by default (outbound 443 only; webhook
      only if TELEGRAM_WEBHOOK_URL set) — fits the inbound-22-only box
- [x] `TELEGRAM_HOME_CHANNEL` (founder chat id) = cron/briefing delivery target
- [x] E0 toolset applied via `hermes tools disable terminal code_execution
      computer_use browser file skills delegation image_gen tts vision` —
      survivors: web, todo, memory, session_search, clarify, cronjob
- [x] RAM: 1.5 GB available at idle post-install (2 GB box carries E0)
- [x] installer extras: ffmpeg skipped (needs sudo; E0 needs none), Playwright
      Chromium ~300 MB downloaded into `~hermes/.cache/ms-playwright` —
      unused with browser tool disabled; delete if disk ever matters
- [x] telegram adapter needs the **`[messaging]`** extra (runtime hint names a
      nonexistent `[telegram]` extra — stale upstream); install with uv, not
      pip (uv venvs ship no pip): `uv pip install --python ./venv/bin/python
      ".[messaging]"` from `~/.hermes/hermes-agent`
- [x] LLM wiring — four traps, all hit on first enable:
      1. **Edit config ONLY via `hermes config set`** — the CLI normalizes and
         rewrites config.yaml on every tools/config command, so sed against
         template text silently matches nothing (cost us the first hour).
      2. **`model.api_key` must be set IN config** — the gateway runtime does
         not honor the `OPENROUTER_API_KEY`/`OPENAI_API_KEY` env fallback for
         `custom` providers ("Missing Authentication header" from the gateway
         while the same key curls fine). chmod 600 config.yaml after.
      3. **`model.max_tokens` must sit under the provider's output cap**
         (2048 is safe) — default blows past it and every call 400s.
      4. **Llama 3.3-70b cannot drive Hermes's tool schema** (Groq-style
         `failed_generation` on function calls) — default is
         `openai/gpt-oss-120b`: price-equivalent class, strong tool calling.
         Charter budget frame unchanged (US$10/mo cap).
      Key validated against /v1/models (309 visible); gateway routes with
      automatic provider failover (observed: bedrock primary, groq fallback).
- [x] on-box one-shot test exists: `hermes -z "<prompt>"` — proves the whole
      agent path without a phone round-trip
- [x] first founder message answered end-to-end 2026-07-11 (Telegram → gateway
      → gpt-oss-120b → reply; founder-confirmed)
- [x] cron `morning-briefing` created (job 0581352d8f6d, `0 21 * * *` UTC =
      07:00 Sydney, delivers to the founder's Telegram; test run fired at
      creation). Content v0 = public endpoints only (hello./status.) — grows
      real metrics (Kuma/Beszel/healthchecks read APIs) post-cutover.
- [x] **trap 5 — founder bot-actions are journal-invisible and look exactly
      like scheduler bugs** (hit 2026-07-13): job 0581352d8f6d's 2026-07-11
      21:00 UTC run delivered, but its gateway session hung afterwards
      (orphaned CLOSE-WAIT to the AI gateway; journal silent from that moment;
      the next restart pruned it as "left by a crashed gateway"). Then
      `jobs.json` emptied at 2026-07-12 01:36 UTC with zero journal trace —
      first read as scheduler stale-claim cleanup, actually **the founder
      stopping the reminder himself from Telegram** (clarified 2026-07-13:
      adapter-level bot commands write job state without journald lines).
      Lesson: before diagnosing a silent state change on a founder-facing
      system, ask the founder first. Detection of a genuinely dead schedule:
      `hermes cron status` + `hermes cron list` (empty = nothing will fire),
      or journal silence spanning a scheduled fire. Recovery (verbatim, as
      `hermes` user; recreated as job d8e6bb992d5e):

          sudo systemctl restart hermes-gateway   # clears the hung thread
          hermes cron create --name morning-briefing --deliver telegram \
            "0 21 * * *" \
            "Morning briefing v0 (public endpoints only, grows real metrics post-cutover). Using the web tool, check these two public endpoints: https://hello.swordfish.cfd (healthy = HTTP 200) and https://status.swordfish.cfd (healthy = HTTP 302 redirect to its login page). Report each as OK or PROBLEM with the HTTP status observed. Then send exactly ONE short Telegram message: one line per endpoint plus a one-line overall summary. Under 10 lines total. No follow-up questions."
          hermes cron run <new-job-id>            # test fire → founder's phone

      The create command was NOT recorded verbatim the first time and proved
      unrecoverable (creating session lived on the laptop; hermes session
      dumps hold only error requests) — hence it is pinned here now. Standing
      check: after any missed 07:00 Sydney briefing, run the detection pair
      above BEFORE suspecting Telegram or the LLM.

## E0 is LIVE (2026-07-11). Next rung: E1

E1 = the conversational relay to Claude Code on syd4 (one allowlisted command,
manual approvals for everything else) — design in
`agent_handoff/archive/founder-interface-plan-2026-07-11.md`. Verdict gate per charter:
2–4 weeks at E0/E1 → keep or drop.

## Rebuild path

syd3 cloud-init does NOT carry Hermes (external installer + secrets can't be
pinned). Rebuild = re-run this script + refill .env. The verdict gate
(charter): 2–4 weeks at E0/E1 → keep or drop.
