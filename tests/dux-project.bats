load helpers/setup

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

@test "add refuses a symlinked .github and writes nothing anywhere" {
  make_repo "$DUX_HOME/repoI" main
  mkdir -p "$DUX_HOME/outside"; ln -s "$DUX_HOME/outside" "$DUX_HOME/repoI/.github"
  run dux-project add repoI "$DUX_HOME/repoI"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to write through a symlink"* ]]
  [ -z "$(ls -A "$DUX_HOME/outside")" ]
  ! grep -q '^- repoI ' "$DUX_HOME/data/projects.md"
}

@test "add refuses a dangling template symlink instead of writing through it" {
  make_repo "$DUX_HOME/repoJ" main
  mkdir -p "$DUX_HOME/repoJ/.github"; ln -s "$DUX_HOME/victim.md" "$DUX_HOME/repoJ/.github/PULL_REQUEST_TEMPLATE.md"
  run dux-project add repoJ "$DUX_HOME/repoJ"
  [ "$status" -eq 2 ]
  [ ! -e "$DUX_HOME/victim.md" ]
}

@test "add refuses a name with characters outside [A-Za-z0-9._-]" {
  make_repo "$DUX_HOME/repoK" main
  run dux-project add '.*' "$DUX_HOME/repoK"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project name must match"* ]]
}

@test "add refuses a path containing whitespace" {
  make_repo "$DUX_HOME/re po" main
  run dux-project add repo "$DUX_HOME/re po"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project path must not contain whitespace"* ]]
}

@test "add refuses the same path under a second name" {
  make_repo "$DUX_HOME/repoL" main
  dux-project add repoL "$DUX_HOME/repoL"
  run dux-project add repoL2 "$DUX_HOME/repoL"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: path $DUX_HOME/repoL already registered as repoL"* ]]
}

@test "add refuses a flag-shaped --base" {
  make_repo "$DUX_HOME/repoM" main
  run dux-project add repoM "$DUX_HOME/repoM" --base --force
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: base branch name is not valid: --force"* ]]
}

@test "resolve-base refuses a flag-shaped docs signal when it is the only one" {
  make_repo "$DUX_HOME/repoN" main
  (cd "$DUX_HOME/repoN" && git remote set-head origin --delete)
  printf 'The base branch is `--prune`.\n' > "$DUX_HOME/repoN/CLAUDE.md"
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project resolve-base "$DUX_HOME/repoN"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: base branch signal is not a valid branch name: --prune"* ]]
}

@test "add is a finding when .github cannot be created, and nothing is registered" {
  make_repo "$DUX_HOME/repoO" main
  chmod 555 "$DUX_HOME/repoO"
  run dux-project add repoO "$DUX_HOME/repoO"
  chmod 755 "$DUX_HOME/repoO"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot create $DUX_HOME/repoO/.github"* ]]
  ! grep -q '^- repoO ' "$DUX_HOME/data/projects.md"
}

@test "add is a finding when the template cannot be written" {
  make_repo "$DUX_HOME/repoP" main
  mkdir -p "$DUX_HOME/repoP/.github"; chmod 555 "$DUX_HOME/repoP/.github"
  run dux-project add repoP "$DUX_HOME/repoP"
  chmod 755 "$DUX_HOME/repoP/.github"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot write $DUX_HOME/repoP/.github/PULL_REQUEST_TEMPLATE.md"* ]]
  ! grep -q '^- repoP ' "$DUX_HOME/data/projects.md"
}

@test "add honors --worktree and validates it against the repo" {
  make_repo "$DUX_HOME/repoQ" main
  printf 'worktree:\n\t@echo wt\n' > "$DUX_HOME/repoQ/Makefile"
  dux-project add repoQ "$DUX_HOME/repoQ" --worktree git
  [ "$(dux-project get repoQ worktree)" = git ]
  make_repo "$DUX_HOME/repoR" main
  run dux-project add repoR "$DUX_HOME/repoR" --worktree make
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no worktree target in $DUX_HOME/repoR/Makefile"* ]]
  run dux-project add repoR "$DUX_HOME/repoR" --worktree zip
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: --worktree must be make, script, or git"* ]]
  ! grep -q '^- repoR ' "$DUX_HOME/data/projects.md"
}
