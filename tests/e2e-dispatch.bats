# bats file_tags=e2e
load helpers/setup

# Runs once per (DUX_BACKEND, DUX_WORKER_HARNESS) pair. Milestone 2 dispatches only
# claude workers, so the Makefile runs it twice: one line per backend.
setup_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    export DUX_TMUX_SOCKET=dux-e2e DUX_TMUX_SESSION=duxe2e
    tmux -L dux-e2e kill-server 2>/dev/null || true
    tmux -L dux-e2e new-session -d -s duxe2e -x 80 -y 24
    # The pane command runs through the default shell; a login shell's rc files
    # re-prepend the operator's real tools ahead of the fakes. /bin/sh reads none.
    tmux -L dux-e2e set-option -t duxe2e default-shell /bin/sh
  fi
}
teardown_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then tmux -L dux-e2e kill-server 2>/dev/null || true; fi
}

ready() { [ -n "${DUX_BACKEND:-}" ] && [ -n "${DUX_WORKER_HARNESS:-}" ]; }

# The worker container does not inherit this test's environment. Hand the wrapper what it needs:
# the fake herdr runs the command in-process, the tmux session takes an environment that new panes inherit.
worker_env() {
  export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/worker.script" DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1
  echo "$DUX_WORKER_HARNESS" > "$DUX_HOME/config/worker-harness"
  if [ "$DUX_BACKEND" = tmux ]; then
    local v
    for v in DUX_HOME DUX_BACKEND DUX_TMUX_SOCKET DUX_TMUX_SESSION PATH FAKE_WORKER_SCRIPT FAKE_WORKER_LOG DUX_WRAP_POLL_SECS DUX_HEARTBEAT_SECS; do
      tmux -L dux-e2e set-environment -t "$DUX_TMUX_SESSION" "$v" "${!v}"
    done
  fi
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

wait_for() {  # $1 file, $2 grep pattern, $3 seconds
  local i=0
  until grep -q "$2" "$1" 2>/dev/null; do i=$((i + 1)); [ "$i" -ge "$3" ] && return 1; sleep 1; done
}
wait_file() {  # $1 path, $2 seconds
  local i=0
  until [ -e "$1" ]; do i=$((i + 1)); [ "$i" -ge "$2" ] && return 1; sleep 1; done
}

container_gone() {  # $1 endpoint
  if [ "$DUX_BACKEND" = tmux ]; then run dux-backend exists "$1"; [ "$status" -eq 1 ]
  else grep -qx 'pane close w1:p9' "$FAKE_HERDR_LOG"; fi
}

# The worker proposes a pull request. It is a scout, so what it is proved to
# have done is write a report, and the url it named never reaches Dux at all.
@test "spawn, a proved result the worker did not choose, teardown" {
  ready || skip "set DUX_BACKEND and DUX_WORKER_HARNESS"
  worker_env
  printf 'report all clear\nstatus working: starting\nstatus done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = running ]
  log="$DUX_HOME/data/tasks/$id/status.log"
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 30
  [ "$(cat "$hand/1/status")" = "done: report" ]
  [ "$(cat "$hand/1/event")" = done ]
  [ "$(cat "$hand/1/run")" = "$(sed -n 's/^run=//p' "$DUX_HOME/state/$id.run")" ]
  ! grep -rq example.invalid "$hand"
  # Nothing terminal reached the status log from the wrapper.
  [ "$(cat "$log")" = "working: starting" ]
  grep -q '"type":"assistant"' "$DUX_HOME/state/$id.out"
  grep -q "^$DUX_WORKER_HARNESS " "$FAKE_WORKER_LOG"
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  sleep 3
  ep="$(dux-ledger get "$id" endpoint)"
  # Teardown reads the ledger, and only the watcher moves it.
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not terminal (ledger: running)"* ]]
  dux-watch --once
  [ "$(tail -n 1 "$log")" = "done: report" ]
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = - ]
  [ -e "$hand/1/consumed" ]
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = done ]
  [ ! -e "$hand" ]; [ ! -e "$DUX_HOME/state/$id.run" ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  container_gone "$ep"
}

@test "a worker that exits without an exit line is recorded as failed and can be torn down" {
  ready || skip
  worker_env
  printf 'status working: starting\nexit 3\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  log="$DUX_HOME/data/tasks/$id/status.log"
  wait_file "$DUX_HOME/state/$id.handoffs/1/status" 30
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/status")" = "failed: worker exited 3" ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  sleep 3
  dux-watch --once
  [ "$(tail -n 1 "$log")" = "failed: worker exited 3" ]
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = failed ]
}

@test "a codex worker is refused end to end and nothing is created" {
  ready || skip
  worker_env
  echo codex > "$DUX_HOME/config/worker-harness"
  id="$(fixture_task proj scout)"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: codex workers are not available: no deny list, so git push --no-verify skips the only guard (milestone 2)"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "on herdr the worker's status is mirrored to the pane" {
  ready || skip
  [ "$DUX_BACKEND" = herdr ] || skip "tmux has no agent state"
  worker_env
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_for "$FAKE_HERDR_LOG" "report-agent w1:p9 --source dux --agent dux-$id --state idle --message dux $id: done" 30
  grep -qF "pane report-metadata w1:p9 --title proj: Do the thing the operator asked for." "$FAKE_HERDR_LOG"
}
