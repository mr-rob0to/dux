load helpers/setup

# dux-result reads Dux's own run record, the repository, and GitHub. It never
# reads a worker's claim, so the fixtures below are the whole of its input.
prepare() {  # $1 shape, $2 optional project name; sets $id, $wt, $runid
  ctx_repo="acme/proj"; ctx_plan="docs/plan.md"; ctx_tasks="1-2"
  id="$(fixture_task "${2:-proj}" "$1")"
  wt="$(dux-worktree create "$id")"
  runid=a1b2c3d4
  git -C "$wt" remote set-url origin "https://github.com/$ctx_repo.git"
  write_run "$1"
}

# The two files dux-worker-wrap writes before it starts a worker. $ctx_repo and
# $ctx_plan let one test change one recorded fact; the run record is hashed from
# whatever the context ends up saying, exactly as the wrapper hashes it.
write_run() {  # $1 shape
  local ctx="$DUX_HOME/state/$id.result-context"
  {
    echo "version=1"; echo "id=$id"; echo "run=$runid"; echo "shape=$1"
    echo "project=proj"; echo "repo=$ctx_repo"; echo "base=main"; echo "branch=dux/$id"
    echo "worktree=$wt"
    if [ "$1" = ship ]; then echo "plan=$ctx_plan"; echo "tasks=$ctx_tasks"
    else echo "plan="; echo "tasks="; fi
  } > "$ctx"
  {
    echo "version=1"; echo "id=$id"; echo "run=$runid"; echo "wrapper=$$"
    echo "shape=$1"; echo "worktree=$wt"; echo "channel=$DUX_HOME/state/channels/$id.$runid"
    echo "context=$(git hash-object "$ctx")"
  } > "$DUX_HOME/state/$id.run"
}

commit_file() {  # $1 path, $2 content, $3 optional chmod
  mkdir -p "$(dirname "$wt/$1")"
  printf '%s\n' "$2" > "$wt/$1"
  [ -z "${3:-}" ] || chmod "$3" "$wt/$1"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "add $1"
}

# One open pull request at the branch head, in the recorded repository.
pr_at_head() {
  local sha; sha="$(git -C "$wt" rev-parse HEAD)"
  FAKE_GH_PR_LIST="$(jq -nc --arg b "dux/$id" --arg s "$sha" \
    '[{number:7,url:"https://github.com/acme/proj/pull/7",isDraft:false,state:"OPEN",
       baseRefName:"main",headRefName:$b,headRefOid:$s,
       headRepository:{name:"proj"},headRepositoryOwner:{login:"acme"}}]')"
  export FAKE_GH_PR_LIST
}

# $1 a jq assignment applied to that pull request, so each test changes one fact.
pr_with() {
  pr_at_head
  FAKE_GH_PR_LIST="$(printf '%s' "$FAKE_GH_PR_LIST" | jq -c "map($1)")"
  export FAKE_GH_PR_LIST
}

green_checks() { export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"}]'; }

plan_docs() {  # a docs-only change that satisfies the plan shape
  commit_file docs/specs/design.md "# Design"
  commit_file docs/plans/plan.md "# Plan"
}

ship_plan() {  # $1 the box for task 2: x or a space; $2 optional path
  local f="${2:-docs/plan.md}"
  mkdir -p "$(dirname "$wt/$f")"
  { echo "# Plan"; echo; echo "## Task 1: one"; echo "- [x] done"; echo
    echo "## Task 2: two"; echo "- [$1] also done"; } > "$wt/$f"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "plan"
}

ship_plan_h3() {  # the same plan with the heading depth every merged plan uses
  local f="${2:-docs/plan.md}"
  mkdir -p "$(dirname "$wt/$f")"
  { echo "# Plan"; echo; echo "## Tasks"; echo
    echo "### Task 1: one"; echo "- [x] done"; echo
    echo "### Task 2: two"; echo "- [$1] also done"; } > "$wt/$f"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "plan"
}

receipt_of() {  # $1.. the phases to file, in the order given
  local r="$DUX_HOME/state/$id.ship-receipt" p sha
  sha="$(git -C "$wt" rev-parse HEAD)"
  { echo "version=1"; echo "id=$id"; echo "run=$runid"; echo "branch=dux/$id"; } > "$r"
  for p in "$@"; do printf 'phase=%s sha=%s at=2026-09-05T00:00:00Z\n' "$p" "$sha" >> "$r"; done
}

# ---- the run record ------------------------------------------------------

@test "a run that is not the recorded run, or a changed context, is a finding" {
  prepare scout
  run dux-result verify "$id" wrongrun
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: run wrongrun is not the run recorded for $id"* ]]
  printf 'worktree=/elsewhere\n' >> "$DUX_HOME/state/$id.result-context"
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the result context for $id changed after the run started"* ]]
}

@test "no run record at all is a finding, not a result" {
  prepare scout
  rm -f "$DUX_HOME/state/$id.run"
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no run record for $id at state/$id.run"* ]]
}

# ---- scout ---------------------------------------------------------------

@test "a bounded report with text in it completes a scout, and nothing else does" {
  prepare scout
  printf '# Findings\nall clear\n' > "$DUX_HOME/report"
  run dux-result verify "$id" "$runid" --report "$DUX_HOME/report"
  [ "$status" -eq 0 ]
  [ "$output" = "done: report" ]
}

@test "a scout without usable report text has no result" {
  prepare scout
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no report was proposed"* ]]
  printf '   \n\t\n' > "$DUX_HOME/report"
  run dux-result verify "$id" "$runid" --report "$DUX_HOME/report"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no text in it"* ]]
  head -c 1100000 /dev/zero | tr '\0' 'x' > "$DUX_HOME/report"
  run dux-result verify "$id" "$runid" --report "$DUX_HOME/report"
  [ "$status" -eq 1 ]
  [[ "$output" == *"larger than 1 MiB"* ]]
}

@test "a pull request never completes a scout" {
  prepare scout
  plan_docs
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [ "$(grep -c 'pull/7' <<< "$output" || true)" -eq 0 ]
}

@test "a report never completes a plan or a ship" {
  prepare plan
  printf '# Findings\nall clear\n' > "$DUX_HOME/report"
  run dux-result verify "$id" "$runid" --report "$DUX_HOME/report"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--report is evidence for a scout task only"* ]]
}

# ---- the pull request ----------------------------------------------------

@test "a docs-only plan pull request completes, and the url is GitHub's" {
  prepare plan
  plan_docs
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}

@test "zero or two open pull requests is no result" {
  prepare plan
  plan_docs
  export FAKE_GH_PR_LIST='[]'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found 0"* ]]
  pr_at_head
  FAKE_GH_PR_LIST="$(printf '%s' "$FAKE_GH_PR_LIST" | jq -c '. + .')"
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found 2"* ]]
}

@test "a draft pull request is no result" {
  prepare plan
  plan_docs
  pr_with '.isDraft = true'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is a draft"* ]]
}

@test "a head in another repository is no result" {
  prepare plan
  plan_docs
  pr_with '.headRepositoryOwner.login = "someone-else"'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"someone-else/proj"* ]]
}

@test "the wrong base or the wrong head branch is no result" {
  prepare plan
  plan_docs
  pr_with '.baseRefName = "release"'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not based on main"* ]]
  pr_with '.headRefName = "dux/other"'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dux/other"* ]]
}

@test "a pull request head that is not the branch tip is no result" {
  prepare plan
  plan_docs
  pr_with '.headRefOid = "0000000000000000000000000000000000000000"'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not the tip of dux/$id"* ]]
}

@test "a url that does not belong to the recorded repository is never printed" {
  prepare plan
  plan_docs
  pr_with '.url = "https://evil.invalid/acme/proj/pull/7"'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not name pull request 7 of acme/proj"* ]]
  [ "$(grep -c 'evil.invalid' <<< "$output" || true)" -eq 0 ]
}

@test "a project with no GitHub repository has no pull request to prove" {
  prepare plan
  plan_docs
  ctx_repo="-"; write_run plan
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no GitHub repository is recorded"* ]]
}

@test "a silent GitHub is no result, never a guess" {
  prepare plan
  plan_docs
  pr_at_head
  export FAKE_GH_FAIL=1
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub did not answer"* ]]
}

@test "a dirty worktree, or one moved off the branch, is no result" {
  prepare plan
  plan_docs
  pr_at_head
  printf 'scratch\n' > "$wt/docs/plans/untracked.md"
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  rm -f "$wt/docs/plans/untracked.md"
  git -C "$wt" checkout -q --detach
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not on dux/$id"* ]]
}

# ---- the plan shape ------------------------------------------------------

@test "a plan pull request may only change docs, and needs a spec and a plan" {
  prepare plan
  plan_docs
  commit_file src/main.sh "echo hi"
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/main.sh"* ]]
}

@test "an executable or a nested html doc fails the plan shape" {
  prepare plan
  plan_docs
  commit_file docs/plans/run.md "# Run" 755
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/plans/run.md"* ]]
}

@test "a plan without a spec markdown is no result" {
  prepare plan
  commit_file docs/plans/plan.md "# Plan"
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/specs/"* ]]
}

@test "a plan without a plan markdown is no result" {
  prepare plan
  commit_file docs/specs/design.md "# Design"
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/plans/"* ]]
}

# ---- recording the /ship phases ------------------------------------------

@test "the five phases record in order against the branch tip" {
  prepare ship
  ship_plan x
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  for phase in checks review security pr ci; do
    run dux-result record-ship "$id" "$runid" "$phase"
    [ "$status" -eq 0 ]
  done
  r="$DUX_HOME/state/$id.ship-receipt"
  [ "$(sed -n 's/^phase=\([a-z]*\) .*/\1/p' "$r" | tr '\n' ' ')" = "checks review security pr ci " ]
  grep -qx "run=$runid" "$r"
  grep -qx "branch=dux/$id" "$r"
  [ "$(grep -c "sha=$(git -C "$wt" rev-parse HEAD)" "$r")" -eq 5 ]
}

@test "a phase out of order, repeated, or unknown is a finding" {
  prepare ship
  ship_plan x
  run dux-result record-ship "$id" "$runid" review
  [ "$status" -eq 2 ]
  [[ "$output" == *"is out of order; expected 'checks'"* ]]
  dux-result record-ship "$id" "$runid" checks
  run dux-result record-ship "$id" "$runid" checks
  [ "$status" -eq 2 ]
  [[ "$output" == *"is out of order; expected 'review'"* ]]
  run dux-result record-ship "$id" "$runid" audit
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown /ship phase 'audit'"* ]]
}

@test "the ci phase refuses until GitHub agrees the checks are green" {
  prepare ship
  ship_plan x
  commit_file src/main.sh "echo hi"
  pr_at_head
  for phase in checks review security pr; do dux-result record-ship "$id" "$runid" "$phase"; done
  export FAKE_GH_PR_CHECKS='[]'
  run dux-result record-ship "$id" "$runid" ci
  [ "$status" -eq 2 ]
  [[ "$output" == *"reported no checks"* ]]
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"FAILURE"}]'
  run dux-result record-ship "$id" "$runid" ci
  [ "$status" -eq 2 ]
  [[ "$output" == *"build"* ]]
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SKIPPED"}]'
  run dux-result record-ship "$id" "$runid" ci
  [ "$status" -eq 2 ]
  [[ "$output" == *"no check succeeded"* ]]
  [ "$(grep -c '^phase=ci ' "$DUX_HOME/state/$id.ship-receipt" || true)" -eq 0 ]
}

@test "only a ship task records phases, and only for its own run" {
  prepare scout
  run dux-result record-ship "$id" "$runid" checks
  [ "$status" -eq 2 ]
  [[ "$output" == *"only ship tasks record"* ]]
  prepare ship other
  run dux-result record-ship "$id" wrongrun checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: run wrongrun is not the run recorded for $id"* ]]
}

# ---- the ship shape ------------------------------------------------------

@test "checked tasks, an implementation file, five phases and green checks complete a ship" {
  prepare ship
  ship_plan x
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  for phase in checks review security pr ci; do dux-result record-ship "$id" "$runid" "$phase"; done
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}

@test "a plan whose tasks are third-level headings completes a ship" {
  # Every plan merged so far writes its tasks as "### Task N" under a "## Tasks"
  # heading. The reader accepted "## Task N" only, so it found no task at all
  # and rejected work that was really finished.
  prepare ship
  ship_plan_h3 x
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  for phase in checks review security pr ci; do dux-result record-ship "$id" "$runid" "$phase"; done
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}

@test "an unchecked third-level task is no result" {
  # The depth must not cost the guard: an unticked box still stops the result.
  prepare ship
  ship_plan_h3 ' '
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 2 in docs/plan.md still has an unchecked box"* ]]
}

@test "a deeper heading inside a task does not cut the task short" {
  # "#### Steps" under a task must stay part of that task, or the boxes below
  # it become invisible and a finished task reads as one with no boxes.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo; echo "## Task 1: one"; echo "- [x] done"; echo
    echo "## Task 2: two"; echo; echo "#### Steps"; echo "- [x] also done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  for phase in checks review security pr ci; do dux-result record-ship "$id" "$runid" "$phase"; done
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}

@test "a tilde fence and an indented fence hide nothing either" {
  # Markdown opens a fenced block with backticks or tildes, at any indent up to
  # three spaces. Reading only one of those forms let a heading inside the
  # others end the task and drop the boxes below it.
  prepare ship
  mkdir -p "$wt/docs"
  tilde='~~~'; fence='```'
  { echo "# Plan"; echo; echo "## Task 1: one"
    echo "$tilde"; echo "## Task 2: quoted in tildes"; echo "$tilde"
    echo "  ${fence}bash"; echo "## Task 2: quoted indented"; echo "  $fence"
    echo "- [ ] not done at all"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a star or plus bullet is a checkbox too" {
  # Markdown takes -, * and + as list markers, and all three render as a box.
  # Reading only the dash made an unticked star box invisible to the guard.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo; echo "## Task 1: one"; echo "* [ ] not done at all"; echo
    echo "## Task 2: two"; echo "+ [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a heading at a task's own level that is not a task never ends the task" {
  # Only a task heading ends a task. A sibling section such as "### Notes", a
  # deeper heading and a pasted shell comment all stay inside the task, so the
  # boxes under them still count. The unchecked box is put below all three:
  # it is only reached if none of them ended the task, so a plan that is read
  # whole rejects here and a plan cut short at any of them passes by mistake.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo; echo "## Tasks"; echo
    echo "### Task 1: one"; echo "- [x] done"
    echo "#### Steps"; echo "- [x] stepped"
    echo "### Notes"; echo "# a pasted comment"; echo "- [ ] not done at all"; echo
    echo "### Task 2: two"; echo "- [x] also done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a task heading quoted in a fenced block does not start a task" {
  # A plan that shows the shape of a task quotes a task heading inside an
  # example block, and plans paste shell, whose comments open with the
  # character a heading opens with. Reading either as a real heading ends the
  # task there and drops every box below it, so an unfinished task reads as a
  # finished one.
  prepare ship
  mkdir -p "$wt/docs"
  fence='```'
  { echo "# Plan"; echo; echo "## Task 1: one"; echo "${fence}bash"
    echo "# a comment, not a heading"; echo "## Task 2: quoted, not real"; echo "$fence"
    echo "- [ ] not done at all"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a subsection inside a task cannot hide an unchecked box" {
  # A section ends at a heading of the same depth or shallower, never at a
  # deeper one. Ending "## Task 1" at "### Verification" would drop every box
  # below it, and an unfinished task would read as a finished one.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo; echo "## Task 1: one"; echo "- [x] done"; echo
    echo "### Verification"; echo "- [ ] not done at all"; echo
    echo "## Task 2: two"; echo "- [x] also done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "an unchecked task in the brief's range is no result" {
  prepare ship
  ship_plan ' '
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 2 in docs/plan.md still has an unchecked box"* ]]
}

@test "a ship pull request that changes nothing but documents is no result" {
  prepare ship
  ctx_plan="docs/plans/plan.md"; write_run ship
  ship_plan x "$ctx_plan"
  commit_file docs/specs/design.md "# Design"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs an implementation file"* ]]
}

@test "a receipt that is short, out of order, or from another commit is no result" {
  prepare ship
  ship_plan x
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not the five phases in order"* ]]
  receipt_of checks security review pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not the five phases in order"* ]]
  receipt_of checks review security pr ci
  commit_file src/more.sh "echo more"
  pr_at_head
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"recorded against another commit"* ]]
}

@test "a ship with no checks, or one that is not green, is no result" {
  prepare ship
  ship_plan x
  commit_file src/main.sh "echo hi"
  pr_at_head
  receipt_of checks review security pr ci
  export FAKE_GH_PR_CHECKS='[]'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reported no checks"* ]]
  export FAKE_GH_PR_CHECKS='[{"name":"build","state":"SUCCESS"},{"name":"lint","state":"PENDING"}]'
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lint"* ]]
}

# ---- the wrapper and the verifier agree ----------------------------------

@test "the run record a real wrapper writes is one dux-result reads" {
  id="$(fixture_task proj scout)"
  wt="$(dux-worktree create "$id")"
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script" DUX_WRAP_POLL_SECS=1 DUX_HEARTBEAT_SECS=1
  printf 'run printf "# Findings\\nall clear\\n" > "$DUX_REPORT"\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  (cd "$wt" && DUX_BACKEND=tmux dux-worker-wrap "$id")
  runid="$(sed -n 's/^run=//p' "$DUX_HOME/state/$id.run")"
  [ -n "$runid" ]
  run dux-result verify "$id" "$runid" --report "$DUX_HOME/data/tasks/$id/report.md"
  [ "$status" -eq 0 ]
  [ "$output" = "done: report" ]
}

@test "task 1 does not answer for task 10" {
  # A plan may run to twelve tasks, so "Task 1" and "Task 10" both exist. If the
  # heading match is a plain prefix, task 1 swallows task 10 and answers with
  # its boxes: an unfinished task 10 fails a ship that only claimed task 1, and
  # a finished task 10 would let an unfinished task 1 through.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "- [x] done"; echo
    echo "## Task 2: two"; echo "- [x] done"; echo
    echo "## Task 10: ten, not yet started"; echo "- [ ] not done at all"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}

@test "task 10 is proved by its own boxes, not by task 1's" {
  # The other direction: naming task 10 must read task 10. A prefix match makes
  # "Task 1" the last heading that set the section, so task 10 would be proved
  # by task 1's ticked box and its own unticked one would never be seen.
  prepare ship
  ctx_tasks="10"; write_run ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "- [x] done"; echo
    echo "## Task 10: ten"; echo "- [ ] not done at all"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 10 in docs/plan.md still has an unchecked box"* ]]
}

@test "a heading too deep for Markdown never ends a task" {
  # Markdown stops making headings at six hashes; a seventh makes it plain text.
  # A reader that ends a task on it drops every box below it, so a worker could
  # park an unfinished half of the task behind a line that renders as prose.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "- [x] the easy half"
    echo "####### Task 99 marker"; echo "- [ ] the hard half"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a tilde line inside a backtick block does not close it" {
  # A fenced block closes only on the marker that opened it. Treating any fence
  # line as a toggle lets a tilde line inside a backtick block close it early,
  # which exposes a quoted task heading, ends the real task and hides the boxes
  # after the block.
  prepare ship
  mkdir -p "$wt/docs"
  fence='```'; tilde='~~~'
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "$fence"; echo "$tilde"
    echo "## Task 9: quoted, not real"; echo "$fence"
    echo "- [ ] the hard half"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "a ticked box quoted in a fenced block is not proof of work" {
  # Plans show what a task looks like, and the example carries a ticked box.
  # Counting it means a task with no real boxes at all reads as finished, so
  # the check that a task has boxes to tick proves nothing.
  prepare ship
  mkdir -p "$wt/docs"
  fence='```'
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "${fence}markdown"
    echo "- [x] this is only an example"; echo "$fence"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md has no checkboxes to prove it was done"* ]]
}

@test "an unchecked box counts however the plan happens to write it" {
  # GitHub renders all of these as an unchecked box: two spaces after the
  # bullet, a tab indent, a star bullet and a numbered item. A narrower reader
  # misses them and swears the task is finished while the rendered plan shows
  # the empty box.
  prepare ship
  mkdir -p "$wt/docs"
  commit_file src/main.sh "echo hi"
  for shape in '-  [ ] two spaces' "$(printf '\t- [ ] tab indented')" '* [ ] a star' '1. [ ] numbered'; do
    { echo "# Plan"; echo
      echo "## Task 1: one"; echo "- [x] the easy half"; printf '%s\n' "$shape"; echo
      echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
    git -C "$wt" add -A; git -C "$wt" commit -q -m "plan $shape"
    pr_at_head; green_checks
    rm -f "$DUX_HOME/state/$id.ship-receipt"
    receipt_of checks review security pr ci
    run dux-result verify "$id" "$runid"
    [ "$status" -eq 1 ] || { echo "accepted [$shape] as finished"; echo "$output"; return 1; }
    [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]] \
      || { echo "wrong reject for [$shape]: $output"; return 1; }
  done
}

@test "a sub-heading of a task does not end the task" {
  # Merged plans break a long task into "Task 0(a)", "Task 0(b)". Those are
  # parts of task 0, not tasks. Ending task 0 at its own first sub-heading
  # leaves it with no boxes, which rejected work that was really finished: the
  # merged milestone 3 plan reads 28 ticked boxes for task 0 and read none
  # before this.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "### Task 0: leftovers"; echo "- [x] the first half"
    echo "#### Task 0(a): the first part"; echo "- [x] done"
    echo "#### Task 0(b): the second part"; echo "- [ ] not done at all"; echo
    echo "### Task 1: one"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  ctx_tasks="0-1"; write_run ship
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 0 in docs/plan.md still has an unchecked box"* ]]
}

@test "the merged plans verify as the finished work they are" {
  # The reader is only worth anything if it agrees with the plans in this
  # repository. It matched none of them once, which is the defect this branch
  # started from, so the real files are the fixture and the real command is
  # what reads them. Milestone 3 task 0 is the one that carries "Task 0(a)"
  # sub-headings; milestone 4 is the plainest plan merged.
  local plan range i=0
  for plan in "docs/plans/2026-09-04-dux-m3-supervision.md 0-7" \
              "docs/plans/2026-09-06-dux-m4-intake.md 1-4"; do
    set -- $plan
    range="$2"
    [ -f "$DUX_ROOT/$1" ] || { echo "missing $1"; return 1; }
    i=$((i + 1))
    prepare ship "proj$i"
    mkdir -p "$wt/docs"
    cp "$DUX_ROOT/$1" "$wt/docs/plan.md"
    git -C "$wt" add -A; git -C "$wt" commit -q -m plan
    commit_file src/main.sh "echo hi"
    ctx_tasks="$range"; write_run ship
    pr_at_head; green_checks
    receipt_of checks review security pr ci
    run dux-result verify "$id" "$runid"
    [ "$status" -eq 0 ] \
      || { echo "$1 tasks $range did not verify:"; echo "$output"; return 1; }
  done
}

@test "a sub-heading naming another task does not end this one" {
  # "#### Task 2(a)" is a note inside task 1, not the start of task 2: Markdown
  # renders it as a sub-heading and the number in it is a reference. Reading it
  # as the next task ends task 1 there and drops the boxes below it, which is
  # how a worker parks the unfinished half of a task behind a line that reads
  # as prose.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "- [x] the easy half"
    echo "#### Task 2(a) is out of scope here"; echo "- [ ] the hard half"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

@test "an unchecked box inside a blockquote still counts" {
  # A plan quotes a review comment or a leftover TODO, and the quote carries an
  # unchecked box. GitHub renders it as an unchecked box like any other. This
  # one is worth catching because it happens by accident, not by design.
  prepare ship
  mkdir -p "$wt/docs"
  { echo "# Plan"; echo
    echo "## Task 1: one"; echo "- [x] the easy half"
    echo "> still to do:"; echo "> - [ ] the hard half"; echo
    echo "## Task 2: two"; echo "- [x] done"; } > "$wt/docs/plan.md"
  git -C "$wt" add -A; git -C "$wt" commit -q -m plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  receipt_of checks review security pr ci
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 1 in docs/plan.md still has an unchecked box"* ]]
}

# ---- the plan template and the reader that proves a plan finished ---------

template_plan() {  # the shipped template, with its boxes ticked
  local f="docs/plan.md"
  mkdir -p "$(dirname "$wt/$f")"
  sed 's/^- \[ \]/- [x]/' "$DUX_ROOT/docs/plans/TEMPLATE.md" \
    | awk '{ print } /^## Task 2:/ { print ""; print "- [x] the box the template leaves to the author" }' \
    > "$wt/$f"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "plan"
}

@test "a plan written from the shipped template is one the reader accepts" {
  # The template and this reader are two files nothing held together, and they
  # drifted: plans written the template's way read as having no tasks at all.
  # This is what pins them, so a change to either is a red test.
  prepare ship
  template_plan
  commit_file src/main.sh "echo hi"
  pr_at_head; green_checks
  for phase in checks review security pr ci; do dux-result record-ship "$id" "$runid" "$phase"; done
  run dux-result verify "$id" "$runid"
  [ "$status" -eq 0 ]
  [ "$output" = "done: PR https://github.com/acme/proj/pull/7" ]
}
