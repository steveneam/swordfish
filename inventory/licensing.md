# Licensing ledger

> AGENTS.md "Licensing hygiene" is the rule; this page is the record. One row per
> tool/dependency whose license needs a judgement call. MIT/Apache/BSD/CC0 hot-path
> tools don't need rows unless something else is notable.

| Tool | License | Judgement | Swap path |
|---|---|---|---|
| Renovate (Mend hosted app) | AGPL-3.0 | **Service-use only** — the app runs on Mend's infra and opens PRs; no AGPL code is embedded in this repo (Bucket 1.5) | Self-host renovate runner (AGPL obligations then apply to any modifications) or manual pin bumps |
| zizmor | MIT | Clean; runs in CI only | — |
| Dokploy | Apache-2.0 | Clean (ADR 0001) | Coolify / raw compose (documented, not pending) |
