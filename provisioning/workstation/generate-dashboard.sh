#!/usr/bin/env bash
set -euo pipefail

# generate-dashboard.sh - founder start page for the syd4 workstation
# (founder-interface-plan-2026-07-11, Leg 1; upgraded to info cards at the
# founder's ask 2026-07-13). Emits ~/dashboard/index.html: one card per
# project under ~/work plus walter (the vault), each linking to code-server's
# ?folder= URL through the Mac's ssh tunnel (localhost:8080), each carrying
# live state: which box, branch, last commit, uncommitted/unpushed counts,
# last file activity, last agent session.
#
# Freshness: setup-dashboard.sh installs a systemd timer that re-runs this
# every 15 minutes and a localhost-only static server on 8090, so the page
# is LIVE at http://localhost:8080/proxy/8090/ through the same tunnel
# (code-server proxies /proxy/<port>/ to local ports). The scp'd Desktop
# copy still works as a fallback snapshot.
#
# The OUTPUT is untracked BY DESIGN: project directory names on this box can
# include guarded portfolio names - they must never enter this repo. Only
# this generic generator is tracked.

OUT_DIR="$HOME/dashboard"
OUT="$OUT_DIR/index.html"
mkdir -p "$OUT_DIR"

now=$(date +%s)
rel() { # $1 = epoch seconds -> human "Xm/Xh/Xd ago"
  local s=$(( now - $1 ))
  [ "$s" -lt 0 ] && s=0
  if   [ "$s" -lt 3600 ];  then echo "$(( s / 60 ))m ago"
  elif [ "$s" -lt 86400 ]; then echo "$(( s / 3600 ))h ago"
  else echo "$(( s / 86400 ))d ago"; fi
}

# NOTE: no `... | sort | head` here - head's early close SIGPIPEs sort, and
# under pipefail+systemd that killed the whole unit (2026-07-13). awk drains
# its whole input, so it can't be broken-piped.
newest_mtime() { # $1 = dir -> epoch of newest file, skipping .git/node_modules
  find "$1" -path '*/.git' -prune -o -path '*/node_modules' -prune -o \
       -type f -printf '%T@\n' 2>/dev/null \
    | awk 'BEGIN{m=0}{if($1>m)m=$1}END{if(m>0)printf "%d\n", m}'
}

last_session() { # $1 = project dir -> epoch of newest agent transcript, or ""
  local slug; slug=$(printf '%s' "$1" | tr '/.' '--')
  find "$HOME/.claude/projects/$slug" -maxdepth 1 -name '*.jsonl' -printf '%T@\n' 2>/dev/null \
    | awk 'BEGIN{m=0}{if($1>m)m=$1}END{if(m>0)printf "%d\n", m}'
}

{
  cat <<'HEAD'
<!doctype html>
<html><head><meta charset="utf-8"><title>syd4 workstation</title>
<meta http-equiv="refresh" content="300">
<style>
  body{background:#0e1116;color:#e6e6e6;font-family:-apple-system,'Helvetica Neue',sans-serif;
       display:flex;flex-direction:column;align-items:center;padding-top:5vh;margin:0}
  h1{font-weight:300;letter-spacing:.12em;font-size:1.6rem;color:#9db4c8}
  a.btn{display:block;width:min(26rem,88vw);margin:.45rem;padding:1rem 1.4rem;
       background:#1a2330;color:#e6e6e6;text-decoration:none;border-radius:.7rem;
       border:1px solid #2c3c50}
  a.btn:hover{background:#24344a;border-color:#3d5470}
  .name{font-size:1.25rem}
  .sub{font-size:.78rem;color:#7b8fa3;margin-top:.4rem;line-height:1.5}
  .warn{color:#e0b060}
  .ok{color:#6fae7f}
  .note{color:#5c7186;margin-top:2rem;font-size:.8rem;text-align:center;max-width:28rem}
</style></head><body>
<h1>syd4 &mdash; pick a project</h1>
HEAD

  for d in "$HOME"/work/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name=$(basename "$d")

    if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
      branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
      lastc=$(git -C "$d" log -1 --format='%cr' 2>/dev/null || echo 'no commits')
      dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
      unpushed=$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
      if [ "$dirty" -eq 0 ] && [ "$unpushed" = "0" ]; then
        state='<span class="ok">clean &middot; all pushed</span>'
      else
        state="<span class=\"warn\">${dirty} uncommitted &middot; ${unpushed} unpushed</span>"
      fi
      git_line="branch ${branch} &middot; last commit ${lastc}<br>${state}"
    else
      git_line='not a git repo'
    fi

    touched=$(newest_mtime "$d"); touched=${touched:+$(rel "$touched")}
    sess=$(last_session "$d");    sess=${sess:+$(rel "$sess")}

    printf '<a class="btn" href="http://localhost:8080/?folder=%s"><div class="name">%s</div><div class="sub">on %s &middot; files touched %s &middot; agent session %s<br>%s</div></a>\n' \
      "$d" "$name" "$(hostname -s)" "${touched:-never}" "${sess:-none yet}" "$git_line"
  done

  # walter = the research vault (founder named it 2026-07-13). Read-only is
  # AGENT protocol, not a founder restriction - no need to say it on his button.
  if [ -d "$HOME/vault" ]; then
    vtouch=$(newest_mtime "$HOME/vault"); vtouch=${vtouch:+$(rel "$vtouch")}
    vcount=$(find "$HOME/vault" -name '*.md' -not -path '*/.git/*' 2>/dev/null | wc -l)
    printf '<a class="btn" href="http://localhost:8080/?folder=%s"><div class="name">walter</div><div class="sub">on %s &middot; the research vault &middot; %s notes &middot; touched %s</div></a>\n' \
      "$HOME/vault" "$(hostname -s)" "$vcount" "${vtouch:-never}"
  fi

  printf '<p class="note">generated %s UTC on %s &middot; auto-refreshes every 15 min at <b>localhost:8080/proxy/8090</b><br>blank page? the ssh tunnel is down &mdash; it restarts itself within ~10 s</p>\n' \
    "$(date -u '+%F %H:%M')" "$(hostname -s)"
  printf '</body></html>\n'
} > "$OUT"

count=$(grep -c 'class="btn"' "$OUT")
echo "wrote $OUT ($count buttons)"
