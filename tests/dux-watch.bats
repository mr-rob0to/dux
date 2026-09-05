bats_require_minimum_version 1.5.0
load helpers/setup

setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  cp "$DUX_ROOT"/templates/config/* "$DUX_HOME/config/"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log"; : > "$FAKE_HERDR_LOG"
  export DUX_BACKEND=herdr DUX_WATCHER=off DUX_STALE_SECS=1200 DUX_WATCH_GRACE_SECS=120
  events="$DUX_HOME/state/events.log"; watchlog="$DUX_HOME/state/watch.log"
}

running_task() {
  mkdir -p "$DUX_HOME/data/tasks/$1"; : > "$DUX_HOME/data/tasks/$1/status.log"
  dux-ledger add "$1" proj scout local
  dux-ledger set "$1" endpoint herdr:w1:p9
  dux-ledger set "$1" state running
  echo herdr:w1:p9 > "$DUX_HOME/state/$1.endpoint"
  stand_in "dux-worker-wrap $1" > "$DUX_HOME/state/$1.pid"
}
status_is() { printf '%s\n' "$2" >> "$DUX_HOME/data/tasks/$1/status.log"; }
age_out() { touch -t 202001010000 "$DUX_HOME/data/tasks/$1/status.log" "$DUX_HOME/state/$1.pid"; }
events_count() { if [ -f "$events" ]; then wc -l < "$events" | tr -d ' '; else echo 0; fi; }
worker_gone() { wait_until 5 bash -c "! kill -0 $(cat "$DUX_HOME/state/$1.pid") 2>/dev/null"; }
start_loop() { DUX_WATCH_INTERVAL_SECS="${1:-1}" dux-watch >> "$watchlog" 2>&1 3>&- & loop=$!; wait_until 5 test -s "$DUX_HOME/state/watch.pid"; }

@test "working never emits and stays running" {
  running_task t1; status_is t1 "working: on it"
  run --separate-stderr dux-watch --once
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
}

@test "done emits once, updates the ledger, and toasts" {
  running_task t1; status_is t1 "working: on it"; status_is t1 "done: PR https://example.invalid/pr/1"
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
  [[ "$(cat "$events")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\ done:\ t1$ ]]
  [ "$(dux-ledger get t1 state)" = done ]
  grep -qF 'notification show Dux --body done: t1' "$FAKE_HERDR_LOG"
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
}

@test "each terminal worker state emits its own state" {
  for s in failed blocked needs-decision ended; do running_task "t-$s"; status_is "t-$s" "$s: because"; done
  dux-watch --once
  [ "$(events_count)" -eq 4 ]
  for s in failed blocked needs-decision ended; do
    grep -q " $s: t-$s$" "$events"
    [ "$(dux-ledger get "t-$s" state)" = "$s" ]
  done
}

@test "a resumed stale worker clears its acknowledgement and can go stale again" {
  running_task t1; status_is t1 "working: slow"; age_out t1
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; [ "$(dux-ledger get t1 state)" = stale ]
  dux-watch --once; [ "$(events_count)" -eq 1 ]
  dux-ledger ack t1
  status_is t1 "working: awake"
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 1 ]; [ "$(dux-ledger get t1 state)" = running ]
  [ "$(dux-ledger get t1 acked)" = - ]; [[ "$stderr" == *"dux: watch: t1 resumed"* ]]
  age_out t1; dux-watch --once
  [ "$(events_count)" -eq 2 ]; [ "$(grep -c ' stale: t1$' "$events")" -eq 2 ]
  run dux-ledger list --unacked; [ "$output" = t1 ]
}

@test "a recent silent worker is not stale" {
  running_task t1; status_is t1 "working: fine"
  DUX_STALE_SECS=3600 dux-watch --once
  [ "$(events_count)" -eq 0 ]
}

@test "a fresh pidfile keeps an old empty status log fresh" {
  running_task t1
  touch -t 202001010000 "$DUX_HOME/data/tasks/t1/status.log"
  run --separate-stderr dux-watch --once
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
}

@test "a stopped wrapper is dead even while the container remains" {
  running_task t1; status_is t1 "working: on it"
  kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; grep -q ' dead: t1$' "$events"
  [ "$(dux-ledger get t1 state)" = dead ]
  dux-watch --once; [ "$(events_count)" -eq 1 ]
}

@test "a stale worker that stops emits dead" {
  running_task t1; status_is t1 "working: slow"; age_out t1
  dux-watch --once; [ "$(dux-ledger get t1 state)" = stale ]
  kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  dux-watch --once
  [ "$(events_count)" -eq 2 ]; grep -q ' dead: t1$' "$events"
}

@test "a recycled pid running another command is dead" {
  running_task t1; status_is t1 "working: on it"
  kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  stand_in not-a-wrapper > "$DUX_HOME/state/t1.pid"
  dux-watch --once
  grep -q ' dead: t1$' "$events"
}

@test "no pidfile starts within grace and becomes dead after grace" {
  running_task t1; kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1; rm "$DUX_HOME/state/t1.pid"
  dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  touch -t 202001010000 "$DUX_HOME/state/t1.endpoint"
  dux-watch --once
  grep -q ' dead: t1$' "$events"
}

@test "a nonnumeric pidfile is an open question" {
  running_task t1; kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1; echo garbage > "$DUX_HOME/state/t1.pid"
  run --separate-stderr dux-watch --once
  [ "$status" -eq 0 ]; [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [[ "$stderr" == *"finding: watch: t1: $DUX_HOME/state/t1.pid does not hold a pid ('garbage')"* ]]
}

@test "a live wrapper stays alive when its container is gone" {
  running_task t1; status_is t1 "working: on it"
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [[ "$stderr" == *"dux: watch: t1: container herdr:w1:p9 is gone but wrapper pid"* ]]
}

@test "backend failure is a changing note and never hides a live wrapper" {
  running_task t1; status_is t1 "working: on it"
  export FAKE_HERDR_GET_FAIL="$DUX_HOME/state/getfail"; touch "$FAKE_HERDR_GET_FAIL"
  start_loop 1
  wait_until 5 grep -q 'dux: watch: t1: backend cannot tell' "$watchlog"
  sleep 3
  [ "$(grep -c 'dux: watch: t1: backend cannot tell' "$watchlog")" -eq 1 ]
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  rm "$FAKE_HERDR_GET_FAIL"
  wait_until 5 grep -q 'dux: watch: every task answers again' "$watchlog"
  sleep 2
  [ "$(grep -c 'every task answers again' "$watchlog")" -eq 1 ]
  kill "$loop"
}

@test "an endpoint from another backend is only a note beside a live wrapper" {
  running_task t1; status_is t1 "working: on it"
  echo tmux:dux:@3 > "$DUX_HOME/state/t1.endpoint"
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [[ "$stderr" == *"dux: watch: t1: backend cannot tell whether tmux:dux:@3 exists"* ]]
}

@test "a live wrapper needs no endpoint to stay running" {
  running_task t1; status_is t1 "working: on it"
  rm "$DUX_HOME/state/t1.endpoint"; dux-ledger set t1 endpoint -
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [[ "$stderr" == *"dux: watch: t1: no endpoint recorded"* ]]
}

@test "a stopped wrapper needs no endpoint to be dead" {
  running_task t1; status_is t1 "working: on it"
  kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  rm "$DUX_HOME/state/t1.endpoint"; dux-ledger set t1 endpoint -
  dux-watch --once
  grep -q ' dead: t1$' "$events"
}

@test "no pidfile and no endpoint is an open question" {
  running_task t1; kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  rm "$DUX_HOME/state/t1.pid" "$DUX_HOME/state/t1.endpoint"; dux-ledger set t1 endpoint -
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: no endpoint and no pidfile"* ]]
}

@test "terminal status wins even when liveness is unknown" {
  running_task t1; echo garbage > "$DUX_HOME/state/t1.pid"; status_is t1 "done: report"
  dux-watch --once
  grep -q ' done: t1$' "$events"
}

@test "an unknown status word is logged and skipped" {
  running_task t1; status_is t1 "pondering: hmm"
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: status log ends in an unknown state 'pondering'"* ]]
}

@test "tasks outside running and stale are not evaluated" {
  for s in queued needs-decision blocked done failed ended dead; do
    running_task "t-$s"; kill -9 "$(cat "$DUX_HOME/state/t-$s.pid")"; age_out "t-$s"; dux-ledger set "t-$s" state "$s"
  done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ -z "$stderr" ]
}

@test "eval prints the target and writes nothing" {
  running_task t1; status_is t1 "done: report"
  run --separate-stderr dux-watch eval t1
  [ "$status" -eq 0 ]; [ "$output" = done ]
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  echo garbage > "$DUX_HOME/state/t1.pid"; : > "$DUX_HOME/data/tasks/t1/status.log"
  run dux-watch eval t1
  [[ "$output" == "skip:$DUX_HOME/state/t1.pid does not hold a pid"* ]]
  run dux-watch eval nope
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task nope not in ledger"* ]]
}

@test "a failed ledger update makes the event repeat" {
  running_task t1; status_is t1 "done: report"
  mkdir "$DUX_HOME/data/backlog.md.lock"
  DUX_LEDGER_WAIT_TENTHS=2 run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 1 ]; [[ "$stderr" == *"ledger not updated for t1; the event will repeat"* ]]
  rmdir "$DUX_HOME/data/backlog.md.lock"
  dux-watch --once
  [ "$(events_count)" -eq 2 ]; [ "$(dux-ledger get t1 state)" = done ]
}

@test "loop records its pid, emits, and exits when displaced" {
  running_task t1; status_is t1 "working: on it"; start_loop 1
  [ "$(cat "$DUX_HOME/state/watch.pid")" = "$loop" ]
  status_is t1 "done: report"
  wait_until 5 grep -q ' done: t1$' "$events"
  echo 999999 > "$DUX_HOME/state/watch.pid"
  wait_until 5 bash -c "! kill -0 $loop 2>/dev/null"
  grep -q 'names another watcher; exiting' "$watchlog"
}

@test "loop exits on TERM and takes its sleep" {
  start_loop 30
  kill -TERM "$loop"
  wait_until 2 bash -c "! kill -0 $loop 2>/dev/null"
  grep -q 'watch: stopping' "$watchlog"
  [ "$(pgrep -P "$loop" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "an unwritable events path is a startup finding" {
  mkdir -p "$DUX_HOME/state/events.log"
  run dux-watch --once
  [ "$status" -eq 2 ]; [[ "$output" == "finding: cannot write $DUX_HOME/state/events.log"* ]]
}

@test "bad watcher arguments are a usage finding" {
  run dux-watch --twice
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-watch [--once] | dux-watch eval <id>"* ]]
}
