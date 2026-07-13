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

## Part 2, the short way — ONE line (preferred; easy to type by hand)

Type this in Terminal, then press Return (the character before `bash` is a
vertical bar - Shift-backslash):

    ssh deploy@syd4.swordfish.cfd cat mac-setup.sh | bash

It pulls both files, loads the tunnel service, verifies port 8080, and opens
the dashboard in the browser - then continue at Part 3 step 2 (bookmark).
The script lives at `~deploy/mac-setup.sh` on syd4 (canonical copy:
`mac-setup.sh` in this directory). The long way below does the same steps
one line at a time.

## Part 2, the long way — on the Mac (Terminal.app; paste ONE line, wait for the prompt to return)

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

1. Still in Terminal — this opens the LIVE dashboard (info cards, refreshes
   itself every 15 min, served from the box through the tunnel):

       open -a "Chromium" http://localhost:8080/proxy/8090/

   (If macOS can't find Chromium, open Chromium yourself and go to that
   address. `~/Desktop/syd4-dashboard.html` remains as a static fallback.)
2. Bookmark it: ⌘D, Done.
3. Make it the start page: ⋮ menu → Settings → On startup → "Open a specific
   page or set of pages" → Add a new page → paste the address from the
   address bar (starts with `file:///`) → Add.
4. Click **swordfish** → VS Code opens with the repo's file tree on the left.
   If the left panel ever says "no folder open", you opened `localhost:8080`
   directly — always enter through a dashboard button (the `?folder=` part of
   the button's URL is what opens the project).

## When the project list changes

Nothing to do — the live page (`localhost:8080/proxy/8090`) regenerates
itself every 15 minutes on the box (setup-dashboard.sh installed the timer).
Only the static Desktop fallback goes stale; refresh it with the second
`scp` line from Part 2 if you care to.

## Undo / troubleshoot

- Stop the tunnel: `launchctl unload ~/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist`
- Tunnel log: `cat /tmp/syd4-tunnel.log`
- Buttons load but pages don't: the tunnel is down — wait 10 s, or check the log.
