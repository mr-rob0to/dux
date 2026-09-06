load helpers/setup

# A task with a brief, rendered settings, and a worktree; runs the wrapper from inside the worktree.
prepare() {  # $1 shape; sets $id and $wt
  id="$(fixture_task proj "$1")"
  wt="$(dux-worktree create "$id")"
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script"
  export DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1
}
wrap() { (cd "$wt" && DUX_BACKEND="${DUX_BACKEND:-tmux}" dux-worker-wrap "$id"); }
status_log() { cat "$DUX_HOME/data/tasks/$id/status.log"; }
# A terminal state no longer reaches status.log from the wrapper. It is a
# handoff the watcher consumes, so tests read the handoff instead.
handoff_status() { cat "$DUX_HOME/state/$id.handoffs/${1:-1}/status"; }
handoff_event() { cat "$DUX_HOME/state/$id.handoffs/${1:-1}/event"; }
handoff_run() { cat "$DUX_HOME/state/$id.handoffs/${1:-1}/run"; }
# A second run of the same id needs this run's own references cleared first.
clear_refs() {
  rm -rf "$DUX_HOME/state/$id".run "$DUX_HOME/state/$id".portal \
    "$DUX_HOME/state/$id".pgid "$DUX_HOME/state/$id".result-context \
    "$DUX_HOME/state/$id".handoffs
}
# The channel is random and goes away with the run, so tests read the name the
# worker itself was given rather than guessing it.
channel_of() { sed -n 's#^DUX_STATUS_LOG=\(.*\)/status.outbox$#\1#p' "$1"; }

@test "happy path: progress lands, the proved result is the handoff, and the worker's url is not" {
  prepare scout
  # The worker proposes a pull request. A scout is proved by its report and by
  # nothing else, so the url it named reaches no file Dux keeps.
  printf 'report all clear\nstatus working: starting\nstatus done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(status_log)" = "working: starting" ]
  [ "$(handoff_status)" = "done: report" ]
  [ "$(handoff_event)" = done ]
  [ "$(handoff_run)" = "$(sed -n 's/^run=//p' "$DUX_HOME/state/$id.run")" ]
  [ "$(grep -rl 'example.invalid' "$DUX_HOME/state/$id.handoffs" | wc -l | tr -d ' ')" -eq 0 ]
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  grep -q '"type":"assistant"' "$DUX_HOME/state/$id.out"
  grep -q -- "--model claude-sonnet-5 --effort medium" "$FAKE_WORKER_LOG"
  grep -qE -- "--settings $DUX_HOME/state/channels/$id\.[A-Za-z0-9]+/worker-settings.json" "$FAKE_WORKER_LOG"
  [ "$(cat "$DUX_HOME/data/tasks/$id/report.md")" = "all clear" ]
}

@test "a done a run cannot prove ends the task instead of completing it" {
  prepare scout
  # Nothing wrote a report, so no evidence says this scout finished. The task
  # ends; it is never guessed done, and the url the worker named is not kept.
  printf 'status done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_event)" = ended ]
  [ "$(handoff_status)" = "ended: the result was not proved: no report was proposed for this scout task" ]
}

@test "a terminal state that is not done is the worker's own line, published as a handoff" {
  prepare scout
  printf 'status needs-decision: A or B? recommend A\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_event)" = needs-decision ]
  [ "$(handoff_status)" = "needs-decision: A or B? recommend A" ]
  [ -z "$(status_log)" ]
}

@test "the handoff is built beside its home and moved into place whole" {
  prepare scout
  printf 'report all clear\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  d="$DUX_HOME/state/$id.handoffs"
  # Nothing half-built is left where a reader looks, and the sequence stays put:
  # the wrapper never removes one, so a watcher killed part-way replays it.
  [ "$(ls -A "$d")" = 1 ]
  [ -d "$d/1" ]
  [ "$(ls "$d/1" | sort | tr '\n' ' ')" = "event run status " ]
}

@test "non-zero exit without an exit line appends failed and writes a failure tail" {
  prepare scout
  printf 'status working: starting\nexit 7\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "failed: worker exited 7" ]
  [ "$(handoff_event)" = failed ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  grep -q 'starting' "$DUX_HOME/data/tasks/$id/report.md"
}

@test "zero exit without an exit line appends ended; blocked is left alone" {
  prepare scout
  printf 'status working: starting\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(handoff_status)" = "ended: exit 0 without terminal status" ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'status blocked: cannot reach the API, tried twice\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(handoff_status)" = "blocked: cannot reach the API, tried twice" ]
}

@test "heartbeat appears only while the out file grows" {
  prepare scout
  printf 'report all clear\nstatus working: a\nsleep 2\nstatus working: b\nsleep 3\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | grep -c '^working: heartbeat$')" -le 3 ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'report all clear\nsleep 3\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c heartbeat || true)" -eq 0 ]
  id3="$(dux-task-new proj scout)"
  dux-brief "$id3" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id3"; wt="$(dux-worktree create "$id")"
  printf 'report all clear\nsay thinking\nsleep 2\nsay still thinking\nsleep 2\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | head -n 1)" = "working: heartbeat" ]
}

@test "the worker's status log is its own channel outbox, never the task's status log" {
  prepare scout
  printf 'report all clear\ndump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
  wrap
  env_file="$DUX_HOME/state/worker.env"
  ch="$(channel_of "$env_file")"
  [ -n "$ch" ]
  [ "$ch" != "$DUX_HOME/data/tasks/$id" ]
  case "$ch" in "$DUX_HOME/state/channels/$id."*) ;; *) false ;; esac
  grep -qx "DUX_REPORT=$ch/report.outbox" "$env_file"
  grep -qx "GIT_CONFIG_COUNT=1" "$env_file"
  grep -qx "GIT_CONFIG_KEY_0=core.hooksPath" "$env_file"
  grep -qx "GIT_CONFIG_VALUE_0=$ch/hooks" "$env_file"
  # The proposal reached a handoff by way of the wrapper, not the worker's hand,
  # and status.log holds nothing the worker asked for.
  [ "$(handoff_status)" = "done: report" ]
  [ -z "$(status_log)" ]
}

@test "the channel holds the worker's own copies and goes away with the run" {
  prepare scout
  printf 'report all clear\nrun ls -ld "$(dirname "$DUX_STATUS_LOG")"/. "$(dirname "$DUX_STATUS_LOG")"/* > %s 2>&1\nrun printf %%s "$DUX_STATUS_LOG" > %s\nstatus done: report\n' \
    "$DUX_HOME/state/chan.ls" "$DUX_HOME/state/chan.path" > "$FAKE_WORKER_SCRIPT"
  wrap
  ls="$DUX_HOME/state/chan.ls"
  grep -qE '^drwx------.*/\.$' "$ls"
  grep -qE '^-rw-------.*status\.outbox$' "$ls"
  grep -qE '^-rw-------.*report\.outbox$' "$ls"
  grep -qE '^-r--------.*brief\.md$' "$ls"
  grep -qE '^-r--------.*worker-settings\.json$' "$ls"
  grep -qE '^drwx------.*/hooks$' "$ls"
  ch="$(dirname "$(cat "$DUX_HOME/state/chan.path")")"
  [ ! -e "$ch" ]
  [ ! -e "$DUX_HOME/state/$id.portal" ]
  [ ! -e "$DUX_HOME/state/$id.pgid" ]
  # What a later result has to be proved against outlives the channel.
  grep -qx "run=${ch##*.}" "$DUX_HOME/state/$id.run"
  grep -qx "id=$id" "$DUX_HOME/state/$id.result-context"
  grep -qx "branch=dux/$id" "$DUX_HOME/state/$id.result-context"
  grep -qx "context=$(git hash-object "$DUX_HOME/state/$id.result-context")" "$DUX_HOME/state/$id.run"
}

@test "a child the harness leaves behind is stopped with the harness" {
  prepare scout
  printf 'report all clear\norphan %s\nstatus done: report\nexit 0\n' "$DUX_HOME/state/orphan.pid" > "$FAKE_WORKER_SCRIPT"
  wrap
  op="$(cat "$DUX_HOME/state/orphan.pid")"
  [[ "$op" =~ ^[0-9]+$ ]]
  run kill -0 "$op"
  [ "$status" -ne 0 ]
  [ "$(handoff_status)" = "done: report" ]
}

@test "terminal state waits for the worker's whole group to be gone" {
  prepare scout
  # The harness proposes done and exits while a child of its own keeps running
  # and ignores TERM, so the wrapper spends its grace period with the group
  # still alive. Nothing terminal may appear in that window.
  printf 'report all clear\nstubborn %s\nstatus done: PR https://example.invalid/pr/9\nexit 0\n' \
    "$DUX_HOME/state/stubborn.pid" > "$FAKE_WORKER_SCRIPT"
  export DUX_WRAP_STOP_GRACE_SECS=6
  (cd "$wt" && DUX_BACKEND=tmux dux-worker-wrap "$id") & wp=$!
  wait_until 20 test -s "$DUX_HOME/state/$id.pgid"
  pgid="$(cat "$DUX_HOME/state/$id.pgid")"
  wait_until 20 test -s "$DUX_HOME/state/stubborn.pid"
  sp="$(cat "$DUX_HOME/state/stubborn.pid")"
  # The harness is the group leader; once the wrapper has reaped it we are
  # inside the stop, with its child still running.
  wait_until 20 not_running "$pgid"
  # Hold the invariant across the window, not at one instant: the wrapper writes
  # terminal state within a poll of the harness exiting when the guard is gone.
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    kill -0 "$sp"
    [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
    [ ! -e "$DUX_HOME/state/$id.handoffs" ]
    sleep 0.2
  done
  wait "$wp" || true
  run kill -0 "$sp"
  [ "$status" -ne 0 ]
  [ "$(handoff_status)" = "done: report" ]
}

@test "a worker group that will not stop blocks terminal state" {
  prepare scout
  printf 'stubborn %s\nstatus done: report\nexit 0\n' \
    "$DUX_HOME/state/stubborn.pid" > "$FAKE_WORKER_SCRIPT"
  export DUX_WRAP_STOP_GRACE_SECS=1 DUX_WRAP_STOP_SIGNALS=off
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"survived TERM and KILL"* ]]
  [ ! -e "$DUX_HOME/state/$id.handoffs" ]
  sp="$(cat "$DUX_HOME/state/stubborn.pid")"
  kill -0 "$sp"
  # Everything a recovery would need to find the survivor is still on disk.
  [ -s "$DUX_HOME/state/$id.pgid" ]
  [ -s "$DUX_HOME/state/$id.portal" ]
  [ -d "$(cat "$DUX_HOME/state/$id.portal")" ]
  kill -KILL -- "-$(cat "$DUX_HOME/state/$id.pgid")" 2>/dev/null || true
}

@test "a worker that rewrites or truncates its status proposals fails the task" {
  prepare scout
  printf 'status working: one\nsleep 3\nrun printf "working: two\\n" > "$DUX_STATUS_LOG"\nsleep 3\nstatus done: report\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id rewrote a status proposal it had already made"* ]]
  # A refusal once the run record exists is a result too, so it is a handoff.
  [ "$(handoff_status)" = "failed: wrapper: the worker for $id rewrote a status proposal it had already made" ]
  [ "$(handoff_event)" = failed ]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'status working: one\nsleep 3\nrun : > "$DUX_STATUS_LOG"\nsleep 3\nstatus done: report\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id truncated its status proposals"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
}

@test "a status proposal that is not a state line fails the task" {
  prepare scout
  printf 'run printf "ready to go\\n" >> "$DUX_STATUS_LOG"\nsleep 3\nstatus done: report\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id proposed a line that is not a status line"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  [ "$(status_log | grep -c 'ready to go' || true)" -eq 0 ]
  [ "$(handoff_status)" = "failed: wrapper: the worker for $id proposed a line that is not a status line" ]
}

@test "a status line the worker never finished fails the task" {
  prepare scout
  printf 'status working: one\nrun printf "done: PR https://example.invalid/pr/1" >> "$DUX_STATUS_LOG"\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id left a status line unfinished"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  [ "$(status_log | grep -c '^ended:' || true)" -eq 0 ]
  [ "$(status_log | head -n 1)" = "working: one" ]
}

@test "a second terminal proposal, or any line after one, fails the task" {
  prepare scout
  printf 'status done: report\nstatus failed: changed my mind\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id proposed a second terminal status"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  [ "$(status_log | grep -c '^failed: changed' || true)" -eq 0 ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'status done: report\nstatus working: one more thing\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id kept writing after its terminal status"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
}

@test "a status line over 200 bytes fails the task, 200 exactly does not" {
  prepare scout
  # "working: " is 9 bytes, so 191 x's is exactly the limit and 192 is over it.
  at="$(printf 'x%.0s' $(seq 1 191))"
  over="$(printf 'x%.0s' $(seq 1 192))"
  printf 'report all clear\nstatus working: %s\nstatus done: report\nexit 0\n' "$at" > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "done: report" ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'status working: %s\nstatus done: report\nexit 0\n' "$over" > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id proposed a status line over 200 bytes"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  [ "$(status_log | grep -c 'xxx' || true)" -eq 0 ]
}

@test "a run reference pointed somewhere else during the run is refused" {
  prepare scout
  # The worker's environment no longer names any Dux path, so the fixture is
  # given the one it rewrites; a real worker would have to find it.
  printf 'report all clear\nrun printf %%s\\n /elsewhere > %s/state/%s.portal\nstatus done: report\nexit 0\n' \
    "$DUX_HOME" "$id" > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the run references for $id no longer name this run's channel"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
}

@test "an outbox the worker replaced is refused, and its contents are not read" {
  prepare scout
  printf 'status working: a\nrun rm -f "$DUX_STATUS_LOG"; printf "done: swapped in\\n" > "$DUX_STATUS_LOG"\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the worker for $id replaced its status outbox"* ]]
  [ "$(status_log | grep -c 'swapped in' || true)" -eq 0 ]

  # Same guard on the other outbox: a fresh file at the same path is a
  # different file, and a symlink is not an outbox at all.
  # A refusal leaves this run's references for recovery; clear them by hand so
  # the second half meets the outbox guard and not the leftover-reference one.
  clear_refs
  printf 'status done: report\nrun rm -f "$DUX_REPORT"; ln -s /dev/null "$DUX_REPORT"\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the worker for $id replaced its report outbox"* ]]
}

@test "a leftover run reference from an earlier run is refused, symlinks included" {
  prepare scout
  printf 'report all clear\nstatus done: report\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  # handoffs belongs here too: a sequence from an earlier run would be numbered
  # behind this run's, so a reader could not tell whose result it was reading.
  for ref in run portal pgid result-context handoffs; do
    printf 'stale\n' > "$DUX_HOME/state/$id.$ref"
    run wrap
    [ "$status" -eq 2 ]
    [[ "$output" == *"finding: $id already has a reference from an earlier run at state/$id.$ref"* ]]
    rm -f "$DUX_HOME/state/$id.$ref"
  done
  # A dangling symlink is a reference too: -e alone would walk straight past it.
  ln -s "$DUX_HOME/state/gone" "$DUX_HOME/state/$id.portal"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $id already has a reference from an earlier run at state/$id.portal"* ]]
  rm -f "$DUX_HOME/state/$id.portal"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "done: report" ]
}

@test "more than 64 KiB of status proposals fails the task" {
  prepare scout
  # One poll, after the worker has written everything and gone, so the wrapper
  # meets the whole file at once rather than a prefix of it.
  export DUX_WRAP_POLL_SECS=5
  printf 'report all clear\nrun yes "working: filler line" | head -c 70000 >> "$DUX_STATUS_LOG"\nstatus done: report\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id wrote more than 65536 bytes of status proposals"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  [ "$(status_log | grep -c 'filler line' || true)" -eq 0 ]
}

@test "a report over 1 MiB fails the task" {
  prepare scout
  printf 'run yes "filler line" | head -c 1100000 >> "$DUX_REPORT"\nstatus done: report\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id wrote more than 1048576 bytes of report"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
  # refuse writes its own failure note there; none of the worker's bytes.
  [ "$(grep -c 'filler line' "$DUX_HOME/data/tasks/$id/report.md" || true)" -eq 0 ]
}

@test "a scout's report reaches report.md through the channel and proves the result" {
  prepare scout
  printf 'run printf "# Findings\\nall clear\\n" > "$DUX_REPORT"\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(handoff_status)" = "done: report" ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/report.md")" = $'# Findings\nall clear' ]
}

@test "refusals are findings and are recorded as failed with a reason" {
  prepare scout
  printf 'status done: report\n' > "$FAKE_WORKER_SCRIPT"
  run dux-worker-wrap "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: dux-worker-wrap must run inside the worktree on dux/$id"* ]]
  [ "$(status_log | tail -n 1)" = "failed: wrapper: dux-worker-wrap must run inside the worktree on dux/$id (cwd is $PWD)" ]
  echo gemini > "$DUX_HOME/data/tasks/$id/harness"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown worker harness gemini"* ]]
  [ "$(status_log | tail -n 1)" = "failed: wrapper: unknown worker harness gemini (claude)" ]
  echo codex > "$DUX_HOME/data/tasks/$id/harness"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: codex workers are not available"* ]]
  [ "$(status_log | tail -n 1)" = "failed: wrapper: codex workers are not available: no deny list, so git push --no-verify skips the only guard (milestone 2)" ]
  rm "$DUX_HOME/data/tasks/$id/harness"
  echo 'plan=m:high ship=m:xhigh scout=m:bogus' > "$DUX_HOME/config/models"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: effort bogus is not valid for claude"* ]]
  [ "$(status_log | tail -n 1)" = "failed: wrapper: effort bogus is not valid for claude" ]
  grep -q '^## Failure$' "$DUX_HOME/data/tasks/$id/report.md"
  cp "$DUX_ROOT/templates/config/models" "$DUX_HOME/config/models"
  run bash -c 'cd "$1" && PATH="$DUX_ROOT/bin:/usr/bin:/bin" DUX_BACKEND=tmux dux-worker-wrap "$2"' _ "$wt" "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: claude is not on PATH inside the worker container"* ]]
  [ ! -e "$DUX_HOME/state/$id.pid" ]
}

@test "the worker inherits its task interfaces and nothing else of Dux's" {
  prepare scout
  printf 'report all clear\ndump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
  (cd "$wt" && CLAUDECODE=1 CLAUDE_PID=4242 CLAUDE_CODE_SESSION_ID=abc \
     HERDR_PANE_ID=w1:p9 TMUX=/tmp/sock,1,0 TMUX_PANE=%3 GIT_CONFIG_GLOBAL=/nowhere \
     DUX_BACKEND=tmux dux-worker-wrap "$id")
  e="$DUX_HOME/state/worker.env"
  [ "$(grep -c '^CLAUDECODE=' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^CLAUDE_' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^HERDR_' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^TMUX' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^DUX_ROOT=' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^DUX_HOME=' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^DUX_BACKEND=' "$e" || true)" -eq 0 ]
  [ "$(grep -c '^GIT_CONFIG_GLOBAL=' "$e" || true)" -eq 0 ]
  # The only DUX_ and GIT_CONFIG_ names left are the four this task hands back.
  [ "$(grep -c '^DUX_' "$e" || true)" -eq 2 ]
  [ "$(grep -c '^DUX_SHIP_RECORD=' "$e" || true)" -eq 0 ]
  grep -q "^DUX_STATUS_LOG=$DUX_HOME/state/channels/$id\." "$e"
  [ "$(grep -c '^GIT_CONFIG_' "$e" || true)" -eq 3 ]
  p="$(sed -n 's/^PATH=//p' "$e")"
  case ":$p:" in *":$DUX_ROOT/bin:"*) false ;; esac
  case ":$p:" in *":$DUX_ROOT/tests/fakes:"*) ;; *) false ;; esac
}

@test "a ship worker gets a recorder bound to its own task and run; no other shape does" {
  prepare ship
  printf 'dump-env %s\nrun "$DUX_SHIP_RECORD" checks\nstatus done: PR https://example.invalid/pr/1\n' \
    "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
  wrap
  e="$DUX_HOME/state/worker.env"
  ch="$(channel_of "$e")"
  grep -qx "DUX_SHIP_RECORD=$ch/ship-record" "$e"
  # The recorder is the only interface a ship gets beyond the two every worker has.
  [ "$(grep -c '^DUX_' "$e" || true)" -eq 3 ]
  # The phase it filed is bound to this task, this run, and this branch, and the
  # worker chose none of the three.
  r="$DUX_HOME/state/$id.ship-receipt"
  grep -qx "id=$id" "$r"
  grep -qx "run=${ch##*.}" "$r"
  grep -qx "branch=dux/$id" "$r"
  grep -q "^phase=checks sha=$(git -C "$wt" rev-parse HEAD) " "$r"
  # One phase is not five and no pull request answers for this branch, so the
  # ship this worker called done ends rather than completing.
  [ "$(handoff_event)" = ended ]
}

@test "a push to the base branch from inside the worker is refused by the channel's hook" {
  prepare scout
  before="$(git -C "$DUX_HOME/proj.origin" rev-parse main)"
  printf 'report all clear\nrun git commit -q --allow-empty -m work\nrun git push origin HEAD:refs/heads/main\nrun git push -q -u origin dux/%s\nstatus done: report\n' "$id" > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" = "$before" ]
  grep -q 'refusing to push to main from a Dux worktree' "$DUX_HOME/state/$id.out"
  git -C "$DUX_HOME/proj.origin" show-ref --verify --quiet "refs/heads/dux/$id"
}

@test "config/worker-harness selects the harness and a codex value never reaches the adapter" {
  prepare scout
  printf 'report all clear\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  echo claude > "$DUX_HOME/config/worker-harness"
  run wrap
  [ "$status" -eq 0 ]
  grep -q '^claude ' "$FAKE_WORKER_LOG"
  clear_refs
  echo codex > "$DUX_HOME/config/worker-harness"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: codex workers are not available"* ]]
  [ "$(grep -c '^codex ' "$FAKE_WORKER_LOG" || true)" -eq 0 ]
}

@test "on herdr every status line is mirrored and the title is set; on tmux nothing is" {
  prepare scout
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  (cd "$wt" && DUX_BACKEND=herdr HERDR_PANE_ID=w1:p9 dux-worker-wrap "$id")
  grep -qF "pane report-metadata w1:p9 --title proj: Do the thing the operator asked for." "$FAKE_HERDR_LOG"
  grep -qF "pane report-agent w1:p9 --source dux --agent dux-$id --state working --message dux $id: working" "$FAKE_HERDR_LOG"
  grep -qF "pane report-agent w1:p9 --source dux --agent dux-$id --state idle --message dux $id: done" "$FAKE_HERDR_LOG"
  [ "$(grep -c 'starting' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  : > "$FAKE_HERDR_LOG"
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  (cd "$wt" && DUX_BACKEND=tmux dux-worker-wrap "$id")
  [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "on herdr without HERDR_PANE_ID the wrapper logs once and finishes" {
  prepare scout
  printf 'report all clear\nstatus working: a\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  run env -u HERDR_PANE_ID bash -c 'cd "$1" && DUX_BACKEND=herdr dux-worker-wrap "$2"' _ "$wt" "$id"
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "done: report" ]
  [ "$(grep -c 'status mirroring unavailable' <<< "$output")" -eq 1 ]
}

@test "a signal before the harness starts is caught, not fatal to the wrapper" {
  prepare scout
  printf 'status done: report\n' > "$FAKE_WORKER_SCRIPT"
  # The title call is the last step before the harness is forked, so a slow one
  # holds the wrapper in the window where the trap must already be installed.
  export FAKE_HERDR_SLOW_METADATA=5
  bash -c 'cd "$1" && DUX_BACKEND=herdr HERDR_PANE_ID=w1:p9 exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    grep -q '^pane report-metadata' "$FAKE_HERDR_LOG" && break
    sleep 0.5
  done
  grep -q '^pane report-metadata' "$FAKE_HERDR_LOG"
  kill -TERM "$wp"
  wait "$wp" || true
  [ "$(handoff_status)" = "failed: wrapper: signalled before the harness started" ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "a signal after the last check and before the fork still stops the harness" {
  prepare scout
  printf 'status working: started\nsleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  # The window the trap cannot cover: signalled is set with no wpid to kill, so
  # only the re-check after the fork can stop the harness.
  export DUX_WRAP_FORK_PAUSE_SECS=5
  bash -c 'cd "$1" && DUX_BACKEND=tmux exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -s "$DUX_HOME/state/$id.pid" ] && break
    sleep 0.3
  done
  [ -s "$DUX_HOME/state/$id.pid" ]
  sleep 1
  kill -TERM "$wp"
  # Without the re-check the wrapper supervises the harness for the full 30s.
  gone=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
    kill -0 "$wp" 2>/dev/null || { gone=1; break; }
    sleep 0.5
  done
  wait "$wp" || true
  [ "$gone" -eq 1 ]
  [ "$(handoff_status)" = "failed: worker exited 143" ]
  [ "$(status_log | grep -c '^done: report' || true)" -eq 0 ]
}

@test "an invalid task id is refused before any file is written" {
  prepare scout
  before="$(ls -A "$DUX_HOME/data" | sort)"
  run dux-worker-wrap ..
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task id must not be all dots: .."* ]]
  [ ! -e "$DUX_HOME/data/status.log" ]
  [ ! -e "$DUX_HOME/data/report.md" ]
  [ "$(ls -A "$DUX_HOME/data" | sort)" = "$before" ]
  run dux-worker-wrap 'a b'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task id must match [A-Za-z0-9._-]+: a b"* ]]
  [ "$(ls -A "$DUX_HOME/data" | sort)" = "$before" ]
}

@test "TERM to the wrapper reaches the harness and is recorded as failed" {
  prepare scout
  printf 'sleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  bash -c 'cd "$1" && DUX_BACKEND=tmux exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  sleep 2; kill -TERM "$wp"
  wait "$wp" || true
  [ "$(handoff_status)" = "failed: worker exited 143" ]
}
