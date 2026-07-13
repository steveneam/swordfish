#!/bin/bash
# mac-setup.sh - run ON THE MAC (one hand-typeable line, no copy needed):
#
#   ssh deploy@syd4.swordfish.cfd cat mac-setup.sh | bash
#
# Does all of MAC-DASHBOARD-SETUP.md Part 2 + opens the dashboard (Part 3
# step 1). Safe to re-run any time. A copy lives at ~deploy/mac-setup.sh on
# syd4 (that short path is what makes the one-liner short); the repo copy
# here is canonical - re-copy after edits.
set -e

mkdir -p "$HOME/Library/LaunchAgents"
scp -q deploy@syd4.swordfish.cfd:work/swordfish/provisioning/workstation/mac/com.swordfish.syd4-tunnel.plist "$HOME/Library/LaunchAgents/"
scp -q deploy@syd4.swordfish.cfd:dashboard/index.html "$HOME/Desktop/syd4-dashboard.html"
echo "== files pulled: tunnel service + Desktop/syd4-dashboard.html"

launchctl unload "$HOME/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.swordfish.syd4-tunnel.plist"
echo "== tunnel service loaded (starts at login, restarts itself after drops)"

sleep 3
if lsof -nP -iTCP:8080 2>/dev/null | grep -q LISTEN; then
  echo "== port 8080 is up."
  echo "   If an old manual 'ssh -L 8080' Terminal window is still open,"
  echo "   close it now - the service tunnel takes over within ~10 seconds."
else
  echo "== tunnel starting - give it ~10 seconds, then it should be up."
fi

# the LIVE dashboard (auto-refreshing, served from the box through the
# tunnel); the Desktop file stays as an offline fallback snapshot
open -a "Chromium" "http://localhost:8080/proxy/8090/" 2>/dev/null \
  || open "http://localhost:8080/proxy/8090/" \
  || open "$HOME/Desktop/syd4-dashboard.html"
echo "== live dashboard opened in the browser. Bookmark it: press Cmd-D. Done."
