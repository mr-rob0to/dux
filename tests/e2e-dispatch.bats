# bats file_tags=e2e
load helpers/setup

# Runs once per (DUX_BACKEND, DUX_WORKER_HARNESS) pair. Milestone 2 dispatches only
# claude workers, so the Makefile runs it twice: one line per backend.
setup_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    use_tmux_tmpdir
    export DUX_TMUX_SOCKET=dux-e2e DUX_TMUX_SESSION=duxe2e
    tmux -L dux-e2e kill-server 2>/dev/null || true
    tmux -L dux-e2e new-session -d -s duxe2e -x 80 -y 24
    # The pane command runs through the default shell; a login shell's rc files
    # re-prepend the operator's real tools ahead of the fakes. /bin/sh reads none.
    tmux -L dux-e2e set-option -t duxe2e default-shell /bin/sh
  fi
}
teardown_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    tmux -L dux-e2e kill-server 2>/dev/null || true
    drop_tmux_tmpdir
  fi
}

ready() { [ -n "${DUX_BACKEND:-}" ] && [ -n "${DUX_WORKER_HARNESS:-}" ]; }

# The worker container does not inherit this test's environment. Hand the wrapper what it needs:
# the fake herdr runs the command in-process, the tmux session takes an environment that new panes inherit.
worker_env() {
  export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  # Spawn will not open a tab in a directory Claude Code has not been told to
  # trust, and the harness has to carry the name the adapter looks for.
  trust_suite_root
  harness_shim
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/worker.script" DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1
  echo "$DUX_WORKER_HARNESS" > "$DUX_HOME/config/worker-harness"
  if [ "$DUX_BACKEND" = tmux ]; then
    local v
    # The git identity and the gh fixtures travel with the pane: a worker that
    # commits has no machine git config to fall back on, and the run's own
    # result proof reads the fake forge from the wrapper's environment.
    for v in DUX_HOME DUX_BACKEND DUX_TMUX_SOCKET DUX_TMUX_SESSION PATH FAKE_WORKER_SCRIPT FAKE_WORKER_ROUND_SCRIPT FAKE_WORKER_LOG DUX_WRAP_POLL_SECS DUX_HEARTBEAT_SECS \
             GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
             FAKE_GH_LOG FAKE_GH_PR_LIST FAKE_GH_PR_LIST_FILE FAKE_GH_PR_CHECKS; do
      tmux -L dux-e2e set-environment -t "$DUX_TMUX_SESSION" "$v" "${!v-}"
    done
  fi
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

wait_for() {  # $1 file, $2 grep pattern, $3 seconds
  local i=0
  until grep -q "$2" "$1" 2>/dev/null; do i=$((i + 1)); [ "$i" -ge "$3" ] && return 1; sleep 1; done
}
wait_file() {  # $1 path, $2 seconds
  local i=0
  until [ -e "$1" ]; do i=$((i + 1)); [ "$i" -ge "$2" ] && return 1; sleep 1; done
}

container_gone() {  # $1 endpoint
  if [ "$DUX_BACKEND" = tmux ]; then run dux-backend exists "$1"; [ "$status" -eq 1 ]
  else grep -qx 'pane close w1:p9' "$FAKE_HERDR_LOG"; fi
}

# The worker proposes a pull request. It is a scout, so what it is proved to
# have done is write a report, and the url it named never reaches Dux at all.
@test "spawn, a proved result the worker did not choose, teardown" {
  ready || skip "set DUX_BACKEND and DUX_WORKER_HARNESS"
  worker_env
  printf 'report all clear\nstatus working: starting\nstatus done: PR https://example.invalid/pr/1\nexit 0\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  run dux-spawn "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = running ]
  log="$DUX_HOME/data/tasks/$id/status.log"
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 30
  [ "$(cat "$hand/1/status")" = "done: report" ]
  [ "$(cat "$hand/1/event")" = done ]
  [ "$(cat "$hand/1/run")" = "$(sed -n 's/^run=//p' "$DUX_HOME/state/$id.run")" ]
  refute grep -rq example.invalid "$hand"
  # Nothing terminal reached the status log from the wrapper.
  [ "$(cat "$log")" = "working: starting" ]
  # No output file: the worker's bytes are its tab's scrollback now, and the
  # wrapper's own log holds Dux's lines and nothing the worker said.
  [ ! -e "$DUX_HOME/state/$id.out" ]
  refute grep -q '"type":"assistant"' "$DUX_HOME/state/$id.wrap.log"
  grep -q "^$DUX_WORKER_HARNESS " "$FAKE_WORKER_LOG"
  [[ "$(cat "$DUX_HOME/state/$id.pid")" =~ ^[0-9]+$ ]]
  sleep 3
  ep="$(dux-ledger get "$id" endpoint)"
  # Teardown reads the ledger, and only the watcher moves it.
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not terminal (ledger: running)"* ]]
  dux-watch --once
  [ "$(tail -n 1 "$log")" = "done: report" ]
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = - ]
  [ -e "$hand/1/consumed" ]
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id" state)" = done ]
  [ ! -e "$hand" ]; [ ! -e "$DUX_HOME/state/$id.run" ]
  [ ! -d "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  container_gone "$ep"
}

# The wrapper does not fork the harness, so there is no exit status to report.
# A session gone with no terminal line is ended, whatever ended it: the operator
# closing the tab, a crash, or the harness exiting on its own. Recovery is where
# the difference is proved.
@test "a worker that goes without a terminal line is recorded as ended and can be torn down" {
  ready || skip
  worker_env
  printf 'status working: starting\nexit 3\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  log="$DUX_HOME/data/tasks/$id/status.log"
  wait_file "$DUX_HOME/state/$id.handoffs/1/status" 30
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/status")" = "ended: the session ended without a terminal status" ]
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/event")" = ended ]
  sleep 3
  dux-watch --once
  [ "$(tail -n 1 "$log")" = "ended: the session ended without a terminal status" ]
  # ended is not a proved result, so teardown refuses it and recovery is the
  # route: what the session actually left behind has still to be proved.
  run dux-teardown "$id"
  [ "$status" -eq 2 ]; [[ "$output" == *"is not terminal (ledger: ended)"* ]]
  [ "$(dux-ledger get "$id" state)" = ended ]
}

@test "a codex worker is refused end to end and nothing is created" {
  ready || skip
  worker_env
  echo codex > "$DUX_HOME/config/worker-harness"
  id="$(fixture_task proj scout)"
  run dux-spawn "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: codex workers are not available: no deny list, so git push --no-verify skips the only guard (milestone 2)"* ]]
  [ "$(dux-ledger get "$id" state)" = queued ]
  [ ! -d "$DUX_HOME/proj/.worktrees" ]
  [ ! -e "$DUX_HOME/state/$id.endpoint" ]
  [ ! -s "$FAKE_WORKER_LOG" ]
}

# The pane holds a real session now, which Herdr detects for itself. A Dux
# mirror would be a second source for one pane, saying something the session did
# not, so the only thing Dux tells the multiplexer is the tab's title.
@test "on herdr the tab gets a title and no agent state at all" {
  ready || skip
  [ "$DUX_BACKEND" = herdr ] || skip "tmux has no title of its own"
  worker_env
  printf 'report all clear\nstatus working: starting\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_file "$DUX_HOME/state/$id.handoffs/1/status" 30
  grep -qF "pane report-metadata w1:p9 --source dux --title proj: Do the thing the operator asked for." "$FAKE_HERDR_LOG"
  [ "$(grep -c 'report-agent' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  [ "$(grep -c 'starting' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

# A worker runs with the operator's own authority, so what it must not have is
# a way to reach Dux by accident: no root, no home, no session, no backend, no
# sibling task, and no dux command on its path.
@test "a worker gets its own channel and nothing of Dux's own session" {
  ready || skip
  worker_env
  envdump="$DUX_HOME/state/worker-env.txt"
  printf 'dump-env %s\nstatus working: starting\nreport all clear\nstatus done: report\n' "$envdump" \
    > "$FAKE_WORKER_SCRIPT"
  sibling="$(fixture_task other scout)"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_file "$DUX_HOME/state/$id.handoffs/1/status" 30
  channel="$(sed -n 's/^channel=//p' "$DUX_HOME/state/$id.run")"
  [ -n "$channel" ]
  for v in DUX_HOME DUX_ROOT DUX_STATE DUX_DATA DUX_TASKS DUX_CONFIG DUX_SESSION_PID DUX_BACKEND \
           DUX_TMUX_SOCKET DUX_TMUX_SESSION CLAUDECODE HERDR_WORKSPACE_ID TMUX; do
    [ "$(grep -c "^$v=" "$envdump" || true)" -eq 0 ] || { echo "$v reached the worker"; return 1; }
  done
  [ "$(grep -c "^PATH=.*$DUX_ROOT/bin:" "$envdump" || true)" -eq 0 ]
  grep -qxF "DUX_STATUS_LOG=$channel/status.outbox" "$envdump"
  grep -qxF "DUX_REPORT=$channel/report.outbox" "$envdump"
  # Nothing about git: the guard is the worktree's own configuration now, so a
  # name here would follow the worker into every other repository it touches.
  [ "$(grep -c '^GIT_CONFIG_' "$envdump" || true)" -eq 0 ]
  # Nothing of this run reached the task next to it.
  [ "$(dux-ledger get "$sibling" state)" = queued ]
  [ ! -s "$DUX_HOME/data/tasks/$sibling/status.log" ]
  [ ! -e "$DUX_HOME/state/$sibling.handoffs" ]
}

# The harness saying done is a proposal. The run is over when the harness and the
# ordinary children it left are all gone, and only then is a result published.
@test "a result waits for the children the harness left behind" {
  ready || skip
  worker_env
  orphanfile="$DUX_HOME/state/orphan.pid"
  printf 'report all clear\nstatus working: starting\nstatus done: report\norphan %s\nexit 0\n' "$orphanfile" \
    > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  wait_file "$DUX_HOME/state/$id.handoffs/1/status" 30
  orphan="$(cat "$orphanfile")"
  [[ "$orphan" =~ ^[0-9]+$ ]]
  # The handoff exists, so the group was already proved gone before it was written.
  not_running "$orphan"
  [ "$(cat "$DUX_HOME/state/$id.handoffs/1/status")" = "done: report" ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/status.log")" = "working: starting" ]
}

# The whole ship shape, proved rather than claimed: the plan tasks the brief
# named are checked, the branch changes a file outside the documents, all five
# /ship phases are on the receipt at the final commit, and GitHub reports one
# open pull request at that commit with checks that are green and not empty.
@test "a ship task completes on the pull request GitHub reports, with five phases behind it" {
  ready || skip
  export FAKE_GH_PR_LIST_FILE="$DUX_HOME/state/pr.json"
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'
  worker_env
  id="$(fixture_task proj ship github)"
  cat > "$FAKE_WORKER_SCRIPT" <<EOF
run mkdir -p docs && printf '# Plan\n\n## Task 1: one\n- [x] one done\n\n## Task 2: two\n- [x] two done\n' > docs/plan.md
run printf 'implementation\n' > src.txt
run git add -A && git commit -q -m work
run "\$DUX_SHIP_RECORD" checks
run "\$DUX_SHIP_RECORD" review
run "\$DUX_SHIP_RECORD" security
run "\$DUX_SHIP_RECORD" pr
run jq -nc --arg s "\$(git rev-parse HEAD)" --arg b "dux/$id" '[{number:7,url:"https://github.com/acme/proj/pull/7",isDraft:false,state:"OPEN",baseRefName:"main",headRefName:\$b,headRefOid:\$s,headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]' > "$DUX_HOME/state/pr.json"
run "\$DUX_SHIP_RECORD" ci
status working: shipping
status done: PR https://example.invalid/pr/1
EOF
  dux-spawn "$id" >/dev/null
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 60
  [ "$(cat "$hand/1/status")" = "done: PR https://github.com/acme/proj/pull/7" ]
  [ "$(cat "$hand/1/event")" = done ]
  refute grep -rq example.invalid "$hand"
  [ "$(sed -n 's/^phase=\([a-z]*\) .*/\1/p' "$DUX_HOME/state/$id.ship-receipt" | tr '\n' ' ')" = "checks review security pr ci " ]
  grep -q '^pr checks 7 --repo acme/proj' "$FAKE_GH_LOG"
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = "https://github.com/acme/proj/pull/7" ]
  run dux-notify "$id"
  [ "$output" = "Review, then merge or send feedback: https://github.com/acme/proj/pull/7 (proj ship)" ]
}

# Two repositories, one after the other. The task that waits stays queued while
# the ship task before it works, and again while that pull request is open. Once
# GitHub reports it merged into the base, and the check the waiting brief names
# has passed on the merge, the waiting task starts in its own repository and
# keeps what was verified. What holds it back is the merge it waits on, never
# the worker limit, which has room for both.
@test "a task in another repository starts only once the ship task before it is merged and checked" {
  ready || skip
  export FAKE_GH_PR_LIST_FILE="$DUX_HOME/state/pr.json"
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'
  worker_env
  first="$(fixture_task proj ship github)"
  make_repo "$DUX_HOME/other" main
  dux-project add "$DUX_HOME/other" --base main --pr-template skip >/dev/null
  trust_path "$DUX_HOME/other"
  next="$(dux-task-new other scout --after "$first")"; t="$DUX_HOME/data/tasks/$next"
  printf 'Build on it.\n' > "$t/intent.md"; printf '1. Built.\n' > "$t/criteria.md"
  dux-brief "$next" --intent-file "$t/intent.md" --criteria-file "$t/criteria.md" --after-check 'deploy api' >/dev/null
  pr=https://github.com/acme/proj/pull/7
  cat > "$FAKE_WORKER_SCRIPT" <<EOF
run mkdir -p docs && printf '# Plan\n\n## Task 1: one\n- [x] one done\n\n## Task 2: two\n- [x] two done\n' > docs/plan.md
run printf 'implementation\n' > src.txt
run git add -A && git commit -q -m work
run "\$DUX_SHIP_RECORD" checks
run "\$DUX_SHIP_RECORD" review
run "\$DUX_SHIP_RECORD" security
run "\$DUX_SHIP_RECORD" pr
run jq -nc --arg s "\$(git rev-parse HEAD)" --arg b "dux/$first" '[{number:7,url:"$pr",isDraft:false,state:"OPEN",baseRefName:"main",headRefName:\$b,headRefOid:\$s,headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]' > "$DUX_HOME/state/pr.json"
run "\$DUX_SHIP_RECORD" ci
sleep 3
status done: PR $pr
EOF
  dux-spawn "$first" >/dev/null
  run dux-spawn "$next"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: $next waits on $first, which is running and has not delivered yet; $next remains queued" ]
  wait_file "$DUX_HOME/state/$first.handoffs/1/status" 60
  [ "$(cat "$DUX_HOME/state/$first.handoffs/1/status")" = "done: PR $pr" ]
  wait_for_workers 30
  dux-watch --once
  [ "$(dux-ledger get "$first" state)" = done ]
  run dux-spawn "$next"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: $next waits on $first, whose pull request $pr is still open; $next remains queued" ]

  m="$DUX_HOME/merger"; head="$(git -C "$DUX_HOME/proj" rev-parse "dux/$first")"
  git clone -q "$DUX_HOME/acme/proj.git" "$m"
  git -C "$m" fetch -q "$DUX_HOME/proj" "dux/$first"
  git -C "$m" merge -q --no-ff -m merged FETCH_HEAD
  git -C "$m" push -q origin main
  export FAKE_GH_PR_STATE=MERGED FAKE_GH_PR_HEAD="dux/$first" FAKE_GH_PR_BASE=main \
    FAKE_GH_PR_HEAD_OID="$head" FAKE_GH_PR_MERGE="$(git -C "$m" rev-parse HEAD)"
  run dux-spawn "$next"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: check 'deploy api' has not run on the merge of $pr; $next remains queued" ]
  [ "$(dux-ledger get "$next" state)" = queued ]
  export FAKE_GH_CHECK_RUNS='{"check_runs":[{"name":"deploy api","status":"completed","conclusion":"success"}]}'
  printf 'report built on it\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  run dux-spawn "$next"
  [ "$status" -eq 0 ]
  [ "$(cat "$t/prerequisite")" = "$(printf 'after=%s\nrepo=acme/proj\npr=%s\nhead=%s\nmerge=%s\ncheck=deploy api' "$first" "$pr" "$head" "$FAKE_GH_PR_MERGE")" ]
  wait_file "$DUX_HOME/state/$next.handoffs/1/status" 60
  [ "$(cat "$DUX_HOME/state/$next.handoffs/1/status")" = "done: report" ]
  [ "$(sed -n 's/^worktree=//p' "$DUX_HOME/state/$next.result-context")" = "$DUX_HOME/other/.worktrees/dux-$next" ]
}

# Several workers at once in one repository. Each has its own worktree, branch,
# push guard and tab, and a second start of a running task is refused.
@test "two workers run at once in one repository, each on its own worktree, branch and tab" {
  ready || skip
  worker_env
  printf 'report all clear\nstatus working: starting\nsleep 15\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  a="$(fixture_task proj scout)"; b="$(fixture_task proj scout)"
  dux-spawn "$a" >/dev/null
  dux-spawn "$b" >/dev/null
  wait_file "$DUX_HOME/state/$a.pgid" 30; wait_file "$DUX_HOME/state/$b.pgid" 30
  # Both live, each wrapper holding its own session.
  kill -0 "$(cat "$DUX_HOME/state/$a.pid")"; kill -0 "$(cat "$DUX_HOME/state/$b.pid")"
  [ "$(cat "$DUX_HOME/state/$a.pgid")" != "$(cat "$DUX_HOME/state/$b.pgid")" ]
  [ "$(dux-ledger get "$a" endpoint)" != "$(dux-ledger get "$b" endpoint)" ]
  for t in "$a" "$b"; do
    w="$DUX_HOME/proj/.worktrees/dux-$t"
    [ "$(dux-worktree path "$t")" = "$w" ]
    [ "$(git -C "$w" branch --show-current)" = "dux/$t" ]
    [ "$(git -C "$w" config --worktree --get core.hooksPath)" = "$DUX_HOME/data/tasks/$t/hooks" ]
    (cd "$w" && git commit -q --allow-empty -m "work on $t")
    run git -C "$w" push -q origin HEAD:refs/heads/main
    [ "$status" -ne 0 ]; [[ "$output" == *"finding: refusing to push to main from a Dux worktree"* ]]
  done
  run dux-status
  [[ $'\n'"$output"$'\n' == *$'\nproj\n  running 2\n'* ]]
  # A second start of a running task is refused before anything is made.
  row="$(dux-ledger line "$a")"; ep="$(cat "$DUX_HOME/state/$a.endpoint")"
  run dux-spawn "$a"
  [ "$status" -eq 2 ]
  [ "$output" = "finding: task $a is running, not queued" ] || { echo "refused: $output"; return 1; }
  [ "$(dux-ledger line "$a")" = "$row" ]; [ "$(cat "$DUX_HOME/state/$a.endpoint")" = "$ep" ]
  [ "$(git -C "$DUX_HOME/proj" worktree list | wc -l | tr -d ' ')" -eq 3 ]
}

# Work that plans first, spawned and parked at the question that asks for its
# approval. Each later turn of that session replays the round script, which a
# test writes before the round it belongs to; state/ship.script is the build.
plan_first() {
  export FAKE_GH_PR_LIST_FILE="$DUX_HOME/state/pr.json" FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'
  export FAKE_WORKER_ROUND_SCRIPT="$DUX_HOME/state/round.script" DUX_WRAP_PARK_MAX_PASSES=120
  worker_env
  make_github_repo proj
  dux-project add "$DUX_HOME/proj" --base main --pr-template skip >/dev/null
  id="$(dux-task-new proj ship)"; t="$DUX_HOME/data/tasks/$id"; s="$DUX_HOME/state"
  wt="$DUX_HOME/proj/.worktrees/dux-$id"; pr=https://github.com/acme/proj/pull/7
  printf 'Plan it, then build what is approved.\n' > "$t/intent.md"; printf '1. Built.\n' > "$t/criteria.md"
  dux-brief "$id" --intent-file "$t/intent.md" --criteria-file "$t/criteria.md" --phase planning >/dev/null
  cat > "$FAKE_WORKER_SCRIPT" <<'EOF'
run mkdir -p docs/plans && printf '# Plan\n\n**Where this stands**\n- Planned.\n\n## Task 1: one\n- [ ] one\n\n## Task 2: two\n- [ ] two\n' > docs/plans/p.md
run git add -A && git commit -q -m plan
status needs-decision: approve tasks 1-2 of docs/plans/p.md
sleep 0.2
touch stopped
idle
EOF
  cat > "$s/ship.script" <<EOF
run printf 'implementation\n' > src.txt && git add -A && git commit -q -m build && git push -q -u origin HEAD
run "\$DUX_SHIP_RECORD" checks && "\$DUX_SHIP_RECORD" review && "\$DUX_SHIP_RECORD" security && "\$DUX_SHIP_RECORD" pr
run jq -nc --arg s "\$(git rev-parse HEAD)" --arg b "dux/$id" '[{number:7,url:"$pr",isDraft:false,state:"OPEN",baseRefName:"main",headRefName:\$b,headRefOid:\$s,headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]' > "$FAKE_GH_PR_LIST_FILE"
run "\$DUX_SHIP_RECORD" ci
EOF
  dux-spawn "$id" >/dev/null
  wait_file "$s/$id.parked" 60
  [ "$(cat "$s/$id.handoffs/1/status")" = "needs-decision: approve tasks 1-2 of docs/plans/p.md" ]
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = needs-decision ]
}

# The whole of integrated approval on the backend. An answer is a round in the
# same session and approves nothing. The approval names the plan, its tasks and
# the commit, and the build it starts is proved against exactly that, then torn
# down with its delivery kept.
@test "work that plans first builds only once an approval round names its plan" {
  ready || skip
  plan_first
  run dux-recover "$id"
  [[ "$output" == *"next: after the operator answers, dux-round $id --purpose answer --file <f>"* ]]
  [[ "$output" == *"next: if the operator approves the plan it names, dux-round $id --purpose approval --file <f> --plan <path> --tasks <range> --commit <sha>"* ]]
  printf 'status needs-decision: approve tasks 1-2 of docs/plans/p.md\nsleep 0.2\ntouch stopped\nidle\n' > "$FAKE_WORKER_ROUND_SCRIPT"
  printf 'Go ahead.\n' > "$t/answer.md"
  run dux-round "$id" --purpose answer --file "$t/answer.md"
  [ "$output" = "round 1 sent to $id" ]
  wait_file "$s/$id.handoffs/2/status" 60
  [ "$(cat "$s/$id.handoffs/2/status")" = "needs-decision: approve tasks 1-2 of docs/plans/p.md" ]
  wait_file "$s/$id.parked" 30
  [ "$(cat "$t/phase")" = planning ]; [ ! -e "$t/round-1.approval" ]
  dux-watch --once
  { printf '%s\n' "run printf '# Plan\n\n**Where this stands**\n- Built.\n\n## Task 1: one\n- [x] one\n\n## Task 2: two\n- [x] two\n' > docs/plans/p.md"
    cat "$s/ship.script"; printf 'status done: PR %s\nsleep 0.2\ntouch stopped\nidle\n' "$pr"; } > "$FAKE_WORKER_ROUND_SCRIPT"
  tip="$(git -C "$wt" rev-parse HEAD)"; printf 'Approved: tasks 1-2.\n' > "$t/approval.md"
  run dux-round "$id" --purpose approval --file "$t/approval.md" --plan docs/plans/p.md --tasks 1-2 --commit "${tip:0:7}"
  [ "$output" = "round 2 sent to $id" ]
  [ "$(cat "$t/round-2.approval")" = "$(printf 'plan=docs/plans/p.md\ntasks=1-2\ncommit=%s' "$tip")" ]
  [ "$(cat "$t/phase")" = implementation ]
  wait_file "$s/$id.handoffs/3/status" 60
  [ "$(cat "$s/$id.handoffs/3/status")" = "done: PR $pr" ]
  wait_file "$s/$id.parked" 30
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = done ]; [ "$(dux-ledger get "$id" pr)" = "$pr" ]
  run dux-teardown "$id"
  [ "$status" -eq 0 ]
  [ "$(cat "$t/delivery/handoff/status")" = "done: PR $pr" ]; [ ! -e "$wt" ]
}

# The stopped-run path a rollback takes. The operator ends an approved build in
# its tab part-way: both processes go, the run is recorded unfinished, and all
# it leaves stays. Recovery proves nothing from boxes still open, and the task
# settles only on the operator's word.
@test "an approved build stopped part-way keeps its evidence and waits for explicit recovery" {
  ready || skip
  plan_first
  { cat "$s/ship.script"; echo 'sleep 60'; } > "$FAKE_WORKER_ROUND_SCRIPT"
  printf 'Approved: tasks 1-2.\n' > "$t/approval.md"
  dux-round "$id" --purpose approval --file "$t/approval.md" --plan docs/plans/p.md --tasks 1-2 --commit "$(git -C "$wt" rev-parse HEAD)" >/dev/null
  wait_for "$s/$id.ship-receipt" '^phase=ci ' 60
  wp="$(cat "$s/$id.pid")"; pg="$(cat "$s/$id.pgid")"
  kill -TERM -- "-$pg"
  wait_file "$s/$id.handoffs/2/status" 30
  [ "$(cat "$s/$id.handoffs/2/status")" = "ended: the session ended without a terminal status" ]
  wait_until 10 refute kill -0 "$wp" 2>/dev/null; group_gone "$pg"
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = ended ]
  grep -qx "run=$(cat "$s/$id.handoffs/2/run")" "$s/$id.run"
  [ "$(sed -n 's/^phase=\([a-z]*\) .*/\1/p' "$s/$id.ship-receipt" | tr '\n' ' ')" = "checks review security pr ci " ]
  [ -f "$t/round-1.approval" ]; [ "$(cat "$t/phase")" = implementation ]
  [ "$(git -C "$wt" log -1 --format=%s)" = build ]
  run dux-recover "$id"
  [[ "$output" == *"$id has no proved result."*"task 1 in docs/plans/p.md still has an unchecked box"* ]]
  [[ "$output" == *"next: dux-recover $id --classify failed, or dispatch a fresh task" ]]
  [ ! -e "$s/$id.handoffs/3" ]
  run dux-recover "$id" --classify failed
  [ "$output" = "classified $id as failed" ]
  [ "$(dux-ledger get "$id" state)" = failed ]; [ -d "$wt" ]
}

# The other gate, end to end. A combined review is four phases, and every hop
# between the operator's classification and the ledger has to agree on that:
# the brief records it, the recorder carries it, the receipt opens on it, the
# proof asks for those four phases and no more, and the watcher accepts what
# the proof accepted. One hop that forgets it strands a delivery that did
# everything it was asked to.
@test "a combined ship task completes on the four phases its gate owed" {
  ready || skip
  export FAKE_GH_PR_LIST_FILE="$DUX_HOME/state/pr.json"
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'
  worker_env
  id="$(fixture_task proj ship github combined)"
  cat > "$FAKE_WORKER_SCRIPT" <<EOF
run mkdir -p docs && printf '# Plan\n\n## Task 1: one\n- [x] one done\n\n## Task 2: two\n- [x] two done\n' > docs/plan.md
run printf 'implementation\n' > src.txt
run git add -A && git commit -q -m work
run "\$DUX_SHIP_RECORD" checks combined
run "\$DUX_SHIP_RECORD" review combined
run "\$DUX_SHIP_RECORD" pr
run jq -nc --arg s "\$(git rev-parse HEAD)" --arg b "dux/$id" '[{number:8,url:"https://github.com/acme/proj/pull/8",isDraft:false,state:"OPEN",baseRefName:"main",headRefName:\$b,headRefOid:\$s,headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]' > "$DUX_HOME/state/pr.json"
run "\$DUX_SHIP_RECORD" ci
status done: PR https://example.invalid/pr/1
EOF
  dux-spawn "$id" >/dev/null
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 60
  [ "$(cat "$hand/1/status")" = "done: PR https://github.com/acme/proj/pull/8" ]
  [ "$(cat "$hand/1/event")" = done ]
  r="$DUX_HOME/state/$id.ship-receipt"
  grep -qx 'review=combined' "$r"
  [ "$(sed -n 's/^phase=\([a-z]*\) .*/\1/p' "$r" | tr '\n' ' ')" = "checks review pr ci " ]
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = done ]
  [ "$(dux-ledger get "$id" pr)" = "https://github.com/acme/proj/pull/8" ]
}

# A plan task delivers documents. One that changes anything else is not a plan
# result, however green everything around it looks.
@test "a plan task that changes an implementation file is not proved done" {
  ready || skip
  export FAKE_GH_PR_LIST_FILE="$DUX_HOME/state/pr.json"
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'
  worker_env
  id="$(fixture_task proj plan github)"
  cat > "$FAKE_WORKER_SCRIPT" <<EOF
run mkdir -p docs/specs docs/plans && printf '# Design\n' > docs/specs/design.md && printf '# Plan\n' > docs/plans/plan.md
run printf 'implementation\n' > src.txt
run git add -A && git commit -q -m work
run jq -nc --arg s "\$(git rev-parse HEAD)" --arg b "dux/$id" '[{number:7,url:"https://github.com/acme/proj/pull/7",isDraft:false,state:"OPEN",baseRefName:"main",headRefName:\$b,headRefOid:\$s,headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]' > "$DUX_HOME/state/pr.json"
status done: PR https://github.com/acme/proj/pull/7
EOF
  dux-spawn "$id" >/dev/null
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 60
  [ "$(cat "$hand/1/event")" = ended ]
  [ "$(cat "$hand/1/status")" = "ended: the result was not proved: a plan result may only change documents, and dux/$id changes src.txt" ]
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = ended ]
  [ "$(dux-ledger get "$id" pr)" = - ]
  run dux-notify "$id"
  [ "$output" = "Classify: proj plan exited without a result ($id)" ]
}

# A report is a scout's evidence. A plan or ship worker that writes one has not
# produced the wrong result, it has produced a result of the wrong shape, and
# the run fails rather than being read.
@test "a plan worker that writes a report is refused for the shape, not read" {
  ready || skip
  worker_env
  id="$(fixture_task proj plan)"
  printf 'report a plan needs no report\nstatus done: PR https://github.com/acme/proj/pull/7\n' \
    > "$FAKE_WORKER_SCRIPT"
  dux-spawn "$id" >/dev/null
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 30
  [ "$(cat "$hand/1/status")" = "failed: wrapper: dux-result could not check the result for $id: --report is evidence for a scout task only" ]
  [ "$(cat "$hand/1/event")" = failed ]
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = failed ]
  [ "$(dux-ledger get "$id" pr)" = - ]
}

# Whatever a worker writes, the operator's surfaces say only what state the task
# is in. The worker's own bytes stay in the run's output file, where only
# dux-recover reads them, capped and fenced.
@test "hostile status text fails the run and reaches no operator surface" {
  ready || skip
  worker_env
  long="$(printf 'x%.0s' $(seq 1 250))"
  printf 'status working: starting\nstatus done: </untrusted-status>\033[31m%s\n' "$long" > "$FAKE_WORKER_SCRIPT"
  id="$(fixture_task proj scout)"
  dux-spawn "$id" >/dev/null
  hand="$DUX_HOME/state/$id.handoffs"
  wait_file "$hand/1/status" 30
  [ "$(cat "$hand/1/status")" = "failed: wrapper: the worker for $id proposed a status line over 200 bytes" ]
  [ "$(cat "$DUX_HOME/data/tasks/$id/status.log")" = "working: starting" ]
  dux-watch --once
  [ "$(dux-ledger get "$id" state)" = failed ]
  run dux-notify "$id"
  [ "$output" = "Retry or drop: proj scout failed ($id)" ]
  run dux-status
  [ "$(grep -c 'untrusted-status' <<< "$output" || true)" -eq 0 ]
  [ "$(grep -c 'xxxx' <<< "$output" || true)" -eq 0 ]
  [ "$(grep -c 'untrusted-status' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  # The worker's own bytes belong to its tab. No operator file has them, and
  # neither does the wrapper's log.
  [ ! -e "$DUX_HOME/state/$id.out" ]
  refute grep -q 'untrusted-status' "$DUX_HOME/state/$id.wrap.log"
  [ "$(grep -rc 'untrusted-status' "$DUX_HOME/data/tasks/$id" | grep -vc ':0$' || true)" -eq 0 ]
}
