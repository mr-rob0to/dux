load helpers/setup

setup() {
  REPO_ROOT="$DUX_ROOT"
  DUX_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")"; export DUX_HOME
  # This file has its own setup, so it does not get the shared one's identity.
  # Without it make_repo cannot commit anywhere git has no global config, which
  # is every CI runner and no development machine.
  export GIT_AUTHOR_NAME=dux-test GIT_AUTHOR_EMAIL=dux-test@example.invalid
  export GIT_COMMITTER_NAME=dux-test GIT_COMMITTER_EMAIL=dux-test@example.invalid
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

# The registry line as bin/dux-project writes it. The first version of these
# tests invented "- <name> <path> <base>", which no code ever produces, so the
# parser read the whole "path=..." token as a path, the skip never fired outside
# the test, and the lint stayed broken. The next test pins this to the real
# writer.
seed_root() {  # $1 dir, $2 text a tracked file must contain
  # The skip only fires for a name that is really in this repo's tracked content,
  # so a root the test wants skipped has to be a repo that contains it.
  mkdir -p "$1/tests"
  git -C "$1" init -q
  printf '%s\n' "$2" > "$1/README.md"
  git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm seed
}

registry_line() {  # $1 name, $2 path
  printf -- '- %s path=%s base=main worktree=git issues=off (added 2026-01-01)\n' "$1" "$2"
}

@test "the registry fixture matches what dux-project actually writes" {
  repo="$DUX_HOME/realproj"; make_repo "$repo" main
  run dux-project add "$repo" --base main --name realproj
  [ "$status" -eq 0 ]
  written="$(grep '^- realproj ' "$DUX_HOME/data/projects.md")"
  fixture="$(registry_line realproj "$repo")"
  # Field 2 is the one the installer parses; if its shape drifts, this fails
  # here instead of silently disabling the skip.
  [ "$(printf '%s' "$written"  | cut -d' ' -f3 | cut -d= -f1)" = path ]
  [ "$(printf '%s' "$fixture"  | cut -d' ' -f3 | cut -d= -f1)" = path ]
  [ "$(printf '%s' "$written"  | cut -d' ' -f3)" = "$(printf '%s' "$fixture" | cut -d' ' -f3)" ]
}

@test "install leaves this repo's own project out of the denylist" {
  # Dux is registered as a project of itself. Writing its name into the paths
  # denylist made every tracked file match, because the name is matched as a
  # substring and every script here is called dux-something. Whole-word matching
  # does not help: a hyphen is a word boundary, so dux-install still matches.
  # The project whose checkout is this repo is the one entry that cannot mean
  # anything here, so it is the one that is skipped.
  root="$DUX_HOME/ro2"; seed_root "$root" "self-hosted, self-named, self everywhere"
  other="$DUX_HOME/widgets"; mkdir -p "$other"
  registry_line self "$root" > "$DUX_HOME/data/projects.md"
  registry_line widgets "$other" >> "$DUX_HOME/data/projects.md"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  refute grep -qx 'self' "$root/tests/personal-identifiers.txt"
  grep -qx 'widgets' "$root/tests/personal-identifiers.txt"
  [[ "$output" == *"left this repo's own project out of the denylist"* ]]
}

@test "a skipped name that starts with a hyphen is a name, not a grep option" {
  # dux-project allows a leading hyphen, so the skipped name can start with one.
  # It has to be THIS repo's project for the name to reach grep at all: without
  # --, grep reads it as options, the pipeline hides the error, and every other
  # project name disappears from the denylist instead of just this one.
  root="$DUX_HOME/ro5"; seed_root "$root" "the -dash name is written here"
  other="$DUX_HOME/widgets2"; mkdir -p "$other"
  registry_line -dash "$root" > "$DUX_HOME/data/projects.md"
  registry_line widgets2 "$other" >> "$DUX_HOME/data/projects.md"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  refute grep -qx -- '-dash' "$root/tests/personal-identifiers.txt"
  # The one that must survive: it is what breaks when grep eats the name.
  grep -qx 'widgets2' "$root/tests/personal-identifiers.txt"
}

@test "this repo registered under a personal name keeps its denylist entry" {
  # The skip is for a name that floods the lint, not for wherever a project sits.
  # Registering this checkout as "rq-dux" used to drop that name from the
  # denylist, so committing it into a tracked file later went unnoticed.
  root="$DUX_HOME/ro6"; seed_root "$root" "nothing personal in here"
  registry_line rq-dux "$root" > "$DUX_HOME/data/projects.md"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  grep -qx 'rq-dux' "$root/tests/personal-identifiers.txt"
  [[ "$output" != *"left this repo's own project out of the denylist"* ]]
}

@test "install keeps every other project name, short ones included" {
  # A short name elsewhere is still a name worth catching. It is not deleted
  # here; the lint refuses it by name, which is the operator's call to make.
  root="$DUX_HOME/ro3"; mkdir -p "$root/tests"
  # The path has to exist, or the comparison against DUX_ROOT is never reached
  # and this passes without testing anything.
  other="$DUX_HOME/api"; mkdir -p "$other"
  registry_line api "$other" > "$DUX_HOME/data/projects.md"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  grep -qx 'api' "$root/tests/personal-identifiers.txt"
}

@test "install says nothing about a skipped project when it skips none" {
  root="$DUX_HOME/ro4"; mkdir -p "$root/tests"
  other="$DUX_HOME/widgets"; mkdir -p "$other"
  registry_line widgets "$other" > "$DUX_HOME/data/projects.md"
  DUX_ROOT="$root" run dux-install --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"left this repo's own project"* ]]
}
