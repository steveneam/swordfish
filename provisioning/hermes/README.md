# Hermes pilot on syd3 — E0 (eyes) → E1 (conversational relay)

Chartered: Checkpoint-1 amendment 6 ladder + Bucket-5 in-flight record (LLM =
founder's Vercel AI Gateway, Groq-hosted Llama 3.3-class, **US$10/mo hard cap**,
expected <$1). Pull-forward to syd3 pre-cutover = founder decision 2026-07-11
(charter amendment queued for next checkpoint). Full design:
`agent_handoff/founder-interface-plan-2026-07-11.md`.

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

## VERIFY on first install (upstream surface may drift from this skeleton)

- [ ] installer path + `hermes` binary location (`~/.local/bin/hermes` assumed)
- [ ] exact gateway start command (`hermes gateway start` assumed)
- [ ] exact .env keys for OpenAI-compatible endpoint (base URL + key)
- [ ] `hermes tools` command to disable the terminal tool at E0
- [ ] RAM headroom on the 2 GB box (`free -m` before/after; E0 gateway only)
- [ ] cron morning-briefing job created and delivered once

Record actuals back into this README + the install script same session
(operating rule 9: capture what worked, in the same session).

## Rebuild path

syd3 cloud-init does NOT carry Hermes (external installer + secrets can't be
pinned). Rebuild = re-run this script + refill .env. The verdict gate
(charter): 2–4 weeks at E0/E1 → keep or drop.
