# Mac dashboard setup — click a project, get VS Code (one-time, ~5 minutes)

Exact-typing format, same as MACBOOK-CHECKLIST.md. After this: open Chromium →
the start page is there → click a project → VS Code opens it. No terminal, no
`ssh -L`, ever again. The tunnel restarts itself within ~10 s of any drop.

## Part 1 — on syd4 (code-server terminal is fine)

    cd ~/work/swordfish
    git pull
    bash provisioning/workstation/generate-dashboard.sh

Expected: `wrote /home/deploy/dashboard/index.html (N buttons)` — one button
per project plus the vault.

## Part 2 — on the Mac (Terminal.app, type each line)

    mkdir -p ~/Library/LaunchAgents
    scp deploy@syd4.swordfish.cfd:work/swordfish/provisioning/workstation/mac/com.swordfish.syd4-tunnel.plist ~/Library/LaunchAgents/
    scp deploy@syd4.swordfish.cfd:dashboard/index.html ~/Desktop/syd4-dashboard.html
    launchctl load ~/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist

Check the tunnel came up (should print one LISTEN line):

    lsof -nP -iTCP:8080 | grep LISTEN

If you had a manual `ssh -L 8080...` running from before, close that window
first — only one process can hold port 8080.

## Part 3 — Chromium (clicks only)

1. Open Chromium → type in the address bar: `file:///Users/YOURUSERNAME/Desktop/syd4-dashboard.html`
   (replace YOURUSERNAME; press Enter — the dashboard should show its buttons).
2. Bookmark it (⌘D) and/or: Settings → On startup → "Open a specific page" →
   Add a new page → paste the same `file:///...` address.
3. Click a project button → VS Code opens that project. Done.

## When the project list changes

Re-run Part 1 on syd4, then on the Mac re-run ONLY the second `scp` line from
Part 2 (the index.html one). Everything else stays.

## Undo / troubleshoot

- Stop the tunnel: `launchctl unload ~/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist`
- Tunnel log: `cat /tmp/syd4-tunnel.log`
- Buttons load but pages don't: the tunnel is down — wait 10 s, or check the log.
