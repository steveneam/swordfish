#!/usr/bin/env bash
# asset-manifest.sh - deterministic asset-tree manifest + diff harness for the
# Project 1 landing zone (migration plan Phase 0.4,
# research/project1-asset-migration-plan-2026-07-15.md). Box-side, no LLM in
# the loop: their agent (or CI-as-hands) calls it to prove a seeded tree
# matches a source manifest byte-for-byte before any cutover/cancel gate.
#
#   asset-manifest.sh manifest <dir>                 # emit manifest on stdout
#   asset-manifest.sh diff <source-manifest> <dir>   # exit 0 iff tree == manifest
#   asset-manifest.sh self-test                      # prove the harness itself
#
# Manifest format (one line per regular file, sorted bytewise by relpath):
#   <sha256>  <size-bytes>  <relpath>
# Determinism: LC_ALL=C sort, relpaths, no timestamps/owners - two runs over
# identical trees produce identical bytes, so manifests can themselves be
# checksummed and land in restic (the corpus is excluded; manifests are the
# covered record - profiles.yaml syd2 exception).
# Diff classes: MISSING (in manifest, not on disk) / EXTRA (on disk, not in
# manifest) / MISMATCH (hash or size differs). Any line => exit 1.

set -euo pipefail
export LC_ALL=C

emit_manifest() { # <dir>
    local dir=$1
    [ -d "$dir" ] || { echo "FAIL: not a directory: $dir" >&2; exit 1; }
    # relpath via -printf '%P'; NUL-delimited so any filename survives;
    # sha256 first, then size, then path - sort key is the path column
    (cd "$dir" && find . -type f -printf '%P\0' | sort -z \
        | while IFS= read -r -d '' f; do
              # the one filename shape the line format cannot carry
              case "$f" in *$'\n'*) echo "FAIL: newline in filename: ${f@Q}" >&2; exit 1;; esac
              # hash via stdin: sha256sum FILENAME flips to backslash-escape
              # mode on odd names, corrupting the hash column
              printf '%s  %s  %s\n' \
                  "$(sha256sum < "$f" | cut -d' ' -f1)" \
                  "$(stat -c %s -- "$f")" \
                  "$f"
          done)
}

cmd=${1:-}
case "$cmd" in
manifest)
    emit_manifest "${2:?usage: asset-manifest.sh manifest <dir>}"
    ;;
diff)
    src=${2:?usage: asset-manifest.sh diff <source-manifest> <dir>}
    dir=${3:?usage: asset-manifest.sh diff <source-manifest> <dir>}
    [ -f "$src" ] || { echo "FAIL: no such manifest: $src"; exit 1; }
    live=$(mktemp); trap 'rm -f "$live"' EXIT
    emit_manifest "$dir" > "$live"
    # join on the path column. Parse positionally, NOT with -F'  ': a relpath
    # may itself contain double spaces. Line = sha256(64) + 2sp + size + 2sp
    # + path, so path starts after the second separator.
    rc=0
    while IFS= read -r line; do
        echo "$line"; rc=1
    done < <(awk '
        function parse(line,   rest, i) {  # sets HASH SIZE PATH globals
            HASH = substr(line, 1, 64)
            rest = substr(line, 67)        # past sha256 + "  "
            i = index(rest, "  ")
            SIZE = substr(rest, 1, i - 1)
            PATH = substr(rest, i + 2)
        }
        NR==FNR { parse($0); src[PATH] = HASH "  " SIZE; next }
        {
            parse($0)
            if (!(PATH in src))                 print "EXTRA:    " PATH
            else {
                if (src[PATH] != HASH "  " SIZE) print "MISMATCH: " PATH " (manifest " src[PATH] "; disk " HASH "  " SIZE ")"
                delete src[PATH]
            }
        }
        END { for (p in src) print "MISSING:  " p }
    ' "$src" "$live" | sort)
    if [ "$rc" = 0 ]; then
        echo "OK: tree matches manifest ($(wc -l < "$src") files, $(basename "$src"))"
    else
        echo "FAIL: tree does not match manifest (classes above)"; exit 1
    fi
    ;;
self-test)
    # fixture tree -> manifest -> self-diff green; then each mutation class
    # (content flip, extra file, deletion) must be CAUGHT. This is the
    # standing "harness runs against a fixture tree" exit-criterion proof.
    work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/fix/sub dir"
    printf 'alpha\n'    > "$work/fix/a.txt"
    printf 'beta\n'     > "$work/fix/sub dir/b.bin"
    printf 'gamma\n'    > "$work/fix/dbl  space.txt"   # double space: parse hazard, kept in the fixture
    : > "$work/fix/empty"
    "$0" manifest "$work/fix" > "$work/fix.manifest"
    [ "$(wc -l < "$work/fix.manifest")" = 4 ] || { echo "FAIL: self-test expected 4 manifest lines"; exit 1; }
    # determinism: a second pass must be byte-identical
    "$0" manifest "$work/fix" | cmp -s - "$work/fix.manifest" \
        || { echo "FAIL: self-test manifest not deterministic"; exit 1; }
    "$0" diff "$work/fix.manifest" "$work/fix" >/dev/null \
        || { echo "FAIL: self-test clean diff did not pass"; exit 1; }
    # capture-then-grep, never diff|grep: under pipefail the expected exit-1
    # from diff fails the whole pipeline even when grep matches (the same
    # pipe-hides-the-verdict family as the 2026-07-13 guard leak)
    printf 'ALPHA\n' > "$work/fix/a.txt"
    out=$("$0" diff "$work/fix.manifest" "$work/fix" 2>/dev/null || true)
    grep -q '^MISMATCH: a.txt' <<<"$out" \
        || { echo "FAIL: self-test missed a content mutation"; exit 1; }
    printf 'alpha\n' > "$work/fix/a.txt"
    printf 'rogue\n' > "$work/fix/rogue"
    out=$("$0" diff "$work/fix.manifest" "$work/fix" 2>/dev/null || true)
    grep -q '^EXTRA:    rogue' <<<"$out" \
        || { echo "FAIL: self-test missed an extra file"; exit 1; }
    rm "$work/fix/rogue" "$work/fix/empty"
    out=$("$0" diff "$work/fix.manifest" "$work/fix" 2>/dev/null || true)
    grep -q '^MISSING:  empty' <<<"$out" \
        || { echo "FAIL: self-test missed a deleted file"; exit 1; }
    echo "OK: asset-manifest self-test green (determinism + all 3 diff classes)"
    ;;
*)
    echo "usage: asset-manifest.sh manifest <dir> | diff <source-manifest> <dir> | self-test" >&2
    exit 2
    ;;
esac
