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
  # Spawn refuses to open a tab in a directory Claude Code has not been told to
  # trust, so every test that expects a start needs a trusted one, and the fake
  # harness has to carry the name the adapter looks for.
  trust_suite_root proj other
  harness_shim
  export DUX_SPAWN_START_SECS=20
  dux-lock acquire >/dev/null
}

# The trusted fixture is shared (helpers/setup). This file also needs the two
# other readings: some other path trusted, and a file that trusts nothing.
trust_home() {  # [$1 path to trust]
  CLAUDE_CONFIG_DIR="$DUX_HOME/claude-config"; export CLAUDE_CONFIG_DIR
  mkdir -p "$CLAUDE_CONFIG_DIR"
  if [ -n "${1:-}" ]; then
    jq -n --arg p "$1" '{ projects: { ($p): { hasTrustDialogAccepted: true } } }' \
      > "$CLAUDE_CONFIG_DIR/.claude.json"
  else
    echo '{"projects":{}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  fi
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
  # And once the container is gone the same task spawns. The first run's own
  # references go with it, the way teardown and recovery clear them: a wrapper
  # refuses a second run that still has the first one's, and that refusal is
  # about the run, not about the container this test is asking after.
  dux-backend close herdr:w1:p9
  rm -rf "$DUX_HOME/state/$id".run "$DUX_HOME/state/$id".pgid \
    "$DUX_HOME/state/$id".result-context "$DUX_HOME/state/$id".handoffs
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
  # herdr opens the tab and then waits for its shell prompt; a pane that never
  # draws one fails the open, and here the cleanup close is refused too, so the
  # pane outlives the failure.
  export FAKE_HERDR_NO_PROMPT=1 FAKE_HERDR_CLOSE_FAIL=1
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
  # The pane runs the launcher the wrapper staged, and the wrapper itself is a
  # process of Dux's own, not the pane's.
  # Quoted: the pane's shell reads this line, and a DUX_HOME with a space in it
  # would otherwise arrive as a command and an argument.
  grep -qE "^pane run w1:p9 '$DUX_HOME/state/channels/$id\\.[A-Za-z0-9]+/launch'$" "$FAKE_HERDR_LOG"
  [ "$(grep -c "dux-worker-wrap" "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  # Alive after spawn returned, and in a process group of its own: a wrapper
  # sharing Dux's group would take every signal the operator sends Dux.
  wpid="$(cat "$DUX_HOME/state/$id.pid")"
  pid_runs "$wpid" "dux-worker-wrap $id"
  [ "$(ps -o pgid= -p "$wpid" | tr -d " ")" != "$(ps -o pgid= -p $$ | tr -d " ")" ]
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
  dux-project add "$DUX_HOME/proj" --base main --pr-template skip >/dev/null
  id="$(dux-task-new proj scout --source 'gh:acme/widgets#12')"
  printf 'x\n' > "$DUX_HOME/i"; printf '1. y\n' > "$DUX_HOME/c"
  # A gh-sourced task is never briefed without its issue text beside it.
  printf 'acme/widgets#12: A title\n\nBody\n' > "$DUX_HOME/data/tasks/$id/issue.md"
  dux-brief "$id" --intent-file "$DUX_HOME/i" --criteria-file "$DUX_HOME/c" --issue-file "$DUX_HOME/data/tasks/$id/issue.md" >/dev/null
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  grep -qxF "issue comment 12 --repo acme/widgets --body Dux started on branch \`dux/$id\`." "$FAKE_GH_LOG"
  [ "$(grep -c '^issue comment' "$FAKE_GH_LOG")" -eq 1 ]
  # The first still counts as running, which the limit of 3 allows. It has to
  # have finished all the same: the fake Herdr holds one live worker at a time.
  wait_result "$id"
  wait_for_workers 30
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

# ---- the wrapper starts outside the tab ------------------------------------
# It is Dux's own process now, not the pane's, so spawn has to watch it start
# and say which of the two ways it failed when it did not.

@test "a wrapper that exits before its run record leaves nothing behind" {
  id="$(fixture_task proj scout)"
  # The pidfile first, because the real wrapper writes it before it opens its
  # run record: what spawn has to read is a pidfile naming a pid that is gone,
  # not the absence of one.
  r="$(root_with_stub dux-worker-wrap '#!/bin/sh
echo $$ > "$DUX_HOME/state/$1.pid"
echo "finding: no." >&2
exit 2')"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the wrapper for $id did not start; see $DUX_HOME/state/$id.wrap.log"* ]]
  # What the wrapper printed is in its log, and only there.
  grep -qF 'finding: no.' "$DUX_HOME/state/$id.wrap.log"
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  [ "$(dux-ledger get "$id" endpoint)" = - ]
  [ -z "$(dux-backend find "$id")" ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$id/brief.md"
  # And the task spawns again with nothing to clear by hand.
  rm -f "$DUX_HOME/state/$id.pid"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  wait_result "$id"
}

# The other half of that ending: a wrapper spawn cannot stop.
@test "a wrapper that will not stop keeps the tab, the endpoint and the worktree" {
  id="$(fixture_task proj scout)"
  # It ignores the signal and never writes a pidfile, so spawn has nothing that
  # says it stopped. Undoing under it would close the tab it is about to run in
  # and discard the worktree it is about to work in.
  r="$(root_with_stub dux-worker-wrap '#!/bin/sh
trap "" TERM
echo $$ > "$DUX_HOME/state/stubborn.pid"
sleep 60')"
  run env DUX_ROOT="$r" DUX_SPAWN_START_SECS=1 "$r/bin/dux-spawn" "$id"
  stub="$(cat "$DUX_HOME/state/stubborn.pid" 2>/dev/null)"
  [ -n "$stub" ] && kill -9 "$stub" 2>/dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the wrapper for $id did not start and pid "*" will not stop; stop it, then run dux-recover $id"* ]]
  # Every reference spawn made is still there, for recovery to read.
  [ "$(cat "$DUX_HOME/state/$id.endpoint")" = herdr:w1:p9 ]
  [ "$(dux-ledger get "$id" endpoint)" = herdr:w1:p9 ]
  [ -n "$(dux-backend find "$id")" ]
  [ -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  grep -qxF -- "- Worktree: $DUX_HOME/proj/.worktrees/dux-$id" "$DUX_HOME/data/tasks/$id/brief.md"
  [ "$(dux-ledger get "$id" state)" = queued ]
}

# A refusal made after the wrapper opened its run record is a proved result, so
# spawn touches nothing: the handoff is the watcher's to apply, and the worktree
# and the tab are what recovery reads. The stub stands in for a wrapper that got
# that far, because the real one writes its pidfile before its run record, and
# spawn reads a live pidfile as a start whatever happens next.
@test "a wrapper that refuses after its run record keeps the worktree and the tab" {
  id="$(fixture_task proj scout)"
  r="$(root_with_stub dux-worker-wrap "#!/bin/sh
d=\"\$DUX_HOME/state/\$1.handoffs/1\"
mkdir -p \"\$d\"
echo run1 > \"\$d/run\"
echo 'failed: wrapper: no worker settings' > \"\$d/status\"
echo failed > \"\$d/event\"
exit 2")"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the wrapper for $id refused before the harness started; see $DUX_HOME/state/$id.wrap.log"* ]]
  # Not running: the handoff is what the watcher turns into failed.
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/event")" = failed ]
  # Kept: both are evidence, and recovery is what clears them.
  [ -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ "$(cat "$DUX_HOME/state/$id.endpoint")" = herdr:w1:p9 ]
  [ -n "$(dux-backend find "$id")" ]
  grep -qxF -- "- Worktree: $DUX_HOME/proj/.worktrees/dux-$id" "$DUX_HOME/data/tasks/$id/brief.md"
}

# The real wrapper's own early refusal, to show the two endings are told apart by
# the handoff and not by which wrapper ran. Its settings are checked before it
# writes its pidfile, so this one leaves no handoff and spawn undoes.
@test "the real wrapper refusing before its run record is undone, not left half open" {
  id="$(fixture_task proj scout)"
  rm -f "$DUX_HOME/data/tasks/$id/worker-settings.json"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the wrapper for $id did not start; see $DUX_HOME/state/$id.wrap.log"* ]]
  grep -qF "no worker settings for $id" "$DUX_HOME/state/$id.wrap.log"
  [ ! -d "$DUX_HOME/state/$id.handoffs" ]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  [ -z "$(dux-backend find "$id")" ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
}

# Spawn looks for the wrapper once a second. A worker that finishes at once makes
# a run of about two seconds, and on a busy machine that run can start and end
# between two looks. The pause holds off the first look until it has, every
# time. The ending it published says it started, so the task is running and the
# watcher applies the ending as for any run.
@test "a run that starts and ends between two looks is spawned, not refused" {
  id="$(fixture_task proj scout)"
  run --separate-stderr env DUX_SPAWN_LOOK_PAUSE_SECS=5 dux-spawn "$id"
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  [ "$status" -eq 0 ]
  [ "$output" = "spawned $id endpoint=herdr:w1:p9 worktree=$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ "$(dux-ledger get "$id" state)" = running ]
  wait_result "$id"
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/status")" = "done: report" ]
}

# The same pause with a wrapper that got as far as its run record and refused:
# it wrote its pidfile, as the real one does first, published the refusal and
# was gone before the first look. That is still a refusal.
@test "a refusal published between two looks is still a refusal" {
  id="$(fixture_task proj scout)"
  r="$(root_with_stub dux-worker-wrap '#!/bin/sh
echo $$ > "$DUX_HOME/state/$1.pid"
d="$DUX_HOME/state/$1.handoffs/1"
mkdir -p "$d"; echo run1 > "$d/run"; echo failed > "$d/event"
echo "failed: wrapper: cannot start the worker for $1 in its tab" > "$d/status"
exit 2')"
  run env DUX_ROOT="$r" DUX_SPAWN_LOOK_PAUSE_SECS=5 "$r/bin/dux-spawn" "$id"
  if [ "$status" -ne 2 ]; then echo "expected a refusal, got $status: '$output'"; return 1; fi
  [[ "$output" == *"finding: the wrapper for $id refused before the harness started; see $DUX_HOME/state/$id.wrap.log"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
}

# A run spawn stopped itself is never reported as spawned, whatever it published.
# With no window at all, spawn signals a wrapper it has not seen start; the pause
# gives the stub time to set its trap first. On the signal the stub publishes an
# ending that is no refusal, and exits.
@test "a run spawn stopped itself is not spawned, whatever it published" {
  id="$(fixture_task proj scout)"
  r="$(root_with_stub dux-worker-wrap '#!/bin/sh
d="$DUX_HOME/state/$1.handoffs/1"
ended() {
  mkdir -p "$d"; echo run1 > "$d/run"; echo ended > "$d/event"
  echo "ended: the session ended without a terminal status" > "$d/status"
  kill "$s"; exit 0
}
trap ended TERM
sleep 30 & s=$!
wait "$s"')"
  run env DUX_ROOT="$r" DUX_SPAWN_START_SECS=0 DUX_SPAWN_LOOK_PAUSE_SECS=2 "$r/bin/dux-spawn" "$id"
  if [ "$status" -ne 2 ]; then echo "expected a refusal, got $status: '$output'"; return 1; fi
  [[ "$output" == *"finding: the wrapper for $id refused before the harness started; see $DUX_HOME/state/$id.wrap.log"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/status")" = "ended: the session ended without a terminal status" ]
}

@test "a worktree Claude Code does not trust is refused before any tab opens" {
  id="$(fixture_task proj scout)"
  trust_home
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: $DUX_HOME/proj is not trusted by Claude Code; open a session in it once and answer \"Yes, I trust this folder\"" ]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ "$(grep -c '^tab create' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$id/brief.md"
  # A config file that is not there, and one that does not parse, read the same.
  rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not trusted by Claude Code"* ]]
  printf 'not json' > "$CLAUDE_CONFIG_DIR/.claude.json"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not trusted by Claude Code"* ]]
  # A trusted folder above the repository is not the repository. Measured on
  # Claude Code 2.1.271, 2026-09-15: a fresh repository under a trusted parent
  # still raises the dialog, so a spawn that took the parent for an answer
  # would leave the worker sitting at it.
  trust_home "$DUX_HOME"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not trusted by Claude Code"* ]]
  [ "$(grep -c '^tab create' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  # Trusting the repository is enough: the worktree is one of its worktrees, and
  # Claude Code resolves a worktree to the repository it was made from.
  trust_home "$DUX_HOME/proj"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  wait_result "$id"
}

# ---- the worker limit ---------------------------------------------------------
# A start is refused once the ledger holds as many running or stale tasks as
# config/max-workers allows (spec section 5.7). The limit is a spending brake,
# not what keeps workers apart: each task has its own worktree, branch, tab and
# state files at any count, so nothing another task leaves behind is read.

# A process whose command line names another task's wrapper, which is what a
# live worker looks like. $$ would not do: pid_runs asks what the pid is
# running, not merely that something is.
live_wrapper_for() {  # $1 id; prints the pid
  local p; p="$(stand_in "dux-worker-wrap $1")"
  echo "$p" > "$DUX_HOME/state/$1.pid"
  echo "$p"
}

other_task() {  # $1 name, $2 ledger state; a row and nothing else
  dux-ledger add "$1-scout-20260918-aaa" proj scout local
  dux-ledger set "$1-scout-20260918-aaa" state "$2"
}

counts() {  # the tab creations and worker starts so far
  printf '%s %s' "$(grep -c '^tab create' "$FAKE_HERDR_LOG")" "$(wc -l < "$FAKE_WORKER_LOG" | tr -d ' ')"
}

# Refused before anything was made: still queued, no worktree, no branch, the
# brief as it was, no endpoint, and no tab opened or worker started since.
untouched() {  # $1 id, $2 counts before the spawn
  [ "$(dux-ledger get "$1" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$1" ]
  run git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$1"; [ "$status" -ne 0 ]
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$1/brief.md"
  [ ! -e "$DUX_HOME/state/$1.endpoint" ]
  [ "$(counts)" = "$2" ]
}

@test "with the limit at 3 a third start goes through and a fourth is refused, creating nothing" {
  [ "$(first_value "$DUX_HOME/config/max-workers")" = 3 ]
  other_task o1 running
  other_task o2 stale
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"; wait_for_workers 30
  # Nothing here applies b's result, so the ledger still counts it as running.
  c="$(fixture_task proj ship)"
  before="$(counts)"
  run dux-spawn "$c"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: 3 Dux workers are running and the limit is 3 (config/max-workers); $c remains queued" ]
  untouched "$c" "$before"
}

# A running task counts whatever else is true of it, its container included,
# and a task that settles stops counting.
@test "with the limit at 1 a second start is refused, and goes through once the other settles" {
  printf '1\n' > "$DUX_HOME/config/max-workers"
  other_task a running
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: 1 Dux workers are running and the limit is 1 (config/max-workers); $b remains queued" ]
  untouched "$b" "0 0"
  dux-ledger set a-scout-20260918-aaa state done
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

# A parked session is idle at its prompt. Once the watcher has applied its
# result the ledger reads done and it does not count; while its handoff is
# pending the ledger still reads running, and it does.
@test "a parked task does not count once its result is applied, and does before" {
  printf '1\n' > "$DUX_HOME/config/max-workers"
  a="$(fixture_task proj scout)"
  run dux-spawn "$a"
  [ "$status" -eq 0 ]
  wait_result "$a"; wait_for_workers 30
  p="$(stand_in "dux-worker-wrap $a")"; g="$(ps -o pgid= -p $$ | tr -d ' ')"
  echo "$p" > "$DUX_HOME/state/$a.pid"; echo "$g" > "$DUX_HOME/state/$a.pgid"
  printf 'run=%s\nwrapper=%s\npgid=%s\n' "$(sed -n 's/^run=//p' "$DUX_HOME/state/$a.run")" "$p" "$g" \
    > "$DUX_HOME/state/$a.parked"
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: 1 Dux workers are running and the limit is 1 (config/max-workers); $b remains queued" ]
  dux-ledger set "$a" state done
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

# These used to refuse every start: a pidfile or group file nobody can read,
# and a live wrapper or group, on another task. They are not read at all now.
@test "another task's unreadable or live evidence no longer refuses a start" {
  a="$(fixture_task proj scout)"; dux-ledger set "$a" state running
  printf 'not-a-pid\n' > "$DUX_HOME/state/$a.pid"
  printf 'x\n' > "$DUX_HOME/state/$a.pgid"
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"; wait_for_workers 30
  live_wrapper_for "$a" >/dev/null
  ps -o pgid= -p $$ | tr -d ' ' > "$DUX_HOME/state/$a.pgid"
  c="$(fixture_task proj ship)"
  run dux-spawn "$c"
  [ "$status" -eq 0 ]
  wait_result "$c"
}

# Nor is another task asked about: a ledger or a backend that will not answer
# about it used to refuse the start, and the start never asks them now.
@test "a ledger or backend that cannot answer about another task no longer refuses a start" {
  a="$(fixture_task proj scout)"; dux-ledger set "$a" state running
  b="$(fixture_task proj ship)"
  r="$(root_with_stub dux-backend "#!/usr/bin/env bash
if [ \"\$1\" = find ] && [ \"\$2\" = $a ]; then echo 'finding: the backend is unavailable' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-backend \"\$@\"")"
  printf '%s\n' "#!/usr/bin/env bash
if [ \"\$1\" = get ] && [ \"\$2\" = $a ]; then echo 'finding: cannot read the ledger' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-ledger \"\$@\"" > "$r/bin/dux-ledger"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

@test "a limit file that is not a usable number refuses the start, and so does no limit at all" {
  b="$(fixture_task proj ship)"
  printf '3x\n' > "$DUX_HOME/config/max-workers"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: config/max-workers must be a whole number from 1 to 99, not '3x'; $b remains queued" ]
  untouched "$b" "0 0"
  rm -f "$DUX_HOME/config/max-workers"
  r="$DUX_HOME/root-nolimit"; mkdir -p "$r"
  cp -R "$DUX_ROOT/bin" "$r/bin"; cp -R "$DUX_ROOT/templates" "$r/templates"
  rm -f "$r/templates/config/max-workers"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: no worker limit in config/max-workers or templates/config/max-workers; $b remains queued" ]
  untouched "$b" "0 0"
}

@test "a ledger that cannot list the tasks refuses the start" {
  b="$(fixture_task proj ship)"
  r="$(root_with_stub dux-ledger "#!/usr/bin/env bash
if [ \"\$1\" = list ]; then echo 'finding: cannot read the ledger' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-ledger \"\$@\"")"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: cannot count the running Dux workers: the ledger did not answer; $b remains queued" ]
  untouched "$b" "0 0"
}

@test "a settled task's leftover container does not block a new start" {
  a="$(fixture_task proj scout)"
  run dux-spawn "$a"
  [ "$status" -eq 0 ]
  wait_result "$a"
  wait_for_workers 30
  # Done, not torn down: the pane is still there and the pidfile names a pid
  # that is gone. Nothing is running, so nothing may be refused.
  dux-ledger set "$a" state done
  [ -n "$(dux-backend find "$a")" ]
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

# ---- a task that waits on another ----------------------------------------------
still_queued() {  # $1 the finding, after "finding: "; the record is left as it was
  local before
  before="$(cat "$DUX_HOME/data/tasks/$id/prerequisite" 2>/dev/null || echo none)"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: $1; $id remains queued" ]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/prerequisite" 2>/dev/null || echo none)" = "$before" ]
  # A start that stopped at the trust check made a worktree and took it away again.
  [ -z "$(ls -A "$DUX_HOME/other/.worktrees" 2>/dev/null)$(ls -A "$DUX_HOME/proj/.worktrees" 2>/dev/null)" ]
  [ "$(grep -c '^tab create' "$FAKE_HERDR_LOG")" = 0 ]
}

@test "a task that waits on another starts once that delivery merged and is on the fetched base, and keeps what was verified" {
  delivered
  waiting
  ! git -C "$DUX_HOME/proj" merge-base --is-ancestor "$merge" refs/remotes/origin/main
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = running ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/prerequisite")" = "$(printf 'after=%s\nrepo=acme/proj\npr=%s\nhead=%s\nmerge=%s' "$pred" "$pr" "$head" "$merge")" ]
  git -C "$DUX_HOME/proj" merge-base --is-ancestor "$merge" refs/remotes/origin/main
  grep -qx "pr view 7 --repo acme/proj --json state,baseRefName,headRefName,headRefOid,mergeCommit" "$FAKE_GH_LOG"
  wait_result "$id"
}

@test "a task waits while the task before it has not delivered, delivered nothing, or its pull request is not merged" {
  delivered
  waiting
  dux-ledger set "$pred" state running
  still_queued "$id waits on $pred, which is running and has not delivered yet"
  for st in failed ended dropped; do
    dux-ledger set "$pred" state "$st"
    still_queued "$id waits on $pred, which is $st and delivered nothing"
  done
  dux-ledger set "$pred" state done
  FAKE_GH_PR_STATE=OPEN still_queued "$id waits on $pred, whose pull request $pr is still open"
  FAKE_GH_PR_STATE=CLOSED still_queued "$id waits on $pred, whose pull request $pr was closed without merging"
}

@test "a task waits while the merge it needs went somewhere other than the registered base, branch and commit" {
  delivered
  waiting
  FAKE_GH_PR_BASE=develop still_queued "pull request $pr merged into develop, not main, the base registered for proj"
  FAKE_GH_PR_HEAD=elsewhere still_queued "pull request $pr was merged from elsewhere, not dux/$pred"
  FAKE_GH_PR_HEAD_OID="$merge" still_queued "the head GitHub merged for $pr is not the commit Dux proved for $pred"
  dux-ledger set "$pred" pr https://github.com/acme/other/pull/7
  echo "done: PR https://github.com/acme/other/pull/7" > "$DUX_HOME/state/$pred.handoffs/1/status"
  still_queued "$id waits on $pred, whose pull request https://github.com/acme/other/pull/7 is not in acme/proj"
  git -C "$DUX_HOME/proj" remote set-url origin "$DUX_HOME/acme/proj.git"
  still_queued "proj is not a GitHub repository, so the merge $id waits on cannot be verified"
}

@test "a task waits while the delivery it needs cannot be verified" {
  delivered
  waiting
  s="$DUX_HOME/state"; h="$s/$pred.handoffs/1"
  mv "$s/$pred.ship-receipt.delivered" "$s/kept"
  still_queued "$id waits on $pred, which has no /ship receipt for the run that delivered it"
  sed 's/^run=r1$/run=r0/' "$s/kept" > "$s/$pred.ship-receipt"
  still_queued "$id waits on $pred, which has no /ship receipt for the run that delivered it"
  rm "$s/$pred.ship-receipt"; mv "$s/kept" "$s/$pred.ship-receipt.delivered"
  mv "$s/$pred.run" "$s/kept"
  still_queued "$id waits on $pred, and the record of the run that delivered it is gone"
  mv "$s/kept" "$s/$pred.run"
  rm "$h/consumed"
  still_queued "$id waits on $pred, and no proved delivery of $pr is on record"
  : > "$h/consumed"
  echo r0 > "$h/run"
  still_queued "$id waits on $pred, and no proved delivery of $pr is on record"
  echo r1 > "$h/run"
  dux-ledger set "$pred" pr https://github.com/acme/proj/pull/8
  still_queued "$id waits on $pred, and no proved delivery of https://github.com/acme/proj/pull/8 is on record"
  dux-ledger set "$pred" pr "$pr"
  FAKE_GH_PR_STATE=DRAFT still_queued "GitHub did not say whether pull request $pr merged"
  FAKE_GH_FAIL=1 still_queued "GitHub did not say whether pull request $pr merged"
  FAKE_GH_PR_MERGE=main still_queued "GitHub named no merge commit for pull request $pr"
  FAKE_GH_PR_MERGE= still_queued "GitHub named no merge commit for pull request $pr"
  FAKE_GH_PR_MERGE=0123456789abcdef0123456789abcdef01234567 \
    still_queued "the merge of $pr is not on origin/main as fetched in $DUX_HOME/proj"
  mv "$DUX_HOME/acme/proj.git" "$DUX_HOME/gone.git"
  still_queued "cannot fetch origin/main in $DUX_HOME/proj"
}

@test "a task waits until the check its brief names has succeeded on the merge" {
  delivered
  waiting 'deploy api'
  still_queued "check 'deploy api' has not run on the merge of $pr"
  FAKE_GH_CHECK_RUNS='{"check_runs":[{"name":"deploy api","status":"in_progress","conclusion":null}]}' \
    still_queued "check 'deploy api' has not succeeded on the merge of $pr"
  FAKE_GH_CHECK_RUNS='{"check_runs":[{"name":"deploy api","status":"completed","conclusion":"failure"}]}' \
    still_queued "check 'deploy api' has not succeeded on the merge of $pr"
  FAKE_GH_CHECK_RUNS='{"check_runs":[{"name":"build","status":"completed","conclusion":"success"}]}' \
    still_queued "check 'deploy api' has not run on the merge of $pr"
  FAKE_GH_API_FAIL=1 still_queued "GitHub did not answer for the checks on the merge of $pr"
  export FAKE_GH_CHECK_RUNS='{"check_runs":[{"name":"deploy api","status":"completed","conclusion":"success"}]}'
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  grep -qx "check=deploy api" "$DUX_HOME/data/tasks/$id/prerequisite"
  grep -qx "api -X GET repos/acme/proj/commits/$merge/check-runs -f check_name=deploy api -f filter=latest" "$FAKE_GH_LOG"
  wait_result "$id"
}

# The task waited on is usually torn down once its pull request merges, and
# teardown clears state/. What proved the delivery is kept in that task's own
# folder, and the waiting task is checked against that copy.
@test "a task starts on a delivery whose task was torn down, and waits when that delivery is lost" {
  delivered
  waiting
  run dux-teardown "$pred"
  [ "$status" -eq 0 ]
  [ ! -e "$DUX_HOME/state/$pred.run" ]; [ ! -e "$DUX_HOME/state/$pred.handoffs" ]
  kept="$DUX_HOME/data/tasks/$pred/delivery"
  mv "$kept" "$DUX_HOME/lost"
  still_queued "$id waits on $pred, and the record of the run that delivered it is gone"
  mv "$DUX_HOME/lost" "$kept"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/prerequisite")" = "$(printf 'after=%s\nrepo=acme/proj\npr=%s\nhead=%s\nmerge=%s' "$pred" "$pr" "$head" "$merge")" ]
  wait_result "$id"
}

# The record stays with the waiting task. A start that stops after the check
# leaves it, the next start is checked against it, and one that no longer
# matches waits. Abandoning a task that never ran removes the record with it.
@test "a task started again is checked against what was verified, and abandoning it removes the record" {
  delivered
  trust_suite_root proj
  waiting; first="$id"; rec="$DUX_HOME/data/tasks/$first/prerequisite"
  run dux-spawn "$first"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: $DUX_HOME/other is not trusted by Claude Code; open a session in it once and answer \"Yes, I trust this folder\"" ]
  [ "$(cat "$rec")" = "$(printf 'after=%s\nrepo=acme/proj\npr=%s\nhead=%s\nmerge=%s' "$pred" "$pr" "$head" "$merge")" ]
  [ "$(dux-ledger get "$first" state)" = queued ]
  waiting; second="$id"
  run dux-spawn "$second"
  [ "$status" -eq 2 ]
  [ -f "$DUX_HOME/data/tasks/$second/prerequisite" ]
  run dux-teardown --abandon "$second"
  [ "$status" -eq 0 ]
  [ ! -e "$DUX_HOME/data/tasks/$second" ]
  trust_path "$DUX_HOME/other"
  id="$first"; cp "$rec" "$DUX_HOME/verified"
  sed "s/^merge=.*/merge=$(printf '%040d' 0)/" "$DUX_HOME/verified" > "$rec"
  still_queued "what $id waits on is no longer what was verified in $rec"
  cp "$DUX_HOME/verified" "$rec"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  cmp "$rec" "$DUX_HOME/verified"
  wait_result "$id"
}
