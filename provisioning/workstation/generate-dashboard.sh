#!/usr/bin/env bash
set -euo pipefail

# generate-dashboard.sh - founder start page for the syd4 workstation
# (founder-interface-plan-2026-07-11, Leg 1). Emits ~/dashboard/index.html:
# one button per project under ~/work plus the vault, each linking to
# code-server's ?folder= URL through the Mac's ssh tunnel (localhost:8080).
#
# The OUTPUT is untracked BY DESIGN: project directory names on this box can
# include guarded portfolio names - they must never enter this repo. Only
# this generic generator is tracked. Re-run whenever ~/work changes, then
# re-copy index.html to the Mac (MAC-DASHBOARD-SETUP.md Part 3).

OUT_DIR="$HOME/dashboard"
OUT="$OUT_DIR/index.html"
mkdir -p "$OUT_DIR"

{
  cat <<'HEAD'
<!doctype html>
<html><head><meta charset="utf-8"><title>syd4 workstation</title>
<style>
  body{background:#0e1116;color:#e6e6e6;font-family:-apple-system,'Helvetica Neue',sans-serif;
       display:flex;flex-direction:column;align-items:center;padding-top:6vh;margin:0}
  h1{font-weight:300;letter-spacing:.12em;font-size:1.6rem;color:#9db4c8}
  a.btn{display:block;width:min(24rem,84vw);margin:.45rem;padding:1.15rem 1.5rem;
       background:#1a2330;color:#e6e6e6;text-decoration:none;border-radius:.7rem;
       font-size:1.3rem;border:1px solid #2c3c50;text-align:center}
  a.btn:hover{background:#24344a;border-color:#3d5470}
  .note{color:#5c7186;margin-top:2.2rem;font-size:.8rem;text-align:center;max-width:26rem}
</style></head><body>
<h1>syd4 &mdash; pick a project</h1>
HEAD

  for d in "$HOME"/work/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    printf '<a class="btn" href="http://localhost:8080/?folder=%s">%s</a>\n' "${d%/}" "$name"
  done

  if [ -d "$HOME/vault" ]; then
    printf '<a class="btn" href="http://localhost:8080/?folder=%s">vault &mdash; read-only</a>\n' "$HOME/vault"
  fi

  printf '<p class="note">generated %s on %s &middot; regenerate: ~/work/swordfish/provisioning/workstation/generate-dashboard.sh<br>blank page? the ssh tunnel is down &mdash; it restarts itself within ~10 s</p>\n' \
    "$(date -u +%F)" "$(hostname -s)"
  printf '</body></html>\n'
} > "$OUT"

count=$(grep -c 'class="btn"' "$OUT")
echo "wrote $OUT ($count buttons)"
