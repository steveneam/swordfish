# NEEDS STEVEN — the founder action queue

> Agent-maintained. One line per OPEN founder action:
> `- [YYYY-MM-DD] text` (date = when it was raised; the dashboard shows age).
> Remove a line ONLY when its source says done — the dashboard renders this
> file verbatim and never invents or retires state on its own.
> ⛔ Guarded project names never go here (tracked file — Project 1/2 only).

- [2026-07-13] Dokploy bookmark: the control plane now lives at **https://deploy.swordfish.cfd** (same login you registered at deploy2 — that name now 404s by design).
- [2026-07-13] ⛔ **SPEND GATE — resize syd2 to 16 GB / 6 vCPU / 180 GB (AUD 78.40/mo, +AUD 39.20)**: this is what lets Project 1's ~41 GB of assets + its compute leave Render. Cancelling Render saves ~US$40/mo, the resize costs ~US$26/mo → **net ≈ US$14/mo CHEAPER than today**, with double the RAM/CPU. Say "resize go" and the agent does it (brief reboot; no data at risk). Detail: `research/capacity-and-data-plan-2026-07-13.md`.
- [2026-07-13] **Do NOT cancel Render yet** — cancel only after Project 1's agent re-seeds the assets onto the box and verifies checksums (nothing is at risk either way: the Render disk is a cache; the real source is that project's private Supabase source-asset bucket).
- [2026-07-13] subscriptions.yml FILL fields (edit the file or tell any agent): Claude → which card; GitHub → next_charge date + which card (from the receipt).
- [2026-07-13] thalon staging: /blog is FIXED and there is now ONE login for everything (site + workspace) — creds refreshed in `~/COPY-ME.txt`; the old second (steven:…) workspace password is retired.
- [2026-07-13] Gmail MCP re-auth (token EXPIRED) — one click in claude.ai settings; unblocks receipt-driven subscriptions.yml fills.
