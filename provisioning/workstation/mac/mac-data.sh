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
#
# The Mac's rsync is Apple's OLD one (2.6.9/openrsync) - flags must stay in
# that dialect. --info=progress2 is rsync 3.x-only and errored out the first
# run (2026-07-13); -P (--partial --progress) is the portable spelling, and
# --partial is what makes a killed multi-GB transfer resume instead of restart.
#
# node_modules never crosses the wire: it regenerates from lockfiles on the
# box, and the census showed the design folder's copy is ORPHANED anyway
# (4,370 of its 4,385 files, with no package.json outside it to reinstall
# from) - founder's dedupe call 2026-07-13.
set -u
BOX=deploy@syd4.swordfish.cfd

PROJECTS=$(ssh -n "$BOX" 'ls "$HOME/work"') || { echo "cannot reach the box"; exit 1; }
ssh -n "$BOX" 'mkdir -p "$HOME/migration/incoming/drive-notes"'

staged=0
for vol in /Volumes/*/; do
  vol="${vol%/}"
  case "$(basename "$vol")" in "Macintosh HD"*) continue ;; esac

  # per-project bulk data folders
  for p in $PROJECTS; do
    src="$vol/$p-data"
    [ -d "$src" ] || continue
    echo "== $(basename "$src")  =>  box (big - progress below, safe to re-run)"
    rsync -aP --exclude .git --exclude node_modules "$src" "$BOX:migration/incoming/" && staged=1
  done

  # generic top-level folders the census flagged as unclaimed
  for name in "Data" "Website Design General"; do
    src="$vol/$name"
    [ -d "$src" ] || continue
    echo "== $name  =>  box"
    rsync -aP --exclude .git --exclude node_modules "$src" "$BOX:migration/incoming/" && staged=1
  done

  # loose top-level .txt notes (the old machine's per-project resume prompts
  # etc) - tiny, and a name-free glob keeps project names out of this file
  for f in "$vol"/*.txt; do
    [ -f "$f" ] || continue
    echo "== note: $(basename "$f")  =>  box"
    rsync -aP "$f" "$BOX:migration/incoming/drive-notes/" && staged=1
  done
done

if [ "$staged" = 1 ]; then
  echo "== bulk data staged. Tell the agent 'data done' - it places + verifies."
else
  echo "== nothing found to stage (drive not mounted? already moved?)."
fi
