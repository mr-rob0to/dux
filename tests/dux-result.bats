load helpers/setup

# dux-result reads Dux's own run record, the repository, and GitHub. It never
# reads a worker's claim, so the fixtures below are the whole of its input.
prepare() {  # $1 shape, $2 optional project name; sets $id, $wt, $runid
  ctx_repo="acme/proj"; ctx_plan="docs/plan.md"
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
    if [ "$1" = ship ]; then echo "plan=$ctx_plan"; echo "tasks=1-2"
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
