bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# ship-env answers from the Dux checkout it was installed from, and it finds
# that checkout two levels above its own directory. Two levels above the real
# script is the operator's own checkout, so every test builds a fake one and
# runs a copy of the script from inside it.
fake_checkout() {  # prints the checkout path
  local c="$DUX_HOME/checkout"
  mkdir -p "$c/skills/ship" "$c/templates/config"
  cp "$DUX_ROOT/skills/ship/ship-env" "$c/skills/ship/ship-env"
  cp "$DUX_ROOT/templates/PULL_REQUEST_TEMPLATE.md" "$c/templates/PULL_REQUEST_TEMPLATE.md"
  # The real bin/, so pr-template is asked of the real dux-project and the two
  # cannot drift. A test that needs the delegate to fail overwrites this.
  ln -s "$DUX_ROOT/bin" "$c/bin"
  printf 'template reviewer command\n' > "$c/templates/config/reviewer"
  printf 'agent:template-security-reviewer\n' > "$c/templates/config/security-reviewer"
  echo "$c"
}

env_at() {  # $1 checkout, $2.. arguments
  local c="$1"; shift
  "$c/skills/ship/ship-env" "$@"
}

@test "a seeded config supplies both reviewers" {
  c="$(fake_checkout)"
  mkdir -p "$c/config"
  printf 'configured reviewer command\n' > "$c/config/reviewer"
  printf 'agent:configured-security-reviewer\n' > "$c/config/security-reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "configured reviewer command" ]
  run --separate-stderr env_at "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:configured-security-reviewer" ]
}

@test "a fresh clone with no config falls back to the bundled defaults" {
  c="$(fake_checkout)"
  [ ! -d "$c/config" ]
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "template reviewer command" ]
  run --separate-stderr env_at "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:template-security-reviewer" ]
}

@test "notes and blank lines above the value are skipped" {
  c="$(fake_checkout)"
  mkdir -p "$c/config"
  printf '# a note about the reviewer\n\n# another note\nthe value line\n' > "$c/config/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "the value line" ]
}

@test "a config file of notes alone falls back rather than answering empty" {
  c="$(fake_checkout)"
  mkdir -p "$c/config"
  printf '# the operator commented the value out\n\n' > "$c/config/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "template reviewer command" ]
}

@test "--root resolves the checkout through the install symlink" {
  c="$(fake_checkout)"
  ln -s "$c/skills/ship" "$DUX_HOME/installed"
  run --separate-stderr "$DUX_HOME/installed/ship-env" --root
  [ "$status" -eq 0 ]
  [ "$output" = "$c" ]
  # The value lookup travels the same path, so the symlinked install answers too.
  run --separate-stderr "$DUX_HOME/installed/ship-env" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "template reviewer command" ]
}

@test "an unknown key is a finding that names the keys there are" {
  c="$(fake_checkout)"
  run --separate-stderr env_at "$c" models
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: unknown key 'models' (reviewer, security-reviewer)" ]
}

@test "a directory that is not a Dux checkout is a finding" {
  mkdir -p "$DUX_HOME/loose/skills/ship"
  cp "$DUX_ROOT/skills/ship/ship-env" "$DUX_HOME/loose/skills/ship/ship-env"
  run --separate-stderr "$DUX_HOME/loose/skills/ship/ship-env" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: ship-env is not inside a Dux checkout: $DUX_HOME/loose/templates/config is not a directory" ]
}

@test "a key with no value in either file is a finding naming both" {
  c="$(fake_checkout)"
  : > "$c/templates/config/reviewer"
  mkdir -p "$c/config"
  : > "$c/config/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no value for reviewer in $c/config/reviewer or $c/templates/config/reviewer" ]
}

@test "no command at all is a finding, not an empty answer" {
  c="$(fake_checkout)"
  run --separate-stderr env_at "$c"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

@test "an argument after a key is a finding" {
  c="$(fake_checkout)"
  run --separate-stderr env_at "$c" reviewer extra
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

# The shipped defaults are what a fresh clone runs on, so the test that reads
# them must not read the operator's config/ instead. A fake checkout carrying
# the real templates and no config/ is the only way to ask that question: run
# against the real root, this test would pass on whatever the operator seeded.
@test "the bundled defaults are answerable by the reader that ships with them" {
  c="$DUX_HOME/bundled"
  mkdir -p "$c/skills/ship" "$c/templates"
  cp "$DUX_ROOT/skills/ship/ship-env" "$c/skills/ship/ship-env"
  cp -R "$DUX_ROOT/templates/config" "$c/templates/config"
  [ ! -d "$c/config" ]
  for k in reviewer security-reviewer; do
    grep -q '^#' "$c/templates/config/$k" || { echo "$k ships with no note line"; return 1; }
    run --separate-stderr env_at "$c" "$k"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    case "$output" in '#'*) echo "ship-env answered a note line for $k"; return 1 ;; esac
  done
}

# A repository under the test's own home, since dux-project only reads the path.
a_repo() {  # $1 name; prints the path
  local d="$DUX_HOME/$1"
  mkdir -p "$d"
  git init -q "$d"
  echo "$d"
}

# Swap the symlinked bin/ for one holding a stand-in dux-project.
stub_project() {  # $1 checkout, $2 script body
  rm "$1/bin"
  mkdir -p "$1/bin"
  { echo '#!/usr/bin/env bash'; echo "$2"; } > "$1/bin/dux-project"
  chmod +x "$1/bin/dux-project"
}

@test "pr-template gives back what dux-project found, one path per line" {
  c="$(fake_checkout)"
  r="$(a_repo withtemplate)"
  mkdir -p "$r/docs"
  : > "$r/docs/pull_request_template.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ "$output" = "docs/pull_request_template.md" ]
  # The same question asked of the owner of the lookup gives the same answer.
  run "$DUX_ROOT/bin/dux-project" pr-template "$r"
  [ "$output" = "docs/pull_request_template.md" ]
}

@test "pr-template says nothing for a repo that has none" {
  c="$(fake_checkout)"
  r="$(a_repo notemplate)"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  # dux-project's own word for it is "none", and that word never travels.
  run "$DUX_ROOT/bin/dux-project" pr-template "$r"
  [ "$output" = none ]
}

@test "pr-template reports the folder form as the folder form" {
  c="$(fake_checkout)"
  r="$(a_repo folderform)"
  mkdir -p "$r/.github/PULL_REQUEST_TEMPLATE"
  : > "$r/.github/PULL_REQUEST_TEMPLATE/one.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ "$output" = ".github/PULL_REQUEST_TEMPLATE/" ]
}

# Empty output means "this repo has no template". A lookup that failed must
# never be read as one, or the gate quietly fills the bundled copy instead.
@test "a delegate that fails is a finding, never an empty answer" {
  c="$(fake_checkout)"
  r="$(a_repo brokenlookup)"
  stub_project "$c" 'echo "finding: something broke" >&2; exit 2'
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"finding: something broke"* ]]
  [[ "$stderr" == *"dux-project pr-template failed for $r"* ]]
}

@test "a delegate that exits non-zero after printing paths is still a finding" {
  c="$(fake_checkout)"
  r="$(a_repo halflookup)"
  stub_project "$c" 'echo docs/pull_request_template.md; exit 1'
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"dux-project pr-template failed for $r"* ]]
}

@test "pr-template needs exactly one repository" {
  c="$(fake_checkout)"
  run --separate-stderr env_at "$c" pr-template
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

@test "pr-template-fallback names the bundled copy" {
  c="$(fake_checkout)"
  run --separate-stderr env_at "$c" pr-template-fallback
  [ "$status" -eq 0 ]
  [ "$output" = "$c/templates/PULL_REQUEST_TEMPLATE.md" ]
  [ -f "$output" ]
}

@test "a checkout with no bundled template is a finding, not a silent empty path" {
  c="$(fake_checkout)"
  rm "$c/templates/PULL_REQUEST_TEMPLATE.md"
  run --separate-stderr env_at "$c" pr-template-fallback
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no bundled pull request template at $c/templates/PULL_REQUEST_TEMPLATE.md" ]
}
