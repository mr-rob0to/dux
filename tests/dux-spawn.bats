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
  # One Dux worker at a time, so the second task only starts once the first has
  # finished and been settled. That is the ordinary sequence, not a test trick.
  wait_result "$id"
  wait_for_workers 30
  dux-ledger set "$id" state done
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

# ---- one Dux-managed worker at a time --------------------------------------
# Several long workers on one subscription is the waste this refuses. It is a
# refusal and not a queue: the operator reruns the same spawn once the active
# task has stopped, and there is no scheduler to go wrong.

# A process whose command line names another task's wrapper, which is the
# evidence dux-spawn reads. $$ would not do: the check asks what the pid is
# running, not merely that something is.
live_wrapper_for() {  # $1 id; prints the pid
  local p; p="$(stand_in "dux-worker-wrap $1")"
  echo "$p" > "$DUX_HOME/state/$1.pid"
  echo "$p"
}

@test "a live worker on another task refuses the start and creates nothing" {
  a="$(fixture_task proj scout)"
  b="$(fixture_task proj ship)"
  live_wrapper_for "$a" >/dev/null
  run dux-spawn "$b"
  rm -f "$DUX_HOME/state/$a.pid"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: another Dux worker is active: $a; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  run git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$b"; [ "$status" -ne 0 ]
  grep -qxF -- '- Worktree: <set by dux-spawn>' "$DUX_HOME/data/tasks/$b/brief.md"
  [ ! -e "$DUX_HOME/state/$b.endpoint" ]
  # The backend is asked whether a container exists, which is a read; what must
  # not have happened is a container being made or a worker being started.
  run grep -c '^tab create' "$FAKE_HERDR_LOG"; [ "$output" = 0 ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

@test "the same spawn goes through once the other worker has stopped" {
  a="$(fixture_task proj scout)"
  b="$(fixture_task proj ship)"
  pid="$(live_wrapper_for "$a")"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  reap "$pid"
  # The pidfile stays, naming a pid that is gone: that is what an ordinary
  # finished run leaves behind, and it must not keep refusing for ever.
  [ -f "$DUX_HOME/state/$a.pid" ]
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

@test "evidence about another task that cannot be read blocks the start" {
  a="$(fixture_task proj scout)"
  b="$(fixture_task proj ship)"
  printf 'not-a-pid\n' > "$DUX_HOME/state/$a.pid"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  # Named for what went quiet, not reported as a live worker: the two are fixed
  # differently, and saying "active" about a file nobody can read is a guess.
  [ "$output" = "finding: cannot tell whether a worker for $a is alive: $DUX_HOME/state/$a.pid does not say; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

# The harness outlives its wrapper now: an operator who kills the wrapper leaves
# a live session in a tab and a pidfile that reads gone. The group file is the
# signal for that, and it is read the same fail-closed way the pidfile is.
@test "another task's live harness group refuses the start, and an unreadable one blocks it" {
  a="$(fixture_task proj scout)"
  b="$(fixture_task proj ship)"
  # This test's own process group: a group that certainly answers kill -0.
  ps -o pgid= -p $$ | tr -d ' ' > "$DUX_HOME/state/$a.pgid"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: another Dux worker is active: $a; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  printf 'x\n' > "$DUX_HOME/state/$a.pgid"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: cannot tell whether a worker for $a is alive: $DUX_HOME/state/$a.pgid does not say; $b remains queued" ]
  # A group that is gone stops refusing, the way a dead pidfile does.
  rm -f "$DUX_HOME/state/$a.pgid"
  run dux-spawn "$b"
  [ "$status" -eq 0 ]
  wait_result "$b"
}

@test "a container for a task Dux believes is running blocks the start" {
  a="$(fixture_task proj scout)"
  run dux-spawn "$a"
  [ "$status" -eq 0 ]
  wait_result "$a"
  wait_for_workers 30
  # The pane outlives the worker on both backends, so with the pidfile settled
  # the container is the only signal left. Dux still records $a as running, so
  # it cannot tell that pane from one with a worker in it.
  rm -f "$DUX_HOME/state/$a.pid"
  [ -n "$(dux-backend find "$a")" ]
  [ "$(dux-ledger get "$a" state)" = running ]
  b="$(fixture_task proj ship)"
  run dux-spawn "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: another Dux worker is active: $a; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$b" ]
}

# A pidfile that cannot be read blocks because Dux cannot prove the slot is
# free. The other two readings are the same question: a ledger that will not
# answer about another task, and a backend that will not answer about one Dux
# believes is running, are both "could not tell". Skipping them answers "free"
# on no evidence, which is the one answer that puts two agents on one account.
@test "a ledger that cannot answer about another task blocks the start" {
  a="$(fixture_task proj scout)"
  b="$(fixture_task proj ship)"
  r="$(root_with_stub dux-ledger "#!/usr/bin/env bash
if [ \"\$1\" = get ] && [ \"\$2\" = $a ]; then echo 'finding: cannot read the ledger' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-ledger \"\$@\"")"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: cannot tell whether a worker for $a is alive: the ledger did not answer; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

@test "a ledger that cannot list the tasks blocks the start" {
  b="$(fixture_task proj ship)"
  r="$(root_with_stub dux-ledger "#!/usr/bin/env bash
if [ \"\$1\" = list ]; then echo 'finding: cannot read the ledger' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-ledger \"\$@\"")"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: cannot tell whether another Dux worker is alive: the ledger could not list the tasks; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
}

@test "a backend that cannot answer about a running task blocks the start" {
  a="$(fixture_task proj scout)"
  run dux-spawn "$a"
  [ "$status" -eq 0 ]
  wait_result "$a"
  wait_for_workers 30
  rm -f "$DUX_HOME/state/$a.pid"
  [ "$(dux-ledger get "$a" state)" = running ]
  b="$(fixture_task proj ship)"
  r="$(root_with_stub dux-backend "#!/usr/bin/env bash
if [ \"\$1\" = find ] && [ \"\$2\" = $a ]; then echo 'finding: the backend is unavailable' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-backend \"\$@\"")"
  run env DUX_ROOT="$r" "$r/bin/dux-spawn" "$b"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: cannot tell whether a worker for $a is alive: the backend did not answer; $b remains queued" ]
  [ "$(dux-ledger get "$b" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$b" ]
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
