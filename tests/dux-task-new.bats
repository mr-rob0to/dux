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
