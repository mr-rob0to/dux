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

