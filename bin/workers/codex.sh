#!/usr/bin/env bash
# Codex worker adapter. Sourced by dux-worker-wrap after dux-env. Spec section 19.
# Full access: a linked worktree's git dir lives under the primary checkout, outside
# any workspace-write root. The ignore_default_excludes flag was here because the
# default environment policy drops names containing KEY, which stripped
# GIT_CONFIG_KEY_0 and broke every git call. That variable is gone: the push guard
# is the worktree's own git configuration now, so nothing about git is handed to a
# worker. The flag is kept until this adapter is next touched.
set -u

worker_cmd() {  # brief model effort settings(ignored)
  # shellcheck disable=SC2016
  printf 'codex exec -m %s --sandbox danger-full-access -c shell_environment_policy.ignore_default_excludes=true -c model_reasoning_effort="%s" "$(cat %s)"\n' \
    "$2" "$3" "$1"
}

# A ship task's recorder and the gate's guard travel in the environment, as the
# claude launcher exports them, so the command line is the same for every shape.
worker_run() {  # brief model effort settings(ignored) [ship_record] [ship_guard]; replaces the current process
  [ -z "${5:-}" ] || export DUX_SHIP_RECORD="$5"
  [ -z "${6:-}" ] || export SHIP_GUARD="$6"
  exec codex exec -m "$2" --sandbox danger-full-access -c shell_environment_policy.ignore_default_excludes=true \
    -c "model_reasoning_effort=\"$3\"" "$(cat "$1")"
}

worker_effort_ok() { case "$1" in minimal|low|medium|high|xhigh) return 0 ;; *) return 1 ;; esac; }

# The usage a `codex exec --json` event stream on stdin reports, as one line:
# `input=<n> output=<n> cache_read=<n> cache_write=<n>`, each a count or
# `unknown`. Only the usage field of a top-level turn.completed event is read,
# never what a run said or what its commands printed, so a reviewer whose events
# a worker printed is counted from the reviewer's own stream alone. Codex counts
# cached input inside input and reasoning inside output (the rollout plan, task
# 32), so cached input is taken out and nothing is added. A resumed thread
# reports its running total, so each thread's last total counts once. Any cache
# write leaves input unknown, since no probe showed whether input includes it.
worker_usage() {
  jq -R -r -s '
    def tokens: if type == "number" and . >= 0 and . == floor then . else null end;
    def total: reduce .[] as $v (0; if . == null or $v == null then null else . + $v end);
    [split("\n")[] | fromjson? | objects]
    | reduce .[] as $e ({thread: null, runs: {}, n: 0};
        if $e.type == "thread.started" then .thread = (($e.thread_id | strings) // null)
        elif $e.type == "turn.completed" then
          (if .thread == null then "run \(.n)" else "thread \(.thread)" end) as $k
          | .runs[$k] = ($e.usage | objects // {}) | .n += 1
        else . end)
    | [.runs[]] as $runs
    | def sum(f): if ($runs | length) == 0 then null else [$runs[] | f] | total end;
      {
        input: sum((.input_tokens | tokens) as $i | (.cached_input_tokens | tokens) as $c
                   | if $i != null and $c != null and $i >= $c
                        and (.cache_write_input_tokens | tokens) == 0
                     then $i - $c else null end),
        output: sum(.output_tokens | tokens),
        cache_read: sum(.cached_input_tokens | tokens),
        cache_write: sum(.cache_write_input_tokens | tokens)
      }
    | "input=\(.input // "unknown") output=\(.output // "unknown") cache_read=\(.cache_read // "unknown") cache_write=\(.cache_write // "unknown")"
  '
}
