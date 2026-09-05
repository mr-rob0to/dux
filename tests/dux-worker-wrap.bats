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
# The channel is random and goes away with the run, so tests read the name the
# worker itself was given rather than guessing it.
channel_of() { sed -n 's#^DUX_STATUS_LOG=\(.*\)/status.outbox$#\1#p' "$1"; }

@test "happy path: status lines land, out and pid files exist, model and settings reach the harness" {
  prepare scout
  printf 'status working: starting\nstatus done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(status_log)" = $'working: starting\ndone: PR https://example.invalid/pr/1' ]
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  grep -q '"type":"assistant"' "$DUX_HOME/state/$id.out"
  grep -q -- "--model claude-sonnet-5 --effort medium" "$FAKE_WORKER_LOG"
  grep -qE -- "--settings $DUX_HOME/state/channels/$id\.[A-Za-z0-9]+/worker-settings.json" "$FAKE_WORKER_LOG"
  [ ! -e "$DUX_HOME/data/tasks/$id/report.md" ]
}

@test "non-zero exit without an exit line appends failed and writes a failure tail" {
  prepare scout
  printf 'status working: starting\nexit 7\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(status_log | tail -n 1)" = "failed: worker exited 7" ]
  grep -q '^## Failure tail' "$DUX_HOME/data/tasks/$id/report.md"
  grep -q 'starting' "$DUX_HOME/data/tasks/$id/report.md"
}

@test "zero exit without an exit line appends ended; blocked is left alone" {
  prepare scout
  printf 'status working: starting\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | tail -n 1)" = "ended: exit 0 without terminal status" ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'status blocked: cannot reach the API, tried twice\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log)" = "blocked: cannot reach the API, tried twice" ]
}

@test "heartbeat appears only while the out file grows" {
  prepare scout
  printf 'status working: a\nsleep 2\nstatus working: b\nsleep 3\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | grep -c '^working: heartbeat$')" -le 3 ]
  id2="$(dux-task-new proj scout)"
  printf 'x\n' > "$DUX_HOME/i2"; printf '1. y\n' > "$DUX_HOME/c2"
  dux-brief "$id2" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id2"; wt="$(dux-worktree create "$id")"
  printf 'sleep 3\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c heartbeat || true)" -eq 0 ]
  id3="$(dux-task-new proj scout)"
  dux-brief "$id3" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id3"; wt="$(dux-worktree create "$id")"
  printf 'say thinking\nsleep 2\nsay still thinking\nsleep 2\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | head -n 1)" = "working: heartbeat" ]
}

@test "the worker's status log is its own channel outbox, never the task's status log" {
  prepare scout
  printf 'dump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
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
  # The proposal reached status.log by way of the wrapper, not the worker's hand.
  [ "$(status_log)" = "done: report" ]
}

@test "the channel holds the worker's own copies and goes away with the run" {
  prepare scout
  printf 'run ls -ld "$(dirname "$DUX_STATUS_LOG")"/. "$(dirname "$DUX_STATUS_LOG")"/* > %s 2>&1\nrun printf %%s "$DUX_STATUS_LOG" > %s\nstatus done: report\n' \
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
  printf 'orphan %s\nstatus done: report\nexit 0\n' "$DUX_HOME/state/orphan.pid" > "$FAKE_WORKER_SCRIPT"
  wrap
  op="$(cat "$DUX_HOME/state/orphan.pid")"
  [[ "$op" =~ ^[0-9]+$ ]]
  run kill -0 "$op"
  [ "$status" -ne 0 ]
  [ "$(status_log | tail -n 1)" = "done: report" ]
}

@test "a scout's report reaches report.md through the channel" {
  prepare scout
  printf 'run printf "# Findings\\nall clear\\n" > "$DUX_REPORT"\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log)" = "done: report" ]
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
  printf 'dump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
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
  grep -q "^DUX_STATUS_LOG=$DUX_HOME/state/channels/$id\." "$e"
  [ "$(grep -c '^GIT_CONFIG_' "$e" || true)" -eq 3 ]
  p="$(sed -n 's/^PATH=//p' "$e")"
  case ":$p:" in *":$DUX_ROOT/bin:"*) false ;; esac
  case ":$p:" in *":$DUX_ROOT/tests/fakes:"*) ;; *) false ;; esac
}

@test "a push to the base branch from inside the worker is refused by the channel's hook" {
  prepare scout
  before="$(git -C "$DUX_HOME/proj.origin" rev-parse main)"
  printf 'run git commit -q --allow-empty -m work\nrun git push origin HEAD:refs/heads/main\nrun git push -q -u origin dux/%s\nstatus done: report\n' "$id" > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" = "$before" ]
  grep -q 'refusing to push to main from a Dux worktree' "$DUX_HOME/state/$id.out"
  git -C "$DUX_HOME/proj.origin" show-ref --verify --quiet "refs/heads/dux/$id"
}

@test "config/worker-harness selects the harness and a codex value never reaches the adapter" {
  prepare scout
  printf 'status done: report\n' > "$FAKE_WORKER_SCRIPT"
  echo claude > "$DUX_HOME/config/worker-harness"
  run wrap
  [ "$status" -eq 0 ]
  grep -q '^claude ' "$FAKE_WORKER_LOG"
  echo codex > "$DUX_HOME/config/worker-harness"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: codex workers are not available"* ]]
  [ "$(grep -c '^codex ' "$FAKE_WORKER_LOG" || true)" -eq 0 ]
}

@test "on herdr every status line is mirrored and the title is set; on tmux nothing is" {
  prepare scout
  printf 'status working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
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
  printf 'status working: a\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  run env -u HERDR_PANE_ID bash -c 'cd "$1" && DUX_BACKEND=herdr dux-worker-wrap "$2"' _ "$wt" "$id"
  [ "$status" -eq 0 ]
  [ "$(status_log | tail -n 1)" = "done: report" ]
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
  [ "$(status_log | tail -n 1)" = "failed: wrapper: signalled before the harness started" ]
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
  [ "$(status_log | tail -n 1)" = "failed: worker exited 143" ]
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
  [ "$(status_log | tail -n 1)" = "failed: worker exited 143" ]
}
