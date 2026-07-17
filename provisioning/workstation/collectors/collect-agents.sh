#!/usr/bin/env bash
set -uo pipefail

# collect-agents.sh - semantic agent state, at a glance (the one thing the
# herdr evaluation conceded it did better than this cockpit: "which agent is
# blocked on ME right now?" had no single home - it was smeared across tmux
# tabs, this dashboard, and ntfy pings). This collector gives it one home, on
# the surface the founder already reads, instead of adopting a pre-1.0 TUI he
# cannot copy text out of. Decision record: research/herdr-evaluation-2026-07-17.md.
#
# States (herdr's vocabulary, deliberately): working | blocked | idle | exited
# | opaque. Detection is DETERMINISTIC pane-text + /proc evidence - no LLM in
# the loop, same family as every other collector.
#
#   blocked  - the agent is waiting on a HUMAN: a permission prompt or an
#              AskUserQuestion selector is on screen. The one state worth an
#              amber badge: work is stopped until the founder acts.
#   working  - the harness says so ("esc to interrupt" is only rendered while
#              a turn runs), or the pane changed within the last POLL seconds.
#   idle     - at the input prompt, pane quiet. Includes "done": a TUI cannot
#              distinguish finished from waiting-for-next-task, so this
#              collector does not pretend to.
#   exited   - the agent process is gone (wrapper shell showing "[claude
#              exited...]", or a bare shell where an agent should be).
#   opaque   - an agent RUNS outside tmux (eamos codex lives in a plain
#              code-server pty, founder call 2026-07-16) so there is no pane
#              to read. CPU evidence separates working/quiet, nothing more -
#              stated honestly rather than guessed. The blocked state is
#              INVISIBLE here; the row says so.
#
# Names come from tmux session names + process cwds - nothing hardcoded,
# project-agnostic like dev-lane.sh (names appear only in the emitted JSON,
# which is untracked like every other dashboard artifact).

. "$(dirname "$0")/lib.sh"

POLL=45  # "recent output" horizon, seconds; > spinner tick, < human patience

# --- tmux side ----------------------------------------------------------------

classify_pane() { # $1 = pane text (last 40 lines) -> state on stdout
  local t="$1"
  # The SPINNER LINE is the working signal - "✽ Accomplishing… (11m 55s ·
  # ↓ 35.3k tokens)" - because it exists exactly while a turn runs. The
  # footer's "esc to interrupt" fragment is deliberately NOT used: it was
  # observed in the footer of running panes and could not be proven absent
  # from idle ones (2026-07-17), and a signal that can't be falsified is
  # chrome, not state. A running turn also ticks the spinner every second,
  # so the window-activity upgrade below covers any capture-timing gap.
  if grep -qE '^[^A-Za-z0-9]{1,3}[A-Z][a-z]+ing…* \([0-9]+m? ?[0-9]*s|↓ [0-9.]+k? tokens' <<<"$t"; then
    echo working; return
  fi
  # blocked = a question/permission UI is on screen and nothing is running:
  # the one state where work is stopped until the founder acts.
  if grep -qE 'Do you want|Would you like|❯ 1\.|Enter to confirm|esc to cancel|\(y/n\)|\(y/N\)' <<<"$t"; then
    echo blocked; return
  fi
  if grep -qE '\[claude exited|\[codex exited' <<<"$t"; then
    echo exited; return
  fi
  echo idle
}

tmux_rows() {
  local rows='[]'
  local sess pid cmd path act now state pane basis
  now=$(date +%s)
  while IFS='|' read -r sess pid cmd path act; do
    [ -n "$sess" ] || continue
    pane=$(tmux capture-pane -p -t "$sess" 2>/dev/null | tail -40 || true)
    case "$cmd" in
      claude|node|codex|python*) state=$(classify_pane "$pane"); basis="pane" ;;
      *) # the agent wrapper fell back to a shell -> the agent is gone
         state=exited; basis="pane (shell where an agent should be)" ;;
    esac
    # recent pane output upgrades idle -> working (a long tool call renders
    # no TUI chrome, but the pane still moves)
    if [ "$state" = idle ] && [ -n "$act" ] && [ $((now - act)) -le "$POLL" ]; then
      state=working; basis="pane activity ${POLL}s"
    fi
    rows=$(jq --arg n "$sess" --arg s "$state" --arg c "$cmd" --arg p "$path" \
              --arg b "$basis" --argjson a "${act:-null}" \
              '. + [{name: $n, runtime: "tmux", state: $s, cmd: $c, cwd: $p,
                     basis: $b, last_activity: $a}]' <<<"$rows")
  done < <(tmux list-panes -a -F '#{session_name}|#{pane_pid}|#{pane_current_command}|#{pane_current_path}|#{window_activity}' 2>/dev/null)
  echo "$rows"
}

# --- plain-pty side (agents living outside tmux, e.g. codex per founder call) --

pty_rows() { # agent processes whose tty is NOT owned by the tmux server
  local rows='[]'
  local pid tty pcpu etimes args cwd name state basis
  while read -r pid tty pcpu etimes args; do
    [ -n "$pid" ] || continue
    case "$tty" in ''|'?') continue ;; esac
    # skip anything already visible as a tmux pane (tmux ptys belong to the
    # tmux server; a pane process's controlling tty appears under it too, so
    # dedupe by asking tmux whether this pid sits in any pane's process tree)
    if tmux list-panes -a -F '#{pane_pid}' 2>/dev/null | grep -qx "$(ps -o sid= -p "$pid" | tr -d ' ')"; then
      continue
    fi
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
    name=$(basename "$cwd")
    # CPU is the only honest signal without a readable screen
    if awk -v c="$pcpu" 'BEGIN{exit !(c > 3.0)}'; then state=working; else state=opaque; fi
    basis="proc only - no pane to read; blocked-on-founder is INVISIBLE here"
    rows=$(jq --arg n "$name" --arg s "$state" --arg c "${args%% *}" --arg p "$cwd" \
              --arg b "$basis" --argjson cpu "$pcpu" --argjson up "$etimes" \
              '. + [{name: $n, runtime: "pty", state: $s, cmd: $c, cwd: $p,
                     basis: $b, cpu_pct: $cpu, uptime_s: $up}]' <<<"$rows")
  done < <(ps -eo pid=,tty=,pcpu=,etimes=,args= | awk '$5 ~ /^(claude|codex)$/ || $5 ~ /\/(claude|codex)$/')
  echo "$rows"
}

main() {
  local t p
  t=$(tmux_rows)
  p=$(pty_rows)
  jq -n --argjson t "$(date +%s)" --arg host "$(hostname -s)" \
        --argjson tmux "$t" --argjson pty "$p" --argjson poll "$POLL" \
    '{generated_at: $t, host: $host, poll_horizon_s: $poll,
      agents: ($tmux + $pty)}' | emit agents
}

main || fail agents "agents collector crashed"
