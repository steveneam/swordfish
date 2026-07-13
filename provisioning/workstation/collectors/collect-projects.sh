#!/usr/bin/env bash
set -uo pipefail

# collect-projects.sh - per-project cards (the v2 dashboard's content, now as
# data) + the "agent asks" fan-out for the Needs-Steven queue.
# Project NAMES appear only in the emitted JSON (untracked, like the HTML):
# directory names on this box can include guarded portfolio names.

. "$(dirname "$0")/lib.sh"

# no `... | sort | head` on find output: head's early close SIGPIPEs the
# producer, and under pipefail+systemd that killed the whole unit (2026-07-13).
# awk drains its whole input, so it can't be broken-piped.
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

git_json() { # $1 = repo dir -> {is_repo, branch, last_commit_rel, dirty, unpushed}
  local d=$1
  if ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    jq -n '{is_repo: false}'
    return
  fi
  local branch lastc dirty unpushed
  branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
  lastc=$(git -C "$d" log -1 --format='%cr' 2>/dev/null || echo 'no commits')
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
  unpushed=$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || echo -1)
  jq -n --arg b "$branch" --arg c "$lastc" --argjson d "$dirty" --argjson u "$unpushed" \
    '{is_repo: true, branch: $b, last_commit_rel: $c, dirty: $d, unpushed: $u}'
}

project_json() { # $1 = dir, $2 = kind (project|vault)
  local d=$1 kind=$2 name touched sess extra='{}'
  name=$(basename "$d")
  touched=$(newest_mtime "$d")
  sess=$(last_session "$d")
  if [ "$kind" = vault ]; then
    name="walter"
    extra=$(jq -n --argjson n "$(find "$d" -name '*.md' -not -path '*/.git/*' 2>/dev/null | wc -l)" '{notes: $n}')
  fi
  jq -n --arg name "$name" --arg path "$d" --arg kind "$kind" \
        --argjson touched "${touched:-null}" --argjson session "${sess:-null}" \
        --argjson git "$(git_json "$d")" --argjson extra "$extra" \
    '{name: $name, path: $path, kind: $kind, touched: $touched,
      session: $session, git: $git} + $extra'
}

main() {
  local projects='[]' asks='[]' d p
  for d in "$HOME"/work/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    p=$(project_json "$d" project) || continue
    projects=$(jq --argjson p "$p" '. + [$p]' <<<"$projects")
  done
  if [ -d "$HOME/vault" ]; then
    p=$(project_json "$HOME/vault" vault)
    projects=$(jq --argjson p "$p" '. + [$p]' <<<"$projects")
  fi

  # agent asks: any "needs steven" line a project agent left in its handoff
  local f proj line
  for f in "$HOME"/work/*/agent_handoff/CURRENT.md; do
    [ -f "$f" ] || continue
    proj=$(basename "$(dirname "$(dirname "$f")")")
    [ "$proj" = swordfish ] && continue # swordfish's queue is NEEDS-STEVEN.md
    while IFS= read -r line; do
      line=$(sed -E 's/^[-*[:space:]]+//; s/\*\*//g' <<<"$line")
      asks=$(jq --arg p "$proj" --arg t "$line" '. + [{project: $p, text: $t}]' <<<"$asks")
    done < <(grep -ih 'needs steven' "$f" | head -5)
  done

  jq -n --argjson t "$(date +%s)" --arg host "$(hostname -s)" \
        --argjson projects "$projects" --argjson asks "$asks" \
    '{generated_at: $t, host: $host, projects: $projects, asks: $asks}' \
    | emit projects
}

main || fail projects "projects collector crashed"
