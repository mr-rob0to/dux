# Dux Milestone 1: Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Where this stands**
- Milestone: 1 of 6 (see `2026-09-03-dux-roadmap.md`). Tasks done: 0 of 8.
- reviewed_sha: none yet. Fix rounds used: 0 of 3.
- Next action: Task 1.

**Goal:** Stand up the Dux repo with its shared shell library, single-session lock, project registry, backend adapters for tmux and Herdr, doctor, operating contract, installer, bundled ship skill, MIT license, and a test harness with fake `claude` and fake `herdr`.

**Architecture:** Dux is an agent distro: a repo that an interactive Claude Code session inhabits. Bash scripts under `bin/` own mechanics and refuse loudly on surprises; `CLAUDE.md` and skills own judgment. Every script sources `bin/dux-env` for paths and helpers. Backends are selected once and called only through `bin/dux-backend`.

**Tech Stack:** bash 3.2-compatible scripts (macOS default), jq, bats-core for tests, shellcheck for lint, tmux, herdr 0.8.2 CLI, gh CLI, Claude Code 2.1.x.

**Spec:** `docs/superpowers/specs/2026-09-03-dux-orchestrator-design.md`

## Global Constraints

- `CLAUDE.md` is at most 150 lines (spec section 13).
- Scripts own mechanics; a script that meets a surprise stops and prints a finding, never guesses (spec section 3).
- Dux never writes to a project repo except through `dux-project` installing a missing PR template (spec sections 2 and 12).
- Backend endpoints are opaque strings recorded from creation responses, never derived from labels (spec section 9).
- Herdr `close` is `herdr pane close` on the exact recorded pane, never `workspace close`; refuse when it is the operator's focused pane (spec section 9).
- `data/`, `state/`, `.worktrees/` are gitignored (spec section 3).
- Every test is break-verified once: break the guarded condition, paste the failure into the commit, restore (spec section 15).
- Commit messages end with the Co-Authored-By and Claude-Session trailers used in this repo's history.
- Open source under MIT (spec section 18). No personal identifiers in tracked files: no operator home path, username, project names, or accounts. `make lint` enforces it from Task 8 on.

## Conventions used by every task

- Exit codes: `0` success, `1` unexpected error (`die`), `2` finding (a refusal the operator must read), `3` lock held by another live session.
- A finding is printed to stderr as `finding: <one line>` so command substitution can never swallow it; the calling agent relays it verbatim. bats `run` merges stderr into `$output`, so tests assert on `$output` unchanged.
- Tests run with `DUX_HOME` pointed at a temp dir so no test touches real `data/` or `state/`. A test that needs `DUX_HOME` unset copies `bin/dux-env` under a temp `DUX_ROOT` first.
- `.gitignore` already ignores `data/`, `state/`, `.worktrees/` (committed with the spec).
- Run the suite with `make test`. Run lint with `make lint`. `make check` runs both.

---

### Task 1: Test harness, Makefile, fakes

**Files:**
- Create: `Makefile`
- Create: `tests/helpers/setup.bash`
- Create: `tests/fakes/claude`
- Create: `tests/fakes/herdr`
- Create: `tests/harness.bats`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `load helpers/setup` in any bats file gives `$DUX_ROOT` (repo), `$DUX_HOME` (fresh temp dir with `data/`, `state/`, `config/`), and `tests/fakes` first on `PATH`.
- Produces: fake `claude` reads `$FAKE_CLAUDE_SCRIPT` (one directive per line: `status <state>: <text>`, `sleep <seconds>`, `exit <code>`), appends status lines to `$DUX_STATUS_LOG`, prints one stream-json-shaped line per directive to stdout.
- Produces: fake `herdr` appends every invocation to `$FAKE_HERDR_LOG`, answers `tab create` with pane `w1:p9`, `pane get` with exit 1 when `$FAKE_HERDR_DEAD` exists, `pane read` with the last N lines of `$FAKE_HERDR_OUTPUT`, and exit 0 for `pane run`, `pane close`, `pane report-agent`, `pane report-metadata`, `notification show`, `status`.

- [ ] **Step 1: Install tools**

Run: `brew install bats-core shellcheck`
Expected: `bats --version` prints `Bats 1.x`; `shellcheck --version` prints a version.

- [ ] **Step 2: Write the Makefile**

```makefile
SHELL := /bin/bash
BATS  ?= bats

.PHONY: test lint check

test:
	$(BATS) --recursive tests

lint:
	shellcheck -s bash bin/dux-* bin/backends/*.sh tests/fakes/* tests/helpers/*.bash

check: lint test
```

- [ ] **Step 3: Write the helper**

`tests/helpers/setup.bash`:

```bash
# Sourced by every bats file via `load helpers/setup`.
DUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUX_ROOT

setup() {
  DUX_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")"
  export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log"
  export FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  : > "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_OUTPUT"
}

teardown() {
  [ -n "${DUX_HOME:-}" ] && rm -rf "$DUX_HOME"
}
```

- [ ] **Step 4: Write fake claude**

`tests/fakes/claude`:

```bash
#!/usr/bin/env bash
# Fake Claude Code for tests. Ignores real flags; replays $FAKE_CLAUDE_SCRIPT.
set -u
script="${FAKE_CLAUDE_SCRIPT:-}"
log="${DUX_STATUS_LOG:-/dev/null}"
[ -n "$script" ] && [ -f "$script" ] || { echo '{"type":"result","subtype":"success"}'; exit 0; }
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    status\ *)  printf '%s\n' "${line#status }" >> "$log"
                printf '{"type":"assistant","text":%s}\n' "$(printf '%s' "${line#status }" | jq -Rs .)" ;;
    sleep\ *)   sleep "${line#sleep }" ;;
    exit\ *)    exit "${line#exit }" ;;
    *)          echo "fake claude: bad directive: $line" >&2; exit 99 ;;
  esac
done < "$script"
echo '{"type":"result","subtype":"success"}'
```

Run: `chmod +x tests/fakes/claude`

- [ ] **Step 5: Write fake herdr**

`tests/fakes/herdr`:

```bash
#!/usr/bin/env bash
# Fake herdr CLI for tests. Records calls; returns canned JSON.
set -u
printf '%s\n' "$*" >> "${FAKE_HERDR_LOG:-/dev/null}"
case "$1 ${2:-}" in
  "tab create")
    echo '{"result":{"tab":{"tab_id":"w1:t9"},"root_pane":{"pane_id":"w1:p9"}}}' ;;
  "pane get")
    if [ -e "${FAKE_HERDR_DEAD:-/nonexistent}" ]; then
      echo '{"error":{"code":"pane_not_found"}}' >&2; exit 1
    fi
    focused=false; [ -e "${FAKE_HERDR_FOCUSED:-/nonexistent}" ] && focused=true
    echo "{\"result\":{\"pane\":{\"pane_id\":\"$3\",\"focused\":$focused}}}" ;;
  "pane read")
    n=120; while [ $# -gt 0 ]; do [ "$1" = "--lines" ] && n="$2"; shift; done
    tail -n "$n" "${FAKE_HERDR_OUTPUT:-/dev/null}" ;;
  "pane close")
    [ -n "${FAKE_HERDR_CLOSE_FAIL:-}" ] && { echo '{"error":{"code":"close_failed"}}' >&2; exit 1; }
    echo '{"result":{}}' ;;
  "pane run"|"pane wait-output"|"pane report-agent"|"pane report-metadata"|"notification show")
    echo '{"result":{}}' ;;
  "status ")
    printf 'server:\n  status: running\n' ;;
  *)
    echo "fake herdr: unhandled: $*" >&2; exit 2 ;;
esac
```

Run: `chmod +x tests/fakes/herdr`

- [ ] **Step 6: Write the harness test**

`tests/harness.bats`:

```bash
load helpers/setup

@test "setup gives a fresh DUX_HOME with data, state, config" {
  [ -d "$DUX_HOME/data" ]; [ -d "$DUX_HOME/state" ]; [ -d "$DUX_HOME/config" ]
}

@test "fake claude replays a script into the status log" {
  export DUX_STATUS_LOG="$DUX_HOME/state/status.log"
  export FAKE_CLAUDE_SCRIPT="$DUX_HOME/state/script"
  printf 'status working: hello\nstatus done: PR https://x/1\nexit 0\n' > "$FAKE_CLAUDE_SCRIPT"
  run claude -p "ignored"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$DUX_STATUS_LOG")" = "working: hello" ]
  [ "$(sed -n 2p "$DUX_STATUS_LOG")" = "done: PR https://x/1" ]
}

@test "fake claude honors exit code" {
  export FAKE_CLAUDE_SCRIPT="$DUX_HOME/state/script"
  printf 'exit 7\n' > "$FAKE_CLAUDE_SCRIPT"
  run claude -p "ignored"
  [ "$status" -eq 7 ]
}

@test "fake herdr records calls and returns pane id on tab create" {
  run herdr tab create --workspace w1 --cwd /tmp --label dux-x --no-focus
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .result.root_pane.pane_id)" = "w1:p9" ]
  grep -q '^tab create --workspace w1' "$FAKE_HERDR_LOG"
}

@test "fake herdr pane get fails when FAKE_HERDR_DEAD exists" {
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run herdr pane get w1:p9
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 7: Run the tests**

Run: `make test`
Expected: 5 tests, all pass.

- [ ] **Step 8: Break-verify one guard**

Edit `tests/fakes/claude` so the `status` branch writes to `/dev/null` instead of `$log`. Run `make test`. Expected: "fake claude replays a script" fails on the `sed -n 1p` comparison. Restore the line. Run `make test` again, expected 5 pass. Paste the failure output into the commit body in Step 9.

- [ ] **Step 9: Add ignores and commit**

Append to `.gitignore`:

```
tests/tmp/
```

```bash
git add Makefile tests .gitignore
git commit -m "test: add bats harness with fake claude and fake herdr

Break-verified: <paste the failing assertion line from Step 8>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 2: Shared library `bin/dux-env`

**Files:**
- Create: `bin/dux-env`
- Test: `tests/dux-env.bats`

**Interfaces:**
- Produces (sourced, never executed): variables `DUX_ROOT`, `DUX_HOME` (defaults to `DUX_ROOT`), `DUX_DATA`, `DUX_STATE`, `DUX_CONFIG`, `DUX_TASKS`; functions `die <msg>` (stderr, exit 1), `finding <msg>` (stderr `finding: <msg>`, exit 2), `log <msg>` (stderr, prefixed `dux:`), `now` (UTC ISO-8601 seconds), `require_cmd <name>...` (dies naming the first missing command).

- [ ] **Step 1: Write the failing test**

`tests/dux-env.bats`:

```bash
load helpers/setup

@test "dux-env exports paths under DUX_HOME and creates them" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; echo "$DUX_DATA $DUX_STATE $DUX_CONFIG $DUX_TASKS"; [ -d "$DUX_TASKS" ]'
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/data $DUX_HOME/state $DUX_HOME/config $DUX_HOME/data/tasks" ]
}

@test "DUX_HOME defaults to DUX_ROOT when unset" {
  mkdir -p "$DUX_HOME/fakeroot/bin"; cp "$DUX_ROOT/bin/dux-env" "$DUX_HOME/fakeroot/bin/"
  run bash -c 'unset DUX_HOME DUX_ROOT; source "'"$DUX_HOME"'/fakeroot/bin/dux-env"; echo "$DUX_HOME"'
  [ "$output" = "$DUX_HOME/fakeroot" ]
}

@test "finding prints to stderr and exits 2" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; finding "worktree is dirty" 2>&1 >/dev/null'
  [ "$status" -eq 2 ]
  [ "$output" = "finding: worktree is dirty" ]
}

@test "finding is not swallowed by command substitution" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; f() { finding "inner"; }; x="$(f)" || exit $?; echo "reached"'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: inner"* ]]
  [[ "$output" != *reached* ]]
}

@test "die prints to stderr and exits 1" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; die "boom" 2>&1'
  [ "$status" -eq 1 ]
  [ "$output" = "dux: boom" ]
}

@test "require_cmd dies naming the missing command" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; require_cmd jq definitely-not-a-cmd 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-cmd"* ]]
}

@test "now is UTC ISO-8601 seconds" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; now'
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/dux-env.bats`
Expected: all 7 fail, "No such file or directory" for `bin/dux-env`.

- [ ] **Step 3: Write the library**

`bin/dux-env`:

```bash
#!/usr/bin/env bash
# Sourced by every dux script. Never executed directly.
# shellcheck disable=SC2034
set -u

DUX_ROOT="${DUX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DUX_HOME="${DUX_HOME:-$DUX_ROOT}"
DUX_DATA="$DUX_HOME/data"
DUX_STATE="$DUX_HOME/state"
DUX_CONFIG="$DUX_HOME/config"
DUX_TASKS="$DUX_DATA/tasks"
mkdir -p "$DUX_DATA" "$DUX_STATE" "$DUX_CONFIG" "$DUX_TASKS"
export DUX_ROOT DUX_HOME DUX_DATA DUX_STATE DUX_CONFIG DUX_TASKS

log()     { printf 'dux: %s\n' "$*" >&2; }
die()     { printf 'dux: %s\n' "$*" >&2; exit 1; }
finding() { printf 'finding: %s\n' "$*" >&2; exit 2; }
now()     { date -u +%Y-%m-%dT%H:%M:%SZ; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bats tests/dux-env.bats`
Expected: 7 pass.

- [ ] **Step 5: Break-verify**

Change `finding` to print to stdout (drop `>&2`). Run the file. Expected: "finding is not swallowed by command substitution" fails because `reached` is printed. Restore. Paste into commit.

- [ ] **Step 6: Commit**

```bash
git add bin/dux-env tests/dux-env.bats
git commit -m "feat: add dux-env shared library

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 3: Single-session lock `bin/dux-lock`

**Files:**
- Create: `bin/dux-lock`
- Test: `tests/dux-lock.bats`

**Interfaces:**
- Consumes: `bin/dux-env`.
- Produces: `dux-lock acquire` (writes `$DUX_STATE/dux.lock` with the session pid: `$DUX_SESSION_PID`, else `$CLAUDE_PID` which Claude Code sets in every Bash tool environment to the live `claude` process, else `$PPID`; exit 0, or exit 3 printing `held by pid <n>` if that pid is alive; reclaims a dead pid's lock), `dux-lock release` (removes the lock only if it holds our pid), `dux-lock status` (prints `free`, or `held by pid <n> (alive|dead)`), `dux-lock holder` (prints the pid or nothing).

- [ ] **Step 1: Write the failing test**

`tests/dux-lock.bats`:

```bash
load helpers/setup

@test "acquire creates the lock with our pid" {
  DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
}

@test "acquire uses CLAUDE_PID when DUX_SESSION_PID is unset" {
  run env -u DUX_SESSION_PID CLAUDE_PID=$$ dux-lock acquire
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
}

@test "second acquire by another live pid exits 3 and names the holder" {
  sleep 30 3>&- & other=$!
  DUX_SESSION_PID=$other dux-lock acquire
  DUX_SESSION_PID=$$ run dux-lock acquire
  kill $other
  [ "$status" -eq 3 ]
  [ "$output" = "held by pid $other" ]
}

@test "acquire reclaims a lock left by a dead pid" {
  echo 999999 > "$DUX_HOME/state/dux.lock"
  DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
}

@test "release removes only our own lock" {
  echo 424242 > "$DUX_HOME/state/dux.lock"
  DUX_SESSION_PID=$$ run dux-lock release
  [ "$status" -eq 0 ]
  [ -f "$DUX_HOME/state/dux.lock" ]
  echo $$ > "$DUX_HOME/state/dux.lock"
  DUX_SESSION_PID=$$ run dux-lock release
  [ ! -f "$DUX_HOME/state/dux.lock" ]
}

@test "status reports free, alive, dead" {
  run dux-lock status; [ "$output" = "free" ]
  echo $$ > "$DUX_HOME/state/dux.lock"
  run dux-lock status; [ "$output" = "held by pid $$ (alive)" ]
  echo 999999 > "$DUX_HOME/state/dux.lock"
  run dux-lock status; [ "$output" = "held by pid 999999 (dead)" ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/dux-lock.bats`
Expected: 6 fail, `dux-lock: command not found`.

- [ ] **Step 3: Write the script**

`bin/dux-lock`:

```bash
#!/usr/bin/env bash
# Single live Dux session per DUX_HOME. See spec section 7.
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"

lock="$DUX_STATE/dux.lock"
me="${DUX_SESSION_PID:-${CLAUDE_PID:-$PPID}}"

alive() { kill -0 "$1" 2>/dev/null; }

holder() { [ -f "$lock" ] && cat "$lock"; }

case "${1:-}" in
  acquire)
    h="$(holder || true)"
    if [ -n "$h" ] && [ "$h" != "$me" ] && alive "$h"; then
      echo "held by pid $h"; exit 3
    fi
    echo "$me" > "$lock" ;;
  release)
    h="$(holder || true)"
    [ "$h" = "$me" ] && rm -f "$lock"; exit 0 ;;
  status)
    h="$(holder || true)"
    if [ -z "$h" ]; then echo free
    elif alive "$h"; then echo "held by pid $h (alive)"
    else echo "held by pid $h (dead)"; fi ;;
  holder) holder || true ;;
  *) die "usage: dux-lock acquire|release|status|holder" ;;
esac
```

Run: `chmod +x bin/dux-lock`

- [ ] **Step 4: Run to verify it passes**

Run: `bats tests/dux-lock.bats`
Expected: 6 pass.

- [ ] **Step 5: Break-verify**

Remove the `alive "$h"` condition in `acquire` so any existing lock refuses. Run. Expected: "acquire reclaims a lock left by a dead pid" fails with status 3. Restore. Paste into commit.

- [ ] **Step 6: Commit**

```bash
git add bin/dux-lock tests/dux-lock.bats
git commit -m "feat: add dux-lock single-session lock

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 4: Project registry `bin/dux-project` and PR template

**Files:**
- Create: `bin/dux-project`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `templates/PULL_REQUEST_TEMPLATE.md` (the copy Dux installs into projects)
- Test: `tests/dux-project.bats`

**Interfaces:**
- Consumes: `bin/dux-env`.
- Produces: `dux-project add <name> <path> [--base <branch>] [--issues off|label:<x>]` appends one line to `$DUX_DATA/projects.md` and installs the PR template if the project lacks one, printing `installed PR template; commit it in <path> before dispatching ship tasks` because an untracked file is invisible to worktrees; `dux-project list` prints names; `dux-project get <name> <key>` prints one field (`path`, `base`, `worktree`, `issues`); `dux-project resolve-base <path>` prints the base branch or a finding when signals disagree.
- Registry line format, exactly: `- <name> path=<abs> base=<branch> worktree=<make|script|git> issues=<off|label:x> (added <YYYY-MM-DD>)`.

- [ ] **Step 1: Write the failing test**

`tests/dux-project.bats`:

```bash
load helpers/setup

make_repo() {  # $1 dir, $2 default branch; creates a bare origin and a clone
  local d="$1" b="$2"
  git init -q -b "$b" "$d.origin.tmp" && (cd "$d.origin.tmp" && git commit -q --allow-empty -m init)
  git clone -q --bare "$d.origin.tmp" "$d.origin" && rm -rf "$d.origin.tmp"
  git clone -q "$d.origin" "$d"
  (cd "$d" && git remote set-head origin "$b")
}

@test "add writes a registry line with detected git worktree mechanism" {
  make_repo "$DUX_HOME/repoA" main
  run dux-project add repoA "$DUX_HOME/repoA"
  [ "$status" -eq 0 ]
  line="$(grep '^- repoA ' "$DUX_HOME/data/projects.md")"
  [[ "$line" == "- repoA path=$DUX_HOME/repoA base=main worktree=git issues=off (added "* ]]
}

@test "add detects make worktree target" {
  make_repo "$DUX_HOME/repoB" main
  printf 'worktree:\n\t@echo wt\n' > "$DUX_HOME/repoB/Makefile"
  dux-project add repoB "$DUX_HOME/repoB"
  [ "$(dux-project get repoB worktree)" = "make" ]
}

@test "add honors --base and --issues" {
  make_repo "$DUX_HOME/repoC" main
  dux-project add repoC "$DUX_HOME/repoC" --base staging --issues label:dux
  [ "$(dux-project get repoC base)" = "staging" ]
  [ "$(dux-project get repoC issues)" = "label:dux" ]
}

@test "add refuses a duplicate name with a finding" {
  make_repo "$DUX_HOME/repoD" main
  dux-project add repoD "$DUX_HOME/repoD"
  run dux-project add repoD "$DUX_HOME/repoD"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: project repoD already registered"* ]]
}

@test "add refuses a path that is not a git repo" {
  mkdir -p "$DUX_HOME/notrepo"
  run dux-project add x "$DUX_HOME/notrepo"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: not a git repository"* ]]
}

@test "add installs the PR template when absent and leaves an existing one" {
  make_repo "$DUX_HOME/repoE" main
  dux-project add repoE "$DUX_HOME/repoE"
  [ -f "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md" ]
  grep -q '^## How to review' "$DUX_HOME/repoE/.github/PULL_REQUEST_TEMPLATE.md"
  make_repo "$DUX_HOME/repoF" main
  mkdir -p "$DUX_HOME/repoF/.github"; echo custom > "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md"
  run dux-project add repoF "$DUX_HOME/repoF"
  [ "$(cat "$DUX_HOME/repoF/.github/PULL_REQUEST_TEMPLATE.md")" = "custom" ]
  [[ "$output" == *"existing PR template left alone"* ]]
}

@test "add stops with a finding when base signals disagree" {
  make_repo "$DUX_HOME/repoH" main
  printf '# Repo\n\nThe base branch is `staging`.\n' > "$DUX_HOME/repoH/CLAUDE.md"
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project add repoH "$DUX_HOME/repoH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: base branch signals disagree"* ]]
  ! grep -q '^- repoH ' "$DUX_HOME/data/projects.md"
}

@test "add with a missing path is a finding, not a bash error" {
  run dux-project add x "$DUX_HOME/does-not-exist"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: not a git repository"* ]]
}

@test "resolve-base uses origin/HEAD when gh is unavailable" {
  make_repo "$DUX_HOME/repoG" develop
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" run dux-project resolve-base "$DUX_HOME/repoG"
  [ "$output" = "develop" ]
}

@test "list prints names in order" {
  make_repo "$DUX_HOME/r1" main; make_repo "$DUX_HOME/r2" main
  dux-project add r1 "$DUX_HOME/r1"; dux-project add r2 "$DUX_HOME/r2"
  run dux-project list
  [ "$output" = $'r1\nr2' ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/dux-project.bats`
Expected: 10 fail, `dux-project: command not found`.

- [ ] **Step 3: Write the PR template**

`templates/PULL_REQUEST_TEMPLATE.md` (and copy the same content to `.github/PULL_REQUEST_TEMPLATE.md` for this repo):

```markdown
## Why
One or two sentences. Problem and link to the plan or issue.

## What changed
- User-visible first, then internal. Flag anything surprising.

## How to review
Suggested file order. What needs thought, what is mechanical.

## Verification
- Checks: command and result
- Evidence: screenshot or recording for UI, or why none
- Break-verification: which guard was broken, the failure it printed

## Reviews
- Codex (model): N findings, fixed / logged
- Security: areas clean, findings
<details><summary>Full findings</summary>

</details>

## Risk
Low | Medium | High, one-line rationale. Backwards compatibility, deploy ordering, deferred follow-ups.
```

- [ ] **Step 4: Write the script**

`bin/dux-project`:

```bash
#!/usr/bin/env bash
# Project registry. See spec section 4.
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"

registry="$DUX_DATA/projects.md"
touch "$registry"

field() {  # $1 name, $2 key
  grep "^- $1 " "$registry" | sed -n "s/.* $2=\([^ ]*\).*/\1/p"
}

detect_worktree() {  # $1 path
  if [ -f "$1/Makefile" ] && grep -qE '^worktree:' "$1/Makefile"; then echo make
  elif ls "$1"/scripts/*worktree* >/dev/null 2>&1; then echo script
  else echo git; fi
}

resolve_base() {  # $1 path. Spec section 4 and /ship step 0.
  local p="$1" forge="" head="" docs=""
  if command -v gh >/dev/null 2>&1; then
    forge="$(cd "$p" && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
  fi
  head="$(cd "$p" && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  for f in CLAUDE.md AGENTS.md CONTRIBUTING.md; do
    [ -f "$p/$f" ] || continue
    docs="$(grep -oiE '(base|default|trunk) branch[^a-z]{0,6}`[a-z0-9_./-]+`' "$p/$f" | head -1 | grep -oE '`[^`]+`' | tr -d '`' || true)"
    [ -n "$docs" ] && break
  done
  local candidates
  candidates="$(printf '%s\n%s\n%s\n' "$docs" "$forge" "$head" | grep -v '^$' | sort -u)"
  [ -z "$candidates" ] && finding "base branch cannot be determined for $p (no gh, no origin/HEAD, no docs)"
  if [ "$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')" -gt 1 ]; then
    finding "base branch signals disagree for $p: docs=${docs:-none} forge=${forge:-none} origin/HEAD=${head:-none}"
  fi
  echo "$candidates"
}

install_template() {  # $1 path
  local t="$1/.github/PULL_REQUEST_TEMPLATE.md"
  if [ -f "$t" ]; then log "existing PR template left alone: $t"; echo "existing PR template left alone"; return; fi
  mkdir -p "$1/.github" && cp "$DUX_ROOT/templates/PULL_REQUEST_TEMPLATE.md" "$t"
  echo "installed PR template; commit it in $1 before dispatching ship tasks"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  add)
    name="${1:?name}"; path="${2:?path}"; given="$2"; shift 2
    base=""; issues="off"
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) base="$2"; shift 2 ;;
        --issues) issues="$2"; shift 2 ;;
        *) die "unknown flag $1" ;;
      esac
    done
    path="$(cd "$path" 2>/dev/null && pwd)" || finding "not a git repository: $given"
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || finding "not a git repository: $path"
    grep -q "^- $name " "$registry" && finding "project $name already registered"
    case "$issues" in off|label:*) ;; *) die "--issues must be off or label:<name>" ;; esac
    if [ -z "$base" ]; then base="$(resolve_base "$path")" || exit $?; fi
    wt="$(detect_worktree "$path")"
    printf -- '- %s path=%s base=%s worktree=%s issues=%s (added %s)\n' \
      "$name" "$path" "$base" "$wt" "$issues" "$(date -u +%Y-%m-%d)" >> "$registry"
    install_template "$path"
    log "registered $name base=$base worktree=$wt issues=$issues" ;;
  list) sed -n 's/^- \([^ ]*\) .*/\1/p' "$registry" ;;
  get)
    name="${1:?name}"; key="${2:?key}"
    grep -q "^- $name " "$registry" || finding "project $name not registered"
    field "$name" "$key" ;;
  resolve-base) resolve_base "${1:?path}" ;;
  *) die "usage: dux-project add|list|get|resolve-base" ;;
esac
```

Run: `chmod +x bin/dux-project`

- [ ] **Step 5: Run to verify it passes**

Run: `bats tests/dux-project.bats`
Expected: 10 pass. If "resolve-base" fails because a real `gh` on `PATH` answers for the temp repo, confirm the test's restricted `PATH` excludes it; the test pins `PATH` to `/usr/bin:/bin` plus `bin/`.

- [ ] **Step 6: Break-verify**

Change `|| exit $?` after `resolve_base` to `|| true`. Run. Expected: "add stops with a finding when base signals disagree" fails because a registry line was written. Restore. Then delete the duplicate-name `finding` line. Expected: "add refuses a duplicate name" fails with status 0. Restore. Paste into commit.

- [ ] **Step 7: Commit**

```bash
git add bin/dux-project templates .github tests/dux-project.bats
git commit -m "feat: add dux-project registry and PR template install

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 5: Backend adapters and `bin/dux-backend`

**Files:**
- Create: `bin/dux-backend`
- Create: `bin/backends/tmux.sh`
- Create: `bin/backends/herdr.sh`
- Test: `tests/backend-adapter.bats` (runs once per backend via `DUX_BACKEND`)
- Test: `tests/dux-backend-select.bats`

**Interfaces:**
- Consumes: `bin/dux-env`.
- Produces: `dux-backend name` prints `tmux` or `herdr`; `dux-backend open <id> <cwd> <cmd>` prints an endpoint; `dux-backend exists <endpoint>` exit 0/1 (container present; process liveness is milestone 2's pid file); `dux-backend tail <endpoint> <n>`; `dux-backend close <endpoint>` (finding if it is the focused pane); `dux-backend notify <title> <body>`.
- Endpoint formats: `tmux:<session>:<window_id>` and `herdr:<pane_id>`.
- Each adapter file defines `backend_open`, `backend_exists`, `backend_tail`, `backend_close`, `backend_notify` with the same arguments. `<cmd>` is always one absolute path plus arguments; Dux never passes shell syntax.
- Selection: `$DUX_BACKEND` env, else `$DUX_CONFIG/backend` file, else `herdr` when `HERDR_ENV=1` and `TMUX` unset, else `tmux`.
- tmux socket: `$DUX_TMUX_SOCKET` if set (tests use `dux-test`), else the default server. tmux session: `$DUX_TMUX_SESSION` if set, else the current session from `$TMUX`, else a session named `dux` created on demand.

- [ ] **Step 1: Write the selection test**

`tests/dux-backend-select.bats`:

```bash
load helpers/setup

@test "DUX_BACKEND env wins" {
  DUX_BACKEND=herdr run dux-backend name; [ "$output" = herdr ]
  DUX_BACKEND=tmux run dux-backend name; [ "$output" = tmux ]
}

@test "config/backend file is second" {
  echo herdr > "$DUX_HOME/config/backend"
  unset DUX_BACKEND
  run dux-backend name; [ "$output" = herdr ]
}

@test "HERDR_ENV=1 without TMUX selects herdr, otherwise tmux" {
  unset DUX_BACKEND; rm -f "$DUX_HOME/config/backend"
  HERDR_ENV=1 TMUX= run env -u TMUX HERDR_ENV=1 dux-backend name; [ "$output" = herdr ]
  run env -u HERDR_ENV TMUX=/tmp/x dux-backend name; [ "$output" = tmux ]
  run env -u HERDR_ENV -u TMUX dux-backend name; [ "$output" = tmux ]
}

@test "unknown backend value is a finding" {
  DUX_BACKEND=zellij run dux-backend name
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown backend zellij"* ]]
}
```

- [ ] **Step 2: Write the shared adapter test**

`tests/backend-adapter.bats`:

```bash
load helpers/setup

# Runs for whichever backend $DUX_BACKEND names. The Makefile runs it twice.
setup_file() {
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    export DUX_TMUX_SOCKET=dux-test DUX_TMUX_SESSION=duxtest
    tmux -L dux-test kill-server 2>/dev/null || true
    tmux -L dux-test new-session -d -s duxtest -x 80 -y 24
  fi
}
teardown_file() {
  [ "${DUX_BACKEND:-}" = tmux ] && tmux -L dux-test kill-server 2>/dev/null || true
}

@test "open returns an endpoint for this backend and runs the command" {
  [ -n "${DUX_BACKEND:-}" ] || skip "DUX_BACKEND unset"
  run dux-backend open t1 "$DUX_HOME" "echo hello-from-worker; sleep 5"
  [ "$status" -eq 0 ]
  [[ "$output" == "$DUX_BACKEND:"* ]]
  echo "$output" > "$DUX_HOME/state/t1.endpoint"
}

@test "exists is true while the container is present" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t2 "$DUX_HOME" "sleep 5")"
  run dux-backend exists "$ep"; [ "$status" -eq 0 ]
}

@test "tmux container survives command exit (remain-on-exit) so output can be read" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip "herdr panes always outlive their process"
  ep="$(dux-backend open t3 "$DUX_HOME" "echo bye")"; sleep 1
  run dux-backend exists "$ep"; [ "$status" -eq 0 ]
  run dux-backend tail "$ep" 5; [[ "$output" == *bye* ]]
}

@test "exists is false after close or when the pane is gone" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = herdr ]; then export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"; ep="herdr:w1:p9"
  else ep="$(dux-backend open t3b "$DUX_HOME" "sleep 5")"; dux-backend close "$ep"; fi
  run dux-backend exists "$ep"; [ "$status" -eq 1 ]
}

@test "tail returns the last n lines" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = herdr ]; then printf 'a\nb\nc\n' > "$FAKE_HERDR_OUTPUT"; ep="herdr:w1:p9"
  else ep="$(dux-backend open t4 "$DUX_HOME" "printf 'a\nb\nc\n'; sleep 5")"; sleep 1; fi
  run dux-backend tail "$ep" 2
  n=${#lines[@]}
  [ "${lines[$((n-2))]}" = b ] && [ "${lines[$((n-1))]}" = c ]
}

@test "close removes the container; alive then false" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t5 "$DUX_HOME" "sleep 30")"
  run dux-backend close "$ep"; [ "$status" -eq 0 ]
  if [ "$DUX_BACKEND" = herdr ]; then grep -q "^pane close w1:p9" "$FAKE_HERDR_LOG"
  else run dux-backend exists "$ep"; [ "$status" -eq 1 ]; fi
}

@test "herdr close failure is a finding, never silent" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_CLOSE_FAIL=1
  run dux-backend close "herdr:w1:p9"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane close failed"* ]]
}

@test "close refuses the focused pane with a finding" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip "tmux focus refusal covered manually in dogfood"
  export FAKE_HERDR_FOCUSED="$DUX_HOME/state/focused"; touch "$FAKE_HERDR_FOCUSED"
  run dux-backend close "herdr:w1:p9"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to close focused pane"* ]]
}

@test "notify reaches the backend" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  run dux-backend notify "Dux" "hello"; [ "$status" -eq 0 ]
  if [ "$DUX_BACKEND" = herdr ]; then grep -q '^notification show Dux --body hello' "$FAKE_HERDR_LOG"; fi
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `DUX_BACKEND=herdr bats tests/backend-adapter.bats tests/dux-backend-select.bats`
Expected: all fail, `dux-backend: command not found`.

- [ ] **Step 4: Write the dispatcher**

`bin/dux-backend`:

```bash
#!/usr/bin/env bash
# Backend selection and dispatch. See spec section 9.
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"

select_backend() {
  local b="${DUX_BACKEND:-}"
  [ -z "$b" ] && [ -f "$DUX_CONFIG/backend" ] && b="$(tr -d '[:space:]' < "$DUX_CONFIG/backend")"
  if [ -z "$b" ]; then
    if [ "${HERDR_ENV:-}" = 1 ] && [ -z "${TMUX:-}" ]; then b=herdr; else b=tmux; fi
  fi
  case "$b" in tmux|herdr) echo "$b" ;; *) finding "unknown backend $b (expected tmux or herdr)" ;; esac
}

backend="$(select_backend)" || exit $?
# shellcheck source=/dev/null
source "$DUX_ROOT/bin/backends/$backend.sh"

cmd="${1:-}"; shift || true
case "$cmd" in
  name)   echo "$backend" ;;
  open)   backend_open "${1:?id}" "${2:?cwd}" "${3:?cmd}" ;;
  exists) backend_exists "${1:?endpoint}" ;;
  tail)   backend_tail "${1:?endpoint}" "${2:-40}" ;;
  close)  backend_close "${1:?endpoint}" ;;
  notify) backend_notify "${1:?title}" "${2:-}" ;;
  *) die "usage: dux-backend name|open|exists|tail|close|notify" ;;
esac
```

Run: `chmod +x bin/dux-backend`

- [ ] **Step 5: Write the tmux adapter**

`bin/backends/tmux.sh`:

```bash
#!/usr/bin/env bash
# tmux adapter. Sourced by dux-backend. Endpoint: tmux:<session>:<window_id>
set -u

_tmux() {
  if [ -n "${DUX_TMUX_SOCKET:-}" ]; then tmux -L "$DUX_TMUX_SOCKET" "$@"; else tmux "$@"; fi
}

_session() {
  if [ -n "${DUX_TMUX_SESSION:-}" ]; then echo "$DUX_TMUX_SESSION"
  elif [ -n "${TMUX:-}" ]; then _tmux display-message -p '#{session_name}'
  else
    _tmux has-session -t dux 2>/dev/null || _tmux new-session -d -s dux -x 120 -y 40
    echo dux
  fi
}

_win() { local ep="$1"; echo "${ep##*:}"; }          # window id (@N)
_ses() { local ep="${1#tmux:}"; echo "${ep%%:*}"; }  # session name

backend_open() {  # id cwd cmd
  local id="$1" cwd="$2" cmd="$3" ses wid
  ses="$(_session)"
  wid="$(_tmux new-window -d -t "$ses" -n "dux-$id" -c "$cwd" -P -F '#{window_id}' "$cmd")" \
    || finding "tmux could not open a window for $id"
  _tmux set-option -w -t "$wid" remain-on-exit on >/dev/null
  echo "tmux:$ses:$wid"
}

backend_exists() {  # endpoint
  local wid; wid="$(_win "$1")"
  _tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -q "^$wid$"
}

backend_tail() {  # endpoint n
  local wid; wid="$(_win "$1")"
  _tmux capture-pane -p -t "$wid" -S "-$2" 2>/dev/null | sed '/^$/d' | tail -n "$2"
}

backend_close() {  # endpoint
  local wid active attached; wid="$(_win "$1")"
  active="$(_tmux display-message -p -t "$wid" '#{window_active}' 2>/dev/null || echo 0)"
  attached="$(_tmux display-message -p -t "$wid" '#{session_attached}' 2>/dev/null || echo 0)"
  if [ "$active" = 1 ] && [ "$attached" != 0 ]; then finding "refusing to close focused pane $1"; fi
  _tmux kill-window -t "$wid" 2>/dev/null || true
}

backend_notify() {  # title body
  _tmux display-message "$1: $2" 2>/dev/null || true
}
```

- [ ] **Step 6: Write the Herdr adapter**

`bin/backends/herdr.sh`:

```bash
#!/usr/bin/env bash
# Herdr adapter. Sourced by dux-backend. Endpoint: herdr:<pane_id>
# Exact pane ids from create responses only. Never workspace close. Spec section 9.
set -u

_pane() { echo "${1#herdr:}"; }

backend_open() {  # id cwd cmd
  local id="$1" cwd="$2" cmd="$3" ws="${HERDR_WORKSPACE_ID:-}" out pane
  [ -n "$ws" ] || finding "HERDR_WORKSPACE_ID is unset; Dux is not running inside a Herdr pane"
  out="$(herdr tab create --workspace "$ws" --cwd "$cwd" --label "dux-$id" --no-focus)" \
    || finding "herdr tab create failed for $id"
  pane="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
  [ -n "$pane" ] || finding "herdr tab create returned no pane id for $id"
  # pane run types into a live shell; wait for a prompt so the command is not lost.
  herdr pane wait-output "$pane" --regex '[$%>#] ?$' --timeout 10000 >/dev/null 2>&1 || true
  herdr pane run "$pane" "$cmd" >/dev/null || finding "herdr pane run failed for $id on $pane"
  echo "herdr:$pane"
}

backend_exists() {  # endpoint
  herdr pane get "$(_pane "$1")" >/dev/null 2>&1
}

backend_tail() {  # endpoint n
  herdr pane read "$(_pane "$1")" --source recent-unwrapped --lines "$2" 2>/dev/null
}

backend_close() {  # endpoint
  local pane focused; pane="$(_pane "$1")"
  focused="$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane.focused // false')"
  [ "$focused" = true ] && finding "refusing to close focused pane $pane"
  herdr pane close "$pane" >/dev/null 2>&1 || finding "herdr pane close failed for $pane"
}

backend_notify() {  # title body
  herdr notification show "$1" --body "$2" --sound done >/dev/null 2>&1 || true
}
```

- [ ] **Step 7: Make the Makefile run the adapter test per backend**

Replace the `test` target in `Makefile`:

```makefile
test:
	$(BATS) --recursive tests --filter-tags '!adapter'
	DUX_BACKEND=herdr $(BATS) tests/backend-adapter.bats
	DUX_BACKEND=tmux  $(BATS) tests/backend-adapter.bats
```

Add `# bats file_tags=adapter` as the first line of `tests/backend-adapter.bats` so the recursive run skips it.

- [ ] **Step 8: Run to verify they pass**

Run: `make test`
Expected: selection 4 pass; herdr adapter 8 pass, 1 skipped (remain-on-exit); tmux adapter 7 pass, 2 skipped (focus refusal, close failure).

- [ ] **Step 9: Break-verify**

In `bin/backends/herdr.sh`, change `backend_close` to skip the focused check. Run `DUX_BACKEND=herdr bats tests/backend-adapter.bats`. Expected: "close refuses the focused pane" fails with status 0. Restore. Paste into commit.

- [ ] **Step 10: Commit**

```bash
git add bin/dux-backend bin/backends tests/backend-adapter.bats tests/dux-backend-select.bats Makefile
git commit -m "feat: add tmux and herdr backend adapters behind dux-backend

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 6: `bin/dux-doctor`

**Files:**
- Create: `bin/dux-doctor`
- Test: `tests/dux-doctor.bats`

**Interfaces:**
- Consumes: `dux-env`, `dux-backend name`, `dux-lock status`.
- Produces: `dux-doctor` prints one line per check (`ok <check>` or `FAIL <check>: <why>`), then `backend: <name>` and `lock: <status>`; exit 0 when all ok, 1 otherwise. Checks: `claude`, `codex`, `gh`, `jq`, `git`, `gh auth status`, backend CLI present, registry file exists with at least one project.

- [ ] **Step 1: Write the failing test**

`tests/dux-doctor.bats`:

```bash
load helpers/setup

@test "doctor passes with fakes, gh stub, and one project" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok claude"* ]] && [[ "$output" == *"backend: herdr"* ]] && [[ "$output" == *"lock: free"* ]]
}

@test "doctor fails and names a missing tool" {
  PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:/usr/bin:/bin" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL codex"* ]]
}

@test "doctor fails on empty registry" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL registry"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/dux-doctor.bats`
Expected: 3 fail, command not found.

- [ ] **Step 3: Write the script**

`bin/dux-doctor`:

```bash
#!/usr/bin/env bash
# Preflight. See spec sections 3 and 9.
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"

rc=0
ok()   { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; rc=1; }

for c in claude codex gh jq git; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || fail "$c" "not on PATH"
done
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && ok "gh auth" || fail "gh auth" "run gh auth login"
fi

backend="$("$DUX_ROOT/bin/dux-backend" name 2>/dev/null)" || backend=""
case "$backend" in
  tmux)  command -v tmux  >/dev/null && ok "tmux"  || fail "tmux"  "not on PATH" ;;
  herdr) command -v herdr >/dev/null && ok "herdr" || fail "herdr" "not on PATH" ;;
  *)     fail "backend" "could not select a backend" ;;
esac

reg="$DUX_DATA/projects.md"
if [ -s "$reg" ] && grep -q '^- ' "$reg"; then ok "registry"; else fail "registry" "no projects in $reg; run dux-project add"; fi

echo "backend: ${backend:-none}"
echo "lock: $("$DUX_ROOT/bin/dux-lock" status)"
exit $rc
```

Run: `chmod +x bin/dux-doctor`

- [ ] **Step 4: Run to verify it passes**

Run: `bats tests/dux-doctor.bats`
Expected: 3 pass.

- [ ] **Step 5: Break-verify**

Change the registry check to `ok "registry"` unconditionally. Run. Expected: "doctor fails on empty registry" fails with status 0. Restore. Paste into commit.

- [ ] **Step 6: Commit**

```bash
git add bin/dux-doctor tests/dux-doctor.bats
git commit -m "feat: add dux-doctor preflight

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

### Task 7: Operating contract `CLAUDE.md`, `dux-project` skill, README

**Files:**
- Create: `CLAUDE.md`
- Create: `.claude/settings.json`
- Create: `skills/dux-project/SKILL.md`
- Create: `README.md`
- Test: `tests/contract.bats`

**Interfaces:**
- Produces: the always-loaded contract every later milestone extends. Sections and their order are fixed here; later milestones add lines, never sections.

- [ ] **Step 1: Write the failing test**

`tests/contract.bats`:

```bash
load helpers/setup

@test "CLAUDE.md is at most 150 lines" {
  [ "$(wc -l < "$DUX_ROOT/CLAUDE.md")" -le 150 ]
}

@test "CLAUDE.md carries the fixed section headers in order" {
  run grep -E '^## ' "$DUX_ROOT/CLAUDE.md"
  [ "${lines[0]}" = "## Identity" ]
  [ "${lines[1]}" = "## Hard rules" ]
  [ "${lines[2]}" = "## Session start" ]
  [ "${lines[3]}" = "## Task lifecycle" ]
  [ "${lines[4]}" = "## Talking to the operator" ]
  [ "${lines[5]}" = "## Skills" ]
}

@test "every skill has frontmatter name and description" {
  for f in "$DUX_ROOT"/skills/*/SKILL.md; do
    head -5 "$f" | grep -q '^name: ' || { echo "missing name: $f"; return 1; }
    head -5 "$f" | grep -q '^description: ' || { echo "missing description: $f"; return 1; }
  done
}

@test "session hooks acquire and release the lock" {
  run jq -r '.hooks.SessionStart[0].hooks[0].command' "$DUX_ROOT/.claude/settings.json"
  [[ "$output" == *"dux-lock acquire"* ]]
  run jq -r '.hooks.SessionEnd[0].hooks[0].command' "$DUX_ROOT/.claude/settings.json"
  [[ "$output" == *"dux-lock release"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/contract.bats`
Expected: 4 fail (no CLAUDE.md, no skills, no settings).

- [ ] **Step 3: Write CLAUDE.md**

`CLAUDE.md`:

```markdown
# Dux

## Identity

You are Dux, the operator's orchestrator. You dispatch, supervise, and report on
worker agents across the projects in `data/projects.md`. You talk to the operator
about goals and decisions. Workers do the work; you never do it yourself.

Scripts in `bin/` own mechanics. When a script prints `finding: ...`, relay it
verbatim and stop that action. Never work around a finding.

## Hard rules

1. Never write to a project repo. Workers change projects inside worktrees and
   deliver through `/ship`. The one exception is `dux-project` installing a
   missing PR template on registration.
2. Never merge a PR without the operator's explicit word in this conversation.
3. Never read a worker's output except through `dux-recover`, and then only the
   last 40 lines. Status lines are your only routine view of a worker.
4. Never put conversation history in a brief. A brief holds intent, acceptance
   criteria, project facts, rules, and definition of done.
5. Never tear down a worktree with uncommitted or unpushed work. A refusal is a
   finding, not an obstacle.
6. Never hold the fleet in conversation memory. `data/` and the backend are the
   state; after a restart, reconcile from them.
7. If `dux-lock acquire` exits 3, you are read-only: no spawn, teardown, or
   recover. Say so.

## Session start

A SessionStart hook has already run `bin/dux-lock acquire`; its output is in
your context. If it said `held by pid`, you are read-only. Then run
`bin/dux-doctor` and `bin/dux-status` (when it exists). Fix anything doctor
fails before dispatching. Show the digest. Then arm the Monitor (milestone 3).
Restart this session daily or after 40 wakes; state is on disk.

## Task lifecycle

queued -> running -> (needs-decision | blocked)* -> done | failed

- Shapes: `plan` (Fable, high effort, docs-only PR), `ship` (Opus, one milestone,
  runs `/ship`), `scout` (Sonnet, report only).
- Worker status protocol, appended to `data/tasks/<id>/status.log`:
  `working: ...`, `needs-decision: ...`, `blocked: ...`, `done: PR <url> | report`,
  `failed: ...`.
- Only `done`, `failed`, `blocked`, `needs-decision`, `stale`, `dead` wake you.
- `needs-decision` and `blocked` are relayed to the operator verbatim.

## Talking to the operator

- Answer first, one or two lines. Then bullets, one idea each.
- Outcomes, not mechanics. PR link, risk, what needs a decision. No task ids,
  branch names, or paths unless asked.
- One question at a time, options as bullets, your recommendation in one line.
- Push a phone notification only for `done` with a PR, `needs-decision`, and
  `failed`. Under 200 characters, leading with what to do.

## Skills

- `skills/dux-project` to register a repo.
- `skills/dux-dispatch` (milestone 2) to turn a goal into a running task.
- `skills/dux-status` (milestone 3) for the fleet digest.
- `skills/dux-recover` (milestone 3) for stuck, dead, or failed workers.
```

- [ ] **Step 4: Write the session hooks**

`.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/bin/dux-lock acquire || true" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/bin/dux-lock release" } ] }
    ]
  }
}
```

`dux-lock` reads `CLAUDE_PID` from the hook environment, so the recorded pid is
the live `claude` process, not the hook's shell.

- [ ] **Step 5: Write the dux-project skill**

`skills/dux-project/SKILL.md`:

```markdown
---
name: dux-project
description: Register a repository with Dux so tasks can be dispatched to it. Use when the operator names a repo Dux does not know, or asks to add, list, or inspect projects.
---

# dux-project

## Register

1. Confirm the absolute path exists and is a git clone with an `origin` remote.
2. Run `bin/dux-project resolve-base <path>`. If it prints a finding, show the
   operator each signal and ask which branch is correct. Pass the answer as
   `--base`.
3. Ask whether GitHub issues should feed the backlog. If yes, ask for the label
   and pass `--issues label:<name>`; otherwise `--issues off`.
4. Run `bin/dux-project add <name> <path> [--base X] [--issues Y]`.
5. Report the registry line in plain words: base branch, worktree mechanism,
   issue intake, and whether a PR template was installed or left alone.

## Inspect

- `bin/dux-project list` for names.
- `bin/dux-project get <name> <key>` for `path`, `base`, `worktree`, `issues`.

## Never

- Never edit `data/projects.md` by hand. The script owns the format.
- Never guess a base branch. Disagreeing signals go to the operator.
```

- [ ] **Step 6: Write README.md**

```markdown
# Dux

An orchestrator you talk to. Dux runs worker agents across your repos in isolated
worktrees, supervises them without spending tokens, and brings back PR links and
decisions. Delivery goes through `/ship`.

Design: `docs/superpowers/specs/2026-09-03-dux-orchestrator-design.md`.
Plans: `docs/superpowers/plans/`.

## Run

    cd ~/Documents/dev/projects/dux && claude

## Develop

    brew install bats-core shellcheck
    make check
```

- [ ] **Step 7: Run to verify it passes**

Run: `make check`
Expected: lint clean; all tests pass.

- [ ] **Step 8: Break-verify**

Append 200 blank lines to `CLAUDE.md`. Run `bats tests/contract.bats`. Expected: "CLAUDE.md is at most 150 lines" fails. Remove the lines. Paste into commit.

- [ ] **Step 9: Dry run the skill**

Open `claude` in the dux repo. Ask it to register `fitfights_ios`. Expected: it runs `resolve-base`, asks about issues, runs `add`, reports the line. Then remove the registry line before committing (registry is gitignored anyway; the dry run is about the skill).

- [ ] **Step 10: Commit and update this plan's header**

Tick all boxes above, set "Tasks done: 7 of 8" in the header, then:

```bash
git add CLAUDE.md .claude/settings.json skills README.md tests/contract.bats docs/superpowers/plans
git commit -m "feat: add Dux operating contract, dux-project skill, README

Break-verified: <paste>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```

---

## Milestone acceptance

- `make check` green on a clean checkout.
- `dux-doctor` passes on the operator's machine under both `DUX_BACKEND=tmux` and, inside Herdr, `DUX_BACKEND=herdr`.
- `dux-project add fitfights_api` resolves `staging` and `fitfights_ios` resolves `main` without a disagreement finding, or the finding lists the disagreeing signals.
- The Herdr adapter opens a visible `dux-<id>` tab in the Dux workspace, with the operator's focus unchanged.
- Every commit body carries a pasted break-verification failure.
- `dux-install --yes` has run on the operator's machine; `~/.claude/skills/ship` resolves into this repo and `/ship` loads in another repo.
- `make lint-identifiers` passes with the operator's real denylist.

---

### Task 8: License, contributing, bundled ship skill, installer, identifier lint

**Files:**
- Create: `LICENSE` (MIT, copyright holder "Dux contributors")
- Create: `CONTRIBUTING.md`
- Create: `skills/ship/SKILL.md` (byte-for-byte copy of `~/.agents/skills/ship/SKILL.md`)
- Create: `bin/dux-install`
- Create: `bin/dux-uninstall`
- Create: `templates/config/reviewer`, `templates/config/security-reviewer`, `templates/config/models`, `templates/config/backend`
- Modify: `Makefile` (lint target)
- Modify: `.gitignore` (add `tests/personal-identifiers.txt`)
- Test: `tests/dux-install.bats`, `tests/identifiers.bats`

**Interfaces:**
- Consumes: `bin/dux-env`.
- Produces: `dux-install [--yes]` symlinks `skills/*` into `$DUX_SKILLS_DIR` (default `~/.claude/skills`), copies `templates/config/*` into `$DUX_CONFIG` when absent, and writes `tests/personal-identifiers.txt` from `$(whoami)`, `$HOME`, and registry project names. A real directory at a target is a finding unless `--yes`, which moves it to `<name>.bak`. `dux-uninstall` removes only symlinks whose target is inside `$DUX_ROOT/skills`.
- Produces: `make lint` fails when any tracked file contains a line from `tests/personal-identifiers.txt`.

- [ ] **Step 1: Write the failing tests**

`tests/dux-install.bats`:

```bash
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
```

`tests/identifiers.bats`:

```bash
load helpers/setup

@test "lint fails when a tracked file contains a personal identifier" {
  tmp="$(mktemp -d)"; git clone -q "$DUX_ROOT" "$tmp/repo"
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/dux-install.bats tests/identifiers.bats`
Expected: all fail (no `dux-install`, no `lint-identifiers` target).

- [ ] **Step 3: Copy the ship skill and write license and contributing**

```bash
mkdir -p skills/ship && cp ~/.agents/skills/ship/SKILL.md skills/ship/SKILL.md
```

`LICENSE`: the MIT text with `Copyright (c) 2026 Dux contributors`.

`CONTRIBUTING.md`:

```markdown
# Contributing

- Scripts own mechanics; skills own judgment. A script that meets a surprise stops with `finding: ...`.
- Every script has a bats file. Every guard is break-verified once and the failure is pasted into the commit.
- `make check` must be green. `make lint` also refuses personal identifiers in tracked files.
- No personal paths, usernames, or project names in tracked files. Personal state lives in `data/`, `state/`, `config/`.
- Changes to the design go through `docs/superpowers/specs/` first.
```

- [ ] **Step 4: Write the default config templates**

```
templates/config/reviewer            codex exec -m gpt-5.6-sol --sandbox read-only
templates/config/security-reviewer   agent:security-reviewer
templates/config/models              plan=claude-fable-5-1:high ship=claude-opus-5:max scout=claude-sonnet-5:medium
templates/config/backend             (empty file; empty means auto-detect)
```

Milestone 5 makes `/ship` read the first two; milestone 2 makes the wrapper read `models`.

- [ ] **Step 5: Write the installer and uninstaller**

`bin/dux-install`:

```bash
#!/usr/bin/env bash
# Symlink bundled skills into the user's skills dir; seed config. Spec section 18.
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"

yes=0; [ "${1:-}" = "--yes" ] && yes=1
target="${DUX_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$target"

for d in "$DUX_ROOT"/skills/*/; do
  n="$(basename "$d")"; dst="$target/$n"; src="$DUX_ROOT/skills/$n"
  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && { log "ok $n"; continue; }
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    [ "$yes" = 1 ] || finding "$dst exists and is not a symlink; rerun with --yes to move it to $n.bak"
    rm -rf "$dst.bak"; mv "$dst" "$dst.bak"; log "moved $dst to $dst.bak"
  fi
  ln -s "$src" "$dst"; log "linked $n"
done

for f in "$DUX_ROOT"/templates/config/*; do
  n="$(basename "$f")"
  [ -e "$DUX_CONFIG/$n" ] || { cp "$f" "$DUX_CONFIG/$n"; log "config $n seeded"; }
done

{
  whoami; basename "$HOME"; echo "$HOME"
  [ -f "$DUX_DATA/projects.md" ] && sed -n 's/^- \([^ ]*\) .*/\1/p' "$DUX_DATA/projects.md"
} | grep -v '^$' | sort -u > "$DUX_ROOT/tests/personal-identifiers.txt"
log "identifier denylist written"
```

`bin/dux-uninstall`:

```bash
#!/usr/bin/env bash
set -u
# shellcheck source=bin/dux-env
source "$(dirname "${BASH_SOURCE[0]}")/dux-env"
target="${DUX_SKILLS_DIR:-$HOME/.claude/skills}"
for l in "$target"/*; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in "$DUX_ROOT/skills/"*) rm -f "$l"; log "removed $(basename "$l")" ;; esac
done
```

Run: `chmod +x bin/dux-install bin/dux-uninstall`

- [ ] **Step 6: Add the identifier lint**

In `Makefile`, add and wire:

```makefile
lint: lint-shell lint-identifiers

lint-shell:
	shellcheck -s bash bin/dux-* bin/backends/*.sh tests/fakes/* tests/helpers/*.bash

lint-identifiers:
	@if [ -s tests/personal-identifiers.txt ]; then \
	  git ls-files -z | xargs -0 grep -nF -f tests/personal-identifiers.txt -- 2>/dev/null \
	    | grep -v '^tests/personal-identifiers.txt' && { echo "personal identifiers found"; exit 1; } || true; \
	fi
```

Append `tests/personal-identifiers.txt` to `.gitignore`.

- [ ] **Step 7: Run to verify they pass**

Run: `bin/dux-install --yes` once on your machine (this replaces `~/.claude/skills/ship` with a symlink; the old directory is kept as `ship.bak`), then `make check`.
Expected: all tests pass; lint clean. Confirm `/ship` still loads in a fresh `claude` session in any repo.

- [ ] **Step 8: Break-verify**

Set `yes=1` unconditionally. Run `bats tests/dux-install.bats`. Expected: "refuses an existing real directory without --yes" fails. Restore. Then remove the `exit 1` from `lint-identifiers`. Run `bats tests/identifiers.bats`. Expected: "lint fails when a tracked file contains a personal identifier" fails. Restore. Paste both.

- [ ] **Step 9: Commit and update this plan's header**

Set "Tasks done: 8 of 8".

```bash
git add LICENSE CONTRIBUTING.md skills/ship bin/dux-install bin/dux-uninstall templates/config Makefile .gitignore tests/dux-install.bats tests/identifiers.bats docs/superpowers/plans
git commit -m "feat: MIT license, bundled ship skill, dux-install, identifier lint

Break-verified: <paste both>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K5NHrLFHm1msoHGdGyDbvT"
```
