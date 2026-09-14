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

worker_cmd() {  # brief model effort settings
  # shellcheck disable=SC2016
  printf 'claude -p "$(cat %s)" --model %s --effort %s --dangerously-skip-permissions --settings %s --output-format stream-json --verbose %s\n' \
    "$1" "$2" "$3" "$4" "${claude_flags[*]}"
}

worker_run() {  # brief model effort settings; replaces the current process
  exec claude -p "$(cat "$1")" --model "$2" --effort "$3" --dangerously-skip-permissions \
    --settings "$4" --output-format stream-json --verbose "${claude_flags[@]}"
}

worker_effort_ok() { case "$1" in low|medium|high|xhigh|max) return 0 ;; *) return 1 ;; esac; }
