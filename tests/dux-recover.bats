bats_require_minimum_version 1.5.0
load helpers/setup

setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  export GIT_AUTHOR_NAME=dux-test GIT_AUTHOR_EMAIL=dux-test@example.invalid
  export GIT_COMMITTER_NAME=dux-test GIT_COMMITTER_EMAIL=dux-test@example.invalid
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  cp "$DUX_ROOT"/templates/config/* "$DUX_HOME/config/"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log" FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log" FAKE_GH_LOG="$DUX_HOME/state/fake-gh.log"
  : > "$FAKE_HERDR_LOG"; : > "$FAKE_HERDR_OUTPUT"; : > "$FAKE_WORKER_LOG"; : > "$FAKE_GH_LOG"
  export DUX_BACKEND=herdr HERDR_WORKSPACE_ID=w1 DUX_WATCHER=off DUX_RECOVER_WAIT_SECS=5
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

task_in() {  # $1 state, [$2 shape]; sets id
  local task shape="${2:-scout}"
  if ! dux-project list | grep -qx proj; then
    make_repo "$DUX_HOME/proj" main
    dux-project add "$DUX_HOME/proj" --base main >/dev/null
  fi
  id="$(dux-task-new proj "$shape")"; task="$DUX_HOME/data/tasks/$id"
  printf 'Do the thing the operator asked for.\n' > "$task/intent.md"
  printf '1. The thing is done.\n' > "$task/criteria.md"
  if [ "$shape" = ship ]; then
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" --plan docs/plan.md --tasks 1-2 >/dev/null
  else
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" >/dev/null
  fi
  dux-ledger set "$id" endpoint herdr:w1:p9; dux-ledger set "$id" state "$1"
  echo herdr:w1:p9 > "$DUX_HOME/state/$id.endpoint"
  stand_in "dux-worker-wrap $id" > "$DUX_HOME/state/$id.pid"
  seq 1 50 | sed 's/^/{"type":"assistant","text":"line /; s/$/"}/' > "$DUX_HOME/state/$id.out"
}
status_is() { printf '%s\n' "$1" >> "$DUX_HOME/data/tasks/$id/status.log"; }
kill_worker() { kill -9 "$(cat "$DUX_HOME/state/$id.pid")"; wait_until 5 bash -c "! kill -0 $(cat "$DUX_HOME/state/$id.pid") 2>/dev/null"; }

@test "recovery requires this session's lock" {
  task_in stale
  DUX_SESSION_PID=424242 run dux-recover "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: the Dux lock is not held by this session; refusing to recover"* ]]
}

@test "stale inspect prints capped status and output evidence" {
  task_in stale; for i in 1 2 3 4 5 6; do status_is "working: step $i"; done
  run --separate-stderr dux-recover "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == "task $id (proj scout) state=stale"$'\n'"extended: no (--extend is available once)"* ]]
  [ "$(grep -c '^working: step' <<< "$output")" -eq 5 ]
  [ "$(grep -c '^working: step 1$' <<< "$output" || true)" -eq 0 ]
  [[ "$output" == *"<untrusted-output>"*"</untrusted-output>"* ]]
  [ "$(sed -n '/<untrusted-output>/,/<\/untrusted-output>/p' <<< "$output" | grep -c 'line ')" -eq 40 ]
  [[ "$output" == *"line 50"* ]]; [ "$(grep -c '"line 10"' <<< "$output" || true)" -eq 0 ]
  [[ "$output" == *"next: dux-recover $id --extend"*"or  dux-recover $id --stop"* ]]
}

@test "recovery tail cuts lines and strips control characters" {
  task_in stale
  printf 'a%.0s' $(seq 1 400) > "$DUX_HOME/state/$id.out"; printf '\n\033[1mbold\r\n' >> "$DUX_HOME/state/$id.out"
  DUX_RECOVER_LINE_CHARS=50 run dux-recover "$id"
  [ "$(sed -n '/<untrusted-output>/,/<\/untrusted-output>/p' <<< "$output" | sed -n 2p | wc -c | tr -d ' ')" -eq 51 ]
  [[ "$output" == *$'\n[1mbold\n'* ]]
}

@test "--extend works once, returns running, and clears ack" {
  task_in stale; status_is "working: slow"; dux-ledger ack "$id"
  run dux-recover "$id" --extend
  [ "$status" -eq 0 ]; [ "$output" = "extended $id once; stale again after 1200s of silence" ]
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/$id/status.log")" = "working: extended once by dux-recover" ]
  [ "$(dux-ledger get "$id" state)" = running ]; [ "$(dux-ledger get "$id" acked)" = - ]
  dux-ledger set "$id" state stale
  run dux-recover "$id" --extend
  [ "$status" -eq 2 ]; [[ "$output" == "finding: $id was already extended once; the next step is --stop"* ]]
  run dux-recover "$id"; [[ "$output" == *"extended: yes (once; the next step is --stop)"* ]]
}

@test "--stop refuses a process that is not the wrapper" {
  task_in stale; kill_worker
  stand_in bystander > "$DUX_HOME/state/$id.pid"
  run dux-recover "$id" --stop
  [ "$status" -eq 2 ]; [[ "$output" == "finding: no live wrapper for $id; the watcher will report it dead"* ]]
  kill -0 "$(cat "$DUX_HOME/state/$id.pid")"; [ "$(dux-ledger get "$id" state)" = stale ]
}

@test "--stop interrupts a real wrapper and follows its failure" {
  export FAKE_HERDR_RUN=1 FAKE_WORKER_SCRIPT="$DUX_HOME/state/script" DUX_WRAP_POLL_SECS=1
  printf 'status working: starting\nsleep 300\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"; dux-spawn "$id" >/dev/null
  wait_until 15 grep -q '^working: starting' "$DUX_HOME/data/tasks/$id/status.log"
  wait_until 5 test -s "$DUX_HOME/state/$id.pid"
  dux-ledger set "$id" state stale
  run dux-recover "$id" --stop
  [ "$status" -eq 0 ]; [[ "$output" == "stopped $id; the wrapper wrote 'failed: worker exited 143'" ]]
  [ "$(dux-ledger get "$id" state)" = failed ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  wait_until 5 bash -c "! kill -0 $(cat "$DUX_HOME/state/$id.pid") 2>/dev/null"
}

@test "--stop waits before refusing a wrapper that ignores SIGINT" {
  task_in stale; kill_worker
  ( trap '' INT; exec -a "dux-worker-wrap $id" sleep 300 ) 3>&- &
  echo $! > "$DUX_HOME/state/$id.pid"; echo $! >> "$DUX_HOME/state/stand-ins"
  t0="$(date +%s)"
  DUX_RECOVER_WAIT_SECS=2 run dux-recover "$id" --stop
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: wrapper pid $(cat "$DUX_HOME/state/$id.pid") for $id is still running 2s after SIGINT; kill it by hand, then rerun"* ]]
  [ $(( $(date +%s) - t0 )) -ge 2 ]; [ "$(dux-ledger get "$id" state)" = stale ]
  [ "$(grep -c '^failed:' "$DUX_HOME/data/tasks/$id/status.log" || true)" -eq 0 ]
}

@test "dead refuses a live wrapper then marks a gone one failed" {
  task_in dead; status_is "working: last words"
  run dux-recover "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: wrapper pid $(cat "$DUX_HOME/state/$id.pid") for $id is alive; $id is not dead"* ]]
  kill_worker
  run dux-recover "$id"
  [ "$status" -eq 0 ]; [ "$output" = "marked $id failed; worktree kept; last 20 output lines saved to tasks/$id/report.md" ]
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/$id/status.log")" = "failed: worker gone without an exit line (dux-recover)" ]
  [ "$(dux-ledger get "$id" state)" = failed ]
  [ "$(sed -n '/^## Failure tail/,$p' "$DUX_HOME/data/tasks/$id/report.md" | grep -c 'line ')" -eq 20 ]
}

@test "a later exit line wins without signalling" {
  task_in stale; status_is "done: PR https://example.invalid/pr/5"
  run dux-recover "$id" --stop
  [ "$status" -eq 0 ]
  [ "$output" = "worker for $id already wrote 'done: PR https://example.invalid/pr/5'; ledger set to done; nothing to recover" ]
  [ "$(dux-ledger get "$id" state)" = done ]; [ "$(dux-ledger get "$id" pr)" = https://example.invalid/pr/5 ]
  kill -0 "$(cat "$DUX_HOME/state/$id.pid")"
}

@test "ended with a branch PR becomes done with its URL" {
  task_in ended; status_is "ended: exit 0 without terminal status"
  FAKE_GH_PR_LIST='[{"url":"https://example.invalid/pr/9","state":"OPEN"}]' run dux-recover "$id"
  [ "$status" -eq 0 ]; [ "$output" = "classified $id as done: PR https://example.invalid/pr/9" ]
  grep -q "^pr list --head dux/$id --state all --json url,state" "$FAKE_GH_LOG"
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/$id/status.log")" = "done: PR https://example.invalid/pr/9" ]
  [ "$(dux-ledger get "$id" state)" = done ]; [ "$(dux-ledger get "$id" pr)" = https://example.invalid/pr/9 ]
}

@test "ended uses a report or an explicit classification" {
  task_in ended; status_is "ended: exit 0 without terminal status"
  echo "# Findings" > "$DUX_HOME/data/tasks/$id/report.md"
  run dux-recover "$id"
  [ "$output" = "classified $id as done: report" ]; [ "$(dux-ledger get "$id" state)" = done ]
  task_in ended; status_is "ended: exit 0 without terminal status"
  run dux-recover "$id"
  [ "$status" -eq 0 ]; [[ "$output" == "unsure: no PR on dux/$id and no report; ask the operator, then dux-recover $id --classify done|failed" ]]
  [ "$(dux-ledger get "$id" state)" = ended ]
  run dux-recover "$id" --classify failed
  [ "$status" -eq 0 ]; [ "$(tail -n 1 "$DUX_HOME/data/tasks/$id/status.log")" = "failed: classified by the operator" ]
  [ "$(dux-ledger get "$id" state)" = failed ]; grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
}

@test "ended treats a gh failure as a finding" {
  task_in ended; status_is "ended: exit 0 without terminal status"
  echo "# Findings" > "$DUX_HOME/data/tasks/$id/report.md"
  FAKE_GH_FAIL=1 run dux-recover "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: gh pr list failed for dux/$id; cannot tell whether a PR exists"* ]]
  [ "$(dux-ledger get "$id" state)" = ended ]; [ "$(grep -c '^done:' "$DUX_HOME/data/tasks/$id/status.log" || true)" -eq 0 ]
}

@test "an unreadable pidfile is a finding" {
  task_in dead; kill_worker; chmod 000 "$DUX_HOME/state/$id.pid"
  run dux-recover "$id"
  chmod 644 "$DUX_HOME/state/$id.pid"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: cannot read $DUX_HOME/state/$id.pid"* ]]
  [ "$(dux-ledger get "$id" state)" = dead ]
}

@test "a failure-only report does not classify ended as done" {
  task_in ended; status_is "ended: exit 0 without terminal status"
  printf '## Failure\nwrapper: no brief\n' > "$DUX_HOME/data/tasks/$id/report.md"
  run dux-recover "$id"
  [[ "$output" == "unsure:"* ]]
}

@test "failed inspect prints the saved failure and retry next step" {
  task_in failed; status_is "failed: worker exited 3"
  printf '## Failure tail\nboom\n' > "$DUX_HOME/data/tasks/$id/report.md"
  run dux-recover "$id"
  [[ "$output" == *"## Failure tail (from report.md)"*"boom"* ]]
  [[ "$output" == *"next: retry through dux-dispatch, or dispatch a scout" ]]
}

@test "blocked inspect prints status for verbatim relay" {
  task_in blocked; status_is "blocked: cannot reach the database"
  run dux-recover "$id"
  [[ "$output" == *"## Last status lines (relay verbatim)"$'\n'"blocked: cannot reach the database"* ]]
  [[ "$output" == *"next: relay the answer, then retry through dux-dispatch" ]]
}
