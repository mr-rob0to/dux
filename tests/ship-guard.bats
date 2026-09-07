bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# The helper is not on PATH: it lives beside SKILL.md so dux-install's symlink
# carries it, and /ship resolves it by path.
guard() { "$DUX_ROOT/skills/ship/ship-guard" "$@"; }

# A repository with two commits, so a test can move HEAD backwards.
new_repo() {  # $1 branch; prints the path
  local d="$DUX_HOME/repo"
  git init -q -b "$1" "$d"
  git -C "$d" commit -q --allow-empty -m one
  git -C "$d" commit -q --allow-empty -m two
  echo "$d"
}

state_file() { echo "$(git rev-parse --absolute-git-dir)/dux-ship/$1"; }
short() { git rev-parse --short HEAD; }

full_gate() {
  guard open && guard record checks && guard record review && guard record security
}

@test "open writes the branch and a zero fix count inside the git directory" {
  cd "$(new_repo main)"
  run --separate-stderr guard open
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  f="$(state_file main)"
  [ -f "$f" ]
  grep -qx 'version=1' "$f"
  grep -qx 'branch=main' "$f"
  grep -qx 'fix_passes=0' "$f"
  # The state is untracked and invisible to the repository being shipped.
  [ -z "$(git status --porcelain)" ]
}

@test "a clean gate records three phases and lets the push through" {
  cd "$(new_repo main)"
  run guard open
  [ "$status" -eq 0 ]
  run guard record checks
  [ "$status" -eq 0 ]
  run guard check checks
  [ "$status" -eq 0 ]
  run guard record review
  [ "$status" -eq 0 ]
  run guard check review
  [ "$status" -eq 0 ]
  run guard record security
  [ "$status" -eq 0 ]
  run guard check security
  [ "$status" -eq 0 ]
  run guard push-ok
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

@test "push-ok refuses a commit that landed after the review" {
  cd "$(new_repo main)"
  full_gate
  reviewed="$(short)"
  git commit -q --allow-empty -m "late fix"
  head="$(short)"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the review covered $reviewed, not HEAD $head; open a fix pass and record it again"* ]]
}

@test "push-ok refuses when the security pass was never recorded" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  guard record review
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no security recorded for main; the gate did not run in order"* ]]
}

@test "check refuses a HEAD that does not descend from the recorded phase" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  recorded="$(short)"
  git commit -q --amend --allow-empty -m "rewritten"
  head="$(short)"
  run guard check checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: HEAD $head does not descend from the checks commit $recorded; open the gate again"* ]]
}

@test "record applies the same descent test as check" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  recorded="$(short)"
  git commit -q --amend --allow-empty -m "rewritten"
  head="$(short)"
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: HEAD $head does not descend from the checks commit $recorded; open the gate again"* ]]
}

@test "record refuses a phase whose predecessor was never recorded" {
  cd "$(new_repo main)"
  guard open
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no checks recorded for main; the gate did not run in order"* ]]
  guard record checks
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no review recorded for main; the gate did not run in order"* ]]
}

@test "check refuses a phase that was never recorded" {
  cd "$(new_repo main)"
  guard open
  run guard check review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no review recorded for main; the gate did not run in order"* ]]
}

@test "record and check refuse an unknown phase" {
  cd "$(new_repo main)"
  guard open
  run guard record pr
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown phase 'pr' (checks, review, security)"* ]]
  run guard check pr
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown phase 'pr' (checks, review, security)"* ]]
}

@test "fix-pass refuses an unknown phase" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown fix pass 'checks' (review, security)"* ]]
}

@test "every verb but open refuses when the gate was never opened" {
  cd "$(new_repo main)"
  for args in "record checks" "check checks" "fix-pass review" "push-ok"; do
    # shellcheck disable=SC2086
    run guard $args
    [ "$status" -eq 2 ]
    [[ "$output" == "finding: no guard file for main; the gate was never opened"* ]]
  done
}

@test "a guard file naming another branch is refused, not trusted" {
  cd "$(new_repo main)"
  guard open
  f="$(state_file main)"
  # The file is untracked and world-writable by anything running as this
  # account, so a file that names another branch is a refusal, not a record.
  sed -i.bak 's/^branch=main$/branch=other/' "$f" && rm -f "$f.bak"
  run guard record checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file names other, not main; open the gate again"* ]]
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file names other, not main; open the gate again"* ]]
}

@test "a renamed branch has no gate of its own" {
  cd "$(new_repo main)"
  full_gate
  git branch -m main renamed
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no guard file for renamed; the gate was never opened"* ]]
}

@test "a detached HEAD is a finding" {
  cd "$(new_repo main)"
  git checkout -q --detach HEAD
  run guard open
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: /ship guard needs a branch; HEAD is detached"* ]]
}

@test "outside a git repository is a finding" {
  cd "$DUX_HOME"
  run guard open
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: /ship guard must run inside a git repository"* ]]
}

@test "a review fix pass clears the checks, the review and the security pass" {
  cd "$(new_repo main)"
  full_gate
  run guard fix-pass review
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
  f="$(state_file main)"
  refute grep -q '^checks=' "$f"
  refute grep -q '^review=' "$f"
  refute grep -q '^security=' "$f"
  grep -qx 'fix_passes=1' "$f"
}

@test "a security fix pass clears the security pass and the checks, not the review" {
  cd "$(new_repo main)"
  full_gate
  reviewed="$(git rev-parse HEAD)"
  run guard fix-pass security
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
  f="$(state_file main)"
  grep -qx "review=$reviewed" "$f"
  refute grep -q '^security=' "$f"
  refute grep -q '^checks=' "$f"
}

@test "the fourth fix pass is refused" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass review
  [[ "$output" == "fix pass 1 of 3" ]]
  run guard fix-pass review
  [[ "$output" == "fix pass 2 of 3" ]]
  run guard fix-pass review
  [[ "$output" == "fix pass 3 of 3" ]]
  run guard fix-pass review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: three fix passes already; revert to the minimal fix and stop"* ]]
}

@test "opening the gate again starts the fix count over" {
  cd "$(new_repo main)"
  guard open
  guard fix-pass review
  guard fix-pass review
  guard fix-pass review
  guard open
  run guard fix-pass review
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
}

@test "the guard works from a subdirectory" {
  repo="$(new_repo main)"
  mkdir -p "$repo/deep/inside"
  cd "$repo/deep/inside"
  run guard open
  [ "$status" -eq 0 ]
  run guard record checks
  [ "$status" -eq 0 ]
  [ -f "$repo/.git/dux-ship/main" ]
}

@test "a linked worktree keeps its own guard file, and a slash in the branch is encoded" {
  repo="$(new_repo main)"
  git -C "$repo" worktree add -q -b feat/x "$repo/wt" >/dev/null
  cd "$repo"
  guard open
  guard record checks
  cd "$repo/wt"
  run guard open
  [ "$status" -eq 0 ]
  # Two gates, two files, neither inside the other's git directory.
  [ -f "$repo/.git/dux-ship/main" ]
  [ -f "$repo/.git/worktrees/wt/dux-ship/feat%2Fx" ]
  # The linked worktree's gate is its own: it has no phase recorded yet.
  run guard check checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no checks recorded for feat/x; the gate did not run in order"* ]]
}

@test "an unknown verb prints the usage line" {
  cd "$(new_repo main)"
  run guard verify
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: ship-guard open | record <phase> | check <phase> | fix-pass <review|security> | push-ok"* ]]
}

@test "push-ok refuses a guard file counting more fix passes than the gate allows" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  # Same reason as the branch check: the file is untracked, so what it claims
  # about itself is checked rather than believed.
  sed -i.bak 's/^fix_passes=0$/fix_passes=9/' "$f" && rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file counts 9 fix passes, more than three; revert to the minimal fix and stop"* ]]
}
