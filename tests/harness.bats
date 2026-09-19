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

@test "fake herdr pane run executes the command in the tab's cwd when FAKE_HERDR_RUN is set" {
  export FAKE_HERDR_RUN=1
  mkdir -p "$DUX_HOME/cwd"
  herdr tab create --workspace w1 --cwd "$DUX_HOME/cwd" --label dux-x --no-focus >/dev/null
  herdr pane run w1:p9 "pwd; echo pane=\$HERDR_PANE_ID" >/dev/null
  sleep 1
  grep -qx "$DUX_HOME/cwd" "$FAKE_HERDR_OUTPUT"
  grep -qx "pane=w1:p9" "$FAKE_HERDR_OUTPUT"
}

# The real pane reports the process that is running in it. The fake has to report
# the same thing, and the pid it records is a shell's until that shell replaces
# itself with the command, which is a thing the shells disagree about: measured
# 2026-09-15, bash and macOS /bin/sh replace themselves with a single -c command
# and Linux's /bin/sh (dash) forks and waits. A fake that reports "sh" is a fake
# that no name check can ever match, which on Linux is every test that starts a
# real wrapper.
@test "fake herdr process-info names the command pane run started, not a shell" {
  export FAKE_HERDR_RUN=1
  mkdir -p "$DUX_HOME/cwd"
  herdr tab create --workspace w1 --cwd "$DUX_HOME/cwd" --label dux-x --no-focus >/dev/null
  herdr pane run w1:p9 "sleep 60" >/dev/null
  argv0() {
    herdr pane process-info --pane w1:p9 \
      | jq -r '.result.process_info.foreground_processes[0].argv0 // empty'
  }
  # Read again on every poll: the pane has a process only once the shell has got
  # as far as starting one.
  names_sleep() { [ "$(argv0)" = sleep ]; }
  wait_until 15 names_sleep
  [ "$(argv0)" = sleep ]
  pid="$(herdr pane process-info --pane w1:p9 | jq -r '.result.process_info.foreground_processes[0].pid')"
  kill -TERM "$pid"
}

@test "use_tmux_tmpdir builds its own directory and refuses one it did not build" {
  DUX_TEST_TMUX_TMPDIR="$DUX_HOME/tmux.own"
  use_tmux_tmpdir
  [ -d "$DUX_TEST_TMUX_TMPDIR" ]

  # A symlink somebody left at the name. The link is the one shape this test can
  # build without a second account on the machine, and it is the shape that gets
  # past an ownership test on its own, since that test follows the link.
  mkdir -p "$DUX_HOME/planted"
  DUX_TEST_TMUX_TMPDIR="$DUX_HOME/tmux.linked"
  ln -s "$DUX_HOME/planted" "$DUX_TEST_TMUX_TMPDIR"
  run use_tmux_tmpdir
  [ "$status" -ne 0 ]
  case "$output" in finding:*) ;; *) echo "no finding on the symlink: $output"; return 1 ;; esac

  # A real directory this account does not own, which needs no second account
  # either: / is one on every machine the suite runs on. It has to be a real
  # directory and not a link, or the check above answers first and this one is
  # never reached. That is what /tmp did here at first, since on macOS /tmp is a
  # link to /private/tmp. Nothing is unowned when the run is root, so there the
  # case has nothing to say.
  if [ "$(id -u)" -ne 0 ]; then
    DUX_TEST_TMUX_TMPDIR=/
    run use_tmux_tmpdir
    [ "$status" -ne 0 ]
    case "$output" in finding:*) ;; *) echo "no finding on a directory we do not own: $output"; return 1 ;; esac
  fi
}

# tests/repeat is how a flake rate is measured, so what it counts has to be
# right: runs that failed, out of runs made, and which tests failed how often.
# Stub jobs give it a known answer: one fails every other run, one never does.
@test "repeat counts the failed runs of a job and names the tests that failed" {
  mkdir -p "$DUX_HOME/jobs"
  cd "$DUX_HOME/jobs"
  printf '%s\n' \
    'job/flaky:' \
    '	@n=$$(($$(cat count 2>/dev/null || echo 0) + 1)); echo $$n > count; \' \
    '	if [ $$((n % 2)) -eq 1 ]; then echo "not ok 3 sometimes"; exit 1; fi; echo "ok 3 sometimes"' \
    'job/pass:' \
    '	@echo "ok 1 always"' > Makefile
  run "$DUX_ROOT/tests/repeat" job/flaky 4
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "job/flaky: 2 failures in 4 runs" ]
  [ "${lines[1]}" = "  2x 3 sometimes" ]
  [ "${#lines[@]}" -eq 2 ]
  run "$DUX_ROOT/tests/repeat" job/pass 3 1
  [ "$status" -eq 0 ]
  [ "$output" = "job/pass: 0 failures in 3 runs" ]
}

# A process that has ended and that its parent has not collected is a zombie,
# and kill -0 still answers for it. tmux can leave a pane's killed process like
# that for more than fifteen seconds, so a test asking kill -0 whether it has
# ended waits out its deadline and fails. gone is the question that matters.
@test "gone is true for an ended process nobody collected, false for a live one" {
  # The parent forks a child that exits at once, prints its pid, and never waits.
  # shellcheck disable=SC2016
  perl -e '$| = 1; my $c = fork; if ($c == 0) { exit 0 } print "$c\n"; sleep 60' > "$DUX_HOME/zombie" &
  parent=$!
  echo "$parent" >> "$DUX_HOME/state/stand-ins"
  wait_until 5 test -s "$DUX_HOME/zombie"
  z="$(cat "$DUX_HOME/zombie")"
  is_zombie() { case "$(ps -o stat= -p "$z" 2>/dev/null | tr -d ' ')" in Z*) return 0 ;; esac; return 1; }
  wait_until 5 is_zombie
  # What makes this the case that matters: kill -0 still answers for it.
  kill -0 "$z"
  gone "$z"
  sleep 60 & live=$!
  echo "$live" >> "$DUX_HOME/state/stand-ins"
  refute gone "$live"
  # A pid this shell has already collected no longer names any process.
  sleep 0 & done_pid=$!
  wait "$done_pid"
  gone "$done_pid"
}

# The same holds for a group on Linux: kill -0 on it answers while a member is a
# zombie, which is how a pane's group looks while tmux has not collected the
# pane's process. group_gone asks whether anything in the group still runs.
@test "group_gone is true for a group whose only member is a zombie, false while a member runs" {
  # A parent forks a child that leads a group of its own and prints its pid once
  # it does. The parent never collects it. Told "exit", the child ends at once;
  # told "sleep", it stays alive in its group.
  lead_group() {  # $1 exit|sleep, $2 file for the child's pid
    # shellcheck disable=SC2016
    perl -e '$| = 1; if (fork == 0) { setpgrp(0, 0); print "$$\n"; exit 0 if $ARGV[0] eq "exit"; sleep 60; exit 0 } sleep 60' "$1" > "$2" &
    echo $! >> "$DUX_HOME/state/stand-ins"
    wait_until 5 test -s "$2"
    g="$(cat "$2")"
    echo "$g" >> "$DUX_HOME/state/stand-ins"
  }
  lead_group exit "$DUX_HOME/zombie-group"
  is_zombie() { case "$(ps -o stat= -p "$g" 2>/dev/null | tr -d ' ')" in Z*) return 0 ;; esac; return 1; }
  wait_until 5 is_zombie
  # What makes this the case that matters on Linux: kill -0 on the group still
  # answers. macOS refuses it with "Operation not permitted", so there the old
  # question already gave the right answer.
  if [ "$(uname -s)" = Linux ]; then kill -0 -- "-$g"; fi
  group_gone "$g"
  lead_group sleep "$DUX_HOME/live-group"
  refute group_gone "$g"
}
