#!/bin/bash
# mac-census.sh - run ON THE MAC:
#
#   ssh deploy@syd4.swordfish.cfd cat mac-census.sh | bash
#
# Ships a complete FILE CENSUS of every non-boot volume to the box at
# ~/migration/incoming/census/<volume>.tsv - one line per file:
# size <tab> mtime-epoch <tab> path. No file CONTENTS travel; the drive is
# never written to. This gives the box-side agent full visibility of what
# exists on the portable drive so it can spot anything the imports missed -
# the agent cannot reach the Mac or the drive directly (the tunnel is
# strictly Mac -> box), so this census IS its eyes.
#
# ssh -n on control calls (see mac-import.sh header for the | bash gotcha);
# the census upload ssh deliberately KEEPS stdin - the file list is its input.
set -u
BOX=deploy@syd4.swordfish.cfd

ssh -n "$BOX" 'mkdir -p "$HOME/migration/incoming/census"'

for vol in /Volumes/*/; do
  vol="${vol%/}"
  name=$(basename "$vol")
  case "$name" in "Macintosh HD"*) continue ;; esac
  echo "== censusing $vol (a big drive can take a few minutes)"
  find "$vol" -type f -not -path '*/.git/*' -exec stat -f '%z%t%m%t%N' {} + 2>/dev/null \
    | ssh "$BOX" "cat > \"\$HOME/migration/incoming/census/${name}.tsv\""
  echo "   -> census/${name}.tsv on the box"
done

echo "== census done. The agent can now see the whole drive's file list."
