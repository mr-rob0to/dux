load helpers/setup

hooks_env() {  # $1 id; prints the env assignments that activate the task's hooks dir
  echo "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=$DUX_HOME/data/tasks/$1/hooks"
}

register() {  # $1 name [--worktree m]; registers $DUX_HOME/<name> on main
  local n="$1"; shift
  make_repo "$DUX_HOME/$n" main
  dux-project add "$n" "$DUX_HOME/$n" --base main "$@" >/dev/null
}

with_makefile() {  # $1 name, $2 Makefile body: a repo registered with worktree=make
  make_repo "$DUX_HOME/$1" main
  printf '%s' "$2" > "$DUX_HOME/$1/Makefile"
  (cd "$DUX_HOME/$1" && git add Makefile && git commit -q -m makefile && git push -q origin main)
  dux-project add "$1" "$DUX_HOME/$1" --base main >/dev/null
  [ "$(dux-project get "$1" worktree)" = make ]
}
# A worktree target that picks its own path and leaves a marker.
custom_target='worktree:
	git worktree add .worktrees/custom-$(subst /,-,$(name)) -b $(name) origin/$(base)
	touch .worktrees/custom-$(subst /,-,$(name))/made-by-make
'

@test "scout under git: worktree at .worktrees/dux-<id> on dux/<id> at the origin tip, hooks dir built, no env copied" {
  register proj
  echo SECRET=1 > "$DUX_HOME/proj/.env"
  id="$(dux-task-new proj scout)"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ "$output" = "$wt" ]
  [ "$(git -C "$wt" branch --show-current)" = "dux/$id" ]
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$DUX_HOME/proj" rev-parse origin/main)" ]
  [ -x "$DUX_HOME/data/tasks/$id/hooks/pre-push" ]
  [ ! -e "$wt/.env" ]
  [ "$(dux-worktree path "$id")" = "$wt" ]
}

ignore_env() {  # $1 project name; the project ignores every .env variant
  printf '.worktrees/\n.env\n.env.*\n' > "$DUX_HOME/$1/.gitignore"
  (cd "$DUX_HOME/$1" && git add .gitignore && git commit -q -m "ignore env" && git push -q origin main)
}

@test "ship under git copies .env files but not examples or symlinks" {
  register proj
  ignore_env proj
  echo A=1 > "$DUX_HOME/proj/.env"; echo B=2 > "$DUX_HOME/proj/.env.local"
  echo X=0 > "$DUX_HOME/proj/.env.example"; ln -s .env "$DUX_HOME/proj/.env.link"
  id="$(dux-task-new proj ship)"
  wt="$(dux-worktree create "$id")"
  [ "$(cat "$wt/.env")" = A=1 ]; [ "$(cat "$wt/.env.local")" = B=2 ]
  [ ! -e "$wt/.env.example" ]; [ ! -e "$wt/.env.link" ]
}

@test "an env file the project does not ignore is a finding and nothing is copied" {
  register proj
  printf '.worktrees/\n.env\n' > "$DUX_HOME/proj/.gitignore"
  (cd "$DUX_HOME/proj" && git add .gitignore && git commit -q -m "ignore env" && git push -q origin main)
  echo A=1 > "$DUX_HOME/proj/.env"; echo B=2 > "$DUX_HOME/proj/.env.production"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: .env.production is not ignored in $DUX_HOME/proj"* ]]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ ! -e "$wt/.env" ]
  [ ! -e "$wt/.env.production" ]
}

@test "ship under make uses the project's target and discovers its path" {
  with_makefile proj "$custom_target"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/proj/.worktrees/custom-dux-$id" ]
  [ -f "$output/made-by-make" ]
  [ -s "$DUX_HOME/data/tasks/$id/worktree.log" ]
}

@test "plan under make ignores the mechanism and uses git worktree add" {
  with_makefile proj "$custom_target"
  id="$(dux-task-new proj plan)"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ ! -e "$DUX_HOME/proj/.worktrees/custom-dux-$id" ]
}

@test "ship under script runs scripts/*worktree* with branch and base" {
  make_repo "$DUX_HOME/proj" main
  mkdir -p "$DUX_HOME/proj/scripts"
  printf '#!/bin/sh\ngit worktree add ".worktrees/s-$(echo "$1" | tr / -)" -b "$1" "origin/$2" && echo "$1 $2" > .worktrees/script-args\n' > "$DUX_HOME/proj/scripts/worktree.sh"
  chmod +x "$DUX_HOME/proj/scripts/worktree.sh"
  (cd "$DUX_HOME/proj" && git add scripts && git commit -q -m script && git push -q origin main)
  dux-project add proj "$DUX_HOME/proj" --base main >/dev/null
  [ "$(dux-project get proj worktree)" = script ]
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/proj/.worktrees/s-dux-$id" ]
  [ "$(cat "$DUX_HOME/proj/.worktrees/script-args")" = "dux/$id main" ]
}

@test "a mechanism that creates no worktree on the branch is a finding" {
  with_makefile proj $'worktree:\n\t@echo nothing\n'
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: mechanism make created no worktree on dux/$id"* ]]
}

@test "a worktree that lands on the primary checkout is a finding" {
  with_makefile proj $'worktree:\n\tgit checkout -q -b $(name)\n'
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: worktree path equals the primary checkout"* ]]
}

@test "a worktree not at the origin tip is a finding" {
  with_makefile proj $'worktree:\n\tgit worktree add .worktrees/x -b $(name) main\n'
  (cd "$DUX_HOME/proj" && git commit -q --allow-empty -m local-only)
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: worktree $DUX_HOME/proj/.worktrees/x is at "*", not origin/main"* ]]
}

@test "create fetches first: a commit pushed by someone else is the tip" {
  register proj
  git clone -q "$DUX_HOME/proj.origin" "$DUX_HOME/elsewhere"
  (cd "$DUX_HOME/elsewhere" && git commit -q --allow-empty -m remote-work && git push -q origin main)
  want="$(git -C "$DUX_HOME/elsewhere" rev-parse HEAD)"
  id="$(dux-task-new proj scout)"
  wt="$(dux-worktree create "$id")"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$want" ]
}

@test "refuses .worktrees not ignored and an existing branch; reuses a clean worktree at the tip" {
  register proj
  : > "$DUX_HOME/proj/.gitignore"
  (cd "$DUX_HOME/proj" && git add .gitignore && git commit -q -m unignore && git push -q origin main)
  id="$(dux-task-new proj scout)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: .worktrees/ is not ignored in $DUX_HOME/proj"* ]]
  printf '.worktrees/\n' > "$DUX_HOME/proj/.gitignore"
  (cd "$DUX_HOME/proj" && git add .gitignore && git commit -q -m ignore && git push -q origin main)
  git -C "$DUX_HOME/proj" branch "dux/$id" origin/main
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id already exists"* ]]
  git -C "$DUX_HOME/proj" branch -D "dux/$id" >/dev/null
  wt="$(dux-worktree create "$id")"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]; [ "$(printf '%s\n' "$output" | tail -n 1)" = "$wt" ]; [[ "$output" == *"reusing clean worktree"* ]]
  (cd "$wt" && git commit -q --allow-empty -m work)
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: a worktree on dux/$id already exists and is not at origin/main"* ]]
}

@test "the pre-push hook refuses the base branch and allows the task branch" {
  register proj
  id="$(dux-task-new proj scout)"
  wt="$(dux-worktree create "$id")"
  (cd "$wt" && git commit -q --allow-empty -m work)
  run env $(hooks_env "$id") git -C "$wt" push -q origin "HEAD:refs/heads/main"
  [ "$status" -ne 0 ]
  [[ "$output" == *"finding: refusing to push to main from a Dux worktree"* ]]
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" != "$(git -C "$wt" rev-parse HEAD)" ]
  run env $(hooks_env "$id") git -C "$wt" push -q -u origin "dux/$id"
  [ "$status" -eq 0 ]
  run env $(hooks_env "$id") git -C "$wt" push -q origin "dux/$id:main"
  [ "$status" -ne 0 ]
}

@test "the hooks dir chains the project's own pre-push and links its other hooks" {
  register proj
  printf '#!/bin/sh\ncat > "$(git rev-parse --show-toplevel)/../upstream-saw-refs"\n' > "$DUX_HOME/proj/.git/hooks/pre-push"
  printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/proj/.git/hooks/pre-commit"
  chmod +x "$DUX_HOME/proj/.git/hooks/pre-push" "$DUX_HOME/proj/.git/hooks/pre-commit"
  id="$(dux-task-new proj scout)"
  wt="$(dux-worktree create "$id")"
  [ -L "$DUX_HOME/data/tasks/$id/hooks/pre-commit" ]
  [ ! -L "$DUX_HOME/data/tasks/$id/hooks/pre-push" ]
  (cd "$wt" && git commit -q --allow-empty -m work)
  env $(hooks_env "$id") git -C "$wt" push -q -u origin "dux/$id"
  grep -q "refs/heads/dux/$id" "$DUX_HOME/proj/.worktrees/upstream-saw-refs"
}

@test "a Worktrees section with worktree=git refuses ship and allows scout" {
  register proj
  printf '# Repo\n\n## Worktrees for this repo\n\nUse make worktree.\n' > "$DUX_HOME/proj/CLAUDE.md"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: proj declares a Worktrees section but is registered with worktree=git"* ]]
  id2="$(dux-task-new proj scout)"
  run dux-worktree create "$id2"
  [ "$status" -eq 0 ]
}

@test "remove refuses dirty, refuses unpushed, succeeds when pushed, keeps the branch, and is idempotent" {
  register proj
  id="$(dux-task-new proj scout)"
  wt="$(dux-worktree create "$id")"
  echo scratch > "$wt/scratch"
  run dux-worktree remove "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worktree $wt has uncommitted changes"* ]]
  rm "$wt/scratch"
  (cd "$wt" && git commit -q --allow-empty -m work)
  run dux-worktree remove "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id has 1 commit(s) and no upstream"* ]]
  (cd "$wt" && git push -q -u origin "dux/$id" && git commit -q --allow-empty -m more)
  run dux-worktree remove "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: worktree $wt has 1 unpushed commit(s)"* ]]
  (cd "$wt" && git push -q)
  run dux-worktree remove "$id"
  [ "$status" -eq 0 ]
  [ ! -d "$wt" ]
  git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"
  run dux-worktree remove "$id"
  [ "$status" -eq 0 ]; [[ "$output" == *"already removed"* ]]
  run dux-worktree path "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: no worktree on dux/$id"* ]]
}

@test "discard removes a fresh worktree and its branch, and refuses one with commits" {
  register proj
  id="$(dux-task-new proj scout)"
  wt="$(dux-worktree create "$id")"
  (cd "$wt" && git commit -q --allow-empty -m work)
  run dux-worktree discard "$id"
  [ "$status" -eq 2 ]; [[ "$output" == "finding: branch dux/$id has 1 commit(s); use remove, not discard"* ]]
  [ -d "$wt" ]
  (cd "$wt" && git reset -q --hard origin/main)
  run dux-worktree discard "$id"
  [ "$status" -eq 0 ]
  [ ! -d "$wt" ]
  ! git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"
  run dux-worktree discard "$id"
  [ "$status" -eq 0 ]
}

run_hook() {  # $1 hook, $2 remote ref name; feeds one pre-push line on stdin
  bash -c 'printf "refs/heads/local sha1 refs/heads/%s sha2\n" "$2" | "$1" origin url' _ "$1" "$2"
}

@test "the rendered hook never re-evaluates the base branch or the upstream path" {
  base='evil$(touch$IFS'"$DUX_HOME"'/pwned-base)'
  make_repo "$DUX_HOME/proj" "$base"
  dux-project add proj "$DUX_HOME/proj" --base "$base" >/dev/null
  git -C "$DUX_HOME/proj" config core.hooksPath 'hooks$(touch$IFS'"$DUX_HOME"'/pwned-upstream)'
  id="$(dux-task-new proj scout)"
  dux-worktree create "$id" >/dev/null
  run run_hook "$DUX_HOME/data/tasks/$id/hooks/pre-push" "$base"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to push to $base from a Dux worktree"* ]]
  [ ! -e "$DUX_HOME/pwned-base" ]
  [ ! -e "$DUX_HOME/pwned-upstream" ]
}

@test "the rendered hook exits 2 on a refused push and survives a quote in the base branch" {
  base="o'brien"
  make_repo "$DUX_HOME/proj" "$base"
  dux-project add proj "$DUX_HOME/proj" --base "$base" >/dev/null
  id="$(dux-task-new proj scout)"
  dux-worktree create "$id" >/dev/null
  hook="$DUX_HOME/data/tasks/$id/hooks/pre-push"
  run run_hook "$hook" "$base"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to push to $base from a Dux worktree"* ]]
  run run_hook "$hook" "dux/$id"
  [ "$status" -eq 0 ]
}
