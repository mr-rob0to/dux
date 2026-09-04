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

@test "happy path: status lines land, out and pid files exist, model and settings reach the harness" {
  prepare scout
  printf 'status working: starting\nstatus done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  [ "$(status_log)" = $'working: starting\ndone: PR https://example.invalid/pr/1' ]
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  grep -q '"type":"assistant"' "$DUX_HOME/state/$id.out"
  grep -q -- "--model claude-sonnet-5 --effort medium" "$FAKE_WORKER_LOG"
  grep -q -- "--settings $DUX_HOME/data/tasks/$id/worker-settings.json" "$FAKE_WORKER_LOG"
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
  ! status_log | grep -q heartbeat
  id3="$(dux-task-new proj scout)"
  dux-brief "$id3" --intent-file "$DUX_HOME/i2" --criteria-file "$DUX_HOME/c2" >/dev/null
  id="$id3"; wt="$(dux-worktree create "$id")"
  printf 'say thinking\nsleep 2\nsay still thinking\nsleep 2\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(status_log | grep -c '^working: heartbeat$')" -ge 1 ]
  [ "$(status_log | head -n 1)" = "working: heartbeat" ]
}

@test "the worker's environment carries the status log and the hooks dir" {
  prepare scout
  printf 'dump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
  wrap
  grep -qx "DUX_STATUS_LOG=$DUX_HOME/data/tasks/$id/status.log" "$DUX_HOME/state/worker.env"
  grep -qx "GIT_CONFIG_COUNT=1" "$DUX_HOME/state/worker.env"
  grep -qx "GIT_CONFIG_KEY_0=core.hooksPath" "$DUX_HOME/state/worker.env"
  grep -qx "GIT_CONFIG_VALUE_0=$DUX_HOME/data/tasks/$id/hooks" "$DUX_HOME/state/worker.env"
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
  [ "$(status_log | tail -n 1)" = "failed: wrapper: unknown worker harness gemini (claude or codex)" ]
  echo codex > "$DUX_HOME/data/tasks/$id/harness"
  echo 'plan=m:high ship=m:xhigh scout=m:max' > "$DUX_HOME/config/models-codex"
  run wrap
  [ "$status" -eq 2 ]; [[ "$output" == "finding: effort max is not valid for codex"* ]]
  [ "$(status_log | tail -n 1)" = "failed: wrapper: effort max is not valid for codex" ]
  grep -q '^## Failure$' "$DUX_HOME/data/tasks/$id/report.md"
  run bash -c 'cd "$1" && PATH="$DUX_ROOT/bin:/usr/bin:/bin" DUX_BACKEND=tmux dux-worker-wrap "$2"' _ "$wt" "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: codex is not on PATH inside the worker container"* ]]
  [ ! -e "$DUX_HOME/state/$id.pid" ]
}

@test "the Dux session's own harness variables never reach the worker" {
  prepare scout
  printf 'dump-env %s\nstatus done: report\n' "$DUX_HOME/state/worker.env" > "$FAKE_WORKER_SCRIPT"
  (cd "$wt" && CLAUDECODE=1 CLAUDE_PID=4242 CLAUDE_CODE_SESSION_ID=abc DUX_BACKEND=tmux dux-worker-wrap "$id")
  ! grep -q '^CLAUDECODE=' "$DUX_HOME/state/worker.env"
  ! grep -q '^CLAUDE_' "$DUX_HOME/state/worker.env"
  grep -qx "DUX_STATUS_LOG=$DUX_HOME/data/tasks/$id/status.log" "$DUX_HOME/state/worker.env"
}

@test "a push to the base branch from inside the worker is refused by the task's hook" {
  prepare scout
  before="$(git -C "$DUX_HOME/proj.origin" rev-parse main)"
  printf 'run git commit -q --allow-empty -m work\nrun git push origin HEAD:refs/heads/main\nrun git push -q -u origin dux/%s\nstatus done: report\n' "$id" > "$FAKE_WORKER_SCRIPT"
  wrap
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" = "$before" ]
  grep -q 'refusing to push to main from a Dux worktree' "$DUX_HOME/state/$id.out"
  git -C "$DUX_HOME/proj.origin" show-ref --verify --quiet "refs/heads/dux/$id"
}

@test "the codex harness runs codex with its own model file" {
  prepare scout
  echo codex > "$DUX_HOME/data/tasks/$id/harness"
  printf 'status done: report\n' > "$FAKE_WORKER_SCRIPT"
  run wrap
  [ "$status" -eq 0 ]
  grep -q '^codex ' "$FAKE_WORKER_LOG"
  grep -q -- '-m gpt-5.6-sol' "$FAKE_WORKER_LOG"
  grep -q -- '--sandbox danger-full-access' "$FAKE_WORKER_LOG"
  ! grep -q '^claude ' "$FAKE_WORKER_LOG"
}

@test "on herdr every status line is mirrored and the title is set; on tmux nothing is" {
  prepare scout
  printf 'status working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  (cd "$wt" && DUX_BACKEND=herdr HERDR_PANE_ID=w1:p9 dux-worker-wrap "$id")
  grep -qF "pane report-metadata w1:p9 --title proj: Do the thing the operator asked for." "$FAKE_HERDR_LOG"
  grep -qF "pane report-agent w1:p9 --source dux --agent dux-$id --state working --message working: starting" "$FAKE_HERDR_LOG"
  grep -qF "pane report-agent w1:p9 --source dux --agent dux-$id --state idle --message done: report" "$FAKE_HERDR_LOG"
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

@test "TERM to the wrapper reaches the harness and is recorded as failed" {
  prepare scout
  printf 'sleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  bash -c 'cd "$1" && DUX_BACKEND=tmux exec dux-worker-wrap "$2"' _ "$wt" "$id" & wp=$!
  sleep 2; kill -TERM "$wp"
  wait "$wp" || true
  [ "$(status_log | tail -n 1)" = "failed: worker exited 143" ]
}
