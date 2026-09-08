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

# The digest counts the ledger. A worker writing its own ending into the status
# log used to move the count and put its url on the screen; now the task stays
# running until a proved handoff moves it, and the url comes with that.
@test "a terminal status line the ledger has not followed changes nothing" {
  setup_fleet
  task a1 api running
  echo "done: PR https://example.invalid/pr/3" >> "$DUX_HOME/data/tasks/a1/status.log"
  run dux-status --prs
  [[ "$output" == *$'api\n  running 1\n'* ]]
  [[ "$output" != *ready* ]]; [[ "$output" != *example.invalid* ]]; [[ "$output" != *note:* ]]
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

@test "an unknown flag is a finding" {
  run dux-status --verbose
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-status [--prs] [--intake]"* ]]
}

@test "--intake runs intake for labelled projects, skips the rest, and one failure is one line" {
  export DUX_SESSION_PID=$$; dux-lock acquire >/dev/null
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux >/dev/null
  make_repo "$DUX_HOME/ios" main; dux-project add "$DUX_HOME/ios" --base main >/dev/null
  make_repo "$DUX_HOME/bare" main; dux-project add "$DUX_HOME/bare" --base main --issues label:dux >/dev/null
  FAKE_GH_ISSUE_LIST='[{"number": 3, "title": "t", "body": "b"}]' run --separate-stderr dux-status --intake
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = intake ]
  [[ "${lines[1]}" == "  queued api-ship-"*" acme/api#3" ]]
  [ "${lines[2]}" = "  intake api: 1 queued, 0 dropped, 0 unlabelled" ]
  [ "${lines[3]}" = "  bare: skipped: finding: project bare has no GitHub origin; intake needs one" ]
  [[ "${lines[4]}" == "watcher: "* ]]
  [ "$(grep -c '^  ios' <<< "$output" || true)" -eq 0 ]
  [ "$(dux-ledger list --project api --state queued | wc -l | tr -d ' ')" -eq 1 ]
}

@test "--intake without the lock skips every labelled project and still prints the digest" {
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux >/dev/null
  run dux-status --intake
  [ "$status" -eq 0 ]
  [[ "$output" == *"  api: skipped: finding: the Dux lock is not held by this session"* ]]
  [ "${lines[${#lines[@]}-1]}" = api ]   # the digest still prints; its last line is the one project's name
}

@test "--intake with no labelled project says so" {
  make_repo "$DUX_HOME/ios" main; dux-project add "$DUX_HOME/ios" --base main >/dev/null
  run dux-status --intake
  [ "${lines[0]}" = intake ]; [ "${lines[1]}" = "  no project has issues enabled" ]
}

@test "an empty registry prints only watcher state" {
  run dux-status
  [ "$output" = "watcher: not running" ]
}

@test "--intake still names a reason when the failure prints no line of its own" {
  # The reason is chosen on the text, not on an exit status: the pipeline that
  # looks for a structured line ends in a drain, which succeeds whether or not
  # anything matched. A failure that prints nothing Dux recognises must still
  # produce a reason rather than an empty one.
  export DUX_SESSION_PID=$$; dux-lock acquire >/dev/null
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux >/dev/null
  fr="$DUX_HOME/fr"; mkdir -p "$fr"; cp -R "$DUX_ROOT/bin" "$fr/bin"
  printf '#!/usr/bin/env bash\nprintf "something the digest does not parse\\n" >&2\nexit 2\n' > "$fr/bin/dux-intake"
  chmod +x "$fr/bin/dux-intake"
  DUX_ROOT="$fr" run dux-status --intake
  [ "$status" -eq 0 ]
  [[ "$output" == *"  api: skipped: intake failed"* ]] \
    || { echo "wanted 'api: skipped: intake failed', got:"; echo "$output"; return 1; }
}
