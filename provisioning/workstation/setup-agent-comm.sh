#!/usr/bin/env bash
set -euo pipefail

# setup-agent-comm.sh - idempotent converge for the live cross-agent
# coordination tool (founder call 2026-07-19). Installs:
#   /usr/local/bin/agent-comm            (root-owned copy of agent-comm.sh)
#   /var/lib/swordfish/agent-comm/       (deploy-owned ledger home)
#   ~/.claude/skills/live-comm/SKILL.md  (user-level skill -> EVERY agent on
#                                         this box sees it; one copy, no per-
#                                         repo distribution to keep in sync)
# then proves the refusal invariants with checks/assert-agent-comm.sh.

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/agent-comm.sh"
BIN=/usr/local/bin/agent-comm
LEDGER_DIR=/var/lib/swordfish/agent-comm
SKILL_SRC="$HERE/skills/live-comm/SKILL.md"
SKILL_DST="$HOME/.claude/skills/live-comm/SKILL.md"

changed=0

if ! sudo -n cmp -s "$SRC" "$BIN" 2>/dev/null; then
  sudo -n install -m 0755 -o root -g root "$SRC" "$BIN"; changed=1
fi

if [ ! -d "$LEDGER_DIR" ]; then
  sudo -n install -d -m 0755 -o deploy -g deploy "$LEDGER_DIR"; changed=1
fi

mkdir -p "$(dirname "$SKILL_DST")"
if ! cmp -s "$SKILL_SRC" "$SKILL_DST" 2>/dev/null; then
  install -m 0644 "$SKILL_SRC" "$SKILL_DST"; changed=1
fi

bash "$HERE/../checks/assert-agent-comm.sh" >/dev/null \
  || { echo "== ABORT: assert-agent-comm.sh FAILED - not converged"; exit 1; }

if [ "$changed" -eq 0 ]; then echo "== converged: no changes (asserts green)"
else echo "== converged: agent-comm installed (asserts green)"; fi
