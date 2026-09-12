bats_require_minimum_version 1.5.0
load helpers/setup

register() {  # $1 name [--worktree m]; registers $DUX_HOME/<name> on main
  local n="$1"; shift
  make_repo "$DUX_HOME/$n" main
  dux-project add "$DUX_HOME/$n" --base main --pr-template skip "$@" >/dev/null
}

with_makefile() {  # $1 name, $2 Makefile body: a repo registered with worktree=make
  make_repo "$DUX_HOME/$1" main
  printf '%s' "$2" > "$DUX_HOME/$1/Makefile"
  (cd "$DUX_HOME/$1" && git add Makefile && git commit -q -m makefile && git push -q origin main)
  dux-project add "$DUX_HOME/$1" --base main --pr-template skip >/dev/null
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
  run --separate-stderr dux-worktree create "$id"
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ "$output" = "$wt" ]
  [ "$(git -C "$wt" branch --show-current)" = "dux/$id" ]
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$DUX_HOME/proj" rev-parse origin/main)" ]
  [ -x "$DUX_HOME/data/tasks/$id/hooks/pre-push" ]
  [ ! -e "$wt/.env" ]
  [ "$(dux-worktree path "$id")" = "$wt" ]
  # The guard is the worktree's own git configuration, so it travels with the
  # worktree and reaches nothing else. The registered checkout keeps its own
  # hooks and still pushes to its base branch.
  [ "$(git -C "$wt" config --worktree --get core.hooksPath)" = "$DUX_HOME/data/tasks/$id/hooks" ]
  [ -z "$(git -C "$DUX_HOME/proj" config --get core.hooksPath)" ]
  (cd "$DUX_HOME/proj" && git commit -q --allow-empty -m "operator work")
  run git -C "$DUX_HOME/proj" push -q origin main
  [ "$status" -eq 0 ]
}

@test "a repository that shares core.worktree with its worktrees is refused, and nothing is written" {
  register proj
  git -C "$DUX_HOME/proj" config core.worktree "$DUX_HOME/proj"
  id="$(dux-task-new proj scout)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $DUX_HOME/proj shares core.worktree with its worktrees; move it to the main worktree's config.worktree (git help worktree, CONFIGURATION FILE) before Dux can scope its hooks"* ]]
  [ -z "$(git -C "$DUX_HOME/proj" config --get extensions.worktreeConfig)" ]
}

@test "a bare repository shared with its worktrees is refused, and nothing is written" {
  register proj
  # A bare clone of the fixture origin, so create's fetch of origin/main has a
  # remote to reach, and core.bare = true sits in the shared config that the
  # registered path, a linked worktree of that clone, reads.
  bare="$DUX_HOME/bare.git"
  git clone -q --bare "$DUX_HOME/proj.origin" "$bare"
  git -C "$bare" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git -C "$bare" worktree add --quiet "$DUX_HOME/bareproj" main
  dux-project add "$DUX_HOME/bareproj" --base main --pr-template skip >/dev/null
  id="$(dux-task-new bareproj scout)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $DUX_HOME/bareproj shares core.bare with its worktrees; move it to the main worktree's config.worktree (git help worktree, CONFIGURATION FILE) before Dux can scope its hooks"* ]]
  [ -z "$(git -C "$bare" config --get extensions.worktreeConfig)" ]
}

@test "a shared key that arrives through an include is refused too" {
  register proj
  # git reads include.path only when asked, and a value that arrives that way
  # counts exactly as much as one written in the file itself.
  printf '[core]\n\tworktree = %s\n' "$DUX_HOME/proj" > "$DUX_HOME/extra.cfg"
  printf '\n[include]\n\tpath = %s\n' "$DUX_HOME/extra.cfg" >> "$DUX_HOME/proj/.git/config"
  id="$(dux-task-new proj scout)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $DUX_HOME/proj shares core.worktree with its worktrees"* ]]
  [ -z "$(git -C "$DUX_HOME/proj" config --get extensions.worktreeConfig)" ]
}

ignore_env() {  # $1 project name; the project ignores the real env files, not the examples
  printf '.worktrees/\n.env\n.env.local\n' > "$DUX_HOME/$1/.gitignore"
  (cd "$DUX_HOME/$1" && git add .gitignore && git commit -q -m "ignore env" && git push -q origin main)
}

commit_in() {  # $1 project name, $2... paths to add and push
  local n="$1"; shift
  (cd "$DUX_HOME/$n" && git add "$@" && git commit -q -m fixture && git push -q origin main)
}

@test "ship under git copies committed env examples, renamed, and no real env file" {
  register proj
  ignore_env proj
  echo SECRET=live > "$DUX_HOME/proj/.env"; echo TOKEN=live > "$DUX_HOME/proj/.env.local"
  echo A=1 > "$DUX_HOME/proj/.env.example"; echo B=2 > "$DUX_HOME/proj/.env.local.sample"
  ln -s .env "$DUX_HOME/proj/.env.staging.example"
  commit_in proj .env.example .env.local.sample .env.staging.example
  id="$(dux-task-new proj ship)"
  wt="$(dux-worktree create "$id")"
  [ "$(cat "$wt/.env")" = A=1 ]; [ "$(cat "$wt/.env.local")" = B=2 ]
  [ ! -e "$wt/.env.staging" ]
  # The negative that matters: no value from a real env file is anywhere in the worktree.
  run grep -rl live "$wt"
  [ "$status" -ne 0 ]; [ -z "$output" ]
  # The copies land on ignored names, so the worktree is still clean for teardown.
  [ -z "$(git -C "$wt" status --porcelain)" ]
}

@test "a project with no committed env example gets no env file and says so" {
  register proj
  ignore_env proj
  echo SECRET=live > "$DUX_HOME/proj/.env"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no committed env example in $DUX_HOME/proj"* ]]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [ ! -e "$wt/.env" ]
  run grep -rl live "$wt"
  [ "$status" -ne 0 ]; [ -z "$output" ]
}

@test "an uncommitted example and an unignored destination are findings, and nothing is copied" {
  register proj
  ignore_env proj
  echo SECRET=live > "$DUX_HOME/proj/.env"; echo A=1 > "$DUX_HOME/proj/.env.example"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: .env.example is not committed in $DUX_HOME/proj"* ]]
  [ ! -e "$DUX_HOME/proj/.worktrees/dux-$id/.env" ]
  commit_in proj .env.example
  printf '.worktrees/\n' > "$DUX_HOME/proj/.gitignore"
  commit_in proj .gitignore
  id2="$(dux-task-new proj ship)"
  run dux-worktree create "$id2"
  [ "$status" -eq 2 ]
  wt2="$DUX_HOME/proj/.worktrees/dux-$id2"
  [[ "$output" == *"finding: .env is not ignored in $wt2; copying .env.example to it would dirty the worktree"* ]]
  [ ! -e "$wt2/.env" ]
}

@test "a locally edited tracked example copies its committed content, not the edit" {
  register proj
  ignore_env proj
  echo A=1 > "$DUX_HOME/proj/.env.example"
  commit_in proj .env.example
  # Tracked, so ls-files would have passed it; edited, so the working copy is not
  # what the repository holds. Nothing the operator typed locally may travel.
  echo A=live-secret > "$DUX_HOME/proj/.env.example"
  id="$(dux-task-new proj ship)"
  wt="$(dux-worktree create "$id")"
  [ "$(cat "$wt/.env")" = A=1 ]
  run grep -rl live-secret "$wt"
  [ "$status" -ne 0 ]; [ -z "$output" ]
}

@test "the ignore rules that decide are the worktree's, not the primary checkout's" {
  register proj
  echo A=1 > "$DUX_HOME/proj/.env.example"
  commit_in proj .env.example
  # Ignored in the primary checkout only: an uncommitted .gitignore edit that the
  # worktree, pinned at origin/main, never sees.
  printf '.worktrees/\n.env\n' > "$DUX_HOME/proj/.gitignore"
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [[ "$output" == *"finding: .env is not ignored in $wt; copying .env.example to it would dirty the worktree"* ]]
  [ ! -e "$wt/.env" ]
}

@test "a destination that already exists is a finding and nothing is written through it" {
  register proj
  ignore_env proj
  echo A=1 > "$DUX_HOME/proj/.env.example"
  commit_in proj .env.example
  id="$(dux-task-new proj ship)"
  wt="$(dux-worktree create "$id")"
  [ "$(cat "$wt/.env")" = A=1 ]
  # A symlink where the copy lands: cp would follow it and write outside the worktree.
  echo untouched > "$DUX_HOME/outside"
  rm "$wt/.env"; ln -s "$DUX_HOME/outside" "$wt/.env"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $wt/.env already exists and is not this example's committed content"* ]]
  [ "$(cat "$DUX_HOME/outside")" = untouched ]
  [ -L "$wt/.env" ]
  # A regular file holding something else is refused too.
  rm "$wt/.env"; printf 'A=tampered\n' > "$wt/.env"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $wt/.env already exists and is not this example's committed content"* ]]
  [ "$(cat "$wt/.env")" = A=tampered ]
  # The copy this script made itself is not something a rerun has to refuse.
  printf 'A=1\n' > "$wt/.env"
  run dux-worktree create "$id"
  [ "$status" -eq 0 ]
}

@test "a committed symlink at the staging name is a finding and its target keeps its content" {
  register proj
  ignore_env proj
  echo A=1 > "$DUX_HOME/proj/.env.example"
  echo untouched > "$DUX_HOME/outside"
  # The worktree is checked out at origin/main, so this symlink is on disk before
  # copy_env runs, and the staging redirection would follow it out of the worktree.
  ln -s "$DUX_HOME/outside" "$DUX_HOME/proj/.env.dux-part"
  commit_in proj .env.example .env.dux-part
  id="$(dux-task-new proj ship)"
  run dux-worktree create "$id"
  [ "$status" -eq 2 ]
  wt="$DUX_HOME/proj/.worktrees/dux-$id"
  [[ "$output" == *"finding: $wt/.env.dux-part already exists; refusing to stage .env.example through it"* ]]
  # The refusal is not the claim being made here: nothing reached the target.
  [ "$(cat "$DUX_HOME/outside")" = untouched ]
  [ -L "$wt/.env.dux-part" ]
  [ ! -e "$wt/.env" ]
}

@test "ship under make uses the project's target and discovers its path" {
  with_makefile proj "$custom_target"
  id="$(dux-task-new proj ship)"
  run --separate-stderr dux-worktree create "$id"
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  [ "$output" = "$DUX_HOME/proj/.worktrees/custom-dux-$id" ]
  [ -f "$output/made-by-make" ]
  [ -s "$DUX_HOME/data/tasks/$id/worktree.log" ]
}

@test "plan under make ignores the mechanism and uses git worktree add" {
  with_makefile proj "$custom_target"
  id="$(dux-task-new proj plan)"
  run --separate-stderr dux-worktree create "$id"
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
  [ "$output" = "$DUX_HOME/proj/.worktrees/dux-$id" ]
  [ ! -e "$DUX_HOME/proj/.worktrees/custom-dux-$id" ]
}

@test "ship under script runs scripts/*worktree* with branch and base" {
  make_repo "$DUX_HOME/proj" main
  mkdir -p "$DUX_HOME/proj/scripts"
  printf '#!/bin/sh\ngit worktree add ".worktrees/s-$(echo "$1" | tr / -)" -b "$1" "origin/$2" && echo "$1 $2" > .worktrees/script-args\n' > "$DUX_HOME/proj/scripts/worktree.sh"
  chmod +x "$DUX_HOME/proj/scripts/worktree.sh"
  (cd "$DUX_HOME/proj" && git add scripts && git commit -q -m script && git push -q origin main)
  dux-project add "$DUX_HOME/proj" --base main --pr-template skip >/dev/null
  [ "$(dux-project get proj worktree)" = script ]
  id="$(dux-task-new proj ship)"
  run --separate-stderr dux-worktree create "$id"
  [ "$status" -eq 0 ]
  if [ -n "$stderr" ]; then echo "expected no stderr, got: '$stderr'"; return 1; fi
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
  run git -C "$wt" push -q origin "HEAD:refs/heads/main"
  [ "$status" -ne 0 ]
  [[ "$output" == *"finding: refusing to push to main from a Dux worktree"* ]]
  [ "$(git -C "$DUX_HOME/proj.origin" rev-parse main)" != "$(git -C "$wt" rev-parse HEAD)" ]
  run git -C "$wt" push -q -u origin "dux/$id"
  [ "$status" -eq 0 ]
  run git -C "$wt" push -q origin "dux/$id:main"
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
  git -C "$wt" push -q -u origin "dux/$id"
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
  run git -C "$DUX_HOME/proj" show-ref --verify --quiet "refs/heads/dux/$id"; [ "$status" -ne 0 ]
  run dux-worktree discard "$id"
  [ "$status" -eq 0 ]
}

run_hook() {  # $1 hook, $2 remote ref name; feeds one pre-push line on stdin
  bash -c 'printf "refs/heads/local sha1 refs/heads/%s sha2\n" "$2" | "$1" origin url' _ "$1" "$2"
}

@test "the rendered hook never re-evaluates the base branch or the upstream path" {
  base='evil$(touch$IFS'"$DUX_HOME"'/pwned-base)'
  make_repo "$DUX_HOME/proj" "$base"
  dux-project add "$DUX_HOME/proj" --base "$base" --pr-template skip >/dev/null
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
  dux-project add "$DUX_HOME/proj" --base "$base" --pr-template skip >/dev/null
  id="$(dux-task-new proj scout)"
  dux-worktree create "$id" >/dev/null
  hook="$DUX_HOME/data/tasks/$id/hooks/pre-push"
  run run_hook "$hook" "$base"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to push to $base from a Dux worktree"* ]]
  run run_hook "$hook" "dux/$id"
  [ "$status" -eq 0 ]
}
