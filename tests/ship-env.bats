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

# The probe reads three things off the host: PATH, the user's agent directory
# and the project directory the gate runs in. Every test that reaches it builds
# all three, so the answer is the one the test asked for and never the machine's
# own codex install or the operator's own agents. Run against the real host,
# these tests would pass here and say nothing about anywhere else.
host() {  # $1.. any of: codex claude user-agent project-agent
  STUB="$DUX_HOME/host/bin"; PROBE_HOME="$DUX_HOME/host/home"
  PROJECT="$DUX_HOME/host/project"
  mkdir -p "$STUB" "$PROBE_HOME/.claude/agents" "$PROJECT/.claude/agents" "$PROJECT/sub"
  [ -d "$PROJECT/.git" ] || git init -q "$PROJECT"
  local w
  for w in "$@"; do
    case "$w" in
      codex | claude) printf '#!/bin/sh\nexit 0\n' > "$STUB/$w"; chmod +x "$STUB/$w" ;;
      user-agent)     : > "$PROBE_HOME/.claude/agents/security-reviewer.md" ;;
      project-agent)  : > "$PROJECT/.claude/agents/security-reviewer.md" ;;
      *) echo "host: unknown ingredient $w"; return 1 ;;
    esac
  done
}

# $STUB first and never an empty field: an empty PATH entry means the working
# directory, which would let a stray file in the checkout answer the probe.
on_host() {  # $1 checkout, $2.. arguments
  local c="$1"; shift
  ( cd "${PROJECT_CWD:-$PROJECT}" && env PATH="$STUB:/usr/bin:/bin" HOME="$PROBE_HOME" \
      CLAUDE_CONFIG_DIR="$PROBE_HOME/.claude" "$c/skills/ship/ship-env" "$@" )
}

# The claude command line the probe falls back to, in one place, so a test that
# asserts it cannot drift from the one ship-env prints.
claude_line='claude -p --safe-mode --disallowedTools WebFetch,WebSearch --model claude-fable-5-1 --effort high --permission-mode plan'
codex_line='codex exec -m gpt-5.6-sol --sandbox read-only -c project_doc_max_bytes=0'

# A checkout whose bundled defaults are the real ones, so the probe is reached
# the way a fresh clone reaches it.
auto_checkout() {  # prints the checkout path
  local c; c="$(fake_checkout)"
  printf 'auto\n' > "$c/templates/config/reviewer"
  printf 'auto\n' > "$c/templates/config/security-reviewer"
  echo "$c"
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
@test "the bundled defaults hand both keys to the probe" {
  c="$DUX_HOME/bundled"
  mkdir -p "$c/skills/ship" "$c/templates"
  cp "$DUX_ROOT/skills/ship/ship-env" "$c/skills/ship/ship-env"
  cp -R "$DUX_ROOT/templates/config" "$c/templates/config"
  [ ! -d "$c/config" ]
  host codex user-agent
  for k in reviewer security-reviewer; do
    grep -q '^#' "$c/templates/config/$k" || { echo "$k ships with no note line"; return 1; }
    # The word itself, not merely a file the reader can answer from: a bundled
    # default that had gone back to naming a command would still answer.
    [ "$(grep -v '^#' "$c/templates/config/$k" | grep -v '^$')" = auto ] \
      || { echo "templates/config/$k does not ship as auto"; return 1; }
    run --separate-stderr on_host "$c" "$k"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    case "$output" in '#'*) echo "ship-env answered a note line for $k"; return 1 ;; esac
  done
}

@test "auto picks codex for the code review when codex is on this host" {
  c="$(auto_checkout)"
  host codex claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
}

@test "auto picks claude for the code review when codex is not on this host" {
  c="$(auto_checkout)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
}

@test "auto with no reviewer on the host stops the gate and names the file" {
  c="$(auto_checkout)"
  host
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no code reviewer on this host: neither codex nor claude is on PATH; put a command line in $c/config/reviewer" ]
}

@test "auto picks the agent for the security pass when the user has defined one" {
  c="$(auto_checkout)"
  host claude user-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:security-reviewer" ]
}

# The project the gate runs in is the repository whose diff is being audited, and
# Claude Code would prefer a definition committed there over the operator's own.
# A branch that could put one in the probe's path would be appointing and writing
# the agent that reviews it, which is the whole of the security pass handed to
# the change under review.
@test "a security-reviewer definition committed to the project is not the agent" {
  c="$(auto_checkout)"
  host claude project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
  [ "$output" != "agent:security-reviewer" ]
  # The file really is where the gate would run, so the test is asking the
  # question it means to ask and not passing because nothing was written.
  [ -f "$PROJECT/.claude/agents/security-reviewer.md" ]
}

# A stated agent: value is not probed, and it is still dispatched by name into
# the worktree, so the refusal has to cover it too. This is the one the probe
# fix does not reach.
@test "a stated agent value is refused when the project defines that agent" {
  c="$(auto_checkout)"
  mkdir -p "$c/config"
  printf 'agent:security-reviewer\n' > "$c/config/security-reviewer"
  host claude user-agent project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"the repository being reviewed defines an agent called security-reviewer"* ]]
  [[ "$stderr" == *"$c/config/security-reviewer"* ]]
}

# The probed answer reaches the same dispatch, so it is refused on the same
# terms. Without this the operator's own machine, which defines the agent, is
# exactly the host the branch can hijack.
@test "a probed agent value is refused when the project defines that agent" {
  c="$(auto_checkout)"
  host claude user-agent project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"remove .claude/agents/security-reviewer.md from the worktree"* ]]
}

# The refusal is about a name collision, not about the project having a .claude
# directory. A project agent by some other name is nobody's business here.
@test "a project agent of another name does not refuse the gate" {
  c="$(auto_checkout)"
  host claude user-agent
  : > "$PROJECT/.claude/agents/some-other-agent.md"
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:security-reviewer" ]
}

# Nothing pins the directory the gate calls from, so a refusal anchored on it
# would miss a definition at the repository root, which is the ordinary place to
# put one and the whole case this check exists for.
@test "the refusal finds a root definition when the gate is called from a subdirectory" {
  c="$(auto_checkout)"
  host claude user-agent project-agent
  PROJECT_CWD="$PROJECT/sub"
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"the repository being reviewed defines an agent called security-reviewer"* ]]
  # The definition really is at the root and not in the directory called from,
  # so the test cannot pass by finding it under $PWD.
  [ -f "$PROJECT/.claude/agents/security-reviewer.md" ]
  [ ! -f "$PROJECT/sub/.claude/agents/security-reviewer.md" ]
}

# Both reviewer commands run inside the repository they read, and neither may
# take its instructions from it, or the change under review writes part of its
# own reviewer's brief. One test each: host() adds to the machine it is building
# rather than replacing it, so asking both questions in one test asks the first
# one twice.
@test "the codex reviewer does not read the reviewed repository's instructions" {
  c="$(auto_checkout)"
  host codex
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  case "$output" in
    *" -c project_doc_max_bytes=0"*) ;;
    *) echo "the codex reviewer loads the project's own instructions: $output"; return 1 ;;
  esac
}

@test "the claude reviewer does not read the reviewed repository's instructions" {
  c="$(auto_checkout)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  # Named, so this cannot pass on the codex line, which answers the same
  # question with a different flag.
  case "$output" in
    claude\ *" --safe-mode "*) ;;
    *) echo "the claude reviewer loads the project's own instructions: $output"; return 1 ;;
  esac
}

# A list-taking flag last would swallow the prompt the gate appends as one
# argument, and the run would end asking for a prompt it was given.
@test "the claude fallback ends on a flag that takes no list" {
  c="$(auto_checkout)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  case "$output" in
    *--disallowedTools*--permission-mode*) ;;
    *) echo "a list-taking flag is last in: $output"; return 1 ;;
  esac
}

@test "auto picks claude for the security pass when no agent is defined" {
  c="$(auto_checkout)"
  host codex claude
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  # codex is on this host and is not the answer: the security pass is its own
  # reviewer and never inherits the code reviewer's command.
  [ "$output" = "$claude_line" ]
}

@test "auto with no security reviewer on the host stops the gate and names the file" {
  c="$(auto_checkout)"
  host codex
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no security reviewer on this host: no security-reviewer agent definition and no claude on PATH; put a command line in $c/config/security-reviewer" ]
}

# The probe exists to answer where nobody has said what they want. A stated
# value is the whole reason the gate is configurable, and a probe that could
# overrule it would take the operator's reviewer away on a machine that happens
# to have another one.
@test "a stated value is never probed, whatever the host has" {
  c="$(auto_checkout)"
  mkdir -p "$c/config"
  printf 'my own reviewer command\n' > "$c/config/reviewer"
  printf 'agent:my-own-security-reviewer\n' > "$c/config/security-reviewer"
  host codex claude user-agent
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "my own reviewer command" ]
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:my-own-security-reviewer" ]
}

# What the installer leaves behind on first run is a copy of the bundled file,
# so the copy has to reach the probe as well. A seeded answer that froze the
# host's state at install time is the defect this change exists to remove.
@test "an auto seeded into config reaches the probe like the bundled file" {
  c="$(auto_checkout)"
  mkdir -p "$c/config"
  printf '# a note the installer copied\nauto\n' > "$c/config/reviewer"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
}

# Commenting the value out asks for the bundled default back, and the bundled
# default is the probe. Emptying both files is still a finding, above.
@test "a config of notes alone over an auto template still reaches the probe" {
  c="$(auto_checkout)"
  mkdir -p "$c/config"
  printf '# the operator commented the value out\n\n' > "$c/config/reviewer"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
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
