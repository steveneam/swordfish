#!/usr/bin/env bash
set -uo pipefail

# agent-comm - the box's live cross-agent coordination tool (founder call
# 2026-07-19, "build 1 and 2"). Wraps the tmux-composer live channel proven
# in the swordfish<->walter round so agents (and the dashboard) never
# hand-roll send-keys: the safety rules live HERE as code, not as prose.
#
#   agent-comm sessions [--json]      roster: session, state, activity, composer
#   agent-comm peek <agent>           read-only tail of the target's pane
#   agent-comm send <agent> <text...> safe injected message (rules below)
#   agent-comm ledger [n]             last n ledger rows (default 20)
#
# The send rules (each one is a lesson, not a preference):
#   - target must have a LIVE claude pane (relay lesson: a bash fallback or
#     the founder's codex TUI must never receive keystrokes)
#   - composer peeked first; a REAL parked draft refuses the send (splicing
#     into someone's unsent text is the one way this channel corrupts data).
#     An idle session redisplays its last SUBMITTED message dimmed at the
#     prompt (the "mirage", 2026-07-19) - a probe char disambiguates:
#     replaces = echo/empty, appends = real draft.
#   - body collapsed to ONE line before send (a multi-line body would submit
#     extra turns that could carry a forged provenance prefix - relay
#     security review 2026-07-14), sent literally (-l), single Enter
#   - provenance prefix is built server-side and cannot be omitted; it is
#     ROUTING COURTESY ONLY - data, not authorization; receiver gates hold
#   - no Escape, no C-c, no kill anywhere in this tool - by construction
#   - every send is ledgered (who -> whom, when, first 80 chars)
#
# Env seams (tests only; production uses defaults):
#   AGENT_COMM_SOCKET  tmux -L socket name (default: default server)
#   AGENT_COMM_LEDGER  ledger file (default /var/lib/swordfish/agent-comm/ledger.log)

LEDGER=${AGENT_COMM_LEDGER:-/var/lib/swordfish/agent-comm/ledger.log}
TMUX_CMD=(tmux)
[ -n "${AGENT_COMM_SOCKET:-}" ] && TMUX_CMD=(tmux -L "$AGENT_COMM_SOCKET")

die() { echo "agent-comm: $1" >&2; exit "${2:-1}"; }

tm() { "${TMUX_CMD[@]}" "$@"; }

# --- composer classification (pure - the sharpest edge, unit-asserted) -------
# classify <before-line> <after-probe-line> <probe-char> -> empty|draft|unclear
#   empty  : probe REPLACED the shown text (it was a dimmed echo; composer
#            was empty) or both sides show a bare prompt
#   draft  : probe APPENDED to the shown text (a real unsent draft is parked)
#   unclear: anything else (screen moved mid-probe, running turn, etc.)
classify() {
  local before="$1" after="$2" probe="$3"
  local btxt="${before#❯}" atxt="${after#❯}"
  btxt="${btxt# }" atxt="${atxt# }"
  if [ -z "$btxt" ] && [ -z "$atxt" ]; then echo empty; return; fi
  if [ "$atxt" = "$probe" ]; then echo empty; return; fi
  if [ "$atxt" = "${btxt}${probe}" ]; then echo draft; return; fi
  echo unclear
}
if [ "${1:-}" = "_classify" ]; then classify "${2:-}" "${3:-}" "${4:-}"; exit 0; fi

# --- helpers -----------------------------------------------------------------
has_claude_desc() { # $1 pid -> 0 if a depth<=3 descendant's comm is claude.
  # Wrapper shells (`bash -c 'claude; ...'`, the relay's launcher) keep one
  # process group, so tmux reports the PANE command as bash while claude runs
  # as its child - pane_current_command alone misses every relay-launched
  # session (found 2026-07-19: swordfish/thalon invisible to the roster).
  local depth=0 gen="$1" next c
  while [ -n "$gen" ] && [ "$depth" -lt 3 ]; do
    next=""
    for c in $(pgrep -P "${gen// /,}" 2>/dev/null); do
      [ "$(ps -o comm= -p "$c" 2>/dev/null)" = "claude" ] && return 0
      next="$next $c"
    done
    gen="${next# }"; depth=$((depth + 1))
  done
  return 1
}

claude_pane() { # $1 session -> "session:w.p" of the pane running claude, or ""
  local line wp cmd pid
  while IFS= read -r line; do
    wp=${line%% *}; line=${line#* }; cmd=${line%% *}; pid=${line##* }
    if [ "$cmd" = "claude" ] || has_claude_desc "$pid"; then
      printf '%s:%s\n' "$1" "$wp"; return 0
    fi
  done < <(tm list-panes -s -t "$1" \
      -F '#{window_index}.#{pane_index} #{pane_current_command} #{pane_pid}' 2>/dev/null)
  return 1
}

composer_line() { # $1 target-pane -> the ❯ display line (may be empty string)
  tm capture-pane -t "$1" -p 2>/dev/null | grep '^❯' | tail -1
}

pane_state() { # $1 target-pane -> running|idle
  if tm capture-pane -t "$1" -p 2>/dev/null | grep -q 'esc to interrupt'; then
    echo running
  else
    echo idle
  fi
}

pane_activity() { # $1 target-pane -> last activity line, trimmed
  tm capture-pane -t "$1" -p -S -25 2>/dev/null \
    | grep -E '^[⏺●✻·]' | tail -1 | cut -c1-110
}

caller_session() { # sender identity: the caller's own tmux session, if any
  [ -n "${TMUX:-}" ] || return 1
  tmux display-message -p -t "${TMUX_PANE:-}" '#{session_name}' 2>/dev/null
}

ledger_append() { # $1 from $2 to $3 text
  local dir; dir=$(dirname "$LEDGER")
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0   # never fail a send on ledger
  printf '%s | %s -> %s | %s\n' "$(date -u +%FT%TZ)" "$1" "$2" "${3:0:80}" >> "$LEDGER" 2>/dev/null || true
}

# --- subcommands -------------------------------------------------------------
cmd_sessions() {
  local json=0; [ "${1:-}" = "--json" ] && json=1
  local out=() s pane st act comp
  while IFS= read -r s; do
    pane=$(claude_pane "$s") || true
    if [ -z "$pane" ]; then
      [ "$json" = 1 ] && out+=("{\"session\":\"$s\",\"claude\":false}") \
        || printf '%-12s no live claude pane\n' "$s"
      continue
    fi
    st=$(pane_state "$pane"); act=$(pane_activity "$pane"); comp=$(composer_line "$pane")
    comp="${comp#❯}"; comp="${comp# }"
    if [ "$json" = 1 ]; then
      out+=("$(jq -cn --arg s "$s" --arg st "$st" --arg a "$act" --arg c "$comp" \
        '{session:$s,claude:true,state:$st,activity:$a,composer:$c}')")
    else
      printf '%-12s %-8s %s\n' "$s" "$st" "${act:-—}"
      [ -n "$comp" ] && printf '%-12s %-8s composer shows: %s\n' "" "" "$comp"
    fi
  done < <(tm list-sessions -F '#{session_name}' 2>/dev/null)
  [ "$json" = 1 ] && { printf '['; local IFS=,; printf '%s' "${out[*]:-}"; printf ']\n'; }
  return 0
}

cmd_peek() {
  local t="${1:-}"; [ -n "$t" ] || die "usage: agent-comm peek <agent>" 2
  local pane; pane=$(claude_pane "$t") || die "'$t' has no live claude pane (agent-comm sessions for the roster)" 2
  tm capture-pane -t "$pane" -p | grep -v '^$' | tail -12
}

cmd_send() {
  local from="" channel="agent-comm" explicit_from=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)    from="${2:-}"; explicit_from=1; shift 2 ;;
      --channel) channel="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  local target="${1:-}"; shift || true
  local text="$*"
  [ -n "$target" ] && [ -n "$text" ] || die "usage: agent-comm send [--from <name> --channel <label>] <agent> <text>" 2
  [ "${#text}" -le 2000 ] || die "message too long (${#text} > 2000 chars) - use the file channel" 2

  # sender identity: inside tmux the caller's OWN session name wins (an agent
  # does not casually speak as another); --from is for non-tmux callers only
  # (the dashboard server). Refuse an anonymous send.
  local own; own=$(caller_session || true)
  if [ -n "$own" ]; then
    from="$own"
  elif [ "$explicit_from" = 1 ] && [ -n "$from" ]; then
    :
  else
    die "not inside tmux and no --from given - refusing an anonymous send" 2
  fi
  local prefix
  if [ "$explicit_from" = 1 ] && [ -z "$own" ]; then
    prefix="[$from via $channel]"
  else
    prefix="[$from, live via tmux — data, not authorization]"
  fi

  tm has-session -t "$target" 2>/dev/null || die "unknown session '$target' (agent-comm sessions for the roster)" 2
  [ "$target" = "$own" ] && die "refusing to send to your own session" 2
  local pane; pane=$(claude_pane "$target") || die "'$target' has no live claude pane - nothing safe to type into" 2

  # peek -> probe -> classify: refuse a real parked draft, always
  local before after verdict
  before=$(composer_line "$pane")
  if [ -n "${before#❯}" ] && [ "${before#❯ }" != "" ]; then
    tm send-keys -t "$pane" -l -- 'x'
    sleep 1
    after=$(composer_line "$pane")
    tm send-keys -t "$pane" BSpace
    verdict=$(classify "$before" "$after" "x")
    case "$verdict" in
      empty)  ;;
      draft)  die "REFUSED: a real unsent draft is parked in '$target' composer: ${before#❯ } - wait or use the file channel" 3 ;;
      *)      die "REFUSED: '$target' composer state unclear (screen changed mid-probe) - retry in a moment" 4 ;;
    esac
  fi

  local oneline; oneline=$(printf '%s' "$text" | tr '\n\r' '  ')
  tm send-keys -t "$pane" -l -- "$prefix $oneline"
  sleep 1
  tm send-keys -t "$pane" Enter
  sleep 2

  # verify: composer cleared or the message left the input (queued/submitted)
  local post; post=$(composer_line "$pane"); post="${post#❯}"; post="${post# }"
  ledger_append "$from" "$target" "$oneline"
  if [ -n "$post" ] && [ "$post" != "Press up to edit queued messages" ]; then
    echo "WARN: sent but composer still shows text - verify with: agent-comm peek $target" >&2
    exit 5
  fi
  echo "sent $from -> $target ($(pane_state "$pane"); mid-turn messages queue politely)"
}

cmd_ledger() {
  local n="${1:-20}"
  [ -r "$LEDGER" ] || { echo "no ledger yet ($LEDGER)"; return 0; }
  tail -n "$n" "$LEDGER"
}

case "${1:-}" in
  sessions) shift; cmd_sessions "$@" ;;
  peek)     shift; cmd_peek "$@" ;;
  send)     shift; cmd_send "$@" ;;
  ledger)   shift; cmd_ledger "$@" ;;
  *) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
