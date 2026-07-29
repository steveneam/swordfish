# NEEDS STEVEN — the founder action queue

> **Who maintains this: the agents, by hand, at every wrap. Nothing here is
> automatic.** The cockpit dashboard renders these lines verbatim and
> deliberately never invents or retires state on its own — so a line stays up
> until an agent removes it. That is why it grows: we add reliably and prune
> rarely. **The rule from 2026-07-29: when an item is done, it moves to
> `archive/NEEDS-STEVEN-closed.md` in the SAME wrap — it does not sit here
> wearing a ✅.** Run `checks/needs-steven-hygiene.sh` to see what has gone stale.
>
> One line per OPEN founder action: `- [YYYY-MM-DD] text` (date = when raised;
> the dashboard shows age). **Keep the `]` immediately after the date** — the
> collector keys on it. Ordered below by how long it takes you, not by age.
>
> Every project's queue feeds the same dashboard card
> (`~/work/*/agent_handoff/NEEDS-STEVEN.md`), so what you see is swordfish's
> lines plus thalon's and eamos's.

## ⚡ Quick — a one-line yes, or one click

- [2026-07-29] 📱 **Did a test alert reach your phone ~07:52 UTC today (title "Kuma alert-path test", 🤖 EXPECTED)?** One word closes the last unknown in the alerting-gap diagnosis: Kuma monitors and detects fine (it recorded the 07-18 outage the minute it happened), its ntfy config is correct, and the test publish was accepted by ntfy.sh — so if the phone did NOT show it, the broken hop is your phone's ntfy subscription (app signed out / muted / iOS delivery), and that is what hid the 7h15m outage. **Yes = path works; No = we propose a second channel.**
- [2026-07-13] 📧 **Gmail MCP re-auth — one click** in claude.ai settings; the token is EXPIRED. Unblocks the receipt-driven `subscriptions.yml` fills below.
- [2026-07-13] 📝 **3 fields in `inventory/secrets/subscriptions.yml`** (edit the file or tell any agent): Claude → which card; GitHub → next_charge date + which card, from the receipt. _(Less urgent than it was: the Actions billing block CLEARED 07-29 and was verified. The GitHub date is still wanted for the records — and if the block was a failed payment, knowing the charge date tells us when it could recur.)_

## 🌐 Browser work only an operator can do

- [2026-07-29] **Register Thalon's staging callback URL on the Meta + LinkedIn (+ Reddit) developer apps — ~10 min, no spend.** Add `https://preview.swordfish.cfd/api/integrations/callback/<platform>` to each app's allowed redirect list (`facebook`, `instagram` — same Meta app —, `linkedin`, `reddit`). The whole infra side is done and verified: the edge passes that exact path un-challenged, the app builds redirects from the right host, and as of today the credential vault has its key. Platforms simply refuse a redirect URI they were not told about, and these are your registered apps — an agent cannot click through those consoles. **Tell any agent once done** and swordfish sets the four `SOCIAL_*_CLIENT_ID/_SECRET` pairs (those come from you too — same consoles). Doing the pairs first would just move the failure one step later. _Nothing is broken meanwhile: Bluesky needs no portal and works now._

## 💸 Money

- [2026-07-13] **SPEND GATE — resize syd2. Standing recommendation: DON'T, not yet.** Measured, not guessed: ffmpeg worker 2.26 GiB, app+render concurrent 4.09 GiB, against 5.90 GiB available — so even after Eamos's backend cut over, ONE render worker still fits with ~1.6 GiB spare. Only a SECOND overlapping render would OOM, and renders are operator-triggered and minutes long. The resize buys concurrency headroom you are not using yet. Trigger is a future condition (overlapping renders on syd2, or memory pressure eating the margin), not present pain. If/when taken: `std-6vcpu` = AUD 78.40/mo (+39.20) priced 07-16 — **re-price live** — and it needs a power-off (Dokploy + thalon + tenant-pg briefly down) with the disk growing 100→180 GB **one-way**.

## 🤔 Decisions — nothing broken, no rush, but they are yours

- [2026-07-28] 🔁 **Auto-reboot posture, fleet-wide.** All three boxes carry `Automatic-Reboot true` + **`WithUsers true`** + `Automatic-Reboot-Time 18:30`. On syd3 that is cheap. On **syd4** it reboots *with users logged in*, killing live agent sessions; on **syd2** that same 18:30 reboot caused the 7h15m edge outage on 07-18. **Kuma gap DIAGNOSED 07-29:** detection and config are fine — it recorded that outage in real time and all five monitors page the one ntfy channel; the suspect hop is ntfy→your phone (see the 📱 quick item above). **Timely tonight: both syd2 and syd4 carry `reboot-required` for TODAY's 18:30 window.** You did not pick an option on 07-28, so nothing was changed. **(a)** leave as-is (it self-heals; auto-patching keeps its value) · **(b)** keep auto-patching, disable auto-*reboot* on syd2+syd4 so reboots are deliberate · **(c)** (b) plus close the Kuma gap so a real outage actually pages you. Config-only, no spend, reversible.
- [2026-07-19] ⚠️ **Key rotation call — swordfish's own provider keys hit a session transcript.** A malformed `.env` echoed the VALUES of essentially every swordfish-held provider credential into the 07-19 transcript as error text: BinaryLane, Porkbun ×2, Vultr, both Dokploy admin keys, B2, the GHCR PAT, UptimeRobot, a healthchecks URL. **On-box only** (syd4, deploy-owned files), never in git or channels. The file format is fixed, so it cannot recur that way. Ranked by blast radius if you want rotations: **① Porkbun (DNS) ② BinaryLane + both Dokploy keys (control-plane god keys) ③ B2 + GHCR PAT ④ Vultr ⑤ UptimeRobot** (trivial). Each is a swordfish-run pass on your go; they can spread over days.
- [2026-07-17] 🔐 **Shared Dokploy = swordfish's admin key can read every tenant's live secrets in plaintext.** Surfaced answering an eamos question: their application record carries `env` inline, so reading it to check deploy config also returns their Supabase service-role key, JWT secret, AI-gateway key, a DB URL with inline password, and your GitHub PAT. **No value was ever reproduced anywhere.** This is inherent to a shared control plane, not a defect — but it sits underneath the charter's separation-of-duties claim. **(a)** accept + record it (the honest state; tenants should know — eamos already told) · **(b)** swordfish uses **scoped tenant keys** for tenant reads where one exists, admin key for fleet ops only · **(c)** per-tenant Dokploy orgs — real isolation, real overhead.
- [2026-07-16] 🔓 **syd4 can SSH straight into syd2 — keep or close?** Disabling BinaryLane's outbound port-blocking on syd4 (your approval, for Render) revealed syd4's key was *always* authorized on syd2: the "CI-as-hands only" property was accidentally enforced by a provider filter, not by policy. Nothing on syd2 was weakened; syd4 merely gained egress. Effect: workspace-box agents can administer production directly, bypassing the CI channel the charter chose. It is genuinely convenient — today's thalon work used it for read-only evidence. **Keep** (say nothing) or **close** (drop that key from syd2's `authorized_keys`; probes move back to CI, costing minutes per check, no capability lost).

---

_Closed items live in `archive/NEEDS-STEVEN-closed.md` — including the Render
cancellation, the syd4 16 GB resize, the eamos deploy-key release, and the
GitHub Actions billing ruling. Nothing there needs you._
