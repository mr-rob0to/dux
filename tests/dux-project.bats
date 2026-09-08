load helpers/setup

@test "a missing argument is a usage finding, not a bash error, for every subcommand" {
  run dux-project add
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: dux-project add <path> [--name <name>] [--base <branch>] [--issues off|label:<name>] [--worktree make|script|git] [--pr-template install|skip]" ]]
  run dux-project add --name onlyaname
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-project add"* ]]
  run dux-project get repoA
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-project get <name> <key>" ]]
  run dux-project resolve-base
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-project resolve-base <path>" ]]
  run dux-project pr-template
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-project pr-template <path>" ]]
  run dux-project frobnicate
  [ "$status" -eq 2 ]; [[ "$output" == "finding: usage: dux-project add|list|get|resolve-base|pr-template" ]]
  [ "$(grep -c 'line [0-9]' <<< "$output" || true)" -eq 0 ]
}

@test "an unknown flag on add is a usage finding and registers nothing" {
  make_repo "$DUX_HOME/repoS" main
  run dux-project add "$DUX_HOME/repoS" --colour red
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: dux-project add"* ]]
  [ ! -s "$DUX_HOME/data/projects.md" ]
}

@test "add derives the name from the folder" {
  make_repo "$DUX_HOME/repoT" main
  run dux-project add "$DUX_HOME/repoT"
  [ "$status" -eq 0 ]
  [ "$(dux-project get repoT path)" = "$DUX_HOME/repoT" ]
}

@test "add --name overrides the folder name" {
  make_repo "$DUX_HOME/repoU" main
  dux-project add "$DUX_HOME/repoU" --name api
  run dux-project list
  [ "$output" = api ]
  [ "$(dux-project get api path)" = "$DUX_HOME/repoU" ]
}

@test "add refuses a folder name outside the id charset and says to pass --name" {
  make_repo "$DUX_HOME/my repo" main
  run dux-project add "$DUX_HOME/my repo"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project path must not contain whitespace"* ]]
  mkdir -p "$DUX_HOME/hold"; make_repo "$DUX_HOME/hold/a:b" main
  run dux-project add "$DUX_HOME/hold/a:b"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: folder name 'a:b' is not usable as a project name; pass --name"* ]]
  [ ! -s "$DUX_HOME/data/projects.md" ]
}

@test "add refuses a derived name that is already registered and names the flag" {
  mkdir -p "$DUX_HOME/one" "$DUX_HOME/two"
  make_repo "$DUX_HOME/one/api" main; make_repo "$DUX_HOME/two/api" main
  dux-project add "$DUX_HOME/one/api"
  run dux-project add "$DUX_HOME/two/api"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project api already registered; pass --name to register it under another name"* ]]
  dux-project add "$DUX_HOME/two/api" --name api2
  [ "$(dux-project get api2 path)" = "$DUX_HOME/two/api" ]
}

@test "the old two-positional form is a usage finding, not a registration" {
  make_repo "$DUX_HOME/repoV" main
  run dux-project add repoV "$DUX_HOME/repoV"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: dux-project add"* ]]
  [ ! -s "$DUX_HOME/data/projects.md" ]
}

@test "add writes a registry line with detected git worktree mechanism" {
  make_repo "$DUX_HOME/repoA" main
  run dux-project add "$DUX_HOME/repoA"
  [ "$status" -eq 0 ]
  line="$(grep '^- repoA ' "$DUX_HOME/data/projects.md")"
  [[ "$line" == "- repoA path=$DUX_HOME/repoA base=main worktree=git issues=off (added "* ]]
}

@test "add detects make worktree target" {
  make_repo "$DUX_HOME/repoB" main
  printf 'worktree:\n\t@echo wt\n' > "$DUX_HOME/repoB/Makefile"
  dux-project add "$DUX_HOME/repoB"
  [ "$(dux-project get repoB worktree)" = "make" ]
}

@test "add honors --base and --issues" {
  make_repo "$DUX_HOME/repoC" main
  dux-project add "$DUX_HOME/repoC" --base staging --issues label:dux
  [ "$(dux-project get repoC base)" = "staging" ]
  [ "$(dux-project get repoC issues)" = "label:dux" ]
}

@test "add refuses an issue label with a space and one with no name" {
  # The registry is one line per project, read by splitting on spaces. Stored
  # whole, "ready for dux" reads back as "label:ready" and intake pulls the
  # issues of a label the operator never asked for.
  make_repo "$DUX_HOME/repoS" main
  run dux-project add "$DUX_HOME/repoS" --issues 'label:ready for dux'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: --issues label must not contain spaces: label:ready for dux" ]]
  run dux-project list
  # Single brackets compare literally; this has to be [[ ]] to glob at all.
  [[ "$output" != *repoS* ]]
  run dux-project add "$DUX_HOME/repoS" --issues 'label:'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: --issues must be off or label:<name>" ]]
}

@test "add refuses a duplicate name with a finding" {
  make_repo "$DUX_HOME/repoD" main
  dux-project add "$DUX_HOME/repoD"
  run dux-project add "$DUX_HOME/repoD"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project repoD already registered"* ]]
}

@test "add refuses a path that is not a git repo" {
  mkdir -p "$DUX_HOME/notrepo"
  run dux-project add "$DUX_HOME/notrepo" --name x
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: not a git repository"* ]]
}

@test "add installs the PR template only on --pr-template install and leaves an existing one alone" {
  make_repo "$DUX_HOME/repoE" main
  dux-project add "$DUX_HOME/repoE" --pr-template install
  [ -f "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md" ]
  grep -q '^## How to review' "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md"
  make_repo "$DUX_HOME/repoF" main
  mkdir -p "$DUX_HOME/repoF/.github"; echo custom > "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md"
  # --separate-stderr, because the line being asserted is the one the caller
  # relays on stdout: log writes the same words to stderr, and a plain run merges
  # the two, so the log line alone would satisfy this while stdout said nothing.
  run --separate-stderr dux-project add "$DUX_HOME/repoF" --pr-template install
  [ "$(cat "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md")" = "custom" ]
  [[ "$output" == *"existing PR template left alone: .github/PULL_REQUEST_TEMPLATE.md"* ]]
}

@test "add stops with a finding when base signals disagree" {
  make_repo "$DUX_HOME/repoH" main
  printf '# Repo\n\nThe base branch is `staging`.\n' > "$DUX_HOME/repoH/CLAUDE.md"
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project add "$DUX_HOME/repoH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: base branch signals disagree"* ]]
  [ "$(grep -c '^- repoH ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

@test "add with a missing path is a finding, not a bash error" {
  run dux-project add "$DUX_HOME/does-not-exist" --name x
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
  dux-project add "$DUX_HOME/r1"; dux-project add "$DUX_HOME/r2"
  run dux-project list
  [ "$output" = $'r1\nr2' ]
}

@test "add refuses a symlinked .github and writes nothing anywhere" {
  make_repo "$DUX_HOME/repoI" main
  mkdir -p "$DUX_HOME/outside"; ln -s "$DUX_HOME/outside" "$DUX_HOME/repoI/.github"
  run dux-project add "$DUX_HOME/repoI" --pr-template install
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to write through a symlink"* ]]
  [ -z "$(ls -A "$DUX_HOME/outside")" ]
  [ "$(grep -c '^- repoI ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

@test "add refuses a dangling template symlink instead of writing through it" {
  make_repo "$DUX_HOME/repoJ" main
  mkdir -p "$DUX_HOME/repoJ/.github"; ln -s "$DUX_HOME/victim.md" "$DUX_HOME/repoJ/.github/PULL_REQUEST_TEMPLATE.md"
  run dux-project add "$DUX_HOME/repoJ" --pr-template install
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to write through a symlink"* ]]
  [ ! -e "$DUX_HOME/victim.md" ]
}

@test "add refuses a name with characters outside [A-Za-z0-9._-]" {
  make_repo "$DUX_HOME/repoK" main
  run dux-project add "$DUX_HOME/repoK" --name '.*'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project name must match"* ]]
}

@test "add refuses a name that is nothing but dots" {
  make_repo "$DUX_HOME/repoL" main
  run dux-project add "$DUX_HOME/repoL" --name ..
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project name must not be all dots"* ]]
  run dux-project add "$DUX_HOME/repoL" --name .
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project name must not be all dots"* ]]
  [ ! -s "$DUX_HOME/data/projects.md" ]
}

@test "add refuses a path containing whitespace" {
  make_repo "$DUX_HOME/re po" main
  run dux-project add "$DUX_HOME/re po" --name repo
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project path must not contain whitespace"* ]]
}

@test "add refuses the same path under a second name" {
  make_repo "$DUX_HOME/repoL" main
  dux-project add "$DUX_HOME/repoL"
  run dux-project add "$DUX_HOME/repoL" --name repoL2
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: path $DUX_HOME/repoL already registered as repoL"* ]]
}

@test "add refuses a flag-shaped --base" {
  make_repo "$DUX_HOME/repoM" main
  run dux-project add "$DUX_HOME/repoM" --base --force
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
  run dux-project add "$DUX_HOME/repoO" --pr-template install
  chmod 755 "$DUX_HOME/repoO"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot create $DUX_HOME/repoO/.github"* ]]
  [ "$(grep -c '^- repoO ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

@test "add is a finding when the template cannot be written" {
  make_repo "$DUX_HOME/repoP" main
  mkdir -p "$DUX_HOME/repoP/.github"; chmod 555 "$DUX_HOME/repoP/.github"
  run dux-project add "$DUX_HOME/repoP" --pr-template install
  chmod 755 "$DUX_HOME/repoP/.github"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot write $DUX_HOME/repoP/.github/PULL_REQUEST_TEMPLATE.md"* ]]
  [ "$(grep -c '^- repoP ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

@test "add honors --worktree and validates it against the repo" {
  make_repo "$DUX_HOME/repoQ" main
  printf 'worktree:\n\t@echo wt\n' > "$DUX_HOME/repoQ/Makefile"
  dux-project add "$DUX_HOME/repoQ" --worktree git
  [ "$(dux-project get repoQ worktree)" = git ]
  make_repo "$DUX_HOME/repoR" main
  run dux-project add "$DUX_HOME/repoR" --worktree make
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no worktree target in $DUX_HOME/repoR/Makefile"* ]]
  run dux-project add "$DUX_HOME/repoR" --worktree zip
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: --worktree must be make, script, or git"* ]]
  [ "$(grep -c '^- repoR ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

@test "add warns that a name shorter than four characters is not linted" {
  # bin/dux-install leaves such a name out of the identifier denylist. Registration
  # is still correct, so this is a log line and the exit status stays 0.
  # --separate-stderr, because the warning has to be on stderr: plain run merges the
  # two, so the same assertions would pass if it moved to stdout.
  make_repo "$DUX_HOME/repoW" main
  run --separate-stderr dux-project add "$DUX_HOME/repoW" --name abc
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"shorter than four characters"* ]]
  [[ "$stderr" == *"dux-project add --name"* ]]
  grep -q '^- abc ' "$DUX_HOME/data/projects.md"
  # Status and the registry line first: a run that ended in a finding also lacks the
  # warning, and would pass the absence check having proved nothing.
  make_repo "$DUX_HOME/repoX" main
  run --separate-stderr dux-project add "$DUX_HOME/repoX" --name abcd
  [ "$status" -eq 0 ]
  grep -q '^- abcd ' "$DUX_HOME/data/projects.md"
  [[ "$stderr" != *"shorter than four characters"* ]]
}

# Writing into a project repo is the one exception to "never write to a project
# repo", so it needs the operator's word. Without the flag nothing is written and
# the project is still registered: declining is a normal outcome, not a finding.
@test "add without consent writes no template and still registers" {
  make_repo "$DUX_HOME/repoAA" main
  run --separate-stderr dux-project add "$DUX_HOME/repoAA"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- repoAA ' "$DUX_HOME/data/projects.md" || true)" -eq 1 ]
  refute [ -e "$DUX_HOME/repoAA/.github/PULL_REQUEST_TEMPLATE.md" ]
  [[ "$output" == *"no PR template found; none installed"* ]]

  make_repo "$DUX_HOME/repoAB" main
  run dux-project add "$DUX_HOME/repoAB" --pr-template skip
  [ "$status" -eq 0 ]
  refute [ -e "$DUX_HOME/repoAB/.github/PULL_REQUEST_TEMPLATE.md" ]

  make_repo "$DUX_HOME/repoAE" main
  run dux-project add "$DUX_HOME/repoAE" --pr-template yes
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: --pr-template must be install or skip: yes"* ]]
  [ "$(grep -c '^- repoAE ' "$DUX_HOME/data/projects.md" || true)" -eq 0 ]
}

# GitHub does not say which template wins when a repo has more than one, so Dux
# never adds a second. A template anywhere GitHub reads one is left alone and its
# path reported, even when the operator asked for an install.
@test "add leaves a template outside .github alone and says where" {
  make_repo "$DUX_HOME/repoAC" main
  mkdir -p "$DUX_HOME/repoAC/docs"; echo custom > "$DUX_HOME/repoAC/docs/pull_request_template.md"
  run --separate-stderr dux-project add "$DUX_HOME/repoAC" --pr-template install
  [ "$status" -eq 0 ]
  refute [ -e "$DUX_HOME/repoAC/.github/PULL_REQUEST_TEMPLATE.md" ]
  [[ "$output" == *"existing PR template left alone: docs/pull_request_template.md"* ]]
}

# GitHub reads a pull request template from the repository root, from docs/, and
# from .github/, in any letter case, with any extension, and as a folder of
# several. This lists all of them so the skill can ask before anything is
# written. The fixture holds exactly one real match per directory, because glob
# order inside one directory follows the machine's locale: measured on macOS,
# en_US.UTF-8 sorts pull_request_template_old.md before pull_request_template.txt
# and C sorts it after. The near miss therefore sits in .github/, where the
# shorter PULL_REQUEST_TEMPLATE sorts first under both.
@test "pr-template lists every place GitHub reads a template from" {
  make_repo "$DUX_HOME/repoY" main
  run dux-project pr-template "$DUX_HOME/repoY"
  [ "$status" -eq 0 ]
  [ "$output" = none ]

  make_repo "$DUX_HOME/repoZ" main
  mkdir -p "$DUX_HOME/repoZ/docs" "$DUX_HOME/repoZ/.github/PULL_REQUEST_TEMPLATE"
  echo body > "$DUX_HOME/repoZ/PULL_REQUEST_TEMPLATE.md"
  echo body > "$DUX_HOME/repoZ/docs/pull_request_template.txt"
  echo body > "$DUX_HOME/repoZ/.github/PULL_REQUEST_TEMPLATE/one.md"
  echo body > "$DUX_HOME/repoZ/.github/pull_request_template_old.md"
  run dux-project pr-template "$DUX_HOME/repoZ"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "PULL_REQUEST_TEMPLATE.md" ]
  [ "${lines[1]}" = "docs/pull_request_template.txt" ]
  [ "${lines[2]}" = ".github/PULL_REQUEST_TEMPLATE/" ]
  [ "${#lines[@]}" -eq 3 ]

  run dux-project pr-template "$DUX_HOME/absent"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no such directory: "* ]]
}

# A directory named like the file form is not a template to GitHub. Matching it
# would make Dux report a template the repo does not have and decline to install.
@test "pr-template ignores a directory named like the file form" {
  make_repo "$DUX_HOME/repoAD" main
  mkdir -p "$DUX_HOME/repoAD/docs/PULL_REQUEST_TEMPLATE.md"
  run dux-project pr-template "$DUX_HOME/repoAD"
  [ "$status" -eq 0 ]
  [ "$output" = none ]
}
