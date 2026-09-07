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
  printf 'abc\n' > "$tmp/repo/tests/personal-identifiers.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"denylist entry [abc] is too short to match safely"* ]]
  # It refuses instead of reporting the flood it would otherwise have produced.
  [[ "$output" != *"README.md"* ]]
}

@test "lint refuses a short entry in the names denylist too" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  printf 'ab\n' > "$tmp/repo/tests/personal-names.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -ne 0 ]
  [[ "$output" == *"denylist entry [ab] is too short to match safely"* ]]
}

@test "lint still accepts an entry at the shortest length it trusts" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # Four characters is the boundary, and the whole-word tests above rely on it.
  printf '%s\n' "$short_name" > "$tmp/repo/tests/personal-names.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}

@test "a generic account name that is short is dropped before the length check" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"; cp "$DUX_ROOT/Makefile" "$tmp/repo/Makefile"
  # "ci" is on the generic list, so it never reaches the length check and is not
  # a reason to fail the build.
  printf 'ci\n' > "$tmp/repo/tests/personal-names.txt"
  run make -C "$tmp/repo" lint-identifiers
  [ "$status" -eq 0 ]
}
