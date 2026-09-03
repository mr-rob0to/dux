load helpers/setup

setup() {
  DUX_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")"; export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  export DUX_SKILLS_DIR="$DUX_HOME/skills-target"; mkdir -p "$DUX_SKILLS_DIR"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
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
  ln -s "$DUX_ROOT/skills/dux-project" "$DUX_SKILLS_DIR/dux-project"
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
