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
  export DUX_BACKEND=herdr HERDR_WORKSPACE_ID=w1
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

# A spawned task whose worker never ran (FAKE_HERDR_RUN unset), so the test writes the status itself.
spawned() {  # $1 shape; sets $id and $wt
  id="$(fixture_task proj "$1")"
  dux-spawn "$id" >/dev/null
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  : > "$FAKE_HERDR_LOG"
}
status_is() { printf '%s\n' "$1" >> "$DUX_HOME/data/tasks/$id/status.log"; }

@test "refuses a non-terminal task" {
  spawned scout
  status_is "working: still going"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task $id is not terminal (ledger: running; last status: working: still going)"* ]]
  [ -d "$wt" ]; [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "refuses when the lock is not this session's" {
  spawned scout; status_is "done: report"
  DUX_SESSION_PID=424242 run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: the Dux lock is not held by this session"* ]]
  [ -d "$wt" ]
}

@test "refuses a dirty worktree and an unpushed branch, closing nothing" {
  spawned scout; status_is "done: report"
  echo scratch > "$wt/scratch"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worktree $wt has uncommitted changes"* ]]
  rm "$wt/scratch"; (cd "$wt" && git commit -q --allow-empty -m work)
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id has 1 commit(s) and no upstream"* ]]
  [ ! -s "$FAKE_HERDR_LOG" ]
  [ "$(dux-ledger get "$id" state)" = running ]
}

@test "done with a PR: worktree removed, pane closed, ledger done with the url, folder kept" {
  spawned scout; status_is "done: PR https://example.invalid/pr/9"
  echo 999999 > "$DUX_HOME/state/$id.pid"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "torn down $id state=done pr=https://example.invalid/pr/9" ]
  [ ! -d "$wt" ]
  grep -qx 'pane close w1:p9' "$FAKE_HERDR_LOG"
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = "https://example.invalid/pr/9" ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]; [ ! -e "$DUX_HOME/state/$id.pid" ]
  [ -f "$DUX_HOME/data/tasks/$id/brief.md" ]
  git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"
}

@test "failed: ledger failed, pr stays empty" {
  spawned scout; status_is "failed: worker exited 3"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "torn down $id state=failed pr=-" ]
  [ "$(dux-ledger get "$id" state)" = failed ]
}

@test "a live worker pid is a refusal even after done" {
  spawned scout; status_is "done: report"
  sleep 30 3>&- & live=$!
  echo "$live" > "$DUX_HOME/state/$id.pid"
  run dux-teardown "$id"
  kill "$live"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worker $live for $id is still running"* ]]
  [ -d "$wt" ]
}

@test "a ledger already marked failed is terminal even with an empty status log" {
  spawned scout
  dux-ledger set "$id" state failed
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [ "$(dux-ledger get "$id" state)" = failed ]
}

@test "a focused pane is a finding; the rerun completes once it is not focused" {
  spawned scout; status_is "done: report"
  export FAKE_HERDR_FOCUSED="$DUX_HOME/state/focused"; touch "$FAKE_HERDR_FOCUSED"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: refusing to close focused pane"* ]]
  [ "$(dux-ledger get "$id" state)" = running ]
  rm "$FAKE_HERDR_FOCUSED"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"torn down $id state=done"* ]]
}

@test "a container that is already gone is logged, not refused" {
  spawned scout; status_is "done: report"
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already gone"* ]]
  [ "$(grep -c '^pane close' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = done ]
}

@test "a failed close is a finding and the ledger is not updated" {
  spawned scout; status_is "done: report"
  FAKE_HERDR_CLOSE_FAIL=1 run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: herdr pane close failed"* ]]
  [ "$(dux-ledger get "$id" state)" = running ]
  [ -e "$DUX_HOME/state/$id.endpoint" ]
}
