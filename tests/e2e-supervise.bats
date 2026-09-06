# bats file_tags=e2e
bats_require_minimum_version 1.5.0
load helpers/setup

# Runs once per backend. A real watcher started by dux-lock, a real wrapper in a
# real container, a fake worker replaying a script.
setup_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    export DUX_TMUX_SOCKET=dux-e2e-sup DUX_TMUX_SESSION=duxe2esup
    tmux -L dux-e2e-sup kill-server 2>/dev/null || true
    tmux -L dux-e2e-sup new-session -d -s duxe2esup -x 80 -y 24
    tmux -L dux-e2e-sup set-option -t duxe2esup default-shell /bin/sh
  fi
}

teardown_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then tmux -L dux-e2e-sup kill-server 2>/dev/null || true; fi
}

ready() { [ -n "${DUX_BACKEND:-}" ]; }

supervised_env() {
  export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/worker.script" DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1000
  export DUX_WATCHER=on DUX_WATCH_INTERVAL_SECS=1 DUX_STALE_SECS=3 DUX_WATCH_GRACE_SECS=30
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
  wait_until 15 count_is stale "$id" 1
  wait_until 10 ledger_is "$id" stale
  [ "$(dux-ledger get "$id" state)" = stale ]
  sleep 3
  [ "$(count stale "$id")" -eq 1 ]
  [ "$(wc -l < "$events" | tr -d ' ')" -eq 1 ]
  if [ "$DUX_BACKEND" = herdr ]; then grep -qF "notification show Dux --body stale: $id" "$FAKE_HERDR_LOG"; fi
  # Recovering stops the wrapper, which publishes its own ending on the way out.
  # Recovery reports that and leaves it; the watcher is what applies it.
  dux-recover "$id" --stop >/dev/null
  wait_until 15 count_is failed "$id" 1
  wait_until 10 ledger_is "$id" failed
  [ "$(dux-ledger get "$id" state)" = failed ]
  sleep 3
  [ "$(count failed "$id")" -le 1 ]
  [ "$(count stale "$id")" -eq 1 ]
  dux-teardown "$id" >/dev/null
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
  harness_pid="$(pgrep -P "$wrapper_pid" | head -n 1)"
  [ -n "$harness_pid" ]
  echo "$harness_pid" >> "$DUX_HOME/state/stand-ins"
  kill -9 "$wrapper_pid"
  wait_until 15 count_is dead "$id" 1
  wait_until 10 ledger_is "$id" dead
  [ "$(dux-ledger get "$id" state)" = dead ]
  dux-recover "$id" >/dev/null
  [ "$(dux-ledger get "$id" state)" = failed ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  sleep 3
  [ "$(count dead "$id")" -eq 1 ]
  kill -TERM "$harness_pid" 2>/dev/null || true
  wait_until 5 bash -c "! kill -0 $harness_pid 2>/dev/null"
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
