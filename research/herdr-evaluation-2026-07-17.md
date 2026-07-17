# herdr — evaluation for the swordfish fleet (2026-07-17)

_Founder ask: "have a read of herdr and see if it would be useful for our vps,
given what I want to achieve." Source: https://herdr.dev · repo
`ogulcancelik/herdr`._

## Verdict: **don't adopt.** Not because it's weak — because we already built it, and its one real differentiator targets a workflow the founder deliberately abandoned.

This is a genuinely good project. The recommendation is about *fit*, not quality.

## What it is

An **agent multiplexer**: tmux, but agent-aware. One Rust binary, self-hosted,
no account, no telemetry, no cloud.

| | |
|---|---|
| License | **AGPL-3.0-or-later**, dual-licensed (commercial available) |
| Maturity | **v0.7.4** (2026-07-15) — pre-1.0, 69 open issues, moving fast |
| Traction | 17.3k stars / 1.1k forks — real, not vapour |
| Install | `curl \| sh`, brew, mise, binary |
| Does | persistent panes · agent state (blocked/working/done/idle) · SSH + thin-client attach · CLI + JSON socket API · 150+ plugins · usable from a phone over SSH |
| Does **not** do | provisioning · backups · monitoring · TLS/DNS · **any messaging integration** |

## The licensing question, answered — it's a non-issue, and here's why

`AGENTS.md` says *"No AGPL code embedded in this repo."* That rule does **not**
bar herdr, and it's worth killing this false alarm precisely:

- The rule governs **code embedded in this repository**. herdr would be a
  **tool the operator runs on a box** — the same category as Linux, bash, and
  git, all of which are GPL and all of which the fleet already runs. Installing
  a copyleft tool has never been what that rule is about.
- AGPL's distinguishing §13 network clause triggers when you convey a
  **modified** version to users **interacting with it over a network**.
  Single-operator, tunnel-only use triggers nothing. Unmodified use triggers
  nothing regardless.
- The live constraints would be: **never vendor herdr's source into this repo**,
  never fork-and-distribute, and don't expose a modified instance as a network
  service. All easy, none load-bearing.

So: licensing is **not** the reason to decline. The reasons are below.

## Why it doesn't fit

### 1. We already own ~80% of it, and ours is incident-hardened

| herdr feature | what the fleet already runs |
|---|---|
| sessions survive disconnect | `agent-tmux.service` — tmux under its own systemd cgroup, *specifically* so it survives a `code-server` restart. Bought with the 2026-07-16 incident that killed every agent. |
| agents reachable remotely | **Hermes E1 relay** — Telegram topics → tmux sessions, hardened founder-id sender gate, Stop-hook reply routing |
| agent state at a glance | cockpit dashboard (fleet-wide `NEEDS-STEVEN.md` ingest) + ntfy alerts carrying expected/unexpected inline |
| one agent per project | per-project tmux sessions + `gogogo` / `CURRENT.md` boot convention |

Adopting herdr means re-litigating a seam that took an outage to get right, in
exchange for features we have.

### 2. Its differentiator is a TUI — the exact thing the founder can't use

This is the decisive point. herdr's value is a **rich, redraw-heavy, full-screen
terminal UI with clickable panes**. But the standing constraint is that the
founder **cannot copy text out of a terminal** — Terminal.app drops the
selection on TUI redraws. That single fact is *why* the fleet runs code-server,
why copy-material goes to `COPY-ME.txt`, and why his commands are one short line.

herdr is maximally redraw-heavy. It would land him back in the exact ergonomic
trap the current architecture was built to escape. **It optimizes for a
terminal-native operator, and he deliberately isn't one** — he drives via
Telegram, code-server buttons, and `gogogo`.

### 3. It has zero messaging integration

Confirmed against its own docs: 15+ agent integrations, **no Telegram, no
messaging**. His primary remote surface is his phone. herdr's phone story is
"SSH into it and use the TUI" — strictly worse than a Telegram topic for
someone who reads alerts while away from a desk. It cannot replace the relay,
so it would be an *additional* layer, not a simplifying one.

### 4. It advances the moat by nothing

`AGENTS.md` rule 9: the moat is reproducible box-building in `provisioning/`.
herdr does no provisioning, backups, monitoring, or TLS. It's an operator
convenience, not product.

### 5. Pre-1.0 in the worst possible seam

v0.7.4, 69 open issues. The agent-session path is the fleet's most
incident-prone seam (07-16 killed every agent). A fast-moving pre-1.0 dependency
there buys risk to solve a problem that isn't hurting.

## The steelman — the one thing herdr does better, and what to do instead

Credit where due: **semantic agent state (blocked/working/done/idle) in one
view** is real, and it's the one place the current stack is genuinely worse.
Today that answer is smeared across three surfaces — tmux tabs, the dashboard,
and ntfy alerts — and "which agent is stuck right now?" has no single home.

But if that pain bites, the fix is **a state column on the cockpit dashboard he
already reads on his phone** — not a TUI he can't copy from. That's a small,
owned change on a surface built for his constraints, versus a new pre-1.0
dependency that still wouldn't reach his phone.

## Recommendation

**No adoption. No spend. No tracked dependency.** Revisit only if (a) the fleet
outgrows one-tmux-session-per-project badly enough that pane management is a
real cost, **and** (b) herdr reaches 1.0, **and** (c) the founder's surface is
still not a terminal — in which case it's still the wrong tool.

If curiosity strikes, it costs nothing to `brew install herdr` on a laptop and
poke it for ten minutes. It changes nothing tracked and commits us to nothing.
That is the appropriate level of investment here.

_Filed under `research/` as a decision record: this question will recur (the
category is crowded and each new entrant looks compelling), and the reasoning —
**own the seam, match the founder's actual surface, don't put pre-1.0 under the
agents** — outlives this particular tool._
