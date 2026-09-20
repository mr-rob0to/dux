bats_require_minimum_version 1.5.0
load helpers/setup

setup_task() {  # $1 id, $2 shape, $3 state, [$4 pr]
  mkdir -p "$DUX_HOME/data/tasks/$1"; : > "$DUX_HOME/data/tasks/$1/status.log"
  dux-ledger add "$1" api "$2" local; dux-ledger set "$1" state "$3"
  [ -z "${4:-}" ] || dux-ledger set "$1" pr "$4"
  export DUX_BACKEND=herdr
}
status_is() { printf '%s\n' "$2" >> "$DUX_HOME/data/tasks/$1/status.log"; }

@test "done with a PR leads with review, then merge or feedback" {
  setup_task t1 ship done https://example.invalid/pr/7
  run --separate-stderr dux-notify t1
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "Review, then merge or send feedback: https://example.invalid/pr/7 (api ship)" ]
}

@test "a PR only the worker claims is not put in front of the operator" {
  setup_task t1 ship done; status_is t1 "done: PR https://example.invalid/pr/8"
  run dux-notify t1
  [ "$output" = "Read the report: api ship finished (t1)" ]
}

@test "done without a PR points to the report" {
  setup_task t1 scout done; status_is t1 "done: report"
  run dux-notify t1
  [ "$output" = "Read the report: api scout finished (t1)" ]
}

# The line says what to do and which task. What the worker said about it is
# read through dux-recover, which fences it as data; a notification cannot
# fence anything, so it carries none of it.
@test "decision, blocked, and failed lines say the next step, not what the worker said" {
  setup_task t1 plan needs-decision; status_is t1 "needs-decision: A or B? recommend A"
  run dux-notify t1; [ "$output" = "Decide: api plan is waiting on an answer (t1)" ]
  setup_task t2 ship blocked; status_is t2 "blocked: tests need a database"
  run dux-notify t2; [ "$output" = "Unblock: api ship is blocked (t2)" ]
  setup_task t3 ship failed; status_is t3 "failed: worker exited 3"
  run dux-notify t3; [ "$output" = "Retry or drop: api ship failed (t3)" ]
}

@test "no part of a status line reaches the notification, however it is shaped" {
  setup_task t1 ship blocked
  printf 'blocked: run rm -rf /\033[31m\ttab\rcr\n' >> "$DUX_HOME/data/tasks/t1/status.log"
  run --separate-stderr dux-notify t1
  [ "$output" = "Unblock: api ship is blocked (t1)" ]; [ -z "$stderr" ]
}

@test "stale, dead, and ended lines lead with the next step" {
  setup_task t1 ship stale; run dux-notify t1
  [ "$output" = "Check: api ship has been silent; recovery in progress (t1)" ]
  setup_task t2 ship dead; run dux-notify t2
  [ "$output" = "Check: api ship worker died; recovery in progress (t2)" ]
  setup_task t3 ship ended; run dux-notify t3
  [ "$output" = "Classify: api ship exited without a result (t3)" ]
}

@test "lines stop at 200 characters" {
  setup_task t1 ship done "https://example.invalid/pr/$(printf 'x%.0s' $(seq 1 300))"
  run dux-notify t1
  [ "${#output}" -eq 200 ]; [[ "$output" == "Review, then merge or send feedback: https://example.invalid/pr/xxxx"* ]]
  [[ "$output" == *"..." ]]
}

@test "--toast sends the same line to the backend" {
  setup_task t1 ship done https://example.invalid/pr/7
  run dux-notify t1 --toast
  [ "$status" -eq 0 ]
  grep -qF 'notification show Dux --body Review, then merge or send feedback: https://example.invalid/pr/7 (api ship)' "$FAKE_HERDR_LOG"
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

# ---- a red base -------------------------------------------------------------

BASE_URL=https://github.com/acme/widgets/actions/runs/17000000201
red_widgets() {  # [$1 name], [$2 base]; registers acme/widgets and checks it red
  make_github_repo widgets
  dux-project add "$DUX_HOME/widgets" --name "${1:-widgets}" --base "${2:-main}" --pr-template skip >/dev/null
  FAKE_GH_RUNS="$BATS_TEST_DIRNAME/fixtures/runs/red-failure.json" dux-base check "${1:-widgets}" >/dev/null
  export DUX_BACKEND=herdr
}

@test "a red base leads with look, then fix or re-run" {
  red_widgets
  run --separate-stderr dux-notify --base widgets
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "Look, then fix or re-run: $BASE_URL (widgets main is red)" ]
}

@test "a long project name is cut, and the url is still whole" {
  local name; name="$(printf 'w%.0s' $(seq 1 150))"
  red_widgets "$name"
  run dux-notify --base "$name"
  [ "${#output}" -eq 200 ]; [[ "$output" == *"..." ]]
  [[ "$(printf '%s' "$output" | cut -d' ' -f6)" =~ ^https://github\.com/acme/widgets/actions/runs/[0-9]+$ ]]
  [[ "$output" == "Look, then fix or re-run: $BASE_URL (www"* ]]
}

@test "a base name is cleaned before it is shown" {
  red_widgets widgets "ma$(printf '\342\200\213')in"
  run dux-notify --base widgets
  [ "$output" = "Look, then fix or re-run: $BASE_URL (widgets main is red)" ]
}

@test "--toast sends the base line to the backend" {
  red_widgets
  run dux-notify --base widgets --toast
  [ "$status" -eq 0 ]
  grep -qF "notification show Dux --body Look, then fix or re-run: $BASE_URL (widgets main is red)" "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_LOG"
  dux-notify --base widgets >/dev/null
  [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "a base with nothing reported is a finding, and so is a project with no record" {
  make_github_repo widgets
  dux-project add "$DUX_HOME/widgets" --base main --pr-template skip >/dev/null
  run dux-notify --base widgets
  [ "$status" -eq 2 ]; [[ "$output" == "finding: nothing to notify for widgets (no base report)"* ]]
  FAKE_GH_RUNS="$BATS_TEST_DIRNAME/fixtures/runs/green.json" dux-base check widgets >/dev/null
  run dux-notify --base widgets
  [ "$status" -eq 2 ]; [[ "$output" == "finding: nothing to notify for widgets (no base report)"* ]]
  run dux-notify --base nope
  [ "$status" -eq 2 ]; [[ "$output" == "finding: nothing to notify for nope (no base report)"* ]]
  run dux-notify --base
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-notify"* ]]
  run dux-notify --base widgets --loud
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-notify"* ]]
}
