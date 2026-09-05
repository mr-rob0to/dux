bats_require_minimum_version 1.5.0
load helpers/setup

setup_task() {  # $1 id, $2 shape, $3 state, [$4 pr]
  mkdir -p "$DUX_HOME/data/tasks/$1"; : > "$DUX_HOME/data/tasks/$1/status.log"
  dux-ledger add "$1" api "$2" local; dux-ledger set "$1" state "$3"
  [ -z "${4:-}" ] || dux-ledger set "$1" pr "$4"
  export DUX_BACKEND=herdr
}
status_is() { printf '%s\n' "$2" >> "$DUX_HOME/data/tasks/$1/status.log"; }

@test "done with a PR leads with review and merge" {
  setup_task t1 ship done https://example.invalid/pr/7
  run --separate-stderr dux-notify t1
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "Review and merge: https://example.invalid/pr/7 (api ship)" ]
}

@test "a PR found only in the status log is included" {
  setup_task t1 ship done; status_is t1 "done: PR https://example.invalid/pr/8"
  run dux-notify t1
  [ "$output" = "Review and merge: https://example.invalid/pr/8 (api ship)" ]
}

@test "done without a PR points to the report" {
  setup_task t1 scout done; status_is t1 "done: report"
  run dux-notify t1
  [ "$output" = "Read the report: api scout finished (t1)" ]
}

@test "decision, blocked, and failed lines carry status text" {
  setup_task t1 plan needs-decision; status_is t1 "needs-decision: A or B? recommend A"
  run dux-notify t1; [ "$output" = "Decide: A or B? recommend A (api plan)" ]
  setup_task t2 ship blocked; status_is t2 "blocked: tests need a database"
  run dux-notify t2; [ "$output" = "Unblock: tests need a database (api ship)" ]
  setup_task t3 ship failed; status_is t3 "failed: worker exited 3"
  run dux-notify t3; [ "$output" = "Retry or drop: api ship failed: worker exited 3" ]
}

@test "stale, dead, and ended lines lead with the next step" {
  setup_task t1 ship stale; run dux-notify t1
  [ "$output" = "Check: api ship has been silent; recovery in progress (t1)" ]
  setup_task t2 ship dead; run dux-notify t2
  [ "$output" = "Check: api ship worker died; recovery in progress (t2)" ]
  setup_task t3 ship ended; run dux-notify t3
  [ "$output" = "Classify: api ship exited without a result (t3)" ]
}

@test "lines stop at 200 characters and discard control characters" {
  setup_task t1 ship needs-decision
  long="$(printf 'x%.0s' $(seq 1 300))"
  status_is t1 "needs-decision: $long"
  run dux-notify t1
  [ "${#output}" -eq 200 ]; [[ "$output" == "Decide: xxxx"* ]]; [[ "$output" == *"..." ]]
  setup_task t2 ship blocked
  printf 'blocked: line one\033[31m\ttab\rcr\n' >> "$DUX_HOME/data/tasks/t2/status.log"
  run dux-notify t2
  [ "$output" = "Unblock: line one[31m tabcr (api ship)" ]
}

@test "--toast sends the same line to the backend" {
  setup_task t1 ship done https://example.invalid/pr/7
  run dux-notify t1 --toast
  [ "$status" -eq 0 ]
  grep -qF 'notification show Dux --body Review and merge: https://example.invalid/pr/7 (api ship)' "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_LOG"
  dux-notify t1 >/dev/null
  [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "non-event states and invalid requests are findings" {
  for state in queued running dropped; do
    setup_task "t-$state" ship "$state"
    run dux-notify "t-$state"
    [ "$status" -eq 2 ]; [[ "$output" == "finding: nothing to notify for t-$state (state $state)"* ]]
  done
  run dux-notify nope; [ "$status" -eq 2 ]; [[ "$output" == "finding: task nope not in ledger"* ]]
  run dux-notify t-queued --loud; [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-notify <id> [--toast]"* ]]
}
