bats_require_minimum_version 1.5.0
load helpers/setup

setup_fleet() {
  make_repo "$DUX_HOME/api" main; make_repo "$DUX_HOME/ios" main
  dux-project add "$DUX_HOME/api" --base main --pr-template skip >/dev/null
  dux-project add "$DUX_HOME/ios" --base main --pr-template skip >/dev/null
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
workers: 3 running (limit 3)
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
  [ "$output" = $'watcher: not running\nworkers: 0 running (limit 3)\napi\n  ready 1\nios' ]
}

@test "torn-down tasks are archived instead of ready or failed" {
  setup_fleet
  task a1 api done https://example.invalid/pr/7 -; task a2 api failed - -
  dux-ledger ack a1 done; dux-ledger ack a2 failed
  run dux-status
  [ "$output" = $'watcher: not running\nworkers: 0 running (limit 3)\napi\nios' ]
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
  [ "${lines[1]}" = "workers: 0 running (limit 3)" ]
  [ "${lines[2]}" = "wakes this session: 3 (restart after 10)" ]
}

# ---- the workers line ------------------------------------------------------
# One line for the whole fleet: the tasks running or stale in any project,
# against the limit dux-spawn starts workers up to.
@test "the workers line counts running and stale tasks in every project against the operator's limit" {
  setup_fleet
  task a1 api running; task a2 api stale; task a3 api queued; task a4 api blocked; task i1 ios running
  printf '# the operator says\n5\n' > "$DUX_HOME/config/max-workers"
  run --separate-stderr dux-status
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "${lines[0]}" = "watcher: not running" ]
  [ "${lines[1]}" = "workers: 3 running (limit 5)" ]
}

@test "with no operator file the workers line reads the template's limit" {
  setup_fleet
  task a1 api running
  rm "$DUX_HOME/config/max-workers"
  run --separate-stderr dux-status
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "${lines[1]}" = "workers: 1 running (limit 3)" ]
}

# A limit that cannot be read is said on the line and the digest carries on.
# dux-doctor names what is wrong with the file.
@test "an unreadable limit is said on the workers line and every project block still prints" {
  setup_fleet
  task a1 api running; task a2 api done https://example.invalid/pr/7; task i1 ios queued
  printf 'lots\n' > "$DUX_HOME/config/max-workers"
  run --separate-stderr dux-status
  [ "$status" -eq 0 ]
  expected="watcher: not running
workers: 1 running (limit unreadable)
api
  running 1
  ready 1
ios
  queued 1
unacknowledged
  done: a2 (api)"
  [ "$output" = "$expected" ]
}

# A ledger that cannot list its running tasks is not an empty fleet.
@test "a count the ledger cannot give is said as unavailable, never as none" {
  setup_fleet
  task a1 api running
  r="$(root_with_stub dux-ledger "#!/usr/bin/env bash
if [ \"\$1 \$2 \$3\" = 'list --state running' ]; then echo 'finding: cannot read the ledger' >&2; exit 2; fi
exec $DUX_ROOT/bin/dux-ledger \"\$@\"")"
  DUX_ROOT="$r" run --separate-stderr dux-status
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "workers: count unavailable (limit 3)" ]
  [[ "$output" == *$'\napi\n  running 1'* ]]
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
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux --pr-template skip >/dev/null
  make_repo "$DUX_HOME/ios" main; dux-project add "$DUX_HOME/ios" --base main --pr-template skip >/dev/null
  make_repo "$DUX_HOME/bare" main; dux-project add "$DUX_HOME/bare" --base main --issues label:dux --pr-template skip >/dev/null
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
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux --pr-template skip >/dev/null
  run dux-status --intake
  [ "$status" -eq 0 ]
  [[ "$output" == *"  api: skipped: finding: the Dux lock is not held by this session"* ]]
  [ "${lines[${#lines[@]}-1]}" = api ]   # the digest still prints; its last line is the one project's name
}

@test "--intake with no labelled project says so" {
  make_repo "$DUX_HOME/ios" main; dux-project add "$DUX_HOME/ios" --base main --pr-template skip >/dev/null
  run dux-status --intake
  [ "${lines[0]}" = intake ]; [ "${lines[1]}" = "  no project has issues enabled" ]
}

@test "an empty registry prints only the watcher and workers lines" {
  run dux-status
  [ "$output" = $'watcher: not running\nworkers: 0 running (limit 3)' ]
}

@test "--intake still names a reason when the failure prints no line of its own" {
  # The reason is chosen on the text, not on an exit status: the pipeline that
  # looks for a structured line ends in a drain, which succeeds whether or not
  # anything matched. A failure that prints nothing Dux recognises must still
  # produce a reason rather than an empty one.
  export DUX_SESSION_PID=$$; dux-lock acquire >/dev/null
  make_github_repo api; dux-project add "$DUX_HOME/api" --base main --issues label:dux --pr-template skip >/dev/null
  fr="$DUX_HOME/fr"; mkdir -p "$fr"; cp -R "$DUX_ROOT/bin" "$fr/bin"
  printf '#!/usr/bin/env bash\nprintf "something the digest does not parse\\n" >&2\nexit 2\n' > "$fr/bin/dux-intake"
  chmod +x "$fr/bin/dux-intake"
  DUX_ROOT="$fr" run dux-status --intake
  [ "$status" -eq 0 ]
  [[ "$output" == *"  api: skipped: intake failed"* ]] \
    || { echo "wanted 'api: skipped: intake failed', got:"; echo "$output"; return 1; }
}

# ---- base branches ----------------------------------------------------------

RED_URL=https://github.com/acme/widgets/actions/runs/17000000201
widgets_checked() {  # $1 fixture; registers acme/widgets and checks its base once
  make_github_repo widgets
  dux-project add "$DUX_HOME/widgets" --base main --pr-template skip >/dev/null
  FAKE_GH_RUNS="$BATS_TEST_DIRNAME/fixtures/runs/$1" dux-base check widgets >/dev/null
}

@test "a base wake missed during a restart is listed" {
  widgets_checked red-failure.json
  run --separate-stderr dux-status
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "watcher: not running
workers: 0 running (limit 3)
widgets
  base red: $RED_URL
unacknowledged
  base-red: widgets" ]
  dux-base ack widgets "$(dux-base get widgets reported)"
  run dux-status
  [ "$output" = "watcher: not running
workers: 0 running (limit 3)
widgets
  base red: $RED_URL" ]
}

@test "a green base, and a base never checked, show no base line" {
  setup_fleet
  widgets_checked green.json
  run --separate-stderr dux-status
  [ -z "$stderr" ]
  [ "$output" = $'watcher: not running\nworkers: 0 running (limit 3)\napi\nios\nwidgets' ]
}

@test "a red base changes no task count and no ledger line" {
  make_github_repo widgets
  dux-project add "$DUX_HOME/widgets" --base main --pr-template skip >/dev/null
  task t1 widgets running; task t2 widgets running
  cp "$DUX_HOME/data/backlog.md" "$DUX_HOME/ledger.before"
  run dux-status
  [ "$output" = $'watcher: not running\nworkers: 2 running (limit 3)\nwidgets\n  running 2' ]
  FAKE_GH_RUNS="$BATS_TEST_DIRNAME/fixtures/runs/red-failure.json" dux-base check >/dev/null
  cmp "$DUX_HOME/ledger.before" "$DUX_HOME/data/backlog.md"
  run dux-status
  [ "$output" = "watcher: not running
workers: 2 running (limit 3)
widgets
  base red: $RED_URL
  running 2
unacknowledged
  base-red: widgets" ]
  cmp "$DUX_HOME/ledger.before" "$DUX_HOME/data/backlog.md"
}
