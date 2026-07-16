# runbooks/ — executable ops procedures

One runbook per procedure: `provision` (the end-to-end zero→operated-box playbook, human gates marked) · `deploy` · `backup-restore` · `incident` · `migration` (one dual-run M0–M6 instance per real move).

Rules:

- A runbook is **documentary** — the weakest ratchet tier — so **every documented command is executed verbatim on the monthly pass** (the backup-restore drill IS that pass for its runbook). A runbook nobody has run is a liability, not documentation.
- When a step can become a script or a CI check, promote it up the ladder (`AGENTS.md` rule 8) and link back here.
- Each incident/lesson edits the runbook (or the provisioning script) **in the same session** — capture and prune in one move.
