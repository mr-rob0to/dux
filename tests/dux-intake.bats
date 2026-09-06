bats_require_minimum_version 1.5.0
load helpers/setup

# The helper's setup body plus the two lines every file that writes under the
# lock adds (tests/dux-spawn.bats:21-22). DUX_SESSION_PID is what `dux-lock
# mine` compares against; without it, `mine` reads $PPID, which is bats and not
# this test, and every write below is refused.
setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  export GIT_AUTHOR_NAME=dux-test GIT_AUTHOR_EMAIL=dux-test@example.invalid
  export GIT_COMMITTER_NAME=dux-test GIT_COMMITTER_EMAIL=dux-test@example.invalid
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  cp "$DUX_ROOT"/templates/config/* "$DUX_HOME/config/"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export DUX_WATCHER=off
  export FAKE_GH_LOG="$DUX_HOME/state/fake-gh.log"
  : > "$FAKE_GH_LOG"
  export DUX_SESSION_PID=$$
  dux-lock acquire >/dev/null
}

labelled_project() {  # registers proj with a GitHub origin and the dux label
  make_github_repo proj
  dux-project add "$DUX_HOME/proj" --base main --issues label:dux >/dev/null
}
FIX="$DUX_ROOT/tests/fixtures/gh-issues.json"

@test "usage: no project, unknown flag, bad shape, --show with a project, two projects" {
  run dux-intake; [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-intake"* ]]
  run dux-intake proj --loud; [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-intake"* ]]
  run dux-intake proj --shape spike; [ "$status" -eq 2 ]; [[ "$output" == "finding: --shape must be plan, ship, or scout: spike"* ]]
  run dux-intake proj --show t1; [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-intake"* ]]
  run dux-intake proj other; [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-intake"* ]]
}

@test "an unregistered project, issues=off, and a project without a GitHub origin are findings" {
  run dux-intake nope; [ "$status" -eq 2 ]; [[ "$output" == "finding: project nope not registered"* ]]
  make_repo "$DUX_HOME/plain" main; dux-project add "$DUX_HOME/plain" --base main >/dev/null
  run dux-intake plain; [ "$status" -eq 2 ]; [[ "$output" == "finding: project plain has issues=off; nothing to pull"* ]]
  make_repo "$DUX_HOME/local" main; dux-project add "$DUX_HOME/local" --base main --issues label:dux >/dev/null
  run dux-intake local; [ "$status" -eq 2 ]; [[ "$output" == "finding: project local has no GitHub origin; intake needs one"* ]]
  make_github_repo gone; dux-project add "$DUX_HOME/gone" --base main --issues label:dux >/dev/null; rm -rf "$DUX_HOME/gone"
  run dux-intake gone; [ "$status" -eq 2 ]; [[ "$output" == "finding: project gone path is gone: $DUX_HOME/gone"* ]]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
}

@test "three labelled issues become three queued ship tasks with the issue saved as data" {
  labelled_project
  FAKE_GH_ISSUE_LIST_FILE="$FIX" run --separate-stderr dux-intake proj
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  grep -qxF 'issue list --repo acme/proj --state open --label dux --limit 100 --json number,title,body' "$FAKE_GH_LOG"
  [ "$(grep -c '^issue ' "$FAKE_GH_LOG")" -eq 1 ]
  [ "$(grep -c '^queued proj-ship-' <<< "$output")" -eq 3 ]
  [[ "$output" == *"intake proj: 3 queued, 0 dropped, 0 unlabelled" ]]
  for n in 12 13 14; do
    id="$(dux-ledger list --source "gh:acme/proj#$n")"; [ -n "$id" ]
    [ "$(dux-ledger get "$id" state)" = queued ]; [ "$(dux-ledger get "$id" shape)" = ship ]
    [ -f "$DUX_HOME/data/tasks/$id/status.log" ]
  done
  id13="$(dux-ledger list --source 'gh:acme/proj#13')"; f="$DUX_HOME/data/tasks/$id13/issue.md"
  [ "$(head -1 "$f")" = "acme/proj#13: Tab and control in title" ]      # cap_line turns the tab into a space and drops the control character
  [ "$(LC_ALL=C grep -c $'\r' "$f" || true)" -eq 0 ]
  [ "$(LC_ALL=C tr -d '\011\012\040-\176' < "$f" | wc -c | tr -d ' ')" -eq 0 ]   # nothing but printable ASCII, tab, newline
  grep -qxF '</untrusted-issue>' "$f"                                             # raw here; the brief and --show escape it
  grep -qxF '[truncated at 3700 bytes]' "$f"
  [ "$(wc -c < "$f" | tr -d ' ')" -lt 4000 ]
  id14="$(dux-ledger list --source 'gh:acme/proj#14')"
  [ "$(wc -l < "$DUX_HOME/data/tasks/$id14/issue.md" | tr -d ' ')" -eq 2 ]      # title line, blank line, no body, no marker
}

@test "--shape scout queues scout tasks, and a task of another shape for the same issue blocks a second" {
  labelled_project
  id="$(dux-task-new proj plan --source 'gh:acme/proj#12')"
  FAKE_GH_ISSUE_LIST_FILE="$FIX" run dux-intake proj --shape scout
  [ "$status" -eq 0 ]
  [ "$(grep -c '^queued proj-scout-' <<< "$output")" -eq 2 ]
  [ "$(dux-ledger list --source 'gh:acme/proj#12')" = "$id" ]
}


@test "exactly the limit logs a warning that the list may be cut" {
  labelled_project
  jq -n '[range(1; 101) | {number: ., title: "t\(.)", body: "b"}]' > "$DUX_HOME/hundred.json"
  FAKE_GH_ISSUE_LIST_FILE="$DUX_HOME/hundred.json" run --separate-stderr dux-intake proj
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"dux: intake: acme/proj has 100 or more open 'dux' issues; only the first 100 were read"* ]]
  [ "$(grep -c '^queued ' <<< "$output")" -eq 100 ]
}


@test "a second run queues nothing and refreshes the issue file only while queued" {
  labelled_project
  FAKE_GH_ISSUE_LIST_FILE="$FIX" dux-intake proj >/dev/null
  before="$(wc -l < "$DUX_HOME/data/backlog.md")"
  id12="$(dux-ledger list --source 'gh:acme/proj#12')"; id13="$(dux-ledger list --source 'gh:acme/proj#13')"
  dux-ledger set "$id13" state running
  jq '(.[] | select(.number == 12) | .body) = "sharpened" | (.[] | select(.number == 13) | .body) = "changed"' "$FIX" > "$DUX_HOME/fix2.json"
  FAKE_GH_ISSUE_LIST_FILE="$DUX_HOME/fix2.json" run --separate-stderr dux-intake proj
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$output" = "intake proj: 0 queued, 0 dropped, 0 unlabelled" ]
  [ "$(wc -l < "$DUX_HOME/data/backlog.md")" -eq "$before" ]
  grep -qxF sharpened "$DUX_HOME/data/tasks/$id12/issue.md"
  [ "$(grep -c changed "$DUX_HOME/data/tasks/$id13/issue.md" || true)" -eq 0 ]
  # Once a brief exists the file is frozen, so brief and issue keep agreeing.
  : > "$DUX_HOME/data/tasks/$id12/brief.md"
  jq '(.[] | select(.number == 12) | .body) = "sharper"' "$FIX" > "$DUX_HOME/fix3.json"
  FAKE_GH_ISSUE_LIST_FILE="$DUX_HOME/fix3.json" dux-intake proj >/dev/null
  grep -qxF sharpened "$DUX_HOME/data/tasks/$id12/issue.md"
}


@test "intake refuses without the lock and leaves the ledger alone" {
  labelled_project; dux-lock release >/dev/null
  FAKE_GH_ISSUE_LIST_FILE="$FIX" run dux-intake proj
  [ "$status" -eq 2 ]; [[ "$output" == "finding: the Dux lock is not held by this session; refusing to queue tasks"* ]]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
}


@test "a closed issue drops its queued task with a note; an unlabelled open one stays queued" {
  labelled_project
  FAKE_GH_ISSUE_LIST_FILE="$FIX" dux-intake proj >/dev/null
  id12="$(dux-ledger list --source 'gh:acme/proj#12')"; id13="$(dux-ledger list --source 'gh:acme/proj#13')"
  jq '[.[] | select(.number == 14)]' "$FIX" > "$DUX_HOME/only14.json"
  FAKE_GH_ISSUE_LIST_FILE="$DUX_HOME/only14.json" FAKE_GH_ISSUE_STATE=CLOSED run --separate-stderr dux-intake proj
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get "$id12" state)" = dropped ]; [ "$(dux-ledger get "$id13" state)" = dropped ]
  grep -q "^dropped: issue acme/proj#12 was closed; seen by intake at " "$DUX_HOME/data/tasks/$id12/report.md"
  [[ "$output" == *"dropped $id12 acme/proj#12"* ]]; [[ "$output" == *"0 queued, 2 dropped, 0 unlabelled" ]]
  grep -qxF 'issue view 12 --repo acme/proj --json state -q .state' "$FAKE_GH_LOG"
}

@test "a failed list, a malformed list, a failed view, and an unknown state are findings that leave the ledger alone" {
  labelled_project
  FAKE_GH_FAIL=1 run dux-intake proj
  [ "$status" -eq 2 ]; [[ "$output" == "finding: gh issue list failed for acme/proj: fake gh: issue list failed"* ]]
  FAKE_GH_ISSUE_LIST='{"number": 1}' run dux-intake proj
  [ "$status" -eq 2 ]; [[ "$output" == "finding: gh issue list returned something other than a list of issues for acme/proj"* ]]
  FAKE_GH_ISSUE_LIST='[{"number": "12", "title": "t", "body": "b"}]' run dux-intake proj
  [ "$status" -eq 2 ]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
  FAKE_GH_ISSUE_LIST='[{"number": 12.5, "title": "t", "body": "b"}]' run dux-intake proj
  [ "$status" -eq 2 ]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
  FAKE_GH_ISSUE_LIST_FILE="$FIX" dux-intake proj >/dev/null
  # The list succeeds and is empty; the view of the vanished issue fails.
  FAKE_GH_ISSUE_LIST='[]' FAKE_GH_VIEW_FAIL=1 run dux-intake proj
  [ "$status" -eq 2 ]; [[ "$output" == "finding: gh issue view failed for acme/proj#12: fake gh: issue view failed"* ]]
  FAKE_GH_ISSUE_LIST='[]' FAKE_GH_ISSUE_STATE=WEIRD run dux-intake proj
  [ "$status" -eq 2 ]; [[ "$output" == "finding: gh issue view returned an unknown state for acme/proj#12: WEIRD"* ]]
  for n in 12 13 14; do [ "$(dux-ledger get "$(dux-ledger list --source "gh:acme/proj#$n")" state)" = queued ]; done
}

