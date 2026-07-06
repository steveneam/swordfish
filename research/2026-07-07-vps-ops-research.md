# VPS ops research — 2026-07 best-practices pass

_Researched 2026-07-07 (Bucket-1 checkpoint session). Portfolio-reusable: findings are generic
VPS/DevOps practice; Swordfish-specific decisions taken from them are in `CHARTER.md`
(Checkpoint-1 amendments) and `inventory/decisions.md`. Guarded-token rule applies: migration
targets are only ever Project 1 / 2 / 3._

## 0. Verdict on the current stack

The 2026 consensus **validates every ADR-0001 / charter pick** — none need re-opening:

- **Dokploy** over Coolify: confirmed lighter (~450–700 MB idle vs heavier Coolify), better
  monitoring, buildpack flexibility. Coolify's edge (280+ templates, bigger community) is not
  needed here. **Komodo** (Rust, fleet-oriented multi-server orchestration) is the new third
  option — added to the documented swap paths, not adopted.
- **Beszel + Uptime Kuma** is the exact pair independent 2026 comparisons recommend for
  1–20 servers: ~150–180 MB total vs 800+ MB for Prometheus/Grafana doing the same job.
  Beszel agent ≈ 10 MB vs Netdata's 200–500 MB; Netdata only when deep-diving one host.
- **fail2ban now, CrowdSec at fleet**: consensus is fail2ban is the *better* engineering
  choice for a single box (less machinery to break); CrowdSec wins decisively across a fleet
  (shared bans, community blocklist, nftables IP sets). Graduation trigger = box #2.
- **restic → B2** remains the small-fleet backup standard; **OpenTofu** is now clearly the
  right Terraform fork (native client-side state/plan encryption since v1.7 — Terraform never
  shipped it; provider `for_each`; 3,900+ providers incl. Vultr + Hetzner; ~12% adoption,
  growing via new projects exactly like this one).
- **dev-sec ansible-collection-hardening** (Apache-2.0) actively maintained, Ubuntu 24.04
  supported — the box-#2 hardening graduation stands.

## 1. The one real gap: Docker silently bypasses ufw

**Any container published on `0.0.0.0` is internet-reachable regardless of ufw.** Docker's NAT
rules route published-port traffic through the FORWARD chain; ufw only manages INPUT, so its
rules are never consulted. This is the most-cited self-hosting security hole of 2026.

Mitigations, strongest first:

1. **Provider cloud firewall** (Vultr firewall groups are free, API-scriptable): enforced
   outside the OS — Docker cannot bypass it. First line of defense; also DDoS-adjacent.
2. **Publish no app ports** (Traefik-only 80/443) — but make it *executable*: a CI assertion
   that `docker ps` shows no `0.0.0.0` publishes besides Traefik's 80/443.
3. Bind host-local services to `127.0.0.1`.
4. `DOCKER-USER` iptables chain / [chaifeng/ufw-docker](https://github.com/chaifeng/ufw-docker)
   for finer control (fallback tooling; not needed if 1–3 hold).

## 2. Host layer additions (beyond the Bucket-1 baseline)

- **Docker `daemon.json`**: `json-file` log driver with `max-size`/`max-file` caps (unbounded
  container logs filling the disk is the #1 self-hosted failure mode) + `live-restore: true`
  (containers survive daemon restarts/upgrades).
- **Kernel updates need a reboot policy**: unattended-upgrades installs kernel packages but
  never reboots, so they don't take effect. Options: `Unattended-Upgrade::Automatic-Reboot`
  in a maintenance window (with uptime monitoring watching), or Ubuntu Pro Livepatch.
  **Ubuntu Pro free tier** (≤5 machines, incl. Livepatch + `usg` CIS audit tooling for 24.04)
  is technically a perfect fit but is licensed "for personal use" — a terms judgment call.
  *Decision here: reboot window, no Pro attach (revisit if the fleet earns paid Pro).*
- **Audit as CI ratchets, not daemons**: run [ssh-audit](https://github.com/jtesta/ssh-audit)
  (crypto/config grade) and optionally [Lynis](https://github.com/CISOfy/lynis) against live
  boxes from the existing smoke workflow on a schedule. Zero on-box RAM; executable-tier
  ratchet. auditd/AIDE deferred to the dev-sec graduation (noise generators on a 2 GB box
  nobody tails).

## 3. Edge layer (reverse proxy + control plane)

- **docker-socket-proxy pattern confirmed** as best practice; the details that matter:
  proxy on its **own internal network** (only the proxy consumer joins; no internet route),
  grant **only** `CONTAINERS=1` (events/exec/volumes/POST denied by default),
  `no-new-privileges:true` + `read_only` on the proxy and edge containers.
  Alternatives: [wollomatic/socket-proxy](https://github.com/wollomatic/socket-proxy)
  (Go, regex ACLs, read-only non-root) and the linuxserver fork.
- **Traefik hardening**: security-headers + HSTS middleware, TLS 1.2+ modern ciphers as
  *tracked dynamic config*; JSON access logs so fail2ban (later a CrowdSec bouncer) can watch
  the HTTP layer, not just sshd.
- **Dokploy operational intel (2026)**: multiple reports of Dokploy *updates* breaking or
  removing its managed Traefik (404s fleet-wide, Traefik container gone). Version-pinning is
  therefore load-bearing, and `/etc/dokploy` + Traefik config must be in the backup set
  **before** any deliberate upgrade. RAM: core idles ~450–700 MB, can grow toward ~950 MB;
  2 GB runs Dokploy but not Dokploy + heavy workloads + on-box builds. CI-side builds dodge
  the worst; expect the resize gate at graduation. Cheap insurance: 1–2 GB swap + zram.

## 4. Backups

- **Dead-man's switch** is the standard pattern: the backup job pings a URL *on success
  only*; the watcher alerts when pings stop (silence = the problem). Uptime Kuma's **push
  monitor** does exactly this (and is already in the stack); healthchecks.io free tier is the
  off-infra witness that still fires when the whole box dies. Use both.
- **`restic check --read-data-subset=10%`** weekly alongside forget/prune — catches silent
  repo corruption *between* restore drills rather than at them.
- **[resticprofile](https://github.com/creativeprojects/resticprofile)** (config-as-code
  wrapper: retention, hooks, healthchecks pings, systemd scheduling in one tracked YAML) —
  one ratchet rung above a hand-rolled timer script. [Backrest](https://github.com/garethgeorge/backrest)
  (leading restic web UI) deliberately skipped: UI = documentary-tier convenience + attack
  surface, and it's GPLv3.
- **Pre-backup hooks for stateful services**: file-level backup of a running database volume
  is not a consistent backup — `pg_dump` (etc.) first.

## 5. Monitoring + image-update flow

- **Uptime Kuma kept**; [Gatus](https://github.com/TwiN/gatus) (Apache-2.0) is the documented
  swap path — functionally similar but configured from YAML in git (configuration-tier ratchet)
  where Kuma is click-state in SQLite. Kuma wins here because its push monitor doubles as the
  backup dead-man switch and its notifier/status-page UX is stronger.
- **Watchtower is discontinued.** With digest-pinned images the correct flow is:
  **Renovate opens PRs** bumping digests/tags in tracked compose files → CI → deploy.
  [Diun](https://github.com/crazy-max/diun) (notify-only, ntfy-compatible) optional for
  on-box drift alerts. Note: Renovate relicensed to **AGPL-3.0** — service-use (hosted app /
  CI runner) embeds nothing in the repo; flagged on the licensing ledger.

## 6. CI supply chain — where 2026 actually moved

**Case study: trivy-action compromise (2026-03).** 75 of 76 version tags force-pushed to
exfiltrate CI secrets from every pipeline running a Trivy scan; stolen credentials cascaded
into PyPI compromises. Per Datadog, 71% of orgs pin no actions. A CI runner holding a box SSH
key means *a compromised action is a box compromise*. Controls:

- **SHA-pin every GitHub Action** (full commit SHA; tag in a comment for readability) —
  the only immutable reference. Renovate maintains the pins, killing the staleness objection.
- **[zizmor](https://github.com/zizmorcore/zizmor)** (MIT/Apache) as a CI job: static analysis
  of workflow YAML — unpinned actions, template injection, dangerous triggers, 24+ rules.
- Default `permissions: read-all` on workflows; deploy-key jobs tightly scoped;
  environment-scoped secrets.
- When image scanning lands (Trivy at the GHCR image bar): pin the action by SHA and the
  scanner image by digest — the ironic lesson of the incident.

## 7. Secrets + IPS + admin plane (later-bucket notes)

- **Infisical at box #2 validated** (best self-hosted DX 2026, $0 self-hosted). Caveat: no
  native credential *rotation* — still Vault territory, and Vault is enterprise-priced now.
  sops+age remains the zero-infrastructure documented alternative and is honestly enough for
  a 2-box fleet if Infisical ever feels heavy.
- **CrowdSec** joins the box-#2 graduation triggers: fleet-shared bans + Traefik bouncer.
  Wazuh = overkill at this scale.
- **Tailscale works entirely over 443** (DERP relays + HTTPS control plane) → real break-glass
  SSH from a 22-blocked network: `ufw allow from 100.64.0.0/10 to any port 22`, eventually
  close public 22. Documented upgrade; the corporate-laptop install probe is founder-optional
  (IT-policy risk). Cloudflare Tunnel is the alternative outbound-443-only channel.

## 8. Provider assessment: Hetzner vs Vultr

**For syd1: Vultr was right; no regrets.** Hetzner has **no Australia region** (DE, FI, 2× US,
SG); Sydney→Singapore ≈ 90–120 ms on every control-plane interaction, and any AU-residency
requirement (Project 1) rules it out. The famous Hetzner bandwidth win **evaporates in APAC**:
SG (and now US) plans include only ~1–2 TB, not the EU 20 TB.

**Where Hetzner re-enters: the high-egress bucket (Project 3 render offload).** EU boxes:
3–5× cheaper compute than US-headquartered providers (€6.49/mo ≈ Vultr's $40 tier),
**20 TB included traffic**, overage ~€1/TB vs ~$10/TB at US providers, cheap ARM (CAX).
That workload is latency-tolerant and stateless — Hetzner-EU's exact sweet spot. Soft caveats:
signup ID verification, tail-risk of abrupt account closures, fewer managed services, NVMe
IOPS below Vultr's high-frequency tier. The OpenTofu graduation (box #3+) makes multi-provider
nearly free to support — keep Hetzner in the Bucket-7 provider matrix.

## 9. The cloud layer — hybrid integration pattern

The architecture 2026 literature converges on, and the one already in place: **boxes are
stateless-rebuildable compute; every stateful or trust-anchoring concern lives one layer up.**
That separation is what makes `swordfish provision <box>` a rebuild, not a recovery.

| Cloud service | Role relative to the boxes |
|---|---|
| GitHub Actions + GHCR | The hands + the image supply chain (no local Docker) |
| Backblaze B2 | Off-box, **off-provider** backup target — survives a provider-account catastrophe |
| Porkbun DNS | Traffic steering; DR lever (repoint A-record at a rebuilt box) |
| UptimeRobot / ntfy.sh / healthchecks.io | Off-infra witnesses — monitoring that doesn't die with the box |
| Vultr firewall group (free) | Provider-side packet filter outside the OS — the layer Docker can't bypass |
| Cloudflare (documented upgrade) | DDoS/WAF (orange-cloud → DNS-01 caveat), Tunnel as 443-only admin channel |
| Cloudflare R2 (Bucket-7 matrix) | Zero-egress object storage for served artifacts |

**Object-storage economics split by workload**: B2 ($6/TB/mo, cheapest at-rest, free egress to
3× stored, free entirely via Cloudflare CDN) = *backups* (write-heavy, restore-rarely).
R2 ($0.015/GB but **zero egress, ever**) = *served artifacts* — render outputs downloaded
repeatedly are the textbook R2 case, and R2 decouples the artifact store from whichever
provider's box rendered them.

## 10. Tool shortlist (license-checked)

| Tool | License | Role | When |
|---|---|---|---|
| tecnativa/docker-socket-proxy | Apache-2.0 | Socket firewall for Traefik | Bucket 2 |
| wollomatic/socket-proxy | MIT | Stricter swap path (regex ACLs) | documented |
| zizmor | MIT/Apache-2.0 | GH Actions workflow lint | Bucket 1.5 |
| Renovate (hosted app) | AGPL-3.0 (service-use only) | Maintains SHA/digest pins via PRs | Bucket 1.5 |
| ssh-audit | MIT | CI crypto grade of live sshd | Bucket 2 |
| Lynis | GPL-3.0 (run, not embedded) | Scheduled host audit | optional |
| resticprofile | GPL-3.0 (run, not embedded) | Config-as-code restic wrapper | Bucket 3 |
| healthchecks.io | free tier (BSD-3 if self-hosted) | Off-infra dead-man witness | Bucket 3 |
| Gatus | Apache-2.0 | Config-as-code Kuma swap path | documented |
| Diun | MIT | Notify-only image-update alerts | optional |
| CrowdSec | MIT | Fleet IPS + Traefik bouncer | Bucket 6 |
| Infisical | MIT (core) | Secrets manager | Bucket 6 |
| dev-sec hardening collection | Apache-2.0 | Ansible os/ssh hardening | Bucket 6 |
| OpenTofu | MPL-2.0 | IaC with state encryption | Bucket 8 |
| Komodo | GPL-3.0 (run, not embedded) | Fleet-orchestration swap path | documented |

## 11. Hermes Agent — assessed as a future dogfood workload, not a build tool

[Hermes Agent](https://github.com/nousresearch/hermes-agent) (Nous Research, Feb 2026, MIT,
~64k stars): open-source always-on AI agent — persistent memory, self-improving skills loop,
40+ tools, OpenAI-compatible API, one gateway daemon serving Telegram/Discord/Slack/WhatsApp/
Signal/email. Terminal backends: local shell, Docker, SSH, Modal/Daytona serverless.
Min footprint ~1 vCPU / 2 GB + Docker + an LLM API key (ongoing spend).

**Security reality:** its own docs say to treat it like SSH access. Skills are *not*
sandboxed — they run with the agent's permissions, and the self-improving loop means an
agent with shell access is a prompt-injection amplifier (messages/web content → skill →
shell). There is a command-approval feature, but the design assumes a trusted environment.

**The benefits case (researched at founder request — what it actually offers):**

- **Runs while you sleep — built-in cron with delivery to any platform.** Scheduled health
  checks, a morning briefing to Telegram ("disk, RAM, backup ping, cert expiry, anomalies"),
  recurring reports, reactive alert triage — the steady-state ops loop a solo founder can't
  staff. This is the genuinely differentiated feature vs. session-based agents.
- **Skills turn runbooks into one-liners.** It builds procedural skills from experience —
  "rotate that cert", "clear logs", "restart the status stack" become reliable one-line
  requests. Skills are portable (agentskills.io standard) — reusable across the portfolio.
- **Real ecosystem for infra tasks:** Cloudflare ships official agent Skills + MCP servers;
  Composio provides a Cloudflare toolkit; a built-in domain-intel skill does DNS/WHOIS/SSL
  inspection (read-only by nature). MCP tool *filtering*, command-approval mode, and
  container isolation are the exact knobs a bounded deployment needs.
- **Fleet-capable:** SSH/Docker terminal backends can run diagnostics and deploys across
  boxes — relevant at Stage 3+ when there are multiple boxes.
- **Model-agnostic:** Nous Portal, OpenRouter, OpenAI, or any endpoint; always-on gateway
  idles cheap, LLM spend accrues per task.

**Claims vs. this stack:** the viral demos — buy a domain, set DNS, issue SSL, configure
NGINX/PM2 — are the *provisioning* story, and on Swordfish that job is already done better:
idempotent gated scripts + CI are reproducible and auditable where a conversational agent is
neither (and NGINX/PM2 is the demo stack; ours is Traefik/Dokploy). Hermes's marginal value
here is **steady-state operations**, not box-building. Provisioning stays scripts; the moat
stays `provisioning/`.

**Fit assessment (updated after the benefits pass):**

- **During building: no.** Builds happen in Claude Code + CI; an extra autonomous agent with
  chat/web channels holding portfolio context is an anonymity-guard liability (same trust
  boundary as the wiki agent — names from outside are guarded until proven otherwise).
- **After launch: yes — via a graduated-autonomy pilot** (revisit at the Bucket-4/5
  checkpoint):
  - **E0 · Eyes** — read-only observability APIs (Beszel/Kuma/restic status) + ntfy publish;
    cron morning briefing + alert triage to Telegram over 443. No shell, no socket, no SSH.
  - **E1 · Propose** — command-approval mode ON: it drafts runbook commands, the founder
    approves each mutation from the phone. Still no standing credentials.
  - **E2 · Constrained hands** — only if E1 earns it: scoped exec on *dogfood workloads only*
    (restart status stack, clear logs, rotate a cert), approval retained for mutations.
  - **Never:** provider keys with spend power (box/domain purchase stays founder-gated),
    guarded-token-adjacent content, docker socket on a shared box, provisioning authority.
- **Portfolio angle:** each project could run its own instance on its own side (separation
  of duties holds — Swordfish provisions the box, never wires the agent into their apps).
  Also a candidate for the "Walter/vault service" dogfood slot.
- **Timing + cost:** it's a workload → invariants apply: nothing before Bucket-3 backups,
  and 2 GB won't carry Dokploy + monitoring + Hermes — post-Bucket-5 resize. Deploy through
  Dokploy (itself a dogfood test). LLM API budget = Approval Gate. Pilot verdict after
  2–4 weeks at E0/E1: keep (fewer founder round-trips) or drop (cost/noise/safety).

## Sources (primary)

- ufw bypass: [zeonedge.com](https://zeonedge.com/blog/ufw-docker-firewall-bypass-fix) · [chaifeng/ufw-docker](https://github.com/chaifeng/ufw-docker) · [Vultr firewall docs](https://docs.vultr.com/products/network/firewall)
- Edge: [Traefik socket-proxy hardening](https://www.simplehomelab.com/traefik-docker-security-best-practices/) · [Dokploy RAM sizing](https://massivegrid.com/blog/best-vps-for-dokploy/) · [Dokploy Traefik-update issue #4245](https://github.com/Dokploy/dokploy/issues/4245) · [PaaS comparison](https://haloy.dev/blog/self-hosted-deployment-tools-compared)
- Host: [fail2ban vs CrowdSec](https://itrpoka.com/blog/fail2ban-vs-crowdsec/) · [dev-sec collection](https://github.com/dev-sec/ansible-collection-hardening) · [Ubuntu Pro](https://ubuntu.com/pro)
- Backups: [restic + healthchecks](https://nerdyarticles.com/backup-strategy-with-restic-and-healthchecks-io/) · [restic GUI roundup](https://usepluton.com/blog/best-restic-gui-2026/)
- Monitoring: [2026 monitoring comparison](https://instapods.com/blog/best-server-monitoring-tools/) · [Watchtower discontinued](https://linuxhandbook.com/blog/watchtower-like-docker-tools/)
- Supply chain: [trivy-action compromise](https://thehackernews.com/2026/03/trivy-security-scanner-github-actions.html) · [CrowdStrike analysis](https://www.crowdstrike.com/en-us/blog/from-scanner-to-stealer-inside-the-trivy-action-supply-chain-compromise/) · [Wiz GH Actions guide](https://www.wiz.io/blog/github-actions-security-guide) · [Renovate docker pinning](https://docs.renovatebot.com/docker/)
- IaC/secrets: [OpenTofu adoption guide](https://www.env0.com/guides/opentofu-adoption-guide-state-encryption-provider-for-each-and-features-terraform-doesnt-have) · [secrets tooling 2026](https://infisical.com/blog/best-secret-management-tools)
- Hermes Agent: [repo](https://github.com/nousresearch/hermes-agent) · [docs](https://hermes-agent.nousresearch.com/docs/) · [use cases](https://www.hostinger.com/tutorials/hermes-agent-use-cases) · [Cloudflare agent setup](https://developers.cloudflare.com/agent-setup/) · [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent)
- Providers/cloud: [Hetzner vs Vultr](https://getdeploying.com/hetzner-vs-vultr) · [Hetzner review](https://betterstack.com/community/guides/web-servers/hetzner-cloud-review/) · [R2 vs S3 vs B2](https://tech-insider.org/cloudflare-r2-vs-s3-vs-backblaze-b2-2026/) · [B2 pricing](https://www.backblaze.com/cloud-storage/pricing) · [Tailscale ports](https://tailscale.com/kb/1082/firewall-ports)
