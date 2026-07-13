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

## Part 2 — on the Mac (Terminal.app; paste ONE line, wait for the prompt to return)

Open Terminal: ⌘-Space, type `terminal`, press Return.

**First:** if an old manual tunnel is still running (a Terminal window with
`ssh -L 8080...`), close that window now — only one process can hold port 8080.

    mkdir -p ~/Library/LaunchAgents

(no output = success)

    scp deploy@syd4.swordfish.cfd:work/swordfish/provisioning/workstation/mac/com.swordfish.syd4-tunnel.plist ~/Library/LaunchAgents/

First-ever connection may ask `Are you sure you want to continue connecting?`
— type `yes`, Return. Success = a progress line ending in `100%`.

    scp deploy@syd4.swordfish.cfd:dashboard/index.html ~/Desktop/syd4-dashboard.html

(same `100%` line; a `syd4-dashboard.html` icon appears on the Desktop)

    launchctl load ~/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist

(no output = success; the tunnel now starts at login and restarts itself)

Check the tunnel came up — should print exactly one line containing LISTEN:

    lsof -nP -iTCP:8080 | grep LISTEN

Nothing printed? Wait 10 s and run it again (KeepAlive is restarting it).
Still nothing: `cat /tmp/syd4-tunnel.log` and read the last line.

## Part 3 — Chromium (one paste, then clicks)

1. Still in Terminal — this opens the dashboard without typing any username:

       open -a "Chromium" ~/Desktop/syd4-dashboard.html

   (If macOS can't find Chromium: open Chromium yourself, press ⌘-O, pick
   `syd4-dashboard.html` on the Desktop.)
2. Bookmark it: ⌘D, Done.
3. Make it the start page: ⋮ menu → Settings → On startup → "Open a specific
   page or set of pages" → Add a new page → paste the address from the
   address bar (starts with `file:///`) → Add.
4. Click **swordfish** → VS Code opens with the repo's file tree on the left.
   If the left panel ever says "no folder open", you opened `localhost:8080`
   directly — always enter through a dashboard button (the `?folder=` part of
   the button's URL is what opens the project).

## When the project list changes

Re-run Part 1 on syd4, then on the Mac re-run ONLY the second `scp` line from
Part 2 (the index.html one). Everything else stays.

## Undo / troubleshoot

- Stop the tunnel: `launchctl unload ~/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist`
- Tunnel log: `cat /tmp/syd4-tunnel.log`
- Buttons load but pages don't: the tunnel is down — wait 10 s, or check the log.
