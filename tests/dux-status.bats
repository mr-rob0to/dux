bats_require_minimum_version 1.5.0
load helpers/setup

setup_fleet() {
  make_repo "$DUX_HOME/api" main; make_repo "$DUX_HOME/ios" main
  dux-project add "$DUX_HOME/api" --base main >/dev/null
  dux-project add "$DUX_HOME/ios" --base main >/dev/null
}

task() {  # $1 id, $2 project, $3 state, [$4 pr], [$5 endpoint]
  mkdir -p "$DUX_HOME/data/tasks/$1"; : > "$DUX_HOME/data/tasks/$1/status.log"
  dux-ledger add "$1" "$2" scout local
  dux-ledger set "$1" endpoint "${5:-herdr:w1:p9}"
  [ -z "${4:-}" ] || [ "$4" = - ] || dux-ledger set "$1" pr "$4"
  dux-ledger set "$1" state "$3"
}

@test "digest groups fleet states under each project" {
  setup_fleet
  task a1 api queued; task a2 api running; task a3 api stale; task a4 api needs-decision; task a5 api blocked
  task a6 api dead; task a7 api ended; task a8 api done https://example.invalid/pr/7; task a9 api done; task a10 api failed
  task i1 ios running
  run --separate-stderr dux-status
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  expected="watcher: not running
api
  queued 1
  running 2 (1 stale)
  awaiting you 2
  needs recovery 2
  ready 2
  failed 1
ios
  running 1
unacknowledged
  stale: a3 (api)
  needs-decision: a4 (api)
  blocked: a5 (api)
  dead: a6 (api)
  ended: a7 (api)
  done: a8 (api)
  done: a9 (api)
  failed: a10 (api)"
  [ "$output" = "$expected" ]
}

@test "acknowledged tasks leave the unacknowledged block" {
  setup_fleet
  task a1 api done https://example.invalid/pr/7
  dux-ledger ack a1 done
  run dux-status
  [ "$output" = $'watcher: not running\napi\n  ready 1\nios' ]
}

@test "torn-down tasks are archived instead of ready or failed" {
  setup_fleet
  task a1 api done https://example.invalid/pr/7 -; task a2 api failed - -
  dux-ledger ack a1 done; dux-ledger ack a2 failed
  run dux-status
  [ "$output" = $'watcher: not running\napi\nios' ]
}

@test "an exit status log overrides a lagging ledger with a note" {
  setup_fleet
  task a1 api running
  echo "done: PR https://example.invalid/pr/3" >> "$DUX_HOME/data/tasks/a1/status.log"
  run dux-status
  [[ "$output" == *$'api\n  ready 1\n'* ]]
  [[ "$output" == *"note: a1 status log says done, ledger says running; the watcher will reconcile"* ]]
  [ "$(grep -c '  running' <<< "$output" || true)" -eq 0 ]
}

@test "running suffix reports stale and long-running counts" {
  setup_fleet
  task a1 api running; task a2 api stale; task a3 api running
  for id in a1 a2 a3; do echo brief > "$DUX_HOME/data/tasks/$id/brief.md"; done
  touch -t 202001010000 "$DUX_HOME/data/tasks/a1/brief.md" "$DUX_HOME/data/tasks/a2/brief.md"
  DUX_LONG_RUNNING_SECS=60 run dux-status
  [[ "$output" == *$'api\n  running 3 (1 stale, 2 long-running)\n'* ]]
}

@test "watcher and wake count reflect session files" {
  setup_fleet
  w="$(stand_in dux-watch)"; echo "$w" > "$DUX_HOME/state/watch.pid"
  echo $$ > "$DUX_HOME/state/dux.lock"; echo 2 > "$DUX_HOME/state/wakes.base"
  printf 'x\nx\nx\nx\nx\n' > "$DUX_HOME/state/events.log"
  run dux-status
  [ "${lines[0]}" = "watcher: running (pid $w)" ]
  [ "${lines[1]}" = "wakes this session: 3 (restart after 40)" ]
}

@test "--prs annotates ready PRs and warns when gh fails" {
  setup_fleet
  task a1 api done https://example.invalid/pr/7; task a2 api done
  FAKE_GH_PR_STATE=MERGED run --separate-stderr dux-status --prs
  [ "$status" -eq 0 ]
  [[ "$output" == *$'  ready 2\n    https://example.invalid/pr/7 MERGED\n'* ]]
  grep -q '^pr view https://example.invalid/pr/7 --json state' "$FAKE_GH_LOG"
  FAKE_GH_FAIL=1 run --separate-stderr dux-status --prs
  [ "$status" -eq 0 ]
  [[ "$output" == *"    https://example.invalid/pr/7 (pr state unavailable)"* ]]
  [[ "$stderr" == *"dux: gh pr view failed for https://example.invalid/pr/7"* ]]
}

@test "--intake and unknown flags are findings" {
  run dux-status --intake
  [ "$status" -eq 2 ]; [[ "$output" == "finding: issue intake is not available yet (milestone 4)"* ]]
  run dux-status --verbose
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-status [--prs] [--intake]"* ]]
}

@test "an empty registry prints only watcher state" {
  run dux-status
  [ "$output" = "watcher: not running" ]
}
