#!/usr/bin/env bash
# Codex worker adapter. Sourced by dux-worker-wrap after dux-env. Spec section 19.
# Full access: a linked worktree's git dir lives under the primary checkout, outside
# any workspace-write root. The default environment policy drops names containing
# KEY, which would strip GIT_CONFIG_KEY_0 and break every git call.
set -u

worker_cmd() {  # brief model effort settings(ignored)
  # shellcheck disable=SC2016
  printf 'codex exec -m %s --sandbox danger-full-access -c shell_environment_policy.ignore_default_excludes=true -c model_reasoning_effort="%s" "$(cat %s)"\n' \
    "$2" "$3" "$1"
}

worker_run() {  # brief model effort settings(ignored); replaces the current process
  exec codex exec -m "$2" --sandbox danger-full-access -c shell_environment_policy.ignore_default_excludes=true \
    -c "model_reasoning_effort=\"$3\"" "$(cat "$1")"
}

worker_effort_ok() { case "$1" in minimal|low|medium|high|xhigh) return 0 ;; *) return 1 ;; esac; }
