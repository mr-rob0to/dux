# Sourced by every bats file via `load helpers/setup`.
DUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUX_ROOT
# shellcheck source=bin/dux-env
source "$DUX_ROOT/bin/dux-env"

# Every tmux socket a test names lives under this directory. Socket names are
# fixed strings (dux-test, dux-e2e), so without this two bats runs on one
# machine share one tmux server: files running side by side, or a second
# session running the suite, each kill the other's windows. tmux puts the
# socket at $TMUX_TMPDIR/tmux-<uid>/<name>, so a directory of our own isolates
# the run and no socket name has to change. It sits under /tmp because a unix
# socket path is capped near 104 bytes and $TMPDIR on macOS spends most of
# that on its own.
#
# A TMUX_TMPDIR the caller already set is overridden rather than honoured. It
# was honoured at first, and that gave back both halves of the bug: two runs
# under one inherited directory collide exactly as before, and teardown would
# be removing a directory it did not create. Tests have no business on the
# operator's tmux server, so the run always uses its own.
DUX_TEST_TMUX_TMPDIR="/tmp/dux-tmux.$(basename "${BATS_RUN_TMPDIR:-run-$$}")"
TMUX_TMPDIR="$DUX_TEST_TMUX_TMPDIR"
export TMUX_TMPDIR

# Called by setup_file in the files that start a tmux server; tmux will not
# create $TMUX_TMPDIR itself. Kept out of setup() so the files that never
# touch tmux leave nothing behind.
#
# It builds the directory rather than accepting one that is already there. /tmp
# is writable by everyone, and the name is derived from BATS_RUN_TMPDIR, which
# on Linux is a /tmp path any account can read the moment bats starts. So a
# second account on the machine can create the path first, and `mkdir -p` would
# have taken it: this run's tmux server ends up inside a directory somebody
# else owns, where they can swap the socket underneath it and feed the suite
# whatever pane text they like. Nobody else is on a personal Mac or a CI runner,
# which is why this was worth a few lines and not a redesign.
use_tmux_tmpdir() {
  mkdir -m 700 "$DUX_TEST_TMUX_TMPDIR" 2>/dev/null && return 0
  # Already there. It is still this run's own if it is a real directory this
  # account owns: /tmp's sticky bit means no one else can leave one of those
  # behind under our name. Symlinks are asked about separately because -O
  # follows them, so a link pointing at a directory we own would pass -O while
  # the attacker still controls where writes land.
  if [ ! -L "$DUX_TEST_TMUX_TMPDIR" ] && [ -d "$DUX_TEST_TMUX_TMPDIR" ] &&
     [ -O "$DUX_TEST_TMUX_TMPDIR" ]; then
    return 0
  fi
  echo "finding: $DUX_TEST_TMUX_TMPDIR exists and is not this run's own directory" >&2
  return 1
}

# The pair of use_tmux_tmpdir, called by teardown_file once the server is gone.
# It names the directory this run built rather than testing $TMUX_TMPDIR, so it
# can only ever remove that one.
drop_tmux_tmpdir() { rm -rf "$DUX_TEST_TMUX_TMPDIR"; }

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
  # A watcher a test starts checks no base branch unless the test asks for it.
  export DUX_BASE_INTERVAL_SECS=0
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log"
  export FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log"
  export FAKE_GH_LOG="$DUX_HOME/state/fake-gh.log"
  : > "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_OUTPUT"
  : > "$FAKE_WORKER_LOG"
  : > "$FAKE_GH_LOG"
}

# A Dux root of real file copies, never symlinks, with one script replaced. The
# copies matter: the scripts call their siblings by absolute path under
# $DUX_ROOT, and writing into a directory of links to the checkout edits the
# checkout.
root_with_stub() {  # $1 script name, $2 body; prints the root
  # Built from nothing every time: a second call with the same name would
  # otherwise copy bin inside the first copy and, worse, follow the templates
  # link and make one inside the real templates directory.
  local r="$DUX_HOME/root-$1"
  rm -rf "$r"
  mkdir -p "$r"
  cp -R "$DUX_ROOT/bin" "$r/bin"
  ln -s "$DUX_ROOT/templates" "$r/templates"
  rm -f "$r/bin/$1"
  printf '%s\n' "$2" > "$r/bin/$1"
  chmod +x "$r/bin/$1"
  echo "$r"
}

# Claude Code records the folders the operator has trusted, and dux-spawn will
# not open a tab for a project that is not there. Trust is per repository, so
# the fixture names the projects themselves and never the suite root above
# them: a trusted parent does not trust a repository inside it, and a fixture
# that trusted the root would pass a spawn the real thing would leave sitting
# at the dialog. The file lives under a CLAUDE_CONFIG_DIR of the suite's own,
# so the operator's real one is neither read nor written.
trust_suite_root() {  # [project names]; default proj
  local n
  CLAUDE_CONFIG_DIR="$DUX_HOME/claude-config"; export CLAUDE_CONFIG_DIR
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo '{"projects":{}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  [ "$#" -gt 0 ] || set -- proj
  for n in "$@"; do trust_path "$DUX_HOME/$n"; done
}

trust_path() {  # $1 a path; adds one trusted entry to the suite's own config
  local f="$CLAUDE_CONFIG_DIR/.claude.json"
  jq --arg p "$1" '.projects[$p] = { hasTrustDialogAccepted: true }' "$f" > "$f.tmp" \
    && mv "$f.tmp" "$f"
}

# A fake harness whose process really is called claude, for any test where the
# wrapper has to find it through the multiplexer. `dux-backend pid` reads the
# name from ps, and ps reports a shebang script's interpreter on macOS and the
# script's own name on Linux. A script called claude whose interpreter is a link
# called claude reads "claude" on both, so no production code has to learn about
# the test environment. Measured 2026-09-14: ps -o comm= gives <dir>/i/claude on
# macOS and claude on Linux. Puts the copy first on PATH.
harness_shim() {
  mkdir -p "$DUX_HOME/hbin/i"
  ln -sf "$(command -v bash)" "$DUX_HOME/hbin/i/claude"
  {
    printf '#!%s\n' "$DUX_HOME/hbin/i/claude"
    tail -n +2 "$DUX_ROOT/tests/fakes/claude"
  } > "$DUX_HOME/hbin/claude"
  chmod 755 "$DUX_HOME/hbin/claude"
  case "$PATH" in "$DUX_HOME/hbin:"*) ;; *) PATH="$DUX_HOME/hbin:$PATH"; export PATH ;; esac
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
      if ! gone "$pid"; then live=1; fi
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

# Whether a process has ended. kill -0 is not that question: it answers for a
# zombie too, a process that has ended and that its parent has not collected,
# and tmux can leave a pane's killed process like that for more than fifteen
# seconds (measured on Linux, 2026-09-18). A zombie has ended. A ps that fails
# or prints nothing leaves the process counted as running, the way group_runs
# in dux-env reads it, because a process wrongly called gone is a survivor
# nobody catches.
gone() {  # $1 pid; 0 once it has ended, collected or not
  local stat
  kill -0 "$1" 2>/dev/null || return 0
  stat="$(ps -o stat= -p "$1" 2>/dev/null)" || return 1
  stat="${stat#"${stat%%[! ]*}"}"
  case "$stat" in Z*) return 0 ;; esac
  return 1
}

not_running() { gone "$1"; }

# Whether a process group has ended: nothing in it runs. On Linux kill -0 on a
# group answers while a member is a zombie, which is how a pane's group looks
# while tmux has not collected its process. group_runs in dux-env already reads
# a group that way and fails closed, and has its own tests in dux-env.bats.
group_gone() { ! group_runs "$1"; }  # $1 pgid

# Moves a task's last sign of life that many seconds into the past: the times of
# its status.log and state/<id>.pid, which the watcher counts silence from. A
# test that needs a long silence sets the clock, instead of sleeping past a
# limit so small that a slow start reaches it first.
age_task() {  # $1 id, $2 seconds
  # shellcheck disable=SC2016
  perl -e '$t = time - shift; exit(utime($t, $t, @ARGV) == @ARGV ? 0 : 1)' "$2" \
    "$DUX_HOME/data/tasks/$1/status.log" "$DUX_HOME/state/$1.pid"
}

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
  while ! gone "$p"; do
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
  # The watcher's stop stops its base check. One still running here outlived a
  # watcher that never got to stop it, and it writes under state/ too.
  if [ -f "$DUX_HOME/state/base.pid" ]; then
    p="$(cat "$DUX_HOME/state/base.pid" 2>/dev/null)"
    if pid_runs "$p" dux-base; then reap "$p" || true; fi
    rm -f "$DUX_HOME/state/base.pid"
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

fixture_task() {  # $1 project name, $2 shape, [$3 github], [$4 combined]; prints the task id. Needs Tasks 2 and 3.
  # A second task in the same project reuses it; registering it twice is a finding.
  if ! dux-project list | grep -x "$1" >/dev/null; then
    if [ "${3:-}" = github ]; then make_github_repo "$1"; else make_repo "$DUX_HOME/$1" main; fi
    dux-project add "$DUX_HOME/$1" --base main --pr-template skip >/dev/null
  fi
  local id; id="$(dux-task-new "$1" "$2")"
  # Where the dispatch skill puts them, so that a retry finds them there too.
  local task="$DUX_HOME/data/tasks/$id"
  printf 'Do the thing the operator asked for.\n' > "$task/intent.md"
  printf '1. The thing is done.\n' > "$task/criteria.md"
  # Only a ship carries a classification, and only the caller that asked for
  # combined gets one: everything else is briefed the way an operator who said
  # nothing about reviews is, which is separate.
  local classify=""
  [ "${4:-}" = combined ] && classify=yes
  if [ "$2" = ship ] && [ -n "$classify" ]; then
    dux-brief "$id" --intent-file "$task/intent.md" --criteria-file "$task/criteria.md" --plan docs/plan.md --tasks 1-2 --review combined --review-reason 'touches none of the sensitive categories' >/dev/null
  elif [ "$2" = ship ]; then
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

# The /ship phases a ship result needs behind it: the phases that review mode
# owes, at a commit id shaped the way Git writes one. Called with no mode it
# writes the receipt a Dux from before review modes wrote, which owed all five.
fake_receipt() {  # $1 id, $2 run, [$3 combined|separate]
  local r="$DUX_HOME/state/$1.ship-receipt" p
  local sha=0123456789abcdef0123456789abcdef01234567
  local phases="checks review security pr ci"
  if [ -n "${3:-}" ]; then
    { echo "version=2"; echo "id=$1"; echo "run=$2"; echo "branch=dux/$1"
      echo "review=$3"; } > "$r"
    [ "$3" != combined ] || phases="checks review pr ci"
  else
    { echo "version=1"; echo "id=$1"; echo "run=$2"; echo "branch=dux/$1"; } > "$r"
  fi
  for p in $phases; do
    printf 'phase=%s sha=%s at=2026-09-05T00:00:00Z\n' "$p" "$sha" >> "$r"
  done
}

# The task it waits on, delivered the way the wrapper and the watcher leave it:
# its run, its /ship receipt whose ci phase names the delivered commit (the
# earlier phases name another, as they do once /ship has pushed a fix), and the
# consumed handoff that put its pull request on the ledger. GitHub reports that pull request
# merged, and the merge is pushed to the registered base from another clone, so
# the project's own clone has it only once spawn fetches. Sets $pred, $head,
# $merge and $pr.
delivered() {
  local m="$DUX_HOME/merger" p
  pred="$(fixture_task proj ship github)"; pr=https://github.com/acme/proj/pull/7
  git clone -q "$DUX_HOME/acme/proj.git" "$m"
  git -C "$m" checkout -q -b "dux/$pred"
  git -C "$m" commit -q --allow-empty -m delivered
  head="$(git -C "$m" rev-parse HEAD)"
  git -C "$m" checkout -q main
  git -C "$m" merge -q --no-ff -m merged "dux/$pred"
  merge="$(git -C "$m" rev-parse HEAD)"
  git -C "$m" push -q origin main
  fake_run "$pred" r1 ship acme/proj
  { echo version=2; echo "id=$pred"; echo run=r1; echo "branch=dux/$pred"; echo review=separate
    for p in checks review security pr; do echo "phase=$p sha=$(printf '%040d' 0) at=2026-09-16T00:00:00Z"; done
    echo "phase=ci sha=$head at=2026-09-16T00:00:00Z"
  } > "$DUX_HOME/state/$pred.ship-receipt.delivered"
  handoff "$pred" "done: PR $pr" "done" r1
  : > "$DUX_HOME/state/$pred.handoffs/1/consumed"
  dux-ledger set "$pred" state "done"; dux-ledger set "$pred" pr "$pr"
  export FAKE_GH_PR_STATE=MERGED FAKE_GH_PR_HEAD="dux/$pred" FAKE_GH_PR_BASE=main \
    FAKE_GH_PR_HEAD_OID="$head" FAKE_GH_PR_MERGE="$merge"
}

# The task that waits is in a repository of its own, so everything checked about
# the merge is checked in the repository it landed in.
waiting() {  # [$1 the check the merge must pass]; sets $id, a scout in other that waits on $pred
  local t
  if ! dux-project list | grep -x other >/dev/null; then
    make_repo "$DUX_HOME/other" main
    dux-project add "$DUX_HOME/other" --base main --pr-template skip >/dev/null
  fi
  id="$(dux-task-new other scout --after "$pred")"; t="$DUX_HOME/data/tasks/$id"
  printf 'Build on it.\n' > "$t/intent.md"; printf '1. Built.\n' > "$t/criteria.md"
  if [ -n "${1:-}" ]; then
    dux-brief "$id" --intent-file "$t/intent.md" --criteria-file "$t/criteria.md" --after-check "$1" >/dev/null
  else
    dux-brief "$id" --intent-file "$t/intent.md" --criteria-file "$t/criteria.md" >/dev/null
  fi
}
