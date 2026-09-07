load helpers/setup

@test "lint fails when a tracked file contains a personal identifier" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  echo 'leak-me-please' > "$tmp/repo/tests/personal-identifiers.txt"
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

# Four characters, the boundary the length check trusts, and absent from every
# tracked file. It is joined from two halves because the paths list matches as a
# substring, so writing it whole here would make it present in this very file.
tok_a=qx; tok_b=zw; boundary_entry="$tok_a$tok_b"

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

# An entry matched as a substring has to be long enough to be an identifier.
# This repo registered itself as a project called "dux", dux-install wrote that
# name into the paths denylist, and the lint then flagged every tracked file.
# Silently matching everything is worse than refusing: the check that fires on
# every line is the check nobody reads.
@test "lint refuses a denylist entry too short to be an identifier" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # The fixture is the real entry that caused this, and it has to be: a short
  # entry that matches nothing would let the last assertion pass with the early
  # exit deleted. "dux" is in 76 tracked files, README.md among them.
  printf 'dux\n' > "$tmp/repo/tests/personal-identifiers.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"denylist entry [dux] is too short to match safely"* ]]
  # And says where the entry came from. Without this the operator is told the
  # build is broken and not that data/projects.md is the file to edit, and
  # there is no dux-project rename or remove to find instead.
  [[ "$output" == *"written by dux-install from data/projects.md"* ]]
  # It refuses instead of reporting the flood it would otherwise have produced.
  [[ "$output" != *"README.md"* ]]
}

# The floor is for substring matching only. The names list is matched as a whole
# word, so a short account name there is an ordinary entry, and refusing it left
# an operator with a three-letter account name a build they could not fix: that
# name comes from whoami, not from any file they can edit.
@test "a short name in the names denylist is kept, and still catches a leak" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf '%s\n' "$short_account" > "$tmp/repo/tests/personal-names.txt"
  printf 'the user %s signed off\n' "$short_account" > "$tmp/repo/LEAK.md"
  git -C "$tmp/repo" add LEAK.md
  git -C "$tmp/repo" commit -qm leak
  run make -C "$tmp/repo" lint-identifiers
  # Refused for length would say so and stop; this has to be the leak itself.
  [ "$status" -ne 0 ]
  [[ "$output" != *"too short"* ]]
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

@test "lint still accepts an entry at the shortest length it trusts" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # Four characters is the boundary. The entry has to be absent from the repo as
  # a substring, or a real match would fail this for a reason that is not length.
  printf '%s\n' "$boundary_entry" > "$tmp/repo/tests/personal-identifiers.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}

@test "a generic account name that is short is dropped before the length check" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # "ci" is on the generic list, so it never reaches the length check and is not
  # a reason to fail the build. It goes in the paths list, which is the only one
  # the length check reads.
  printf 'ci\n' > "$tmp/repo/tests/personal-identifiers.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}
