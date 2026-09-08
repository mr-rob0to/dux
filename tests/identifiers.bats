load helpers/setup

@test "lint fails when a tracked file contains a personal identifier" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  echo 'leak-me-please' > "$tmp/repo/tests/personal-identifiers.txt"
  echo 'this line says leak-me-please' >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
  # A failure that names only the file leaves the reader with no way to tell a
  # leak from an entry left behind by an earlier install, so it says where the
  # lists come from and how to get rid of a stale one.
  [[ "$output" == *"written by dux-install"* ]]
  [[ "$output" == *"run the installer again"* ]]
}

# cat joins two files with nothing between them. Both list locations resolve to
# the same file in a main checkout, so a list hand-edited and saved without a
# final newline has its last entry fused to its own first entry: the list then
# matches nothing and the target exits 0 while reporting success.
@test "lint still catches a leak when a list file has no final newline" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s' 'leak-me-please' > "$tmp/repo/tests/personal-identifiers.txt"
  echo 'this line says leak-me-please' >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "lint passes on the clean repo" {
  run make -C "$DUX_ROOT" lint-identifiers
  [ "$status" -eq 0 ]
}

# The CI account of this repo is named after an ordinary English word. Its home
# path is assembled from that name so no tracked file carries the literal path,
# which the paths half of the denylist matches as a substring.
ci_account=runner

# A stand-in for a personal account name. It is spelled out here only inside a
# longer word, because this file is one of the tracked files the lint searches:
# a bare spelling would make the test trip over its own source.
long_word=zephyr
short_name="${long_word%yr}"

# A three-letter account name, for the same reason and by the same trick: it is
# never spelled bare here, so this file does not match its own fixture.
long_account=bobby
short_account="${long_account%by}"

@test "lint ignores a denylist entry that is an ordinary word" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n/home/%s\n' "$ci_account" "$ci_account" > "$tmp/repo/tests/personal-identifiers.txt"
  echo "a slow CI $ci_account shows up as a timeout" >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}

@test "lint still catches the home path even when the bare name is generic" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n/home/%s\n' "$ci_account" "$ci_account" > "$tmp/repo/tests/personal-identifiers.txt"
  echo "see /home/$ci_account/work/dux for the checkout" >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "lint does not match a denylist name inside a longer word" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  echo "$short_name" > "$tmp/repo/tests/personal-names.txt"
  echo "the $long_word logs rotate nightly" >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}

@test "lint catches a denylist name standing on its own" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  echo "$short_name" > "$tmp/repo/tests/personal-names.txt"
  echo "ask $short_name about the logs" >> "$tmp/repo/README.md"
  (cd "$tmp/repo" && git add README.md)
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

# Both denylist files are git-ignored, so a fresh worktree does not inherit
# them. Every feature branch is written in a worktree, so the check was passing
# there without reading anything: the one place it needed to work. A worktree
# can still have them, because dux-install writes the lists beside its own bin/
# and so puts them wherever it is run from; the test after this one covers that.
@test "lint reads the denylist from the main checkout when run in a worktree" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n' "$short_account" > "$tmp/repo/tests/personal-names.txt"
  git -C "$tmp/repo" worktree add -q "$tmp/wt" -b probe
  # The worktree checks out committed content, so it carries the old Makefile.
  cp "$DUX_ROOT/Makefile" "$tmp/wt/Makefile"
  printf 'ask %s about the logs\n' "$short_account" > "$tmp/wt/LEAK.md"
  git -C "$tmp/wt" add LEAK.md
  git -C "$tmp/wt" commit -qm leak
  # The denylist is in $tmp/repo, not $tmp/wt, and nothing copies it across.
  [ ! -e "$tmp/wt/tests/personal-names.txt" ]
  run make -C "$tmp/wt" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"LEAK.md"* ]]
}

# dux-install writes the lists beside its own bin/ directory, so run from a
# worktree it puts them in that worktree. Reading only the main checkout left
# those ignored, which reopened the same hole through the other door.
@test "lint reads a denylist that exists only in the worktree" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  git -C "$tmp/repo" worktree add -q "$tmp/wt" -b probe
  cp "$DUX_ROOT/Makefile" "$tmp/wt/Makefile"
  printf '%s\n' "$short_name" > "$tmp/wt/tests/personal-names.txt"
  # The main checkout has none, so only the local one can catch this.
  [ ! -e "$tmp/repo/tests/personal-names.txt" ]
  printf 'ask %s about the logs\n' "$short_name" > "$tmp/wt/LEAK.md"
  git -C "$tmp/wt" add LEAK.md
  git -C "$tmp/wt" commit -qm leak
  run make -C "$tmp/wt" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"LEAK.md"* ]]
}

# The search is git ls-files, and its failure is swallowed, so outside a git
# repository the target would exit 0 having read nothing at all. A check that
# passes without looking is worse than one that is not run.
@test "lint refuses to run outside a git work tree instead of passing" {
  tmp="$(mktemp -d)"
  cp "$DUX_ROOT/Makefile" "$tmp/Makefile"
  mkdir -p "$tmp/tests"
  run make -C "$tmp" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a git work tree"* ]]
}

# A bare repository is the case that exits 0 while printing "false", so a guard
# reading only the exit status lets it through and the target checks nothing.
@test "lint refuses a bare repository, which has no work tree to check" {
  tmp="$(mktemp -d)"
  git init -q --bare "$tmp/bare.git"
  cp "$DUX_ROOT/Makefile" "$tmp/bare.git/Makefile"
  run make -C "$tmp/bare.git" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a git work tree"* ]]
}

# The skip has to stay for the case it was written for: CI checks out the repo
# and has no denylist anywhere, and that is not a leak.
@test "lint passes when no denylist exists in the worktree or the main checkout" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  [ ! -e "$tmp/repo/tests/personal-names.txt" ]
  [ ! -e "$tmp/repo/tests/personal-identifiers.txt" ]
  git -C "$tmp/repo" worktree add -q "$tmp/wt" -b probe
  cp "$DUX_ROOT/Makefile" "$tmp/wt/Makefile"
  run make -C "$tmp/wt" lint-identifiers
  [ "$status" -eq 0 ]
}

# A short name in the names list is an ordinary entry: it is matched as a whole
# word, and an account name of three letters is nothing unusual. It comes from
# whoami, not from any file the operator can edit.
@test "a short name in the names denylist is kept, and still catches a leak" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n' "$short_account" > "$tmp/repo/tests/personal-names.txt"
  printf 'the user %s signed off\n' "$short_account" > "$tmp/repo/LEAK.md"
  git -C "$tmp/repo" add LEAK.md
  git -C "$tmp/repo" commit -qm leak
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"LEAK.md"* ]]
  [[ "$output" == *"personal identifiers found"* ]]
}

@test "a short name in the names denylist does not match inside a longer word" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n' "$short_account" > "$tmp/repo/tests/personal-names.txt"
  printf 'the %ssled team\n' "$short_account" > "$tmp/repo/CLEAN.md"
  git -C "$tmp/repo" add CLEAN.md
  git -C "$tmp/repo" commit -qm clean
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}

# The generic list is the names half's volume limit, and an ordinary English word
# floods whole-word too. "run" is 1624 lines here.
@test "an account name that is an ordinary word does not flood the names list" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf 'run\n' > "$tmp/repo/tests/personal-names.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
  [[ "$output" != *"Makefile:"* ]]
}

@test "a generic account name that is short never reaches the search" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # "ci" is on the generic list, so it is dropped before the search and is not a
  # reason to fail the build. Two characters, in the list matched as a substring:
  # if the generic drop ever stopped applying to short entries it would flood 56
  # lines here, which the ordinary-word test above cannot show.
  printf 'ci\n' > "$tmp/repo/tests/personal-identifiers.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}
