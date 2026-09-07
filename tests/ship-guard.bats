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

@test "push-ok refuses a commit that landed after the gate ran" {
  cd "$(new_repo main)"
  full_gate
  gated="$(short)"
  git commit -q --allow-empty -m "late fix"
  head="$(short)"
  run guard push-ok
  [ "$status" -eq 2 ]
  # Every phase is stale here; the first one reported is the earliest.
  [[ "$output" == "finding: the checks covered $gated, not HEAD $head; open a fix pass and record every phase again"* ]]
}

@test "push-ok names the review when the review is the stale one" {
  cd "$(new_repo main)"
  full_gate
  reviewed="$(short)"
  git commit -q --allow-empty -m "late fix"
  head="$(git rev-parse HEAD)"
  # Only a hand-edited file can single the review out: a legal flow can no
  # longer move checks and security past it without a fix pass clearing it too.
  f="$(state_file main)"
  sed -i.bak -e "s/^checks=.*/checks=$head/" -e "s/^security=.*/security=$head/" "$f"
  rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the review covered $reviewed, not HEAD $(short); open a fix pass and record every phase again"* ]]
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

@test "every verb but open refuses when the gate was never opened" {
  cd "$(new_repo main)"
  for args in "record checks" "check checks" "fix-pass" "push-ok"; do
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

@test "a fix pass clears every phase, so each one is recorded again" {
  cd "$(new_repo main)"
  full_gate
  run guard fix-pass
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
  f="$(state_file main)"
  refute grep -q '^checks=' "$f"
  refute grep -q '^review=' "$f"
  refute grep -q '^security=' "$f"
  grep -qx 'fix_passes=1' "$f"
}

@test "a fix pass reaches a push, which is the whole point of clearing the phases" {
  cd "$(new_repo main)"
  full_gate
  guard fix-pass
  git commit -q --allow-empty -m "the fix"
  guard record checks
  guard record review
  guard record security
  run guard push-ok
  [ "$status" -eq 0 ]
}

@test "fix-pass takes no argument" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: ship-guard open | record <phase> | check <phase> | fix-pass | push-ok"* ]]
}

@test "the fourth fix pass is refused" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass
  [[ "$output" == "fix pass 1 of 3" ]]
  run guard fix-pass
  [[ "$output" == "fix pass 2 of 3" ]]
  run guard fix-pass
  [[ "$output" == "fix pass 3 of 3" ]]
  run guard fix-pass
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: three fix passes already; revert to the minimal fix and stop"* ]]
}

@test "opening the gate again starts the fix count over" {
  cd "$(new_repo main)"
  guard open
  guard fix-pass
  guard fix-pass
  guard fix-pass
  guard open
  run guard fix-pass
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
  [[ "$output" == "finding: usage: ship-guard open | record <phase> | check <phase> | fix-pass | push-ok"* ]]
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

@test "record refuses to move a phase to a new commit without a fix pass" {
  cd "$(new_repo main)"
  full_gate
  recorded="$(short)"
  git commit -q --allow-empty -m "one more small fix"
  # The refusal push-ok prints says "record it again". Doing literally that is
  # how the gate gets walked past, so record has to refuse it.
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: review is already recorded at $recorded; a new commit needs a fix pass, or open the gate again"* ]]
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: security is already recorded at $recorded; a new commit needs a fix pass, or open the gate again"* ]]
}

@test "record at the commit already recorded is allowed, so a repeated call is not a trap" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  run guard record checks
  [ "$status" -eq 0 ]
}

@test "push-ok refuses when the checks are older than the commit going out" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  checked="$(short)"
  git commit -q --allow-empty -m "committed after the suite ran"
  head="$(short)"
  guard record review
  guard record security
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the checks covered $checked, not HEAD $head; open a fix pass and record every phase again"* ]]
}

@test "a fix count that is not a number is a finding, not a fresh gate" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  sed -i.bak 's/^fix_passes=0$/fix_passes=three/' "$f" && rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's fix count is not a number; open the gate again"* ]]
  run guard fix-pass
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's fix count is not a number; open the gate again"* ]]
}

@test "record and push-ok refuse a fix that was never committed" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  guard record review
  echo "the fix" > tracked.txt
  git add tracked.txt
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worktree has uncommitted changes; the push would not carry them"* ]]
  git commit -q -m "the fix"
  guard open && guard record checks && guard record review && guard record security
  echo "forgotten" >> tracked.txt
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worktree has uncommitted changes; the push would not carry them"* ]]
}

@test "untracked files do not block the gate, because ship worktrees carry env files" {
  cd "$(new_repo main)"
  full_gate
  echo "SECRET=x" > .env
  run guard push-ok
  [ "$status" -eq 0 ]
}
