# COORDINATION — lane board

> Parallel-lane ledger (protocol summary: `AGENTS.md` rule 10). **One writer per row** — the lead owns assignments + merge-order; each owner writes only its own `status`. Messages append-only. Status vocab: `pending · in_progress · blocked:<what> · review · merged`. **Contract** for this repo = provisioning-script interfaces + `compose/` templates + the `inventory/` schema — frozen per sprint once committed; a lane needing a mid-flight contract edit = re-plan, not an ad-hoc edit. Merges serialize through `main` in merge-order: rebase → CI green (guard + any tests) → review → merge; never on red. Worktree lanes receive gitignored context (vault pointer, env) via `.worktreeinclude`.

## Lanes

*(none yet — the board activates when the charter cuts file-disjoint buckets, e.g. `provisioning/` vs `compose/` vs `runbooks/`)*

| lane | owner | owns (glob) | branch | status | depends-on | merge-order |
|------|-------|-------------|--------|--------|------------|-------------|

## Messages (append-only)

- 2026-07-07 bootstrap: board created with the repo skeleton. First lanes get cut at the Stage-1 charter if its buckets are file-disjoint.
- 2026-07-13 **Mode B is now crash-proof.** `agent-term` (code-server's default terminal profile; canonical `provisioning/host/setup-qol.sh`) lands every terminal in a tmux session named after its folder, claude auto-started. Founder-opened lane terminals therefore survive window/browser crashes — reopening the folder's terminal reattaches to the live lane; `work` (ssh) converges on the same folder-named session. This removes Mode B's old fragility (a bare-pty lane died with its window); all-N-concurrent lanes are now as durable as in-session worktree subagents.
