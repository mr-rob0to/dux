load helpers/setup

# The lint is the only thing standing between this defect class and a fourth
# recurrence, so its own coverage is asserted rather than assumed. Each case is
# one line in a fixture: what must be rejected, and what must not be.

check() {  # $1 file; prints the offending lines, exits 1 when there are any
  awk -f "$DUX_ROOT/tests/lint-pipes.awk" "$1"
}

@test "the pipe lint rejects every shape of reader that stops early" {
  f="$DUX_HOME/bad.sh"
  cat > "$f" <<'EOF'
a | head -1
a | head -n 1
a | head -c 10
printf x | grep -q y
printf x | grep -qE y
printf x | grep -Em1 y
printf x | grep -m 1 y
printf x | grep --quiet y
printf x | grep --silent y
printf x | grep --max-count=1 y
EOF
  run check "$f"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 10 ] || { echo "wanted 10 rejections, got ${#lines[@]}:"; echo "$output"; return 1; }
}

@test "the pipe lint reaches a stage the line before continued" {
  f="$DUX_HOME/cont.sh"
  # Both spellings of a pipeline broken over two lines. A line-at-a-time check
  # sees neither, which is how the first version of this lint missed them.
  printf 'a |\n  head -c 10\n' > "$f"
  printf 'b \\\n  | grep -q y\n' >> "$f"
  printf 'c |\n  grep -m1 y\n' >> "$f"
  run check "$f"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 3 ] || { echo "wanted 3 rejections, got ${#lines[@]}:"; echo "$output"; return 1; }
}

@test "the pipe lint leaves alone what has no producer to break" {
  f="$DUX_HOME/good.sh"
  cat > "$f" <<'EOF'
head -c 4000 "$f" | tr -d x
head -n 1 "$f"
grep -q '^- ' "$registry"
grep -qE 'pat' "$f" && echo yes
producer | take_bytes 10
producer | take_line
printf x | grep -E y >/dev/null
printf x | grep -v -E y | sed 's/a/b/'
printf x | grep -oiE 'pat' | take_line
take_bytes() { head -c "$1"; cat >/dev/null; }
take_line()  { head -n 1;    cat >/dev/null; }
# a | head -1
EOF
  run check "$f"
  [ "$status" -eq 0 ] || { echo "the lint rejected a line it should accept:"; echo "$output"; return 1; }
  [ -z "$output" ]
}
