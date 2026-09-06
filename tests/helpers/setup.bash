# Sourced by every bats file via `load helpers/setup`.
DUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUX_ROOT
# shellcheck source=bin/dux-env
source "$DUX_ROOT/bin/dux-env"

setup() {
  # Physical path: git prints worktree paths resolved through symlinks (/private/tmp on macOS).
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"
  export DUX_HOME
  # Throwaway repos need an identity; never depend on the machine's git config.
  export GIT_AUTHOR_NAME=dux-test GIT_AUTHOR_EMAIL=dux-test@example.invalid
  export GIT_COMMITTER_NAME=dux-test GIT_COMMITTER_EMAIL=dux-test@example.invalid
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  cp "$DUX_ROOT"/templates/config/* "$DUX_HOME/config/"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export DUX_WATCHER=off
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log"
  export FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log"
  export FAKE_GH_LOG="$DUX_HOME/state/fake-gh.log"
  : > "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_OUTPUT"
  : > "$FAKE_WORKER_LOG"
  : > "$FAKE_GH_LOG"
}

wait_for_workers() {  # $1 seconds; returns 1 if a worker is still alive after that
  local deadline="$1" i=0 pidfile pid live
  while :; do
    live=0
    for pidfile in "$DUX_HOME"/state/*.pid; do
      [ -f "$pidfile" ] || continue
      case "$pidfile" in */watch.pid) continue ;; esac
      pid="$(cat "$pidfile" 2>/dev/null)"
      case "$pid" in '' | *[!0-9]*) continue ;; esac
      if kill -0 "$pid" 2>/dev/null; then live=1; fi
    done
    if [ "$live" -eq 0 ]; then return 0; fi
    i=$((i + 1))
    if [ "$i" -ge $((deadline * 5)) ]; then return 1; fi
    sleep 0.2
  done
}

# Start a quiet process whose command line ends with the requested words.
stand_in() {  # $1 command-line needle
  local fifo; fifo="$DUX_HOME/state/stand-in.$$.$RANDOM.fifo"
  mkfifo "$fifo" || return 1
  # Perl receives the literal $SIG and $ARGV names below.
  # shellcheck disable=SC2016
  ( exec perl -e '$SIG{INT} = "DEFAULT"; exec {"/bin/cat"} $ARGV[0]' "$1" ) <> "$fifo" >/dev/null 2>&1 3>&- &
  echo $! >> "$DUX_HOME/state/stand-ins"
  echo $!
}

not_running() { ! kill -0 "$1" 2>/dev/null; }

# A bare `! cmd` can never fail a bats test: bash ignores errexit for a command
# whose return value is being inverted. An assertion that something is absent
# goes through this instead, so that the inversion happens inside a function
# and the call itself is an ordinary command that can fail.
refute() { ! "$@"; }

wait_until() {  # $1 seconds, $2.. command; polls every 0.2 seconds
  local i=0 max=$(( $1 * 5 )); shift
  until "$@"; do i=$((i + 1)); [ "$i" -ge "$max" ] && return 1; sleep 0.2; done
}

reap() {  # $1 pid; kill it and wait until it is actually gone
  local p="$1" i=0
  kill "$p" 2>/dev/null || return 0
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 50 ] && return 1
    sleep 0.2
  done
}

stop_watcher_if_any() {
  local p
  if [ -f "$DUX_HOME/state/watch.pid" ]; then
    p="$(cat "$DUX_HOME/state/watch.pid" 2>/dev/null)"
    # Waited on, not just signalled. Every dux command the watcher runs sources
    # dux-env, which mkdir -p's data/ and state/, so a watcher still alive when
    # teardown starts recreates the very directories rm -rf is removing.
    if pid_runs "$p" dux-watch; then reap "$p" || true; fi
    rm -f "$DUX_HOME/state/watch.pid"
  fi
  if [ -f "$DUX_HOME/state/stand-ins" ]; then
    while read -r p; do reap "$p" || true; done < "$DUX_HOME/state/stand-ins"
  fi
}

teardown() {
  [ -n "${DUX_HOME:-}" ] || return 0
  stop_watcher_if_any
  # A spawned worker keeps writing into $DUX_HOME after it appends its last
  # status line, so removing the home under it makes rm fail with "Directory
  # not empty". Wait for every worker the test started, then remove.
  wait_for_workers 30 || {
    echo "teardown: a worker is still running under $DUX_HOME; not removing it" >&2
    return 1
  }
  rm -rf "$DUX_HOME"
}

make_repo() {  # $1 dir, $2 default branch; creates a bare origin and a clone
  local d="$1" b="$2"
  git init -q -b "$b" "$d.origin.tmp" && (cd "$d.origin.tmp" && git commit -q --allow-empty -m init)
  git clone -q --bare "$d.origin.tmp" "$d.origin" && rm -rf "$d.origin.tmp"
  git clone -q "$d.origin" "$d"
  (cd "$d" && git remote set-head origin "$b")
  printf '.worktrees/\n' > "$d/.gitignore"
  (cd "$d" && git add .gitignore && git commit -q -m "ignore worktrees" && git push -q origin "$b")
}

# A project whose origin url reads as https://github.com/acme/<name>, so a run
# records repo=acme/<name> while every fetch stays inside the test's home.
make_github_repo() {  # $1 project dir name under $DUX_HOME
  local d="$DUX_HOME/$1" o="$DUX_HOME/acme/$1.git" u="https://github.com/acme/$1.git"
  mkdir -p "$DUX_HOME/acme"
  git init -q -b main "$d.seed" && (cd "$d.seed" && git commit -q --allow-empty -m init)
  git clone -q --bare "$d.seed" "$o" && rm -rf "$d.seed"
  git clone -q "$o" "$d"
  # The remote says what a real GitHub clone says, so github_slug is reading the
  # same shape of url in the tests as on the operator's machine. insteadOf sends
  # the actual fetches and pushes to the bare repo beside it, so nothing here
  # touches the network. A local path with github.com in it would read as GitHub
  # only because the old substring test was wrong, and it is not wrong now.
  git -C "$d" config "url.$o.insteadOf" "$u"
  git -C "$d" remote set-url origin "$u"
  (cd "$d" && git remote set-head origin main)
  printf '.worktrees/\n' > "$d/.gitignore"
  (cd "$d" && git add .gitignore && git commit -q -m "ignore worktrees" && git push -q origin main)
}

fixture_task() {  # $1 project name, $2 shape, [$3 github]; prints the task id. Needs Tasks 2 and 3.
  # A second task in the same project reuses it; registering it twice is a finding.
  if ! dux-project list | grep -qx "$1"; then
    if [ "${3:-}" = github ]; then make_github_repo "$1"; else make_repo "$DUX_HOME/$1" main; fi
    dux-project add "$DUX_HOME/$1" --base main >/dev/null
  fi
  local id; id="$(dux-task-new "$1" "$2")"
  # Where the dispatch skill puts them, so that a retry finds them there too.
  local task="$DUX_HOME/data/tasks/$id"
  printf 'Do the thing the operator asked for.\n' > "$task/intent.md"
  printf '1. The thing is done.\n' > "$task/criteria.md"
  if [ "$2" = ship ]; then
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" --plan docs/plan.md --tasks 1-2 >/dev/null
  else
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" >/dev/null
  fi
  echo "$id"
}

# The two files dux-worker-wrap writes before a worker starts. A test that needs
# a run record without running a wrapper builds it here, the same way.
fake_run() {  # $1 id, $2 run, $3 shape, [$4 repo slug], [$5 worktree]
  local ctx="$DUX_HOME/state/$1.result-context" tree="${5:-$DUX_HOME}"
  {
    echo "version=1"; echo "id=$1"; echo "run=$2"; echo "shape=$3"
    echo "project=proj"; echo "repo=${4:-acme/proj}"; echo "base=main"
    echo "branch=dux/$1"; echo "worktree=$tree"
    echo "plan="; echo "tasks="
  } > "$ctx"
  {
    echo "version=1"; echo "id=$1"; echo "run=$2"; echo "wrapper=$$"
    echo "shape=$3"; echo "worktree=$tree"
    echo "channel=$DUX_HOME/state/channels/$1.$2"
    echo "context=$(git hash-object "$ctx")"
  } > "$DUX_HOME/state/$1.run"
}

# A terminal handoff, put where a wrapper would have put it. dux-env is sourced
# once, before a setup() moves DUX_HOME, so the paths it derived point at the
# repository; the subshell re-derives them rather than writing outside the
# test's home.
handoff() {  # $1 id, $2 status line, $3 event, [$4 run]
  ( DUX_STATE="$DUX_HOME/state"; publish_handoff "$1" "${4:-r00}" "$2" "$3" ) > /dev/null
}

# The five /ship phases a ship result needs behind it.
fake_receipt() {  # $1 id, $2 run
  local r="$DUX_HOME/state/$1.ship-receipt" p
  { echo "version=1"; echo "id=$1"; echo "run=$2"; echo "branch=dux/$1"; } > "$r"
  for p in checks review security pr ci; do
    printf 'phase=%s sha=deadbeef at=2026-09-05T00:00:00Z\n' "$p" >> "$r"
  done
}
