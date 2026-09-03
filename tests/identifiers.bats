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
