load helpers/setup

# The wrapper no longer forks the harness: it starts it in a pane and finds it
# through the multiplexer. So every test here needs a real tmux window, on this
# file's own socket, and the tab has to exist before the wrapper runs, because
# that is what dux-spawn does.
setup_file() {
  use_tmux_tmpdir
  # Pinned, not defaulted: this file's tab is a real tmux window, so an ambient
  # DUX_BACKEND would point the wrapper at a pane that is not there. The one
  # test about Herdr names that backend itself.
  export DUX_BACKEND=tmux DUX_TMUX_SOCKET=dux-wrap DUX_TMUX_SESSION=duxwrap
  tmux -L dux-wrap kill-server 2>/dev/null || true
  tmux -L dux-wrap new-session -d -s duxwrap -x 80 -y 24
}
teardown_file() {
  tmux -L dux-wrap kill-server 2>/dev/null || true
  drop_tmux_tmpdir
}

# What the pane's shell has to carry for the fake to work. The launcher strips
# every DUX_, CLAUDE_, HERDR_, TMUX and GIT_CONFIG_ name, so only these reach
# the harness. tmux gives a respawned pane the session's environment; the herdr
# fake starts the command itself and inherits the wrapper's.
pane_env() {
  local v
  for v in "PATH=$PATH" "FAKE_WORKER_SCRIPT=$FAKE_WORKER_SCRIPT" \
           "FAKE_WORKER_LOG=$FAKE_WORKER_LOG" \
           "GIT_AUTHOR_NAME=$GIT_AUTHOR_NAME" "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL" \
           "GIT_COMMITTER_NAME=$GIT_COMMITTER_NAME" "GIT_COMMITTER_EMAIL=$GIT_COMMITTER_EMAIL"; do
    tmux -L dux-wrap set-environment -t duxwrap "${v%%=*}" "${v#*=}"
  done
}

# The tab dux-spawn would have opened, and where it recorded it. The Herdr fake
# answers for one workspace, the way the real CLI reads the pane Dux runs in.
open_tab() {  # [$1 backend]
  # FAKE_HERDR_RUN makes the fake actually start what `pane run` is given, in a
  # session of its own, so the wrapper has a real process to discover.
  [ "${1:-tmux}" != herdr ] || export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  DUX_BACKEND="${1:-tmux}" dux-backend open "$id" "$wt" > "$DUX_HOME/state/$id.endpoint"
}

# A task with a brief, rendered settings, a worktree, and the tab its worker runs in.
prepare() {  # $1 shape; sets $id and $wt
  id="$(fixture_task proj "$1")"
  wt="$(dux-worktree create "$id")"
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script"
  export DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1
  harness_shim
  pane_env
  open_tab
}
# A second task in one test needs its own tab, so this is what follows a new id.
reprepare() {  # sets $wt for the current $id
  wt="$(dux-worktree create "$id")"
  harness_shim
  open_tab
}
wrap() { (cd "$wt" && dux-worker-wrap "$id"); }
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
  # The worker's output is its tab's scrollback. Dux captures none of it.
  [ ! -e "$DUX_HOME/state/$id.out" ]
  # The group the wrapper wrote is the harness's own, found through the pane.
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

# A session that goes with no terminal line is ended however it went: the
# operator typed /exit, the harness crashed, the machine took it. The wrapper
# did not fork it, so there is no exit status to tell those apart, and ended is
# where all three belong -- recovery proves what the run actually left behind.
@test "a harness that goes with no terminal line ends the run, whatever its exit code" {
  prepare scout
  printf 'status working: starting\nexit 7\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "ended: the session ended without a terminal status" ]
  [ "$(handoff_event)" = ended ]
  # ended is not failed, so nothing writes a failure tail; a scout that proposed
  # no report leaves no report.md at all.
  refute test -e "$DUX_HOME/data/tasks/$id/report.md"
}

@test "zero exit without an exit line appends ended; blocked is left alone" {
  prepare scout
  printf 'status working: starting\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(handoff_status)" = "ended: the session ended without a terminal status" ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; reprepare
  printf 'status blocked: cannot reach the API, tried twice\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(handoff_status)" = "blocked: cannot reach the API, tried twice" ]
}

# The heartbeat is the beat file's mtime moving. Claude Code's PostToolUse and
# Stop hooks touch it; the fake touches it directly, which is the same file and
# the same question. It is a liveness hint, never proof and never read for
# content: the wrapper only ever asks whether the number changed.
@test "heartbeat appears only while the beat file's mtime moves" {
  prepare scout
  printf 'report all clear\nstatus working: a\ntouch beat\nsleep 2\ntouch beat\nsleep 2\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  # The channel goes with the run, so the beat file is not left behind.
  [ ! -e "$DUX_HOME/state/$id.beat" ]

  # A worker that never touches it is silent, however long it runs.
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; reprepare
  printf 'report all clear\nsleep 4\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c heartbeat || true)" -eq 0 ]

  # And one that beats without proposing anything is heard, which is the whole
  # point: an interactive session writes nothing to Dux between status lines.
  id3="$(dux-task-new proj scout)"
  dux-brief "$id3" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id3"; reprepare
  printf 'report all clear\ntouch beat\nsleep 2\ntouch beat\nsleep 2\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | take_line)" = "working: heartbeat" ]
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
  [ "$(grep -c '^GIT_CONFIG_' "$env_file" || true)" -eq 0 ]
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
  # No hooks: the worktree's own git configuration names the task hooks
  # directory, so the channel has nothing to stage.
  [ "$(grep -cE '/hooks$' "$ls" || true)" -eq 0 ]
  ch="$(dirname "$(cat "$DUX_HOME/state/chan.path")")"
  [ ! -e "$ch" ]
  [ ! -e "$DUX_HOME/state/$id.portal" ]
  [ ! -e "$DUX_HOME/state/$id.pgid" ]
  # What a later result has to be proved against outlives the channel.
  grep -qx "run=${ch##*.}" "$DUX_HOME/state/$id.run"
  grep -qx "id=$id" "$DUX_HOME/state/$id.result-context"
  grep -qx "branch=dux/$id" "$DUX_HOME/state/$id.result-context"
  grep -qx "context=$(git hash-object "$DUX_HOME/state/$id.result-context")" "$DUX_HOME/state/$id.run"
  # Which repository the run belongs to is read by github_slug, the same helper
  # intake builds a source key with. No GitHub origin records "-".
  grep -qx "repo=-" "$DUX_HOME/state/$id.result-context"
  id="$(fixture_task proj2 scout github)"
  reprepare
  wrap
  grep -qx "repo=acme/proj2" "$DUX_HOME/state/$id.result-context"
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
  # The pane no longer holds a live harness, so the wrapper is about to stop the
  # group. Not "the pid is gone": nothing waits on a process it did not fork, so
  # the harness sits as a zombie kill -0 answers for until the group is reaped.
  ep="$(cat "$DUX_HOME/state/$id.endpoint")"
  wait_until 20 refute dux-backend pid "$ep" claude
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
  id="$id2"; reprepare
  printf 'status working: one\nsleep 3\nrun : > "$DUX_STATUS_LOG"\nsleep 3\nstatus done: report\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker for $id truncated its status proposals"* ]]
  [ "$(status_log | grep -c '^done:' || true)" -eq 0 ]
}

# GNU stat spells the format -c and reads -f as --file-system: handed a format
# string it prints a whole filesystem report to stdout and then fails. Asking it
# the BSD way first and keeping whatever came out gave the outbox a different
# identity on every call, which failed every run on Linux and nothing on macOS.
# The shim answers the way GNU stat does, on either kind of machine.
@test "the outbox identity survives a stat that answers the GNU way" {
  prepare scout
  shim="$DUX_HOME/shim"; mkdir -p "$shim"
  cat > "$shim/stat" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -c) case "${2:-}" in
        '%d:%i'|'%Y') /usr/bin/stat -c "$2" "$3" 2>/dev/null && exit 0
                      case "$2" in '%d:%i') exec /usr/bin/stat -f '%d:%i' "$3" ;; *) exec /usr/bin/stat -f %m "$3" ;; esac ;;
        *) exit 1 ;;
      esac ;;
  -f) printf '  File: "%s"\n' "${3:-}"
      printf 'Blocks: Total: 100 Free: %s\n' "$RANDOM"
      printf "stat: cannot read file system information for '%s'\n" "${2:-}" >&2
      exit 1 ;;
esac
exec /usr/bin/stat "$@"
SH
  chmod +x "$shim/stat"
  export PATH="$shim:$PATH"
  printf 'report all clear\nstatus working: one\nstatus done: report\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(handoff_status)" = "done: report" ]
  [ "$(status_log)" = "working: one" ]
}

# The pin is a second name for the outbox, so its inode cannot be freed and
# handed to a replacement. Losing the pin is a replacement too: without it the
# question "is this still the same file" has nothing to answer with.
@test "a worker that removes the outbox's pin fails the task" {
  prepare scout
  printf 'status working: a\nrun rm -f "$(dirname "$DUX_STATUS_LOG")/.status.pin"\nsleep 2\nstatus done: report\nexit 0\n' \
    > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the worker for $id replaced its status outbox"* ]]
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
  id="$id2"; reprepare
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
  id="$id2"; reprepare
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
  # The only DUX_ names left are the two this task hands back, and no git name
  # at all: the worker's git is configured by the worktree it stands in.
  [ "$(grep -c '^DUX_' "$e" || true)" -eq 2 ]
  [ "$(grep -c '^DUX_SHIP_RECORD=' "$e" || true)" -eq 0 ]
  grep -q "^DUX_STATUS_LOG=$DUX_HOME/state/channels/$id\." "$e"
  [ "$(grep -c '^GIT_CONFIG_' "$e" || true)" -eq 0 ]
  p="$(sed -n 's/^PATH=//p' "$e")"
  case ":$p:" in *":$DUX_ROOT/bin:"*) false ;; esac
  case ":$p:" in *":$DUX_ROOT/tests/fakes:"*) ;; *) false ;; esac
}

# The one that proves the fix cures workers: make_repo's exact operation, a
# throwaway repository pushed to its own main, performed from inside the
# environment this wrapper built. It passes only when no git configuration
# reached the worker, and the worktree is still guarded all the same.
@test "a worker's git guard stops at its worktree" {
  make_repo "$DUX_HOME/proj" main
  # The project's own pre-push, so the chain through the rendered hook is visible.
  printf '#!/bin/sh\ncat > "$(git rev-parse --show-toplevel)/../upstream-saw-refs"\n' \
    > "$DUX_HOME/proj/.git/hooks/pre-push"
  chmod +x "$DUX_HOME/proj/.git/hooks/pre-push"
  dux-project add "$DUX_HOME/proj" --base main --pr-template skip >/dev/null
  prepare scout
  (cd "$wt" && git commit -q --allow-empty -m work)
  before="$(git -C "$DUX_HOME/proj.origin" rev-parse main)"
  t="$DUX_HOME/throwaway"; rc="$DUX_HOME/state/rc"
  cat > "$FAKE_WORKER_SCRIPT" <<EOF
report all clear
run d=$t; git init -q -b main "\$d.o" && git -C "\$d.o" commit -q --allow-empty -m init && git clone -q --bare "\$d.o" "\$d.origin" && git clone -q "\$d.origin" "\$d" && git -C "\$d" commit -q --allow-empty -m fixture; git -C "\$d" push -q origin main; echo \$? > $rc.fixture
run git push -q origin HEAD:refs/heads/main 2> $DUX_HOME/state/push.err; echo \$? > $rc.base
run git push -q -u origin dux/$id; echo \$? > $rc.task
status done: report
EOF
  wrap
  # A fixture repository is nobody's business but its own.
  [ "$(cat "$rc.fixture")" = 0 ]
  [ "$(git -C "$t.origin" rev-parse main)" = "$(git -C "$t" rev-parse HEAD)" ]
  # The worktree is still refused on the base branch, and origin did not move.
  [ "$(cat "$rc.base")" != 0 ]
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" = "$before" ]
  grep -q "finding: refusing to push to main from a Dux worktree" "$DUX_HOME/state/push.err"
  # The task branch goes, and the project's own pre-push saw the same refs.
  [ "$(cat "$rc.task")" = 0 ]
  grep -q "refs/heads/dux/$id" "$DUX_HOME/proj/.worktrees/upstream-saw-refs"
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

@test "a push to the base branch from inside the worker is refused by the worktree's hook" {
  prepare scout
  before="$(git -C "$DUX_HOME/proj.origin" rev-parse main)"
  printf 'report all clear\nrun git commit -q --allow-empty -m work\nrun git push origin HEAD:refs/heads/main 2> %s\nrun git push -q -u origin dux/%s\nstatus done: report\n' \
    "$DUX_HOME/state/push.err" "$id" > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" = "$before" ]
  grep -q 'refusing to push to main from a Dux worktree' "$DUX_HOME/state/push.err"
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

# The title is set by endpoint, because the wrapper has no pane of its own any
# more. Nothing else is reported to the multiplexer: a real session in the pane
# is something Herdr detects by itself, and a Dux mirror would be a second
# source for one pane saying something the session did not.
@test "the title is set by endpoint and nothing else is reported to the backend" {
  prepare scout
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id2="$id"; wt2="$wt"
  open_tab herdr
  ep="$(cat "$DUX_HOME/state/$id.endpoint")"
  pane="${ep#herdr:}"
  (cd "$wt" && DUX_BACKEND=herdr dux-worker-wrap "$id")
  [ "$(handoff_status)" = "done: report" ]
  grep -qF "pane report-metadata $pane --source dux --title proj: Do the thing the operator asked for." "$FAKE_HERDR_LOG"
  # No agent state, and not one word the worker wrote.
  [ "$(grep -c 'report-agent' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  [ "$(grep -c 'starting' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  : > "$FAKE_HERDR_LOG"
  # tmux has no title of its own: backend_find matches the window name.
  id="$id2"; wt="$wt2"
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; reprepare
  wrap
  [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "a signal before the harness starts is caught, not fatal to the wrapper" {
  prepare scout
  printf 'status done: report\n' > "$FAKE_WORKER_SCRIPT"
  open_tab herdr
  # The title call is the last step before the launcher is started, so a slow
  # one holds the wrapper in the window where the trap must already be there.
  export FAKE_HERDR_SLOW_METADATA=5
  bash -c 'cd "$1" && DUX_BACKEND=herdr exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
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

# The window the trap cannot cover: signalled is set while there is no group to
# send anything to, so only the re-check after discovery can stop the harness.
@test "a signal after the last check and before the harness starts still stops it" {
  prepare scout
  printf 'status working: started\nsleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
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
  [ "$(handoff_status)" = "ended: the session ended without a terminal status" ]
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

# A signal to the wrapper still reaches the harness through its group, even
# though the wrapper never forked it. The run ends rather than failing: there is
# no exit status to read, and a stopped session is recovery's to look at.
@test "TERM to the wrapper reaches the harness and ends the run" {
  prepare scout
  printf 'sleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  bash -c 'cd "$1" && DUX_BACKEND=tmux exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  wait_until 20 test -s "$DUX_HOME/state/$id.pgid"
  hg="$(cat "$DUX_HOME/state/$id.pgid")"
  kill -TERM "$wp"
  wait "$wp" || true
  [ "$(handoff_status)" = "ended: the session ended without a terminal status" ]
  # The harness's whole group went with it, from outside its parent chain.
  run kill -0 -- "-$hg"
  [ "$status" -ne 0 ]
}

# ---- risk routes a ship task's model ---------------------------------------

@test "a bounded ship task runs on the bounded model and a complex one on the complex model" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  # fixture_task briefs a planned ship task, so dux-brief stored complex.
  [ "$(cat "$DUX_HOME/data/tasks/$id/risk")" = complex ]
  wrap
  grep -q -- "--model claude-opus-5 --effort max" "$FAKE_WORKER_LOG"
  [ "$(grep -c -- '--model claude-sonnet-5' "$FAKE_WORKER_LOG" || true)" -eq 0 ]

  : > "$FAKE_WORKER_LOG"
  clear_refs
  rm -f "$DUX_HOME/state/$id.pid"
  echo bounded > "$DUX_HOME/data/tasks/$id/risk"
  wrap
  grep -q -- "--model claude-sonnet-5 --effort medium" "$FAKE_WORKER_LOG"
  [ "$(grep -c -- '--model claude-opus-5' "$FAKE_WORKER_LOG" || true)" -eq 0 ]
}

@test "a ship task from before risk existed routes to the complex model" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  rm -f "$DUX_HOME/data/tasks/$id/risk"
  wrap
  grep -q -- "--model claude-opus-5 --effort max" "$FAKE_WORKER_LOG"
  [ "$(grep -c -- '--model claude-sonnet-5' "$FAKE_WORKER_LOG" || true)" -eq 0 ]
}

@test "a risk file that is not bounded or complex is a refusal, not a guess" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  printf 'cheap\n' > "$DUX_HOME/data/tasks/$id/risk"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: risk for $id must be bounded or complex, not 'cheap'"* ]]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "a models file with no entry for the task's risk is a refusal" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  echo 'plan=m:high scout=m:medium' > "$DUX_HOME/config/models"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: model entry for complex in $DUX_HOME/config/models must be <model>:<effort>, got 'nothing'"* ]]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "plan and scout tasks still route by shape" {
  prepare plan
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  grep -q -- "--model claude-fable-5-1 --effort high" "$FAKE_WORKER_LOG"
  [ ! -e "$DUX_HOME/data/tasks/$id/risk" ]
}

# ---- the run ends when the line does, not when the session does -------------

# An interactive harness finishes its turn and waits at the prompt. The protocol
# has one terminal line per run, so the wrapper ends the run on that line rather
# than waiting for a session that will never exit by itself. A session left
# alive behind the line would be a second run Dux has no record of.
@test "a terminal line ends the run within a poll, even though the session would go on" {
  prepare scout
  printf 'report all clear\nstatus done: report\nsleep 600\n' > "$FAKE_WORKER_SCRIPT"
  bash -c 'cd "$1" && DUX_BACKEND=tmux exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  wait_until 30 test -s "$DUX_HOME/state/$id.pgid"
  hg="$(cat "$DUX_HOME/state/$id.pgid")"
  # Two polls for the line plus the stop. The deadline is enforced here rather
  # than by waiting, so a wrapper that never notices fails in seconds instead of
  # holding the suite for the ten minutes the harness asked to sleep.
  gone=0
  for _ in $(seq 1 $(( 2 * DUX_WRAP_POLL_SECS + 4 ))); do
    kill -0 "$wp" 2>/dev/null || { gone=1; break; }
    sleep 1
  done
  if [ "$gone" -ne 1 ]; then
    kill -TERM "$wp" 2>/dev/null || true
    kill -KILL -- "-$hg" 2>/dev/null || true
    wait "$wp" || true
    echo "the wrapper was still supervising a finished run after the terminal line"
    return 1
  fi
  wait "$wp" || true
  [ "$(handoff_status)" = "done: report" ]
  [ "$(handoff_event)" = done ]
  # The session and everything it started went with the line.
  run kill -0 -- "-$hg"
  [ "$status" -ne 0 ]
}

# Discovery asks two questions of the pane's foreground process: is it the
# harness, and is it in this task's worktree. A pane holding anything else is a
# refusal at the end of the window, never a wrapper supervising the wrong thing.
@test "a pane that never holds the harness is a refusal, not a silent supervision" {
  prepare scout
  printf 'report all clear\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  # Something on PATH under the harness's name that is not the harness: the
  # pane gets a live foreground process the whole time, and it is never claude.
  printf '#!/bin/sh\nexec sleep 60\n' > "$DUX_HOME/hbin/claude"
  chmod 755 "$DUX_HOME/hbin/claude"
  export DUX_WRAP_START_SECS=2
  run wrap
  [ "$status" -eq 2 ]
  # And the refusal says what to do about the pane, because this is the refusal
  # that can leave a session running with no group file to hold the slot.
  [[ "$output" == *"the harness for $id did not appear in its pane within 2s; if a session is running there, end it in the tab before starting another task"* ]]
  [ "$(handoff_status)" = "failed: wrapper: the harness for $id did not appear in its pane within 2s; if a session is running there, end it in the tab before starting another task" ]
  [ "$(handoff_event)" = failed ]
  # Nothing was supervised, so no group was ever recorded.
  [ ! -e "$DUX_HOME/state/$id.pgid" ]
  # The impostor is still in the pane; the wrapper never signalled anything.
  ep="$(cat "$DUX_HOME/state/$id.endpoint")"
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 0 ]
  kill -TERM -- "-$(printf '%s' "$output" | cut -d' ' -f2)" 2>/dev/null || true
}

# ---- the review mode the brief recorded -------------------------------------
# The wrapper does not choose the mode and does not pass it anywhere: the brief
# carries it to the worker. What it does is refuse to start on a classification
# nothing can read, because the alternative is a worker that spends a whole
# session and then has its gate refused by dux-result for a file dux-brief wrote.

@test "a review file that is not combined or separate is a refusal, not a guess" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  printf 'mode=quick\nreason=faster\n' > "$DUX_HOME/data/tasks/$id/review"
  run wrap
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: review mode for $id must be combined or separate, not 'quick'"* ]]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "a ship task from before the review file existed starts, and is separate" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  rm -f "$DUX_HOME/data/tasks/$id/review"
  wrap
  [ -s "$FAKE_WORKER_LOG" ]
}

@test "a combined review file starts the worker" {
  prepare ship
  printf 'status working: hi\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  printf 'mode=combined\nreason=nothing sensitive\n' > "$DUX_HOME/data/tasks/$id/review"
  wrap
  [ -s "$FAKE_WORKER_LOG" ]
}
