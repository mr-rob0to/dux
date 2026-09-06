bats_require_minimum_version 1.5.0
load helpers/setup

# Spawn tests run on the fake Herdr backend with a fake worker that finishes at once.
setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  export GIT_AUTHOR_NAME=dux-test GIT_AUTHOR_EMAIL=dux-test@example.invalid
  export GIT_COMMITTER_NAME=dux-test GIT_COMMITTER_EMAIL=dux-test@example.invalid
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  cp "$DUX_ROOT"/templates/config/* "$DUX_HOME/config/"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export DUX_WATCHER=off
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log" FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log" FAKE_GH_LOG="$DUX_HOME/state/fake-gh.log"
  : > "$FAKE_HERDR_LOG"; : > "$FAKE_HERDR_OUTPUT"; : > "$FAKE_WORKER_LOG"; : > "$FAKE_GH_LOG"
  export DUX_BACKEND=herdr HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script" DUX_WRAP_POLL_SECS=1
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

wait_for() {  # $1 file, $2 grep pattern, $3 seconds
  local i=0
  until grep -q "$2" "$1" 2>/dev/null; do i=$((i + 1)); [ "$i" -ge "$3" ] && return 1; sleep 1; done
}
# A run ends by publishing a handoff, not by writing a terminal status line, so
# "the worker is finished" is that sequence appearing.
wait_result() {  # $1 id
  local i=0 f="$DUX_HOME/state/$1.handoffs/1/status"
  until [ -e "$f" ]; do i=$((i + 1)); [ "$i" -ge 15 ] && return 1; sleep 1; done
}

@test "refuses when the lock is not this session's, and touches nothing" {
  id="$(fixture_task proj scout)"
  DUX_SESSION_PID=424242 run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the Dux lock is not held by this session"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  [ ! -s "$FAKE_HERDR_LOG" ]
}

@test "refuses a task that is not queued and an endpoint that already exists" {
  id="$(fixture_task proj scout)"
  dux-ledger set "$id" state running
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task $id is running, not queued"* ]]
  dux-ledger set "$id" state queued
  echo herdr:w1:p9 > "$DUX_HOME/state/$id.endpoint"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: endpoint already recorded for $id"* ]]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

@test "refuses an unregistered project" {
  mkdir -p "$DUX_HOME/data/tasks/ghost-scout-20260903-abc"
  dux-ledger add ghost-scout-20260903-abc ghost scout local
  run dux-spawn ghost-scout-20260903-abc
  [ "$status" -eq 2 ]; [[ "$output" == "finding: project ghost not registered"* ]]
}

@test "refuses a missing brief, a brief without the worktree line, and an unknown harness" {
  id="$(fixture_task proj scout)"
  b="$DUX_HOME/data/tasks/$id/brief.md"
  cp "$b" "$DUX_HOME/brief.bak"; rm "$b"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: no brief for $id"* ]]
  grep -v 'set by dux-spawn' "$DUX_HOME/brief.bak" > "$b"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: brief for $id has no worktree line to fill"* ]]
  cp "$DUX_HOME/brief.bak" "$b"
  run dux-spawn "$id" --harness gemini
  [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown worker harness gemini"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

@test "an unavailable backend is a finding and nothing is created" {
  id="$(fixture_task proj scout)"
  DUX_BACKEND=zellij run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown backend zellij"* ]]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

@test "a failed open removes the new worktree, restores the brief, and leaves the task queued" {
  id="$(fixture_task proj scout)"
  run env -u HERDR_WORKSPACE_ID dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: HERDR_WORKSPACE_ID is unset"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  run git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"; [ "$status" -ne 0 ]
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$id/brief.md"
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  [ -z "$(dux-backend find "$id")" ]
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
}

@test "a spawn that died after the container started is not re-spawnable" {
  id="$(fixture_task proj scout)"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  # The container is what this test asks about, so the other signal is settled
  # first: once the wrapper has exited its pidfile names a dead pid and stops
  # deciding the answer. The pidfile's own refusal has its own test.
  wait_result "$id"
  wait_for_workers 30
  # Exactly the disk state a spawn killed between backend open and the endpoint
  # write leaves: a live container, no endpoint file, the ledger still queued.
  rm -f "$DUX_HOME/state/$id.endpoint"
  dux-ledger set "$id" state queued
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a container for $id already exists at herdr:w1:p9"* ]]
  # Putting the placeholder back was the workaround the old refusal invited. The
  # container is what is asked, so the brief cannot talk a second worker into life.
  b="$DUX_HOME/data/tasks/$id/brief.md"
  sed 's#^- Worktree: /.*#- Worktree: <set by dux-spawn>#' "$b" > "$b.tmp" && mv "$b.tmp" "$b"
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$b"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a container for $id already exists at herdr:w1:p9"* ]]
  [ "$(grep -c '^tab create' "$FAKE_HERDR_LOG")" -eq 1 ]
  [ "$(grep -c '^pane run' "$FAKE_HERDR_LOG")" -eq 1 ]
  # And once the container is gone the same task spawns, with no file to delete.
  dux-backend close herdr:w1:p9
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
}

@test "a live wrapper pidfile refuses the spawn even when the backend reports no container" {
  id="$(fixture_task proj scout)"
  pf="$DUX_HOME/state/$id.pid"
  echo $$ > "$pf"
  # The backend has nothing for this task, so the pidfile is the only signal left:
  # a worker started under the other backend, or in a container someone renamed.
  [ -z "$(dux-backend find "$id")" ]
  run dux-spawn "$id"
  # This harness's teardown waits on every pidfile under state/, and this one
  # names a process that outlives the test, so it goes before anything can abort.
  rm -f "$pf"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: worker pid $$ for $id is still running"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  # The probe above logged its own tab list, so count what a spawn would have done.
  [ "$(grep -c '^tab create' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "a pidfile only lets the spawn through when it names a pid that is gone" {
  id="$(fixture_task proj scout)"
  pf="$DUX_HOME/state/$id.pid"
  printf 'not-a-pid\n' > "$pf"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $pf does not hold a pid"* ]]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  [ ! -s "$FAKE_HERDR_LOG" ]
  # A pid that has certainly exited: $() reaps the shell that printed it.
  bash -c 'echo $$' > "$pf"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  wait_result "$id"
}

@test "a spawn that died after the worktree and before the container is spawnable again" {
  id="$(fixture_task proj scout)"
  b="$DUX_HOME/data/tasks/$id/brief.md"
  # Exactly the disk state a spawn killed between dux-worktree create and backend
  # open leaves: the worktree made, the brief's line filled, no container, queued.
  wt="$(dux-worktree create "$id")"
  awk -v to="- Worktree: $wt" '/^- Worktree: / { print to; next } { print }' "$b" > "$b.tmp" && mv "$b.tmp" "$b"
  grep -qxF -- "- Worktree: $wt" "$b"
  [ -z "$(dux-backend find "$id")" ]
  # No file to delete, no status line to fake, no placeholder to restore.
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  # dux-worktree logs that it reused the worktree, so the report is the last line.
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "spawned $id endpoint=herdr:w1:p9 worktree=$wt" ]
  [ "$(dux-ledger get "$id" state)" = running ]
  grep -qxF -- "- Worktree: $wt" "$b"
  wait_result "$id"
}

@test "an open that fails with the container alive refuses to discard the worktree" {
  id="$(fixture_task proj scout)"
  # herdr types into a live shell: pane run can fail after the command went out,
  # and here the cleanup close is refused too, so the pane outlives the failure.
  export FAKE_HERDR_RUN_FAIL=1 FAKE_HERDR_CLOSE_FAIL=1
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: backend open failed for $id but a container for it is alive at herdr:w1:p9"* ]]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ -d "$wt" ]
  [ "$(dux-ledger get "$id" state)" = queued ]
  # The brief is back to the placeholder, so the operator is never blocked by it.
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$id/brief.md"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a container for $id already exists at herdr:w1:p9"* ]]
}

@test "a DUX_ROOT containing a space still starts the worker" {
  id="$(fixture_task proj scout)"
  mkdir -p "$DUX_HOME/dux root"
  ln -s "$DUX_ROOT" "$DUX_HOME/dux root/dux"
  run env DUX_ROOT="$DUX_HOME/dux root/dux" dux-spawn "$id"
  [ "$status" -eq 0 ]
  wait_result "$id"
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  grep -q '^claude ' "$FAKE_WORKER_LOG"
}

@test "a worktree finding propagates and leaves the task queued" {
  id="$(fixture_task proj ship)"
  git -C "$DUX_HOME/proj" branch "dux/$id" origin/main
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id already exists"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
}

@test "success records the endpoint and running, fills the worktree line, and the worker runs" {
  id="$(fixture_task proj scout)"
  run --separate-stderr dux-spawn "$id"
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ "$output" = "spawned $id endpoint=herdr:w1:p9 worktree=$wt" ]
  [ "$(cat "$DUX_HOME/state/$id.endpoint")" = herdr:w1:p9 ]
  [ "$(dux-ledger get "$id" state)" = running ]
  [ "$(dux-ledger get "$id" endpoint)" = herdr:w1:p9 ]
  grep -qxF -- "- Worktree: $wt" "$DUX_HOME/data/tasks/$id/brief.md"
  grep -qF "tab create --workspace w1 --cwd $wt --label dux-$id --no-focus" "$FAKE_HERDR_LOG"
  grep -qxF "pane run w1:p9 $DUX_ROOT/bin/dux-worker-wrap $id" "$FAKE_HERDR_LOG"
  wait_result "$id"
  grep -q '^claude ' "$FAKE_WORKER_LOG"
  [ ! -s "$FAKE_GH_LOG" ]
}

# The refusal sits where the harness is chosen, so all three inputs hit it.
codex_refused() {  # asserts the last `run` refused and started nothing for $id
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: codex workers are not available: no deny list, so git push --no-verify skips the only guard (milestone 2)"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  [ ! -s "$FAKE_HERDR_LOG" ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "codex is refused from the flag, from config, and from the task file" {
  id="$(fixture_task proj scout)"
  run dux-spawn "$id" --harness codex
  codex_refused
  echo codex > "$DUX_HOME/config/worker-harness"
  run dux-spawn "$id"
  codex_refused
  echo claude > "$DUX_HOME/config/worker-harness"
  echo codex > "$DUX_HOME/data/tasks/$id/harness"
  run dux-spawn "$id"
  codex_refused
  # The flag is the choice, so it overrides the task file and the spawn goes ahead.
  run dux-spawn "$id" --harness claude
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/harness")" = claude ]
  wait_result "$id"
  grep -q '^claude ' "$FAKE_WORKER_LOG"
  [ "$(grep -c '^codex ' "$FAKE_WORKER_LOG" || true)" -eq 0 ]
}

@test "a gh source gets one start comment; a failed comment is a warning, not a refusal" {
  make_repo "$DUX_HOME/proj" main
  dux-project add "$DUX_HOME/proj" --base main >/dev/null
  id="$(dux-task-new proj scout --source 'gh:acme/widgets#12')"
  printf 'x\n' > "$DUX_HOME/i"; printf '1. y\n' > "$DUX_HOME/c"
  # A gh-sourced task is never briefed without its issue text beside it.
  printf 'acme/widgets#12: A title\n\nBody\n' > "$DUX_HOME/data/tasks/$id/issue.md"
  dux-brief "$id" --intent-file "$DUX_HOME/i" --criteria-file "$DUX_HOME/c" --issue-file "$DUX_HOME/data/tasks/$id/issue.md" >/dev/null
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  grep -qxF "issue comment 12 --repo acme/widgets --body Dux started on branch \`dux/$id\`." "$FAKE_GH_LOG"
  [ "$(grep -c '^issue comment' "$FAKE_GH_LOG")" -eq 1 ]
  id2="$(dux-task-new proj scout --source 'gh:acme/widgets#13')"
  printf 'acme/widgets#13: A title\n\nBody\n' > "$DUX_HOME/data/tasks/$id2/issue.md"
  dux-brief "$id2" --intent-file "$DUX_HOME/i" --criteria-file "$DUX_HOME/c" --issue-file "$DUX_HOME/data/tasks/$id2/issue.md" >/dev/null
  FAKE_GH_FAIL=1 run dux-spawn "$id2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not comment on gh:acme/widgets#13"* ]]
  [ "$(dux-ledger get "$id2" state)" = running ]
}

# Spawn builds a task path, a branch name and a worktree path from the id.
@test "an id that is not a task id is a finding" {
  run dux-spawn ../../x
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task id must match [A-Za-z0-9._-]+: ../../x"* ]]
}

# The open starts the worker, and a worker that refuses at once leaves a proved
# terminal handoff the watcher can apply before spawn writes running. The hook
# stands in for that watcher: it settles the task while the container is
# opening. Spawn asks for the change from queued, so the proved state wins.
@test "a result proved while the container opens is not put back to running" {
  id="$(fixture_task proj scout)"
  export FAKE_HERDR_RUN_HOOK="dux-ledger set $id state failed"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: task $id has state=failed, not queued; refusing to set it to running"* ]]
  [ "$(dux-ledger get "$id" state)" = failed ]
  # The endpoint is recorded either way: the container is open and the worker
  # in it is this spawn's, whatever the ledger now says about the task.
  [ "$(dux-ledger get "$id" endpoint)" = herdr:w1:p9 ]
}
