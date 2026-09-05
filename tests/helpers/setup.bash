# Sourced by every bats file via `load helpers/setup`.
DUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUX_ROOT

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

teardown() {
  [ -n "${DUX_HOME:-}" ] || return 0
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

fixture_task() {  # $1 project name, $2 shape; prints the task id. Needs Tasks 2 and 3.
  make_repo "$DUX_HOME/$1" main
  dux-project add "$DUX_HOME/$1" --base main >/dev/null
  local id; id="$(dux-task-new "$1" "$2")"
  printf 'Do the thing the operator asked for.\n' > "$DUX_HOME/intent.$id"
  printf '1. The thing is done.\n' > "$DUX_HOME/criteria.$id"
  if [ "$2" = ship ]; then
    dux-brief "$id" --intent-file "$DUX_HOME/intent.$id" --criteria-file "$DUX_HOME/criteria.$id" --plan docs/plan.md --tasks 1-2 >/dev/null
  else
    dux-brief "$id" --intent-file "$DUX_HOME/intent.$id" --criteria-file "$DUX_HOME/criteria.$id" >/dev/null
  fi
  echo "$id"
}
