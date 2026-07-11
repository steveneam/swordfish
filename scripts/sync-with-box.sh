#!/usr/bin/env bash
set -euo pipefail

# sync-with-box.sh - the cross-machine sync ratchet (founder-ratified
# 2026-07-11): seamless, ADDITIVE-ONLY sync of the things git cannot carry -
# agent memory (both directions) and gitignored secrets (push) - between the
# current machine and the box. Generic by design: works for ANY project and
# ANY machine (Windows/Git Bash, macOS, Linux); contains NO project names so
# it is safe in this tracked repo. Tracked work still rides git: commit+push
# BEFORE running this.
#
# Usage:
#   sync-with-box.sh PROJECT_PATH [--host HOST] [--box-path REMOTE_PROJECT_PATH]
#   e.g. sync-with-box.sh /e/thalon
#        sync-with-box.sh /e/somerepo --box-path /home/deploy/work/somerepo
#
# Semantics (NEVER destructive):
#   memory : files absent on either side are copied across; MEMORY.md index
#            lines are merged by link target (a line whose ](file.md) target
#            already exists on the destination is skipped). Nothing is ever
#            overwritten or deleted - divergent same-name files are REPORTED.
#   secrets: .env* files, inventory/secrets/, .context/ are pushed to the box
#            if absent there (mode 600). Existing-but-different files are
#            REPORTED, never overwritten (rotations are deliberate acts).

PROJ="${1:?usage: sync-with-box.sh PROJECT_PATH [--host HOST] [--box-path PATH]}"
shift
HOST="deploy@syd4.swordfish.cfd"
BOXPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host)     HOST="$2"; shift 2 ;;
    --box-path) BOXPATH="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

PROJ="$(cd "$PROJ" && pwd)"
NAME="$(basename "$PROJ" | tr '[:upper:]' '[:lower:]')"
[ -n "$BOXPATH" ] || BOXPATH="/home/deploy/work/$NAME"
SSH="ssh -o ConnectTimeout=10 -o BatchMode=yes"

# Claude Code project slug = absolute path with [:\/] -> '-'
# (E:\proj -> E--proj ; /home/deploy/work/proj -> -home-deploy-work-proj)
slug() { printf '%s' "$1" | sed -e 's/[:\\/]/-/g'; }
LOCAL_MEM="$HOME/.claude/projects/$(slug "$PROJ")/memory"
# Git Bash pwd gives /e/proj - restore the drive-letter form for the slug
case "$PROJ" in
  /[a-z]/*) winpath="$(printf '%s' "$PROJ" | sed -E 's|^/([a-z])/|\U\1:\\|; s|/|\\|g')"
            LOCAL_MEM="$HOME/.claude/projects/$(slug "$winpath")/memory" ;;
esac
BOX_MEM="~/.claude/projects/$(slug "$BOXPATH")/memory"

echo "== sync $NAME  local:$PROJ  box:$HOST:$BOXPATH"
$SSH "$HOST" "true" || { echo "FAIL: no SSH path to the box (locked network?). List pending transfers in your handoff instead."; exit 1; }

# --- memory: two-way additive -------------------------------------------------
if [ -d "$LOCAL_MEM" ] && $SSH "$HOST" "test -d $BOX_MEM"; then
  local_files=$(ls "$LOCAL_MEM" | grep -v '^MEMORY.md$' || true)
  box_files=$($SSH "$HOST" "ls $BOX_MEM" | grep -v '^MEMORY.md$' || true)
  for f in $local_files; do
    if ! printf '%s\n' "$box_files" | grep -qx "$f"; then
      cat "$LOCAL_MEM/$f" | $SSH "$HOST" "cat > $BOX_MEM/$f"; echo "  memory -> box: $f"
    fi
  done
  for f in $box_files; do
    if [ ! -f "$LOCAL_MEM/$f" ]; then
      $SSH "$HOST" "cat $BOX_MEM/$f" > "$LOCAL_MEM/$f"; echo "  memory <- box: $f"
    fi
  done
  # MEMORY.md merge by ](target.md)
  $SSH "$HOST" "cat $BOX_MEM/MEMORY.md" > /tmp/box-MEMORY.md 2>/dev/null || true
  while IFS= read -r line; do
    tgt=$(printf '%s' "$line" | grep -o '](\([^)]*\.md\))' | head -1) || true
    [ -n "$tgt" ] || continue
    grep -qF "$tgt" "$LOCAL_MEM/MEMORY.md" || { printf '%s\n' "$line" >> "$LOCAL_MEM/MEMORY.md"; echo "  index <- box: $tgt"; }
  done < /tmp/box-MEMORY.md
  while IFS= read -r line; do
    tgt=$(printf '%s' "$line" | grep -o '](\([^)]*\.md\))' | head -1) || true
    [ -n "$tgt" ] || continue
    grep -qF "$tgt" /tmp/box-MEMORY.md || { printf '%s\n' "$line" | $SSH "$HOST" "cat >> $BOX_MEM/MEMORY.md"; echo "  index -> box: $tgt"; }
  done < "$LOCAL_MEM/MEMORY.md"
  # report divergent same-name files (content differs) - human decides
  for f in $local_files; do
    if printf '%s\n' "$box_files" | grep -qx "$f"; then
      lh=$(md5sum "$LOCAL_MEM/$f" | cut -d' ' -f1)
      bh=$($SSH "$HOST" "md5sum $BOX_MEM/$f" | cut -d' ' -f1)
      [ "$lh" = "$bh" ] || echo "  DIVERGED (not touched): memory/$f"
    fi
  done
else
  echo "  memory: skipped (missing dir on one side: $LOCAL_MEM vs box $BOX_MEM)"
fi

# --- secrets: push-if-absent ---------------------------------------------------
push_secret() { # $1 = path relative to project root
  local rel="$1"
  if $SSH "$HOST" "test -e $BOXPATH/$rel"; then
    lh=$(md5sum "$PROJ/$rel" | cut -d' ' -f1)
    bh=$($SSH "$HOST" "md5sum $BOXPATH/$rel" | cut -d' ' -f1)
    [ "$lh" = "$bh" ] || echo "  DIFFERS (not touched): $rel"
  else
    $SSH "$HOST" "mkdir -p \$(dirname $BOXPATH/$rel)"
    cat "$PROJ/$rel" | $SSH "$HOST" "install -m 600 /dev/stdin $BOXPATH/$rel"
    echo "  secret -> box: $rel"
  fi
}
cd "$PROJ"
for f in .env .env.*; do [ -f "$f" ] && push_secret "$f"; done
for d in inventory/secrets .context; do
  [ -d "$d" ] || continue
  find "$d" -type f | while IFS= read -r f; do push_secret "$f"; done
done

echo "== sync complete (additive only; DIVERGED/DIFFERS lines need a human call)"
