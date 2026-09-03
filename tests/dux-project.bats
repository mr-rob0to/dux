load helpers/setup

make_repo() {  # $1 dir, $2 default branch; creates a bare origin and a clone
  local d="$1" b="$2"
  git init -q -b "$b" "$d.origin.tmp" && (cd "$d.origin.tmp" && git commit -q --allow-empty -m init)
  git clone -q --bare "$d.origin.tmp" "$d.origin" && rm -rf "$d.origin.tmp"
  git clone -q "$d.origin" "$d"
  (cd "$d" && git remote set-head origin "$b")
}

@test "add writes a registry line with detected git worktree mechanism" {
  make_repo "$DUX_HOME/repoA" main
  run dux-project add repoA "$DUX_HOME/repoA"
  [ "$status" -eq 0 ]
  line="$(grep '^- repoA ' "$DUX_HOME/data/projects.md")"
  [[ "$line" == "- repoA path=$DUX_HOME/repoA base=main worktree=git issues=off (added "* ]]
}

@test "add detects make worktree target" {
  make_repo "$DUX_HOME/repoB" main
  printf 'worktree:\n\t@echo wt\n' > "$DUX_HOME/repoB/Makefile"
  dux-project add repoB "$DUX_HOME/repoB"
  [ "$(dux-project get repoB worktree)" = "make" ]
}

@test "add honors --base and --issues" {
  make_repo "$DUX_HOME/repoC" main
  dux-project add repoC "$DUX_HOME/repoC" --base staging --issues label:dux
  [ "$(dux-project get repoC base)" = "staging" ]
  [ "$(dux-project get repoC issues)" = "label:dux" ]
}

@test "add refuses a duplicate name with a finding" {
  make_repo "$DUX_HOME/repoD" main
  dux-project add repoD "$DUX_HOME/repoD"
  run dux-project add repoD "$DUX_HOME/repoD"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project repoD already registered"* ]]
}

@test "add refuses a path that is not a git repo" {
  mkdir -p "$DUX_HOME/notrepo"
  run dux-project add x "$DUX_HOME/notrepo"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: not a git repository"* ]]
}

@test "add installs the PR template when absent and leaves an existing one" {
  make_repo "$DUX_HOME/repoE" main
  dux-project add repoE "$DUX_HOME/repoE"
  [ -f "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md" ]
  grep -q '^## How to review' "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md"
  make_repo "$DUX_HOME/repoF" main
  mkdir -p "$DUX_HOME/repoF/.github"; echo custom > "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md"
  run dux-project add repoF "$DUX_HOME/repoF"
  [ "$(cat "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md")" = "custom" ]
  [[ "$output" == *"existing PR template left alone"* ]]
}

@test "add stops with a finding when base signals disagree" {
  make_repo "$DUX_HOME/repoH" main
  printf '# Repo\n\nThe base branch is `staging`.\n' > "$DUX_HOME/repoH/CLAUDE.md"
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project add repoH "$DUX_HOME/repoH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: base branch signals disagree"* ]]
  ! grep -q '^- repoH ' "$DUX_HOME/data/projects.md"
}

@test "add with a missing path is a finding, not a bash error" {
  run dux-project add x "$DUX_HOME/does-not-exist"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: not a git repository"* ]]
}

@test "resolve-base uses origin/HEAD when gh is unavailable" {
  make_repo "$DUX_HOME/repoG" develop
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project resolve-base "$DUX_HOME/repoG"
  [ "$output" = "develop" ]
}

@test "list prints names in order" {
  make_repo "$DUX_HOME/r1" main; make_repo "$DUX_HOME/r2" main
  dux-project add r1 "$DUX_HOME/r1"; dux-project add r2 "$DUX_HOME/r2"
  run dux-project list
  [ "$output" = $'r1\nr2' ]
}
