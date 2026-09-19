# bats file_tags=e2e
bats_require_minimum_version 1.5.0
load helpers/setup

# Runs once per backend. A real watcher started by dux-lock, a real wrapper in a
# real container, a fake worker replaying a script.
setup_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    use_tmux_tmpdir
    export DUX_TMUX_SOCKET=dux-e2e-sup DUX_TMUX_SESSION=duxe2esup
    tmux -L dux-e2e-sup kill-server 2>/dev/null || true
    tmux -L dux-e2e-sup new-session -d -s duxe2esup -x 80 -y 24
    tmux -L dux-e2e-sup set-option -t duxe2esup default-shell /bin/sh
  fi
}

teardown_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    tmux -L dux-e2e-sup kill-server 2>/dev/null || true
    drop_tmux_tmpdir
  fi
}

ready() { [ -n "${DUX_BACKEND:-}" ]; }

supervised_env() {
  export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  trust_suite_root
  harness_shim
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/worker.script" DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1000
  # A limit no start comes near. A test that needs a silent worker ages it with
  # age_task; a small limit here is one a slow start reaches first.
  export DUX_WATCHER=on DUX_WATCH_INTERVAL_SECS=1 DUX_STALE_SECS=3600 DUX_WATCH_GRACE_SECS=30
  if [ "$DUX_BACKEND" = tmux ]; then
    local v
    for v in DUX_HOME DUX_BACKEND DUX_TMUX_SOCKET DUX_TMUX_SESSION PATH FAKE_WORKER_SCRIPT FAKE_WORKER_LOG DUX_WRAP_POLL_SECS DUX_HEARTBEAT_SECS; do
      tmux -L dux-e2e-sup set-environment -t "$DUX_TMUX_SESSION" "$v" "${!v}"
    done
  fi
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
  events="$DUX_HOME/state/events.log"
}

count() { grep -c " $1: $2\$" "$events" 2>/dev/null || true; }

# The count must be read again on every wait_until poll.
count_is() { [ "$(count "$1" "$2")" -eq "$3" ]; }

# The watcher records the event before the ledger, on purpose, so that a crash
# cannot lose a wake. Seeing the event therefore says nothing yet about the
# ledger, and a test that reads one straight after the other is racing it.
ledger_is() { [ "$(dux-ledger get "$1" state)" = "$2" ]; }

@test "a worker that goes silent is stale after the threshold, exactly once, and the toast fires" {
  ready || skip "set DUX_BACKEND"
  supervised_env
  printf 'status working: starting\nsleep 300\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 15 grep -q '^working: starting' "$DUX_HOME/data/tasks/$id/status.log"
  # The worker has spoken and will say nothing more; its silence starts an hour ago.
  age_task "$id" 3600
  wait_until 15 count_is stale "$id" 1
  wait_until 10 ledger_is "$id" stale
  [ "$(dux-ledger get "$id" state)" = stale ]
  sleep 3
  [ "$(count stale "$id")" -eq 1 ]
  [ "$(wc -l < "$events" | tr -d ' ')" -eq 1 ]
  if [ "$DUX_BACKEND" = herdr ]; then grep -qF "notification show Dux --body stale: $id" "$FAKE_HERDR_LOG"; fi
  # Recovering stops the wrapper, which publishes its own ending on the way out.
  # Recovery reports that and leaves it; the watcher is what applies it. A
  # session stopped before it said anything is ended, not failed: there is no
  # exit status to read from a harness the wrapper did not fork, and what the
  # run actually left behind is recovery's own proof to make.
  dux-recover "$id" --stop >/dev/null
  wait_until 15 count_is ended "$id" 1
  wait_until 10 ledger_is "$id" ended
  [ "$(dux-ledger get "$id" state)" = ended ]
  sleep 3
  [ "$(count ended "$id")" -le 1 ]
  [ "$(count stale "$id")" -eq 1 ]
}

@test "a worker whose wrapper is killed is dead, and recover marks it failed" {
  ready || skip
  supervised_env
  printf 'status working: starting\nsleep 300\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 15 test -s "$DUX_HOME/state/$id.pid"
  wait_until 15 grep -q '^working: starting' "$DUX_HOME/data/tasks/$id/status.log"
  wrapper_pid="$(cat "$DUX_HOME/state/$id.pid")"
  echo "$wrapper_pid" >> "$DUX_HOME/state/stand-ins"
  # The harness is not the wrapper's child any more: it is the pane's, and what
  # the wrapper holds is its process group. That is the whole point of this
  # test now, because killing the wrapper leaves the session running in its tab.
  wait_until 15 test -s "$DUX_HOME/state/$id.pgid"
  harness_pgid="$(cat "$DUX_HOME/state/$id.pgid")"
  [ -n "$harness_pgid" ]
  echo "$harness_pgid" >> "$DUX_HOME/state/stand-ins"
  kill -9 "$wrapper_pid"
  kill -0 -- "-$harness_pgid"
  wait_until 15 count_is dead "$id" 1
  wait_until 10 ledger_is "$id" dead
  [ "$(dux-ledger get "$id" state)" = dead ]
  dux-recover "$id" >/dev/null
  [ "$(dux-ledger get "$id" state)" = failed ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  sleep 3
  [ "$(count dead "$id")" -eq 1 ]
  kill -TERM -- "-$harness_pgid" 2>/dev/null || true
  wait_until 5 group_gone "$harness_pgid"
}

@test "a worker that finishes produces exactly one done event, even across a watcher restart" {
  ready || skip
  supervised_env
  # The worker proposes a pull request. It is a scout, so the proof answers with
  # the report it actually wrote, and the url it named never reaches Dux.
  printf 'report all clear\nstatus working: starting\nsleep 2\nstatus done: PR https://example.invalid/pr/1\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 20 count_is done "$id" 1
  wait_until 10 ledger_is "$id" done
  [ "$(dux-ledger get "$id" state)" = done ]
  w1="$(cat "$DUX_HOME/state/watch.pid")"
  dux-lock acquire >/dev/null
  w2="$(cat "$DUX_HOME/state/watch.pid")"
  [ "$w1" != "$w2" ]
  sleep 3
  [ "$(count done "$id")" -eq 1 ]
  [ "$(dux-ledger get "$id" pr)" = - ]
  run dux-notify "$id"
  [ "$output" = "Read the report: proj scout finished ($id)" ]
  run dux-status
  [[ "$output" == *"watcher: running (pid $w2)"* ]]
  [[ "$output" == *"  ready 1"* ]]
  [[ "$output" == *"  done: $id (proj)"* ]]
  dux-ledger ack "$id" done
  run dux-status
  [ "$(grep -c 'unacknowledged' <<< "$output" || true)" -eq 0 ]
  wait_for_workers 10
  dux-teardown "$id" >/dev/null
  run dux-status
  [ "$(grep -c '  ready' <<< "$output" || true)" -eq 0 ]
}

@test "release stops the watcher and the next acquire starts a fresh one that emits nothing already recorded" {
  ready || skip
  supervised_env
  printf 'report all clear\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 20 count_is done "$id" 1
  w="$(cat "$DUX_HOME/state/watch.pid")"
  dux-lock release
  wait_until 5 bash -c "! kill -0 $w 2>/dev/null"
  [ ! -e "$DUX_HOME/state/watch.pid" ]
  dux-lock acquire >/dev/null
  sleep 3
  [ "$(count done "$id")" -eq 1 ]
  wait_for_workers 10
}

# A task started before the security-boundary upgrade has no run record, so no
# result can ever be proved for it. Retirement is the supported way out: stop the
# old worker, record a failure, keep the work, retry once, then tear down.
@test "a worker from before the upgrade is retired, recorded failed, retried once, and torn down" {
  ready || skip
  supervised_env
  printf 'report all clear\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  # The disk state of a pre-amendment task: a live wrapper, a worktree and a
  # branch, and no run record, channel or handoff anywhere.
  wt="$(dux-worktree create "$id")"
  dux-ledger set "$id" state running
  stand_in "dux-worker-wrap $id" > "$DUX_HOME/state/$id.pid"
  legacy="$(cat "$DUX_HOME/state/$id.pid")"
  [ ! -e "$DUX_HOME/state/$id.run" ]
  run dux-recover "$id" --retire-legacy
  [ "$status" -eq 0 ]
  not_running "$legacy"
  wait_until 15 count_is failed "$id" 1
  wait_until 10 ledger_is "$id" failed
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/$id/status.log")" = "failed: stopped for security-boundary upgrade; worktree kept" ]
  # The work itself is untouched.
  [ -d "$wt" ]
  git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"
  run dux-notify "$id"
  [ "$output" = "Retry or drop: proj scout failed ($id)" ]
  # The one ordinary retry, which is a new task with its own worktree and run.
  run dux-recover "$id" --retry
  [ "$status" -eq 0 ]
  new="$(cat "$DUX_HOME/data/tasks/$id/retry")"
  wait_until 20 count_is done "$new" 1
  wait_until 10 ledger_is "$new" done
  run dux-recover "$id" --retry
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $id was already retired"* ]] || [[ "$output" == "finding: $id was already retried as $new"* ]]
  # Ordinary teardown for both, and nothing of either run is left behind.
  wait_for_workers 15
  dux-teardown "$id" >/dev/null
  [ ! -d "$wt" ]
  dux-teardown "$new" >/dev/null
  for f in run handoffs portal pgid result-context ship-receipt; do
    [ ! -e "$DUX_HOME/state/$id.$f" ] || { echo "state/$id.$f survived teardown"; return 1; }
    [ ! -e "$DUX_HOME/state/$new.$f" ] || { echo "state/$new.$f survived teardown"; return 1; }
  done
  [ -z "$(ls -A "$DUX_HOME/state/channels" 2>/dev/null)" ]
}

# A wrapper killed outright leaves its channel, portal and pgid behind, and the
# worker it started keeps running. Recovery clears them only when that group has
# gone; teardown is the last owner either way.
@test "a crashed wrapper leaves references that recovery keeps and teardown clears" {
  ready || skip
  supervised_env
  printf 'status working: starting\nsleep 300\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 15 test -s "$DUX_HOME/state/$id.pid"
  wait_until 15 grep -q '^working: starting' "$DUX_HOME/data/tasks/$id/status.log"
  wrapper="$(cat "$DUX_HOME/state/$id.pid")"
  echo "$wrapper" >> "$DUX_HOME/state/stand-ins"
  channel="$(cat "$DUX_HOME/state/$id.portal")"
  pg="$(cat "$DUX_HOME/state/$id.pgid")"
  [ -d "$channel" ]
  kill -9 "$wrapper"
  wait_until 15 count_is dead "$id" 1
  wait_until 10 ledger_is "$id" dead
  run dux-recover "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the worker's own processes for $id are still running as group $pg"* ]]
  [ -d "$channel" ]
  [ "$(dux-ledger get "$id" state)" = failed ]
  kill -TERM -- "-$pg" 2>/dev/null || true
  wait_until 10 group_gone "$pg"
  dux-teardown "$id" >/dev/null
  [ ! -e "$channel" ]
  for f in portal pgid run handoffs result-context; do
    [ ! -e "$DUX_HOME/state/$id.$f" ] || { echo "state/$id.$f survived teardown"; return 1; }
  done
}

# A watcher killed part-way through applying a handoff comes back to a sequence
# that is not marked consumed. What it already did is behind its own markers, so
# the second pass finishes the work rather than repeating it.
@test "a handoff half applied by a killed watcher is finished, not replayed" {
  ready || skip
  supervised_env
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_until 20 count_is done "$id" 1
  wait_until 10 ledger_is "$id" done
  d="$DUX_HOME/state/$id.handoffs/1"
  [ -e "$d/did-status" ] && [ -e "$d/did-event" ] && [ -e "$d/consumed" ]
  before_status="$(cat "$DUX_HOME/data/tasks/$id/status.log")"
  before_events="$(cat "$events")"
  # Exactly what a crash between the ledger write and the consumed marker leaves.
  rm -f "$d/consumed"
  dux-watch --once
  [ -e "$d/consumed" ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/status.log")" = "$before_status" ]
  [ "$(cat "$events")" = "$before_events" ]
  [ "$(count done "$id")" -eq 1 ]
  [ "$(dux-ledger get "$id" state)" = done ]
  # And a crash before either surface was written replays both, once.
  rm -f "$d/consumed" "$d/did-status" "$d/did-event"
  dux-watch --once
  [ "$(grep -c '^done: report$' "$DUX_HOME/data/tasks/$id/status.log")" -eq 2 ]
  [ "$(count done "$id")" -eq 2 ]
  [ "$(dux-ledger get "$id" state)" = done ]
}
