#!/bin/bash
# mac-data.sh - run ON THE MAC (one hand-typeable line):
#
#   ssh deploy@syd4.swordfish.cfd cat mac-data.sh | bash
#
# The BULK companion to mac-import.sh. That one moves small, urgent things
# (boot notes, secrets, memories) and stays fast; this one moves the big
# data folders the census found still sitting on the drive:
#   - "<project>-data" for every project the box knows (list read at runtime,
#     so no project names live in this tracked file - anonymity guard)
#   - "Data" and "Website Design General" (generic top-level folders)
# Everything lands in box:~/migration/incoming/ for the agent to place.
#
# SLOW BY NATURE: this is gigabytes going over the founder's home UPLOAD link.
# rsync is incremental and resumable - if it dies, just run the line again and
# it picks up where it stopped. ssh -n on control calls (see mac-import.sh).
set -u
BOX=deploy@syd4.swordfish.cfd

PROJECTS=$(ssh -n "$BOX" 'ls "$HOME/work"') || { echo "cannot reach the box"; exit 1; }
ssh -n "$BOX" 'mkdir -p "$HOME/migration/incoming"'

staged=0
for vol in /Volumes/*/; do
  vol="${vol%/}"
  case "$(basename "$vol")" in "Macintosh HD"*) continue ;; esac

  # per-project bulk data folders
  for p in $PROJECTS; do
    src="$vol/$p-data"
    [ -d "$src" ] || continue
    echo "== $(basename "$src")  =>  box (big - progress below, safe to re-run)"
    rsync -a --info=progress2 --exclude .git "$src" "$BOX:migration/incoming/" && staged=1
  done

  # generic top-level folders the census flagged as unclaimed
  for name in "Data" "Website Design General"; do
    src="$vol/$name"
    [ -d "$src" ] || continue
    echo "== $name  =>  box"
    rsync -a --info=progress2 --exclude .git "$src" "$BOX:migration/incoming/" && staged=1
  done
done

if [ "$staged" = 1 ]; then
  echo "== bulk data staged. Tell the agent 'data done' - it places + verifies."
else
  echo "== nothing found to stage (drive not mounted? already moved?)."
fi
