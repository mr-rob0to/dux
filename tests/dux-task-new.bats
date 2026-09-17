bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

setup_project() { make_repo "$DUX_HOME/proj" main; dux-project add "$DUX_HOME/proj" --base main --pr-template skip >/dev/null; }

@test "allocates an id, a folder with an empty status log, and a queued ledger line" {
  setup_project
  # Separated, because a merged stderr line would corrupt the id and the failure
  # would name the pattern without ever showing the value that missed it.
  run --separate-stderr dux-task-new proj scout
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  if ! [[ "$output" =~ ^proj-scout-[0-9]{8}-[a-z0-9]{3}$ ]]; then
    echo "id does not match ^proj-scout-[0-9]{8}-[a-z0-9]{3}\$: '$output'"; return 1
  fi
  [ -d "$DUX_HOME/data/tasks/$output" ]
  [ -f "$DUX_HOME/data/tasks/$output/status.log" ]
  [ ! -s "$DUX_HOME/data/tasks/$output/status.log" ]
  [ "$(dux-ledger get "$output" state)" = queued ]
  [ "$(dux-ledger get "$output" source)" = local ]
  [ "$(dux-ledger get "$output" shape)" = scout ]
}

@test "refuses an unregistered project and leaves nothing behind" {
  run dux-task-new ghost scout
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project ghost not registered"* ]]
  [ -z "$(ls -A "$DUX_HOME/data/tasks")" ]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
}

@test "refuses an unknown shape" {
  setup_project
  run dux-task-new proj deploy
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown shape deploy"* ]]
  [ -z "$(ls -A "$DUX_HOME/data/tasks")" ]
}

@test "records a gh source and refuses a malformed one" {
  setup_project
  id="$(dux-task-new proj ship --source 'gh:acme/widgets#12')"
  [ "$(dux-ledger get "$id" source)" = 'gh:acme/widgets#12' ]
  run dux-task-new proj ship --source 'gh:acme/widgets'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: source must be local or gh:<owner>/<repo>#<n>"* ]]
  run dux-task-new proj ship --source jira:1
  [ "$status" -eq 2 ]
}

@test "five collisions are a finding, not a loop" {
  setup_project
  DUX_TASK_SUFFIX=abc dux-task-new proj scout >/dev/null
  DUX_TASK_SUFFIX=abc run dux-task-new proj scout
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: could not allocate a task id for proj after 5 tries"* ]]
  [ "$(dux-ledger list | wc -l | tr -d ' ')" -eq 1 ]
}

# ---- one predecessor ---------------------------------------------------------
# A task can wait on one earlier task that delivers a pull request. The waiting
# task keeps the reference in its own folder; the task it waits on is untouched.

@test "--after records the one task a new task waits on, in the new task's own folder" {
  setup_project
  first="$(dux-task-new proj ship)"
  other="$(dux-task-new proj ship)"
  id="$(dux-task-new proj ship --after "$first")"
  [ "$(cat "$DUX_HOME/data/tasks/$id/after")" = "$first" ]
  [ ! -e "$DUX_HOME/data/tasks/$first/after" ]
  [ "$(dux-ledger get "$id" state)" = queued ]
  id="$(dux-task-new proj scout --source 'gh:acme/widgets#12' --after "$other")"
  [ "$(cat "$DUX_HOME/data/tasks/$id/after")" = "$other" ]
  [ "$(dux-ledger get "$id" source)" = 'gh:acme/widgets#12' ]
  id="$(dux-task-new proj ship)"
  [ ! -e "$DUX_HOME/data/tasks/$id/after" ]
}

@test "--after takes one known ship task, and a refusal leaves nothing behind" {
  setup_project
  first="$(dux-task-new proj ship)"
  second="$(dux-task-new proj ship)"
  scout="$(dux-task-new proj scout)"
  planned="$(dux-task-new proj plan)"
  run dux-task-new proj ship --after "$first" --after "$second"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: a task waits on one task at most; sequencing is linear, so --after comes once" ]
  run dux-task-new proj ship --after ../x
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task id must match [A-Za-z0-9._-]+: ../x" ]
  run dux-task-new proj ship --after ''
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task id must match [A-Za-z0-9._-]+: " ]
  run dux-task-new proj ship --after proj-ship-20260916-zzz
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task proj-ship-20260916-zzz not in ledger" ]
  run dux-task-new proj ship --after "$scout"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task $scout is a scout task; only ship work can be waited on, because only its delivered commit is on record" ]
  run dux-task-new proj ship --after "$planned"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task $planned is a plan task; only ship work can be waited on, because only its delivered commit is on record" ]
  run dux-task-new proj ship --after
  [ "$status" -eq 1 ]
  [ "$output" = "dux: --after needs a task id" ]
  [ "$(ls "$DUX_HOME/data/tasks" | wc -l | tr -d ' ')" -eq 4 ]
  [ "$(dux-ledger list | wc -l | tr -d ' ')" -eq 4 ]
}
