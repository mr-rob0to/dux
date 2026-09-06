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

running_task() {  # $1 id, [$2 shape]
  mkdir -p "$DUX_HOME/data/tasks/$1"; : > "$DUX_HOME/data/tasks/$1/status.log"
  dux-ledger add "$1" proj "${2:-scout}" local
  dux-ledger set "$1" endpoint herdr:w1:p9
  dux-ledger set "$1" state running
  echo herdr:w1:p9 > "$DUX_HOME/state/$1.endpoint"
  stand_in "dux-worker-wrap $1" > "$DUX_HOME/state/$1.pid"
  fake_run "$1" r00 "${2:-scout}"
}
status_is() { printf '%s\n' "$2" >> "$DUX_HOME/data/tasks/$1/status.log"; }
seq_dir() { printf '%s' "$DUX_HOME/state/$1.handoffs/${2:-1}"; }
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

@test "a proved handoff writes the status, the event, the ledger and the url once" {
  running_task t1 plan; status_is t1 "working: on it"
  handoff t1 "done: PR https://github.com/acme/proj/pull/7" done
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
  [[ "$(cat "$events")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\ done:\ t1$ ]]
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/t1/status.log")" = "done: PR https://github.com/acme/proj/pull/7" ]
  [ "$(dux-ledger get t1 state)" = done ]
  [ "$(dux-ledger get t1 pr)" = "https://github.com/acme/proj/pull/7" ]
  grep -qF 'notification show Dux --body done: t1' "$FAKE_HERDR_LOG"
  # Each step leaves its own marker, which is what a restart reads to know the
  # step is already done. Without them a replay would write everything twice.
  [ -e "$(seq_dir t1)/did-status" ]
  [ -e "$(seq_dir t1)/did-event" ]
  [ -e "$(seq_dir t1)/consumed" ]
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
  [ "$(grep -c '^done: ' "$DUX_HOME/data/tasks/t1/status.log")" -eq 1 ]
}

@test "a consumed sequence is retained, and the next one is applied behind it" {
  running_task t1
  handoff t1 "ended: exit 0 without terminal status" ended
  dux-watch --once
  [ "$(dux-ledger get t1 state)" = ended ]
  [ -d "$(seq_dir t1 1)" ]; [ -e "$(seq_dir t1 1)/consumed" ]
  # Recovery proving a late result publishes behind the one the run left.
  handoff t1 "done: report" done
  dux-watch --once
  [ "$(events_count)" -eq 2 ]
  [ "$(dux-ledger get t1 state)" = done ]
  [ -d "$(seq_dir t1 1)" ]; [ -e "$(seq_dir t1 2)/consumed" ]
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/t1/status.log")" = "done: report" ]
}

@test "sequence 2 waits for sequence 1" {
  running_task t1
  handoff t1 "blocked: waiting on the operator" blocked
  handoff t1 "done: report" done
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; grep -q ' blocked: t1$' "$events"
  [ "$(dux-ledger get t1 state)" = blocked ]
  # blocked is not running, so only the pending handoff brings the task back.
  dux-watch --once
  [ "$(events_count)" -eq 2 ]; grep -q ' done: t1$' "$events"
  [ "$(dux-ledger get t1 state)" = done ]
}

@test "each terminal worker state emits its own state" {
  for s in failed blocked needs-decision ended; do running_task "t-$s"; handoff "t-$s" "$s: because" "$s"; done
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
  dux-ledger ack t1 stale
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

@test "a terminal-looking status line with nothing behind it is ignored" {
  # The only way to finish is a handoff. A line that says done, from a legacy
  # wrapper or from anything else that reached the file, proves nothing: the
  # wrapper is gone, so the task is dead and recovery decides.
  running_task t1; status_is t1 "done: PR https://github.com/acme/proj/pull/7"
  kill -9 "$(cat "$DUX_HOME/state/t1.pid")"; worker_gone t1
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; grep -q ' dead: t1$' "$events"
  [ "$(dux-ledger get t1 state)" = dead ]
  [ "$(dux-ledger get t1 pr)" = - ]
}

@test "a handoff naming another run, or none at all, is refused" {
  running_task t1; status_is t1 "working: on it"
  handoff t1 "done: report" done otherrun
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 names run otherrun, not this task's run"* ]]
  [ "$(grep -c '^done:' "$DUX_HOME/data/tasks/t1/status.log" || true)" -eq 0 ]
}

@test "a handoff for a task that never recorded a run is refused unless it names no run" {
  running_task t1; status_is t1 "working: on it"
  rm "$DUX_HOME/state/t1.run" "$DUX_HOME/state/t1.result-context"
  handoff t1 "failed: wrapper: no brief" failed r00
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 names a run but t1 recorded none"* ]]
  rm -rf "$DUX_HOME/state/t1.handoffs"
  handoff t1 "failed: wrapper: no brief" failed -
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; grep -q ' failed: t1$' "$events"
  [ "$(tail -n 1 "$DUX_HOME/data/tasks/t1/status.log")" = "failed: wrapper: no brief" ]
}

# What makes the single rename safe from the reading side: a directory that is
# not a whole handoff is not one, so a reader that somehow catches a part of one
# refuses it instead of acting on half a result.
@test "a part-built handoff is refused and never counted as a result" {
  running_task t1
  d="$DUX_HOME/state/t1.handoffs/1"; mkdir -p "$d"
  printf 'r00\n' > "$d/run"; printf 'done: report\n' > "$d/status"
  dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  [ ! -e "$d/consumed" ]
  run dux-watch eval t1
  [[ "$output" == "skip:handoff 1 has no event file"* ]]
}

# And from the writing side: the sequence appears under its own name only when
# the rename succeeds, and a rename that cannot happen leaves nothing behind for
# the next publish to trip over. A symlink holding the name is one such case.
@test "a publish that cannot land leaves nothing where a reader looks" {
  running_task t1
  d="$DUX_HOME/state/t1.handoffs"; mkdir -p "$d"
  ln -s "$DUX_HOME/elsewhere" "$d/1"
  run handoff t1 "done: report" done
  [ "$status" -ne 0 ]
  [ -L "$d/1" ]; [ ! -e "$DUX_HOME/elsewhere" ]
  [ "$(ls -A "$d")" = 1 ]
  dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
}

@test "a handoff whose status is not one grammatical line is refused" {
  running_task t1; status_is t1 "working: on it"
  handoff t1 "pondering: hmm" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 does not hold one status line"* ]]
  rm -rf "$DUX_HOME/state/t1.handoffs"
  handoff t1 "done: $(printf 'x%.0s' $(seq 1 200))" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 does not hold one status line"* ]]
  rm -rf "$DUX_HOME/state/t1.handoffs"
  handoff t1 "done: report" done
  printf 'done: report\ndone: again\n' > "$(seq_dir t1)/status"
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 does not hold one status line"* ]]
}

@test "a handoff whose event does not answer its status is refused" {
  running_task t1; status_is t1 "working: on it"
  handoff t1 "done: report" failed
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 records event failed for a done status"* ]]
}

@test "a done handoff must match the shape the run recorded" {
  running_task t1 scout; status_is t1 "working: on it"
  handoff t1 "done: PR https://github.com/acme/proj/pull/7" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: a pull request does not complete a scout task"* ]]
  running_task t2 plan; handoff t2 "done: report" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t2: a report does not complete a plan task"* ]]
}

@test "a done handoff carrying a url outside the registered repository is refused" {
  running_task t1 plan; status_is t1 "working: on it"
  handoff t1 "done: PR https://github.com/evil/proj/pull/7" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 pr)" = - ]
  [[ "$stderr" == *"finding: watch: t1: handoff 1 names a pull request outside acme/proj"* ]]
}

@test "a ship result needs the five-phase receipt behind it" {
  running_task t1 ship; status_is t1 "working: on it"
  handoff t1 "done: PR https://github.com/acme/proj/pull/7" done
  run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 0 ]
  [[ "$stderr" == *"finding: watch: t1: no complete /ship receipt behind the result for t1"* ]]
  fake_receipt t1 r00
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; [ "$(dux-ledger get t1 state)" = done ]
}

@test "a consumption interrupted at any step is replayed without duplicating anything" {
  # The markers are how a restart knows what it already wrote. Removing the
  # ledger update alone is what a crash between the two writes leaves behind.
  running_task t1 plan
  handoff t1 "done: PR https://github.com/acme/proj/pull/7" done
  d="$(seq_dir t1)"
  # Interrupted after the status line, before the event.
  printf 'done: PR https://github.com/acme/proj/pull/7\n' >> "$DUX_HOME/data/tasks/t1/status.log"
  : > "$d/did-status"
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
  [ "$(grep -c '^done: ' "$DUX_HOME/data/tasks/t1/status.log")" -eq 1 ]
  [ "$(dux-ledger get t1 state)" = done ]
  # Interrupted after the event, before the ledger.
  running_task t2 plan
  handoff t2 "done: PR https://github.com/acme/proj/pull/8" done
  d2="$(seq_dir t2)"
  printf 'done: PR https://github.com/acme/proj/pull/8\n' >> "$DUX_HOME/data/tasks/t2/status.log"
  printf '%s done: t2\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$events"
  : > "$d2/did-status"; : > "$d2/did-event"
  dux-watch --once
  [ "$(grep -c ' done: t2$' "$events")" -eq 1 ]
  [ "$(grep -c '^done: ' "$DUX_HOME/data/tasks/t2/status.log")" -eq 1 ]
  [ "$(dux-ledger get t2 state)" = done ]
  [ "$(dux-ledger get t2 pr)" = "https://github.com/acme/proj/pull/8" ]
  [ -e "$d2/consumed" ]
}

@test "a handoff left unconsumed after the ledger moved is still finished" {
  # A crash between the ledger write and the consumed marker takes the task out
  # of running, so only the pending handoff brings the watcher back to it.
  running_task t1
  handoff t1 "done: report" done
  d="$(seq_dir t1)"
  printf 'done: report\n' >> "$DUX_HOME/data/tasks/t1/status.log"
  printf '%s done: t1\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$events"
  : > "$d/did-status"; : > "$d/did-event"
  dux-ledger set t1 state done
  dux-watch --once
  [ "$(events_count)" -eq 1 ]
  [ "$(grep -c '^done: ' "$DUX_HOME/data/tasks/t1/status.log")" -eq 1 ]
  [ -e "$d/consumed" ]
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
  running_task t1; handoff t1 "done: report" done
  run --separate-stderr dux-watch eval t1
  [ "$status" -eq 0 ]; [ "$output" = done ]
  [ "$(events_count)" -eq 0 ]; [ "$(dux-ledger get t1 state)" = running ]
  # The handoff has to go first: proved terminal state outranks liveness, so
  # while one is pending the pid file is never looked at.
  rm -rf "$DUX_HOME/state/t1.handoffs"
  echo garbage > "$DUX_HOME/state/t1.pid"; : > "$DUX_HOME/data/tasks/t1/status.log"
  run dux-watch eval t1
  [[ "$output" == "skip:$DUX_HOME/state/t1.pid does not hold a pid"* ]]
  run dux-watch eval nope
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task nope not in ledger"* ]]
}

@test "a failed ledger update leaves the handoff pending and never repeats the event" {
  running_task t1; handoff t1 "done: report" done
  mkdir "$DUX_HOME/data/backlog.md.lock"
  DUX_LEDGER_WAIT_TENTHS=2 run --separate-stderr dux-watch --once
  [ "$(events_count)" -eq 1 ]; [[ "$stderr" == *"ledger not updated for t1; the handoff stays until it is"* ]]
  [ ! -e "$(seq_dir t1)/consumed" ]
  rmdir "$DUX_HOME/data/backlog.md.lock"
  dux-watch --once
  [ "$(events_count)" -eq 1 ]; [ "$(dux-ledger get t1 state)" = done ]
  [ "$(grep -c '^done: ' "$DUX_HOME/data/tasks/t1/status.log")" -eq 1 ]
  [ -e "$(seq_dir t1)/consumed" ]
}

@test "loop records its pid, emits, and exits when displaced" {
  running_task t1; status_is t1 "working: on it"; start_loop 1
  [ "$(cat "$DUX_HOME/state/watch.pid")" = "$loop" ]
  handoff t1 "done: report" done
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
