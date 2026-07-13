#!/bin/bash
# mac-import.sh - run ON THE MAC (one hand-typeable line):
#
#   ssh deploy@syd4.swordfish.cfd cat mac-import.sh | bash
#
# Stages everything git never carries from the portable drive to the box:
#   1. every <project>-migration folder on any mounted volume
#      -> box:~/migration/            (per-project boot notes + secrets;
#                                      the MAC-COMMANDS.txt convention)
#   2. for each project the box knows (~/work/*, minus swordfish which is
#      already complete on the box): gitignored valuables found in the
#      drive's copy of that project (.env*, secrets/, inventory/secrets/,
#      .context/) -> box:~/migration/incoming/<project>/
#   3. a walter/ folder (the vault; renamed on the drive 2026-07-10)
#      -> box:~/migration/incoming/walter/   (diffed on the box, never
#                                             blindly applied - ~/vault is
#                                             a live git repo)
#
# Nothing lands inside the repos directly - the box-side agent distributes
# from staging and verifies each file stays gitignored. Generic by design:
# the project list comes from the box at runtime, so no project names live
# in this tracked file (anonymity guard). Safe to re-run any time.
# Canonical copy: this file; working copy: ~deploy/mac-import.sh on syd4.
#
# Every bare ssh below uses -n: this script arrives via `cat ... | bash`, so
# an ssh without -n inherits that pipe as stdin and SWALLOWS THE REST OF THE
# SCRIPT as remote input - execution just stops, silently (hit live
# 2026-07-13; rsync/scp are immune, their transport ssh gets its own stdin).
set -u
BOX=deploy@syd4.swordfish.cfd

PROJECTS=$(ssh -n "$BOX" 'ls "$HOME/work"') || { echo "cannot reach the box"; exit 1; }
ssh -n "$BOX" 'mkdir -p "$HOME/migration/incoming"'

staged=0
for vol in /Volumes/*/; do
  vol="${vol%/}"
  case "$(basename "$vol")" in "Macintosh HD"*) continue ;; esac
  echo "== scanning $vol"

  # 1. per-project hand-off folders. BOTH suffixes: agents named them
  #    "<p>-migration" AND "<p>-migration-staging" - the narrower glob silently
  #    skipped a whole project's boot notes + secrets (found 2026-07-13 by the
  #    file census, not by the import: an import can only miss things quietly).
  for m in "$vol"/*-migration "$vol"/*-migration-staging; do
    [ -d "$m" ] || continue
    echo "   -> $(basename "$m")  =>  box:~/migration/"
    rsync -a "$m" "$BOX:migration/" && staged=1
  done

  # 2. gitignored valuables inside the drive's copies of known projects
  for p in $PROJECTS; do
    [ "$p" = "swordfish" ] && continue
    for src in "$vol/$p" "$vol/work/$p"; do
      [ -d "$src" ] || continue
      for item in secrets inventory/secrets .context; do
        [ -e "$src/$item" ] || continue
        echo "   -> $p/$item  =>  box:~/migration/incoming/$p/"
        ssh -n "$BOX" "mkdir -p \"\$HOME/migration/incoming/$p\""
        rsync -a --exclude .git "$src/$item" "$BOX:migration/incoming/$p/" && staged=1
      done
      for f in "$src"/.env*; do
        [ -f "$f" ] || continue
        echo "   -> $p/$(basename "$f")  =>  box:~/migration/incoming/$p/"
        ssh -n "$BOX" "mkdir -p \"\$HOME/migration/incoming/$p\""
        scp -q "$f" "$BOX:migration/incoming/$p/" && staged=1
      done
      break
    done
  done

  # 3. the vault (drive-side name: walter)
  if [ -d "$vol/walter" ]; then
    echo "   -> walter  =>  box:~/migration/incoming/walter/"
    rsync -a --exclude .git "$vol/walter" "$BOX:migration/incoming/" && staged=1
  fi

  # 4. agent memories snapshot: if the drive's claude-home staging was
  #    refreshed after the box's 2026-07-10 copy (e.g. a weekend session on
  #    the old machine), this catches the delta. Compared box-side by mtime,
  #    never blindly applied.
  if [ -d "$vol/migration-staging/claude-home/projects" ]; then
    echo "   -> claude-home/projects snapshot  =>  box:~/migration/incoming/claude-home/"
    ssh -n "$BOX" 'mkdir -p "$HOME/migration/incoming/claude-home"'
    rsync -a "$vol/migration-staging/claude-home/projects" "$BOX:migration/incoming/claude-home/" && staged=1
  fi
done

if [ "$staged" = 1 ]; then
  echo "== staged on the box. Tell the agent 'imported' - it verifies and distributes."
else
  echo "== nothing found to stage - tell the agent what the drive shows (ls /Volumes)."
fi
