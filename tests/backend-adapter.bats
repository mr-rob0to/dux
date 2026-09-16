# bats file_tags=adapter
load helpers/setup

# Runs for whichever backend $DUX_BACKEND names. The Makefile runs it twice.

# Where tmux puts the socket named by -L, worked out the same way the adapter does.
tmux_socket_path() { printf '%s/tmux-%s/%s\n' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "$1"; }

setup_file() {
  if [ "${DUX_BACKEND:-}" = herdr ]; then
    # FAKE_HERDR_RUN makes the fake actually start what `pane run` is given, in a
    # session of its own, so `pid` has a real process to report on.
    export HERDR_WORKSPACE_ID=w1 FAKE_HERDR_RUN=1
  fi
  if [ "${DUX_BACKEND:-}" = tmux ]; then
    use_tmux_tmpdir
    export DUX_TMUX_SOCKET=dux-test DUX_TMUX_SESSION=duxtest
    tmux -L dux-test kill-server 2>/dev/null || true
    tmux -L dux-test new-session -d -s duxtest -x 80 -y 24
  fi
}
teardown_file() {
  [ "${DUX_BACKEND:-}" = tmux ] || return 0
  tmux -L dux-test kill-server 2>/dev/null || true
  tmux -L dux-test-stopped kill-server 2>/dev/null || true
  tmux -L dux-test-stale kill-server 2>/dev/null || true
  rm -f "$(tmux_socket_path dux-test-stale)" "$(tmux_socket_path dux-test-notsock)"
  drop_tmux_tmpdir
}

@test "open returns an endpoint for this backend and starts no command" {
  [ -n "${DUX_BACKEND:-}" ] || skip "DUX_BACKEND unset"
  run dux-backend open t1 "$DUX_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == "$DUX_BACKEND:"* ]]
  echo "$output" > "$DUX_HOME/state/t1.endpoint"
}

@test "exists is true while the container is present" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t2 "$DUX_HOME")"
  run dux-backend exists "$ep"; [ "$status" -eq 0 ]
}

@test "exists is false after close or when the pane is gone" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = herdr ]; then export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"; ep="herdr:w1:p9"
  else ep="$(dux-backend open t3b "$DUX_HOME")"; dux-backend close "$ep"; fi
  run dux-backend exists "$ep"; [ "$status" -eq 1 ]
}

@test "exists is a finding when the backend cannot answer, never a gone" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = tmux ]; then
    ep="$(dux-backend open t30 "$DUX_HOME")"
    FAKE_TMUX_FAIL=list-windows run dux-backend exists "$ep"
    [[ "$output" == *"finding: tmux could not list windows while checking $ep"* ]]
  else
    export FAKE_HERDR_GET_FAIL="$DUX_HOME/state/getfail"; touch "$FAKE_HERDR_GET_FAIL"
    run dux-backend exists "herdr:w1:p9"
    [[ "$output" == *"finding: herdr pane get failed for w1:p9 with server_unreachable"* ]]
  fi
  [ "$status" -eq 2 ]
}

@test "herdr exists reads only pane_not_found as gone" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run dux-backend exists "herdr:w1:p9"
  [ "$status" -eq 1 ]
}

@test "tmux exists reads a socket path holding a non-socket as a finding" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  sock="$(tmux_socket_path dux-test-notsock)"
  : > "$sock"
  DUX_TMUX_SOCKET=dux-test-notsock run dux-backend exists "tmux:duxtest:@1"
  rm -f "$sock"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the tmux socket path"* ]]
}

@test "this run's tmux server stands on a socket of its own, not the machine's" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # Socket names here are fixed strings, so before the suite took a TMUX_TMPDIR
  # of its own every run on the machine opened one shared path, and two runs at
  # once killed each other's servers. Any directory this run did not build for
  # itself is that bug again, whether it is the machine default or one the
  # caller exported, so the test is that the directory is this run's own and
  # the server is really in it.
  if [ "$TMUX_TMPDIR" != "$DUX_TEST_TMUX_TMPDIR" ]; then
    echo "this run's tmux is at $TMUX_TMPDIR, not its own $DUX_TEST_TMUX_TMPDIR;"
    echo "a second run sharing that directory would fight this one"
    return 1
  fi
  [ -S "$(tmux_socket_path dux-test)" ]
}

@test "tmux exists reads a server that is not running as gone" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  tmux -L dux-test-stopped new-session -d -s gone -x 80 -y 24
  tmux -L dux-test-stopped kill-server
  DUX_TMUX_SOCKET=dux-test-stopped run dux-backend exists "tmux:gone:@1"
  [ "$status" -eq 1 ]
}

@test "find names the task's container while it exists and prints nothing before and after" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  run dux-backend find t20
  [ "$status" -eq 0 ]; [ -z "$output" ]
  ep="$(dux-backend open t20 "$DUX_HOME")"
  run dux-backend find t20
  [ "$status" -eq 0 ]; [ "$output" = "$ep" ]
  # A different task's container is not this task's answer.
  run dux-backend find t20b
  [ "$status" -eq 0 ]; [ -z "$output" ]
  dux-backend close "$ep"
  run dux-backend find t20
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "find is a finding when the backend cannot answer, never an empty answer" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = tmux ]; then
    # The backend CLI's own error text reaches $output first, so match anywhere.
    FAKE_TMUX_FAIL=list-windows run dux-backend find t21
    [[ "$output" == *"finding: tmux could not list windows while looking for dux-t21"* ]]
  else
    FAKE_HERDR_LIST_FAIL=1 run dux-backend find t21
    [[ "$output" == *"finding: herdr tab list failed while looking for dux-t21"* ]]
  fi
  [ "$status" -eq 2 ]
}

@test "tmux find reads a server that is not running as no container, not as a failure" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # A server that was started and stopped. Whether tmux left the socket behind or
  # removed it, both readings are evidence of no window, so the answer is "none"
  # either way. The two branches are pinned separately below.
  tmux -L dux-test-stopped new-session -d -s gone -x 80 -y 24
  tmux -L dux-test-stopped kill-server
  DUX_TMUX_SOCKET=dux-test-stopped run dux-backend find t23
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "tmux find reads a socket name nothing has ever listened on as no container" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # Real tmux, real message: the first spawn on a machine asks through a socket
  # path no server has ever been reachable at, and tmux answers "error
  # connecting". No socket file is positive evidence of no container, so this
  # must be an answer and not a refusal, or the first spawn can never run.
  [ ! -e "$(tmux_socket_path dux-test-absent)" ]
  DUX_TMUX_SOCKET=dux-test-absent run dux-backend find t27
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "tmux find refuses a socket path holding something that is not a socket" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # The case no error text can decide: a plain file sits where the socket belongs,
  # and tmux says "Socket operation on non-socket" under 3.6a on macOS but "no
  # server running" under 3.4 on Linux. Reading the second as an answer would let
  # a second worker start on a branch that already has one, so the path itself has
  # to decide, and a path that is not a socket answers nothing.
  sock="$(tmux_socket_path dux-test-notsock)"
  : > "$sock"
  DUX_TMUX_SOCKET=dux-test-notsock run dux-backend find t28
  rm -f "$sock"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: the tmux socket path"* ]]
  [[ "$output" == *"is not a socket, so nothing there can answer for dux-t28"* ]]
}

@test "tmux find reads a real socket no server answers on as no container" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # A server killed outright leaves its socket behind: a real socket with nothing
  # listening. Real tmux, real message on both platforms. That is a normal state
  # a spawn must not wedge on, so it has to be an answer and not a refusal.
  local sock spid i
  sock="$(tmux_socket_path dux-test-stale)"
  tmux -L dux-test-stale new-session -d -s stale -x 80 -y 24
  spid="$(tmux -L dux-test-stale display-message -p '#{pid}')"
  kill -9 "$spid"
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$spid" 2>/dev/null || break; sleep 0.2; done
  [ -S "$sock" ]
  DUX_TMUX_SOCKET=dux-test-stale run dux-backend find t29
  rm -f "$sock"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "tmux find reads a listing failure on a socket that is there as an unanswered question" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  # dux-test has a live server, so its socket file is there: tmux failing anyway
  # means it did not look, and a live server holding the worker reads the same.
  [ -e "$(tmux_socket_path dux-test)" ]
  FAKE_TMUX_FAIL=list-windows \
  FAKE_TMUX_FAIL_MSG='error connecting to /tmp/tmux-0/dux-test (No such file or directory)' \
  run dux-backend find t25
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: tmux could not list windows while looking for dux-t25"* ]]
}

@test "tmux find reads no server running as no container" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  FAKE_TMUX_FAIL=list-windows \
  FAKE_TMUX_FAIL_MSG='no server running on /tmp/tmux-0/dux-test' \
  run dux-backend find t26
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "herdr find refuses a labelled tab it cannot resolve to a pane" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  # A create that returned no pane id and could not be closed: the tab is real and
  # may hold a worker, and no pane names it. That must not read as "nothing there".
  FAKE_HERDR_NO_PANE_ID=1 FAKE_HERDR_TAB_CLOSE_FAIL=1 run dux-backend open t22 "$DUX_HOME"
  [ "$status" -eq 2 ]
  run dux-backend find t22
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr tab w1:t9 is labelled dux-t22 but has no pane"* ]]
}

@test "herdr find refuses a tab listing without a tab array" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  FAKE_HERDR_LIST_JUNK=1 run dux-backend find t24
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr tab list returned no tab array while looking for dux-t24"* ]]
}

@test "close removes the container; alive then false" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t5 "$DUX_HOME")"
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

@test "herdr open waits for the operator's own prompt, not just a dollar sign" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  # Starship and oh-my-zsh draw a chevron. A pattern that only knows $ % > #
  # times out on every open, and no worker can be dispatched on that machine.
  FAKE_HERDR_PROMPT='~/code/demo   main ❯ ' run dux-backend open t5 "$DUX_HOME"
  [ "$status" -eq 0 ]; [ "$output" = herdr:w1:p9 ]
  grep -q '^pane wait-output w1:p9' "$FAKE_HERDR_LOG"
}

@test "herdr open is a finding when no shell prompt appears, and no endpoint is handed out" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1
  run dux-backend open t6 "$DUX_HOME"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no shell prompt in pane w1:p9"* ]]
  [ "$(grep -c '^pane run ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  grep -q '^pane close w1:p9' "$FAKE_HERDR_LOG"
}

@test "herdr open closes the tab it created when the create returns no pane id" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PANE_ID=1
  run dux-backend open t12 "$DUX_HOME"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr tab create returned no pane id for t12"* ]]
  grep -qx 'tab close w1:t9' "$FAKE_HERDR_LOG"
  # A bare "! grep" mid-test is ignored by bats, so count the lines instead.
  [ "$(grep -c '^pane run ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

# run is the wrapper's call, not spawn's, so a failure here is a wrapper refusal
# that publishes failed and leaves the tab where the operator can read it.
@test "herdr run is a finding and leaves the pane open" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  ep="$(dux-backend open t13 "$DUX_HOME")"
  FAKE_HERDR_RUN_FAIL=1 run dux-backend run "$ep" "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: herdr pane run failed on w1:p9"* ]]
  [ "$(grep -c '^pane close ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

@test "herdr close refuses when the focus state cannot be read" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_BAD_JSON=1
  run dux-backend close "herdr:w1:p9"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane get returned no focus state"* ]]
  [ "$(grep -c '^pane close ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

@test "herdr close refuses when pane get fails" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_DEAD="$DUX_HOME/state/dead"; touch "$FAKE_HERDR_DEAD"
  run dux-backend close "herdr:w1:p9"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane get failed for w1:p9"* ]]
}

@test "tmux close of a missing window is a finding" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  run dux-backend close "tmux:duxtest:@9999"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: tmux window @9999 not found"* ]]
}

@test "herdr open with no prompt still refuses to close a focused pane" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1 FAKE_HERDR_FOCUSED="$DUX_HOME/state/focused"; touch "$FAKE_HERDR_FOCUSED"
  run dux-backend open t8 "$DUX_HOME"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to close focused pane w1:p9"* ]]
  [ "$(grep -c '^pane close ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

@test "herdr open with no prompt reports a failed cleanup close" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1 FAKE_HERDR_CLOSE_FAIL=1
  run dux-backend open t9 "$DUX_HOME"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane close failed for w1:p9"* ]]
}

@test "tmux close is a finding when window state cannot be read, and the window stays" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  ep="$(dux-backend open t10 "$DUX_HOME")"
  FAKE_TMUX_FAIL=display-message run dux-backend close "$ep"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot read tmux state for"* ]]
  run dux-backend exists "$ep"; [ "$status" -eq 0 ]
}

@test "tmux close is a finding when kill-window fails" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  ep="$(dux-backend open t11 "$DUX_HOME")"
  FAKE_TMUX_FAIL=kill-window run dux-backend close "$ep"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: tmux kill-window failed for"* ]]
}

# The endpoint decides which pane is titled. The wrapper runs outside the tab
# now and carries the orchestrator's own HERDR_PANE_ID, so a pane read from the
# environment would title the orchestrator's pane instead of the worker's.
@test "title names the pane in the endpoint, not one from the environment" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t7 "$DUX_HOME")"
  : > "$FAKE_HERDR_LOG"
  HERDR_PANE_ID=w1:pORCH run dux-backend title "$ep" "proj: ship the login screen"
  [ "$status" -eq 0 ]
  if [ "$DUX_BACKEND" = herdr ]; then
    grep -qF "pane report-metadata ${ep#herdr:} --source dux --title proj: ship the login screen" "$FAKE_HERDR_LOG"
    [ "$(grep -c 'w1:pORCH' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  else
    [ ! -s "$FAKE_HERDR_LOG" ]
  fi
}

@test "title refuses an endpoint from the other backend" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  other=zellij:nope
  run dux-backend title "$other" "a title"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: endpoint $other does not belong to backend $DUX_BACKEND"* ]]
}

# ---- prompt: one line typed into the pane's foreground process ---------------
# A round reaches a parked session this way, so the line has to arrive whole and
# submitted. On tmux the reader is a real process on the pane's terminal, which
# hands a line over only once Enter arrives. The Herdr fake has no terminal: it
# appends what `pane run` types into a live pane to a file standing in for one.
@test "prompt types the line and Enter into the pane's foreground process" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  line="Read $DUX_HOME/channel/round-1.md and follow it."
  if [ "$DUX_BACKEND" = tmux ]; then
    reader=cat typed="$DUX_HOME/typed"
    printf '#!/bin/sh\nexec cat > "%s"\n' "$typed" > "$DUX_HOME/reader"
  else
    reader=sleep typed="$FAKE_HERDR_LOG.input"
    printf '#!/bin/sh\nexec sleep 60\n' > "$DUX_HOME/reader"
  fi
  chmod +x "$DUX_HOME/reader"
  ep="$(dux-backend open t44 "$DUX_HOME")"
  dux-backend run "$ep" "$DUX_HOME" "'$DUX_HOME/reader'"
  wait_until 15 dux-backend pid "$ep" "$reader"
  pid="$(dux-backend pid "$ep" "$reader" | cut -d' ' -f1)"
  run dux-backend prompt "$ep" "$line"
  wait_until 10 test -s "$typed" || true
  kill -TERM -- "-$pid"
  wait_until 15 not_running "$pid"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  if [ ! -s "$typed" ]; then echo "the reader in the pane never received a line"; return 1; fi
  [ "$(cat "$typed")" = "$line" ]
  [ "$(wc -c < "$typed" | tr -d ' ')" -eq $(( ${#line} + 1 )) ]
}

@test "prompt is a finding when the line could not be typed, never a silent success" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t45 "$DUX_HOME")"
  if [ "$DUX_BACKEND" = tmux ]; then
    FAKE_TMUX_FAIL=send-keys run dux-backend prompt "$ep" "Read it and follow it."
  else
    FAKE_HERDR_RUN_FAIL=1 run dux-backend prompt "$ep" "Read it and follow it."
  fi
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: $DUX_BACKEND could not type into $ep"* ]]
}

@test "prompt refuses an endpoint from the other backend" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  run dux-backend prompt zellij:nope "Read it and follow it."
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: endpoint zellij:nope does not belong to backend $DUX_BACKEND"* ]]
}

# ---- pid: the pane's foreground process, by name ---------------------------
# Four readings, the same on both adapters: the process is there and its group
# and directory are reported; a name that is not running answers nothing; the
# group stop from outside ends it; and once it is gone there is nothing to
# report. On tmux the last one is the dead pane under remain-on-exit, which
# keeps a stale pane_pid the system may hand to another process entirely.
@test "pid reports the pane's foreground process and stops reporting once its group is stopped" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t40 "$DUX_HOME")"
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 1 ]; [ -z "$output" ]
  dux-backend run "$ep" "$DUX_HOME" "sh -c 'exec sleep 60'"
  # The shell has to get as far as the exec before the process is there to find.
  wait_until 15 dux-backend pid "$ep" sleep
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  pid="$(printf '%s' "$output" | cut -d' ' -f1)"
  pgid="$(printf '%s' "$output" | cut -d' ' -f2)"
  cwd="$(printf '%s' "$output" | cut -d' ' -f3-)"
  [[ "$pid" =~ ^[0-9]+$ ]]
  [ "$pgid" = "$pid" ]
  [ "$cwd" = "$DUX_HOME" ]
  kill -0 "$pid"
  # A foreground process under another name is not this one.
  run dux-backend pid "$ep" nothing
  [ "$status" -eq 1 ]; [ -z "$output" ]
  # The group stop Dux uses, sent from outside the pane.
  kill -TERM -- "-$pgid"
  wait_until 15 not_running "$pid"
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 1 ]; [ -z "$output" ]
  # The container outlives the process it ran, on both backends.
  run dux-backend exists "$ep"
  [ "$status" -eq 0 ]
}

# What `run` takes is a command line, and both multiplexers put it through a
# shell: Herdr types it into the pane's own shell and tmux respawns the pane
# under sh -c. So a path with a space in it, a Dux home under "My Projects",
# reaches the shell as two words unless the caller quoted it, and the wrapper
# quotes it for exactly this reason.
@test "run starts a program whose path holds a space, when the caller quoted it" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  spaced="$DUX_HOME/a dir"; mkdir -p "$spaced"
  printf '#!/bin/sh\nexec sleep 60\n' > "$spaced/launch"; chmod +x "$spaced/launch"
  ep="$(dux-backend open t42 "$DUX_HOME")"
  dux-backend run "$ep" "$DUX_HOME" "'$spaced/launch'"
  wait_until 15 dux-backend pid "$ep" sleep
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 0 ]
  pid="$(printf '%s' "$output" | cut -d' ' -f1)"
  pgid="$(printf '%s' "$output" | cut -d' ' -f2)"
  kill -TERM -- "-$pgid"
  wait_until 15 not_running "$pid"
}

# tmux hands a command line it cannot read as plain words to the pane's shell,
# and shells disagree about a single -c command: bash and macOS /bin/sh replace
# themselves with it, Linux's /bin/sh (dash) forks and waits. A shell left
# waiting is the pane's process, so `pid` answers "sh", the wrapper never finds
# the harness it just started, and the start times out at two minutes. Measured
# 2026-09-15 that was every tmux end-to-end test on Linux, and those suites are
# what prove the ending; what is read here is the line tmux recorded, because
# whether a shell stands in the way at all is the machine's business and this
# reading is the same on every one of them.
@test "tmux run hands the pane over, so the pane's own pid is the command's" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip "the Herdr pane keeps the shell it was opened with"
  printf '#!/bin/sh\nexec sleep 60\n' > "$DUX_HOME/handover"; chmod +x "$DUX_HOME/handover"
  ep="$(dux-backend open t43 "$DUX_HOME")"
  tmux -L dux-test set-option -t duxtest default-shell /bin/sh
  dux-backend run "$ep" "$DUX_HOME" "'$DUX_HOME/handover'"
  [[ "$(tmux -L dux-test list-panes -t "${ep##*:}" -F '#{pane_start_command}')" == *"exec '$DUX_HOME/handover'"* ]]
  wait_until 15 dux-backend pid "$ep" sleep
  run dux-backend pid "$ep" sleep
  [ "$status" -eq 0 ]
  pid="$(printf '%s' "$output" | cut -d' ' -f1)"
  [ "$pid" = "$(tmux -L dux-test list-panes -t "${ep##*:}" -F '#{pane_pid}')" ]
  tmux -L dux-test set-option -u -t duxtest default-shell
  kill -TERM -- "-$pid"
  wait_until 15 not_running "$pid"
}

@test "pid is a finding when the multiplexer did not answer, never a gone" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  ep="$(dux-backend open t41 "$DUX_HOME")"
  if [ "$DUX_BACKEND" = herdr ]; then
    FAKE_HERDR_PROCINFO_FAIL=1 run dux-backend pid "$ep" sleep
    [[ "$output" == *"finding: herdr pane process-info failed for w1:p"* ]]
  else
    FAKE_TMUX_FAIL=list-panes run dux-backend pid "$ep" sleep
    [[ "$output" == *"finding: tmux could not read the pane of"* ]]
  fi
  [ "$status" -eq 2 ]
}

@test "herdr pid refuses a reply with no process information" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  ep="$(dux-backend open t42 "$DUX_HOME")"
  FAKE_HERDR_PROCINFO_JUNK=1 run dux-backend pid "$ep" sleep
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: herdr pane process-info returned no process information"* ]]
}
