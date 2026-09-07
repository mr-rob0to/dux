load helpers/setup

setup() {
  REPO_ROOT="$DUX_ROOT"
  DUX_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")"; export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  # A throwaway DUX_ROOT: dux-install writes the identifier denylist under it, and
  # must not leave one behind in the checkout the suite is running from.
  mkdir -p "$DUX_HOME/root/tests"
  ln -s "$REPO_ROOT/skills" "$DUX_HOME/root/skills"
  ln -s "$REPO_ROOT/templates" "$DUX_HOME/root/templates"
  DUX_ROOT="$DUX_HOME/root"; export DUX_ROOT
  export DUX_SKILLS_DIR="$DUX_HOME/skills-target"; mkdir -p "$DUX_SKILLS_DIR"
  export PATH="$REPO_ROOT/tests/fakes:$REPO_ROOT/bin:$PATH"
}

@test "install symlinks every bundled skill and copies default config" {
  run dux-install
  [ "$status" -eq 0 ]
  for d in "$DUX_ROOT"/skills/*/; do
    n="$(basename "$d")"
    [ -L "$DUX_SKILLS_DIR/$n" ]
    [ "$(readlink "$DUX_SKILLS_DIR/$n")" = "$DUX_ROOT/skills/$n" ]
  done
  [ -f "$DUX_HOME/config/reviewer" ]
  grep -q 'codex exec' "$DUX_HOME/config/reviewer"
}

@test "install writes the denylist under DUX_ROOT, never the source tree" {
  root="$DUX_HOME/ro"; mkdir -p "$root/tests"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  [ -f "$root/tests/personal-identifiers.txt" ]
}

@test "install refuses an existing real directory without --yes" {
  mkdir -p "$DUX_SKILLS_DIR/ship"; echo old > "$DUX_SKILLS_DIR/ship/SKILL.md"
  run dux-install
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $DUX_SKILLS_DIR/ship exists and is not a symlink"* ]]
  [ -f "$DUX_SKILLS_DIR/ship/SKILL.md" ]
}

@test "install --yes moves an existing directory to .bak" {
  mkdir -p "$DUX_SKILLS_DIR/ship"; echo old > "$DUX_SKILLS_DIR/ship/SKILL.md"
  run dux-install --yes
  [ "$status" -eq 0 ]
  [ -L "$DUX_SKILLS_DIR/ship" ]
  [ "$(cat "$DUX_SKILLS_DIR/ship.bak/SKILL.md")" = old ]
}

@test "install does not overwrite existing config" {
  echo mine > "$DUX_HOME/config/reviewer"
  dux-install
  [ "$(cat "$DUX_HOME/config/reviewer")" = mine ]
}

@test "uninstall removes only symlinks into this repo" {
  dux-install
  ln -s /tmp "$DUX_SKILLS_DIR/other"
  run dux-uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$DUX_SKILLS_DIR/ship" ]
  [ -L "$DUX_SKILLS_DIR/other" ]
}

@test "install --yes refuses to destroy an existing .bak" {
  mkdir -p "$DUX_SKILLS_DIR/ship" "$DUX_SKILLS_DIR/ship.bak"
  echo old > "$DUX_SKILLS_DIR/ship/SKILL.md"; echo older > "$DUX_SKILLS_DIR/ship.bak/SKILL.md"
  run dux-install --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $DUX_SKILLS_DIR/ship.bak already exists"* ]]
  [ "$(cat "$DUX_SKILLS_DIR/ship.bak/SKILL.md")" = older ]
  [ "$(cat "$DUX_SKILLS_DIR/ship/SKILL.md")" = old ]
}

@test "install refuses to replace a symlink into another place without --yes" {
  ln -s /tmp "$DUX_SKILLS_DIR/ship"
  run dux-install
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $DUX_SKILLS_DIR/ship is a symlink to /tmp"* ]]
  [ "$(readlink "$DUX_SKILLS_DIR/ship")" = /tmp ]
  run dux-install --yes
  [ "$status" -eq 0 ]
  [ "$(readlink "$DUX_SKILLS_DIR/ship")" = "$DUX_ROOT/skills/ship" ]
}

@test "install leaves a dangling config symlink alone" {
  ln -s "$DUX_HOME/nowhere" "$DUX_HOME/config/reviewer"
  run dux-install
  [ "$status" -eq 0 ]
  [ -L "$DUX_HOME/config/reviewer" ]
  [ ! -e "$DUX_HOME/nowhere" ]
}

@test "install is a finding when the skills dir cannot be created" {
  mkdir -p "$DUX_HOME/ro"; chmod 555 "$DUX_HOME/ro"
  DUX_SKILLS_DIR="$DUX_HOME/ro/skills" run dux-install
  chmod 755 "$DUX_HOME/ro"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot create $DUX_HOME/ro/skills"* ]]
}

@test "install is a finding when a skill cannot be linked" {
  chmod 555 "$DUX_SKILLS_DIR"
  run dux-install
  chmod 755 "$DUX_SKILLS_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot link $DUX_SKILLS_DIR/"* ]]
}

@test "install --yes is a finding when the backup move fails, and the skill dir stays" {
  # The installer links skills in directory order and stops at the first problem.
  # Pre-link everything before `ship` so the read-only dir reports the backup
  # move, not `cannot link` for some other skill.
  for d in "$DUX_ROOT"/skills/*/; do
    n="$(basename "$d")"; [ "$n" = ship ] && continue
    ln -s "$DUX_ROOT/skills/$n" "$DUX_SKILLS_DIR/$n"
  done
  mkdir -p "$DUX_SKILLS_DIR/ship"; echo old > "$DUX_SKILLS_DIR/ship/SKILL.md"
  chmod 555 "$DUX_SKILLS_DIR"
  run dux-install --yes
  chmod 755 "$DUX_SKILLS_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: cannot move $DUX_SKILLS_DIR/ship"* ]]
  [ "$(cat "$DUX_SKILLS_DIR/ship/SKILL.md")" = old ]
}

@test "install is a finding when config cannot be seeded" {
  chmod 555 "$DUX_HOME/config"
  run dux-install
  chmod 755 "$DUX_HOME/config"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: cannot write $DUX_HOME/config/"* ]]
}

@test "install keeps a short project name out of the denylist and says so" {
  # This repo is registered as a project called "dux". Writing that into the
  # paths denylist made every tracked file match, and the lint went from a guard
  # to noise. A name too short to match safely is dropped, out loud.
  printf -- '- dux /tmp/dux main\n- widgets /tmp/widgets main\n' > "$DUX_HOME/data/projects.md"
  root="$DUX_HOME/ro2"; mkdir -p "$root/tests"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  refute grep -qx 'dux' "$root/tests/personal-identifiers.txt"
  grep -qx 'widgets' "$root/tests/personal-identifiers.txt"
  [[ "$output" == *"dropped 1 denylist entry shorter than 4 characters"* ]]
}

@test "install says nothing about dropped entries when it drops none" {
  printf -- '- widgets /tmp/widgets main\n' > "$DUX_HOME/data/projects.md"
  root="$DUX_HOME/ro3"; mkdir -p "$root/tests"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"dropped"* ]]
}
