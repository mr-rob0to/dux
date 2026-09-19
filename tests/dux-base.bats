bats_require_minimum_version 1.5.0
load helpers/setup

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
RUNS_URL=https://github.com/acme/widgets/actions/runs

runs() { printf '%s' "$BATS_TEST_DIRNAME/fixtures/runs/$1"; }
widgets() {  # [$1 base]; registers acme/widgets on main unless another base is named
  make_github_repo widgets
  dux-project add "$DUX_HOME/widgets" --base "${1:-main}" --pr-template skip >/dev/null
}
record() { printf '%s' "$DUX_HOME/state/base/widgets/record"; }
check_with() { FAKE_GH_RUNS="$(runs "$1")" dux-base check widgets; }  # $1 fixture
# A base already seen red, and a copy of its record to compare against.
red_base() { widgets; check_with red-failure.json >/dev/null; cp "$(record)" "$DUX_HOME/record.before"; }
record_unchanged() { cmp "$DUX_HOME/record.before" "$(record)"; }
no_call_folder() { local f; for f in "$DUX_HOME"/state/base-call.*; do [ ! -e "$f" ] || return 1; done; }
reap_later() { printf '%s\n' "$@" >> "$DUX_HOME/state/stand-ins"; }

# ---- what one base branch answers ------------------------------------------

@test "only five fields are asked for" {
  widgets
  check_with green.json >/dev/null
  [ "$(cat "$FAKE_GH_LOG")" = "run list --repo acme/widgets --branch main --event push --limit 20 --json databaseId,headSha,status,conclusion,attempt" ]
}

@test "a failed run is red, and the record names that run" {
  widgets
  run --separate-stderr check_with red-failure.json
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "widgets main red $RUNS_URL/17000000201" ]
  [ "$(sed -n '1,4p' "$(record)")" = "verdict=red
sha=$A
run=17000000201
attempt=1" ]
  [[ "$(dux-base get widgets checked)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  no_call_folder
}

@test "a run that timed out is red" {
  widgets
  run check_with red-timed-out.json
  [ "$output" = "widgets main red $RUNS_URL/17000000201" ]
  [ "$(dux-base get widgets verdict)" = red ]
}

@test "a run that could not start is red" {
  widgets
  run check_with red-startup-failure.json
  [ "$output" = "widgets main red $RUNS_URL/17000000201" ]
  [ "$(dux-base get widgets verdict)" = red ]
}

@test "red wins while another run on the same commit is still going" {
  widgets
  run check_with red-while-pending.json
  [ "$output" = "widgets main red $RUNS_URL/17000000201" ]
  [ "$(dux-base get widgets verdict)" = red ]
}

@test "a passing run is green, and the record names that run" {
  widgets
  run --separate-stderr check_with green.json
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "widgets main green" ]
  [ "$(dux-base get widgets verdict)" = green ]
  [ "$(dux-base get widgets sha)" = "$A" ]
  [ "$(dux-base get widgets run)" = 17000000201 ]
  [ "$(dux-base get widgets attempt)" = 1 ]
}

@test "the highest run id picks the commit, whatever order the rows arrive in" {
  red_base
  run check_with green-over-older-red.json
  [ "$output" = "widgets main green" ]
  [ "$(dux-base get widgets sha)" = "$B" ]
  [ "$(dux-base get widgets run)" = 17000000301 ]
}

@test "a newer commit still running is pending and leaves a red base red" {
  red_base
  run --separate-stderr check_with pending.json
  [ "$status" -eq 0 ]; [ "$output" = "widgets main pending" ]
  record_unchanged
}

@test "no push runs at all is none, and writes nothing" {
  widgets
  run check_with none-no-runs.json
  [ "$output" = "widgets main none" ]
  [ ! -e "$(record)" ]
}

@test "a cancelled newer run does not clear a red base" {
  red_base
  run check_with none-cancelled.json
  [ "$output" = "widgets main none" ]
  record_unchanged
}

@test "a status or conclusion GitHub adds later is never no answer" {
  red_base
  run check_with unknown-status.json
  [ "$output" = "widgets main pending" ]
  run check_with unknown-conclusion.json
  [ "$output" = "widgets main none" ]
  record_unchanged
}

# ---- no answer ------------------------------------------------------------

@test "a poll GitHub did not answer leaves a red base red" {
  red_base
  FAKE_GH_RUN_EXIT=1 run --separate-stderr check_with green.json
  [ "$status" -eq 0 ]; [ "$output" = "widgets main no-answer" ]
  [ "$stderr" = "dux: base: widgets: no answer from GitHub (gh exited 1)" ]
  record_unchanged
}

@test "an answer that is not JSON is no answer" {
  red_base
  run --separate-stderr check_with not-json.txt
  [ "$output" = "widgets main no-answer" ]
  [ "$stderr" = "dux: base: widgets: no answer from GitHub (the answer is out of shape)" ]
  record_unchanged
}

@test "a run id that is not a number is no answer" {
  red_base
  run --separate-stderr check_with run-id-not-digits.json
  [ "$output" = "widgets main no-answer" ]
  [ "$stderr" = "dux: base: widgets: no answer from GitHub (the answer is out of shape)" ]
  record_unchanged
}

@test "a commit that is not 40 hex is no answer" {
  red_base
  run --separate-stderr check_with sha-not-hex.json
  [ "$output" = "widgets main no-answer" ]
  [ "$stderr" = "dux: base: widgets: no answer from GitHub (the answer is out of shape)" ]
  record_unchanged
}

@test "a call that hangs is stopped" {
  red_base
  : > "$DUX_HOME/gh.pids"
  # The test holds its own ceiling, so a check that never stops the call
  # fails here instead of hanging the suite.
  FAKE_GH_RUN_SLEEP=30 FAKE_GH_PIDS="$DUX_HOME/gh.pids" DUX_BASE_GH_SECS=1 \
    dux-base check widgets > "$DUX_HOME/out" 2> "$DUX_HOME/err" 3>&- &
  local check=$!
  reap_later "$check"
  wait_until 5 test -s "$DUX_HOME/gh.pids"
  reap_later "$(cat "$DUX_HOME/gh.pids")"
  wait_until 10 not_running "$check"
  [ "$(cat "$DUX_HOME/out")" = "widgets main no-answer" ]
  [ "$(cat "$DUX_HOME/err")" = "dux: base: widgets: no answer from GitHub within 1s" ]
  wait_until 2 not_running "$(cat "$DUX_HOME/gh.pids")"
  no_call_folder
  record_unchanged
}

# ---- reading the record ---------------------------------------------------

@test "get reads each key of the record" {
  red_base
  [ "$(dux-base get widgets verdict)" = red ]
  [ "$(dux-base get widgets sha)" = "$A" ]
  [ "$(dux-base get widgets run)" = 17000000201 ]
  [ "$(dux-base get widgets attempt)" = 1 ]
  [ "$(dux-base get widgets acked)" = - ]
}

@test "a project with no record, a key get does not know, and a bad name are findings" {
  widgets
  run dux-base get widgets verdict
  [ "$status" -eq 2 ]; [[ "$output" == "finding: no base record for widgets"* ]]
  check_with red-failure.json >/dev/null
  run dux-base get widgets color
  [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown base key color"* ]]
  run dux-base get ../widgets verdict
  [ "$status" -eq 2 ]; [[ "$output" == "finding: project name must match [A-Za-z0-9._-]+: ../widgets"* ]]
}

@test "a project that is not registered is a finding from the registry" {
  run dux-base check nope
  [ "$status" -eq 2 ]; [[ "$output" == "finding: project nope not registered"* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "bad arguments are a usage finding" {
  run dux-base
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-base check [<project>] | get <project> <key> | ack <project> <key> | list --unacked"* ]]
  run dux-base check a b
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-base"* ]]
}
