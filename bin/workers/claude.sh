#!/usr/bin/env bash
# Claude Code worker adapter. Sourced by dux-worker-wrap after dux-env. Spec section 19.
set -u

worker_cmd() {  # brief model effort settings
  # shellcheck disable=SC2016
  printf 'claude -p "$(cat %s)" --model %s --effort %s --dangerously-skip-permissions --settings %s --output-format stream-json --verbose\n' \
    "$1" "$2" "$3" "$4"
}

worker_run() {  # brief model effort settings; replaces the current process
  exec claude -p "$(cat "$1")" --model "$2" --effort "$3" --dangerously-skip-permissions \
    --settings "$4" --output-format stream-json --verbose
}

worker_effort_ok() { case "$1" in low|medium|high|xhigh|max) return 0 ;; *) return 1 ;; esac; }
