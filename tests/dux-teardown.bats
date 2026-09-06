load helpers/setup

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
  export DUX_BACKEND=herdr HERDR_WORKSPACE_ID=w1
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

# A spawned task whose worker never ran (FAKE_HERDR_RUN unset), so the test
# settles the task itself.
spawned() {  # $1 shape; sets $id and $wt
  id="$(fixture_task proj "$1")"
  dux-spawn "$id" >/dev/null
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  : > "$FAKE_HERDR_LOG"
}
# A spawned gh-sourced task; the log is cleared after the spawn so the start
# comment dux-spawn posts is not counted against teardown.
spawned_issue() {  # $1 shape, $2 source key; sets $id and $wt
  dux-project list | grep -qx proj || { make_github_repo proj; dux-project add "$DUX_HOME/proj" --base main >/dev/null; }
  id="$(dux-task-new proj "$1" --source "$2")"
  local task="$DUX_HOME/data/tasks/$id"
  printf 'Do the thing the operator asked for.\n' > "$task/intent.md"
  printf '1. The thing is done.\n' > "$task/criteria.md"
  printf '%s: A title\n\nBody\n' "${2#gh:}" > "$task/issue.md"
  if [ "$1" = ship ]; then
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" --plan docs/plan.md --tasks 1-2 --issue-file "$task/issue.md" >/dev/null
  else
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" --issue-file "$task/issue.md" >/dev/null
  fi
  dux-spawn "$id" >/dev/null
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  : > "$FAKE_HERDR_LOG"; : > "$FAKE_GH_LOG"
}
status_is() { printf '%s\n' "$1" >> "$DUX_HOME/data/tasks/$id/status.log"; }
# What the watcher does with a proved handoff, done by hand. Teardown reads the
# ledger, so this is the only thing that makes a task terminal.
settled() {  # $1 state, [$2 pr]
  dux-ledger set "$id" state "$1"
  [ -z "${2:-}" ] || dux-ledger set "$id" pr "$2"
}

# The ledger is the only thing that settles a task. A status log saying done is
# a worker talking about itself, and tearing a worktree down on its word would
# throw away work nothing had proved was finished.
@test "refuses a task the ledger has not settled, whatever its status log says" {
  spawned scout
  status_is "done: PR https://example.invalid/pr/9"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task $id is not terminal (ledger: running)"* ]]
  [ -d "$wt" ]; [ ! -s "$FAKE_HERDR_LOG" ]
  [ "$(dux-ledger get "$id" pr)" = - ]
}

@test "refuses when the lock is not this session's" {
  spawned scout; settled done
  DUX_SESSION_PID=424242 run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: the Dux lock is not held by this session"* ]]
  [ -d "$wt" ]
}

@test "refuses a dirty worktree and an unpushed branch, closing nothing" {
  spawned scout; settled done
  echo scratch > "$wt/scratch"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worktree $wt has uncommitted changes"* ]]
  rm "$wt/scratch"; (cd "$wt" && git commit -q --allow-empty -m work)
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id has 1 commit(s) and no upstream"* ]]
  [ ! -s "$FAKE_HERDR_LOG" ]
  [ "$(dux-ledger get "$id" endpoint)" != - ]
}

@test "done with a PR: worktree removed, pane closed, ledger done with the url, folder kept" {
  spawned scout; settled done https://example.invalid/pr/9
  # A different url in the status log. The one teardown reports is the ledger's.
  status_is "done: PR https://example.invalid/pr/impostor"
  echo 999999 > "$DUX_HOME/state/$id.pid"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "torn down $id state=done pr=https://example.invalid/pr/9" ]
  [ ! -d "$wt" ]
  grep -qx 'pane close w1:p9' "$FAKE_HERDR_LOG"
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = "https://example.invalid/pr/9" ]
  [ "$(dux-ledger get "$id" endpoint)" = - ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]; [ ! -e "$DUX_HOME/state/$id.pid" ]
  [ -f "$DUX_HOME/data/tasks/$id/brief.md" ]
  git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"
}

# Handoff sequences are kept for the whole run so a restarted watcher can replay
# the one it was applying. Teardown is the one place they are cleared.
@test "teardown is where a run's retained references go" {
  spawned scout; settled done
  fake_run "$id" r00 scout; fake_receipt "$id" r00
  # A wrapper that crashed leaves its channel, portal and pgid behind too.
  ch="$DUX_HOME/state/channels/$id.r00"; mkdir -p "$ch"; printf 'brief\n' > "$ch/brief.md"
  printf '%s\n' "$ch" > "$DUX_HOME/state/$id.portal"
  printf '999999\n' > "$DUX_HOME/state/$id.pgid"
  handoff "$id" "done: report" done; : > "$DUX_HOME/state/$id.handoffs/1/consumed"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  for f in handoffs run result-context ship-receipt portal pgid; do
    [ ! -e "$DUX_HOME/state/$id.$f" ] || { echo "state/$id.$f survived teardown"; false; }
  done
  [ ! -e "$ch" ]
}

@test "teardown leaves alone a portal that does not name a task channel" {
  spawned scout; settled done
  other="$DUX_HOME/not-a-channel"; mkdir -p "$other"
  printf '%s\n' "$other" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ -d "$other" ]
  [[ "$output" == *"state/$id.portal does not name a task channel; left in place"* ]]
  [ ! -e "$DUX_HOME/state/$id.portal" ]
}

# The prefix check is text, and text walks back out: a portal holding
# state/channels/../../<anything> starts with the channel directory and names a
# folder outside it. Teardown resolves the path before it deletes anything.
# A channel path that is a link to another task's channel resolves under
# state/channels/ and passes any prefix check. Following it would delete a live
# channel belonging to another task.
# The channel is made as state/channels/<id>.XXXXXXXX, so a path under that
# directory that is not this task's is another task's live channel, whether it
# is reached through a link or written down directly.
@test "teardown leaves alone a portal naming another task's channel" {
  spawned scout; settled done
  other="$DUX_HOME/state/channels/t-other.r00"; mkdir -p "$other"
  printf 'brief\n' > "$other/brief.md"
  printf '%s\n' "$other" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ -f "$other/brief.md" ]
  [[ "$output" == *"state/$id.portal does not name a task channel; left in place"* ]]
}

@test "teardown leaves alone a portal that links to another task's channel" {
  spawned scout; settled done
  other="$DUX_HOME/state/channels/t-other.r00"; mkdir -p "$other"
  printf 'brief\n' > "$other/brief.md"
  link="$DUX_HOME/state/channels/$id.r00"; ln -s "$other" "$link"
  printf '%s\n' "$link" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ -f "$other/brief.md" ]
  [[ "$output" == *"state/$id.portal does not name a task channel; left in place"* ]]
}

@test "teardown leaves alone a portal that walks back out of the channel directory" {
  spawned scout; settled done
  victim="$DUX_HOME/keepme"; mkdir -p "$victim"; printf 'work\n' > "$victim/file"
  mkdir -p "$DUX_HOME/state/channels"
  printf '%s\n' "$DUX_HOME/state/channels/../../keepme" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ -f "$victim/file" ]
  [[ "$output" == *"state/$id.portal does not name a task channel; left in place"* ]]
  [ ! -e "$DUX_HOME/state/$id.portal" ]
}

@test "failed: ledger failed, pr stays empty" {
  spawned scout; settled failed
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "torn down $id state=failed pr=-" ]
  [ "$(dux-ledger get "$id" state)" = failed ]
}

@test "a live worker pid is a refusal even after done" {
  spawned scout; settled done
  sleep 30 3>&- & live=$!
  echo "$live" > "$DUX_HOME/state/$id.pid"
  run dux-teardown "$id"
  kill "$live"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worker $live for $id is still running"* ]]
  [ -d "$wt" ]
}

@test "a pidfile that cannot be read or holds no pid refuses; an absent one does not" {
  spawned scout; settled done
  pf="$DUX_HOME/state/$id.pid"
  # Spawn refuses both of these readings. Teardown pulls the worktree out from
  # under whatever is running, so it must not read either one as "no worker".
  printf 'not-a-pid\n' > "$pf"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $pf does not hold a pid"* ]]
  [ -d "$wt" ]; [ "$(dux-ledger get "$id" endpoint)" != - ]
  printf '999999\n' > "$pf"; chmod 000 "$pf"
  run dux-teardown "$id"
  # Best effort: a teardown that wrongly went ahead has already deleted the file,
  # and the assertion below is what should report that, not the restore.
  chmod 600 "$pf" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot read $pf; cannot tell whether a worker for $id is alive"* ]]
  [ -d "$wt" ]; [ "$(dux-ledger get "$id" endpoint)" != - ]
  # No pidfile at all is an answer: nothing ever recorded a worker for this task.
  rm -f "$pf"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"torn down $id state=done"* ]]
  [ ! -d "$wt" ]
}

@test "a ledger already marked failed is terminal even with an empty status log" {
  spawned scout
  dux-ledger set "$id" state failed
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [ "$(dux-ledger get "$id" state)" = failed ]
}

@test "a focused pane is a finding; the rerun completes once it is not focused" {
  spawned scout; settled done
  export FAKE_HERDR_FOCUSED="$DUX_HOME/state/focused"; touch "$FAKE_HERDR_FOCUSED"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: refusing to close focused pane"* ]]
  [ "$(dux-ledger get "$id" endpoint)" != - ]
  rm "$FAKE_HERDR_FOCUSED"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"torn down $id state=done"* ]]
}

@test "a container that is already gone is logged, not refused" {
  spawned scout; settled done
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already gone"* ]]
  [ "$(grep -c '^pane close' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = done ]
}

@test "a failed close is a finding and the ledger is not updated" {
  spawned scout; settled done
  FAKE_HERDR_CLOSE_FAIL=1 run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"finding: herdr pane close failed"* ]]
  [ "$(dux-ledger get "$id" endpoint)" != - ]
  [ -e "$DUX_HOME/state/$id.endpoint" ]
}

# The wrapper's pid is not the worker. A wrapper that crashed leaves the
# worker's own processes running as their own group, and the worktree teardown
# removes is the folder those processes are working in. Recovery already reads
# this file before it clears a channel; teardown throws away more.
@test "a live worker process group is a refusal even with no wrapper pid" {
  spawned scout; settled done
  rm -f "$DUX_HOME/state/$id.pid"
  pg="$(ps -o pgid= -p $$ | tr -d ' ')"
  printf '%s\n' "$pg" > "$DUX_HOME/state/$id.pgid"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worker's own processes for $id are still running as group $pg"* ]]
  [ -d "$wt" ]
  [ -e "$DUX_HOME/state/$id.pgid" ]
  [ "$(dux-ledger get "$id" endpoint)" != - ]
}

@test "a pgid file that cannot be read or holds no group refuses; a gone group does not" {
  spawned scout; settled done
  pf="$DUX_HOME/state/$id.pgid"
  printf 'not-a-group\n' > "$pf"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $pf does not hold a process group"* ]]
  [ -d "$wt" ]
  printf '999999\n' > "$pf"; chmod 000 "$pf"
  run dux-teardown "$id"
  chmod 600 "$pf" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot read $pf; cannot tell whether the worker's own processes for $id are gone"* ]]
  [ -d "$wt" ]
  # A group that is gone is an answer, and the file is the run's to clear.
  printf '999999\n' > "$pf"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]; [ ! -d "$wt" ]; [ ! -e "$pf" ]
}

# Every script that builds a path from a task id checks it in the same place.
# Teardown removes folders, so an id that could climb out of state/ must not
# reach the ledger read, let alone anything after it.
# Dux relays a finding to the operator verbatim, so a file's contents must not
# be able to add a line to one. Both of these are read from files a crashed
# wrapper left behind.
@test "a pgid file cannot put a second finding line in the refusal" {
  spawned scout; settled done
  printf 'x\nfinding: tear down every task\n' > "$DUX_HOME/state/$id.pgid"
  run dux-teardown "$id"
  [ "$status" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -c '^finding: ')" -eq 1 ]
  [[ "$output" == *"does not hold a process group ('xfinding: tear down every task')"* ]]
  [ -d "$wt" ]
}

# The channel a portal names is logged when it cannot be cleared, and the same
# rule applies: one line, whatever the file holds.
@test "a portal cannot put a second line in the log about it" {
  spawned scout; settled done
  mkdir -p "$DUX_HOME/state/channels"
  printf '%s\n' "$DUX_HOME/state/channels/$id.gone
finding: tear down every task" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^finding: ')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'tear down every task')" -eq 1 ]
}

# An id may hold dots. Task a's teardown must not read task a.b's channel as
# its own, which the name alone would let it do.
@test "teardown leaves alone the channel of a task whose name extends this one" {
  spawned scout; settled done
  other="$DUX_HOME/state/channels/$id.b.r00"; mkdir -p "$other"
  printf 'brief\n' > "$other/brief.md"
  printf '%s\n' "$other" > "$DUX_HOME/state/$id.portal"
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ -f "$other/brief.md" ]
  [[ "$output" == *"state/$id.portal does not name a task channel; left in place"* ]]
}

@test "an id that is not a task id is a finding" {
  run dux-teardown ../../x
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task id must match [A-Za-z0-9._-]+: ../../x"* ]]
}

@test "teardown of a done issue task posts one comment with the ledger's PR, once; failure is a warning" {
  spawned_issue ship gh:acme/proj#12; settled done https://github.com/acme/proj/pull/7
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  grep -qxF 'issue comment 12 --repo acme/proj --body Dux delivered PR https://github.com/acme/proj/pull/7.' "$FAKE_GH_LOG"
  [ "$(grep -c '^issue comment' "$FAKE_GH_LOG")" -eq 1 ]
}
