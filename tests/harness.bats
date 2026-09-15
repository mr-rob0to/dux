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
