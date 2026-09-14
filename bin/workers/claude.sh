#!/usr/bin/env bash
# Claude Code worker adapter. Sourced by dux-worker-wrap after dux-env. Spec section 19.
set -u

# The flags both entry points share, written once so a printed command and an
# executed one cannot drift apart.
#
# --tools: a Dux worker reads, searches, writes and runs commands, and that is
# all. Every other built-in tool is prompt on every turn that nothing in a task
# ever calls. Skills, /ship included, are not one of them: the harness puts a
# skill's instructions in the prompt, so the gate still runs with the six. Safe
# mode is not used, because it would take Bash away; settings-source isolation
# is not used, because it would take the project's own instructions away.
#
# --strict-mcp-config with an empty file: a worker connects to nothing. Without
# it a worker inherits whatever MCP servers the operator has configured for
# their own sessions, which is both tool descriptions it pays for and reach into
# services the task never asked for.
#
# --no-chrome: same argument, for the browser integration.
claude_flags=(
  --tools 'Bash,Read,Glob,Grep,Write,Edit'
  --strict-mcp-config --mcp-config "$DUX_ROOT/templates/worker-mcp.json"
  --no-chrome
)

# The name the harness's process carries in the pane, for `dux-backend pid`.
# One function, because an install that shows another name changes here alone.
worker_process_name() { echo claude; }

worker_cmd() {  # brief model effort settings; the exec line the launcher carries
  # shellcheck disable=SC2016
  printf 'claude --model %s --effort %s --dangerously-skip-permissions --settings %s %s "$(cat %s)"\n' \
    "$2" "$3" "$4" "${claude_flags[*]}" "$1"
}

# The launcher is what the pane's shell runs. The shell in that pane is the
# harness's parent now, not the wrapper, so everything the wrapper used to do to
# its own environment before forking has to be in this file: the scrub, the
# PATH without Dux's own bin directory, and the three outbox variables. Every
# path is baked in as a single-quoted literal, so a DUX_HOME holding a space
# still works and no Dux environment has to reach the pane. A quote in any of
# them would end a literal early, so it refuses instead, as the ship recorder
# does.
worker_launcher() {  # path brief model effort settings dux_bin [ship_record]
  local path="$1" brief="$2" model="$3" effort="$4" settings="$5" dux_bin="$6" ship="${7:-}"
  local channel q flag
  channel="$(dirname "$path")"
  for q in "$path" "$brief" "$model" "$effort" "$settings" "$dux_bin" "$ship" "$channel" "${claude_flags[@]}"; do
    case "$q" in *\'*) log "cannot build a launcher: a path or value holds a quote"; return 1 ;; esac
  done
  # Every line below is written literally into the launcher; nothing in a
  # single-quoted string here is meant to expand in this shell.
  # shellcheck disable=SC2016
  {
    echo '#!/bin/sh'
    echo '# Starts one worker harness in its own pane. Made for one task and one'
    echo '# run; do not reuse.'
    # 1. The scrub, the same case patterns the wrapper used before it forked.
    echo 'for dux_v in $(env | cut -d= -f1); do'
    echo '  case "$dux_v" in'
    echo '    DUX_*|CLAUDECODE|CLAUDE_*|HERDR_*|TMUX|TMUX_*|GIT_CONFIG_*) unset "$dux_v" ;;'
    echo '  esac'
    echo 'done'
    # 2. PATH without Dux's own bin. strip_dux_bin needs dux-env, which this
    # file must not source, so the same walk is written out with the directory
    # baked in: the wrapper cannot know what the pane shell's PATH will be.
    printf "dux_bin='%s'\n" "$dux_bin"
    echo 'dux_p=""; dux_rest="$PATH"'
    echo 'while :; do'
    echo '  dux_e="${dux_rest%%:*}"'
    echo '  [ "$dux_e" = "$dux_bin" ] || dux_p="${dux_p:+$dux_p:}$dux_e"'
    echo '  case "$dux_rest" in *:*) dux_rest="${dux_rest#*:}" ;; *) break ;; esac'
    echo 'done'
    echo 'PATH="$dux_p"; export PATH'
    # 3. The outboxes, which live in the channel this launcher was written into.
    printf "export DUX_STATUS_LOG='%s' DUX_REPORT='%s'\n" \
      "$channel/status.outbox" "$channel/report.outbox"
    [ -z "$ship" ] || printf "export DUX_SHIP_RECORD='%s'\n" "$ship"
    # 4. The harness itself, as an ordinary interactive session whose opening
    # prompt is the brief. No -p, no --output-format, no --verbose.
    printf "exec claude --model '%s' --effort '%s' --dangerously-skip-permissions --settings '%s'" \
      "$model" "$effort" "$settings"
    for flag in "${claude_flags[@]}"; do printf " '%s'" "$flag"; done
    printf ' "$(cat '"'%s'"')"\n' "$brief"
  } > "$path" || { log "cannot write the launcher at $path"; return 1; }
  chmod 500 "$path" || { log "cannot restrict $path"; return 1; }
}

worker_effort_ok() { case "$1" in low|medium|high|xhigh|max) return 0 ;; *) return 1 ;; esac; }
