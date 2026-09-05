# bats file_tags=adapter
load helpers/setup

# Runs for whichever backend $DUX_BACKEND names. The Makefile runs it twice.

# Where tmux puts the socket named by -L, worked out the same way the adapter does.
tmux_socket_path() { printf '%s/tmux-%s/%s\n' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "$1"; }

setup_file() {
  if [ "${DUX_BACKEND:-}" = herdr ]; then
    export HERDR_WORKSPACE_ID=w1
  fi
  if [ "${DUX_BACKEND:-}" = tmux ]; then
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

@test "exists is a finding when the backend cannot answer, never a gone" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  if [ "$DUX_BACKEND" = tmux ]; then
    ep="$(dux-backend open t30 "$DUX_HOME" "sleep 30")"
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
  ep="$(dux-backend open t20 "$DUX_HOME" "sleep 30")"
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
  FAKE_HERDR_NO_PANE_ID=1 FAKE_HERDR_TAB_CLOSE_FAIL=1 run dux-backend open t22 "$DUX_HOME" "sleep 5"
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

@test "herdr open is a finding when no shell prompt appears, and the command is never sent" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1
  run dux-backend open t6 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no shell prompt in pane w1:p9"* ]]
  [ "$(grep -c '^pane run ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
  grep -q '^pane close w1:p9' "$FAKE_HERDR_LOG"
}

@test "herdr open closes the tab it created when the create returns no pane id" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PANE_ID=1
  run dux-backend open t12 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr tab create returned no pane id for t12"* ]]
  grep -qx 'tab close w1:t9' "$FAKE_HERDR_LOG"
  # A bare "! grep" mid-test is ignored by bats, so count the lines instead.
  [ "$(grep -c '^pane run ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

@test "herdr open closes the pane it created when pane run fails" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_RUN_FAIL=1
  run dux-backend open t13 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finding: herdr pane run failed for t13 on w1:p9"* ]]
  grep -qx 'pane close w1:p9' "$FAKE_HERDR_LOG"
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
  run dux-backend open t8 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: refusing to close focused pane w1:p9"* ]]
  [ "$(grep -c '^pane close ' "$FAKE_HERDR_LOG" || true)" -eq 0 ]
}

@test "herdr open with no prompt reports a failed cleanup close" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1 FAKE_HERDR_CLOSE_FAIL=1
  run dux-backend open t9 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane close failed for w1:p9"* ]]
}

@test "tmux close is a finding when window state cannot be read, and the window stays" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  ep="$(dux-backend open t10 "$DUX_HOME" "sleep 30")"
  FAKE_TMUX_FAIL=display-message run dux-backend close "$ep"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot read tmux state for"* ]]
  run dux-backend exists "$ep"; [ "$status" -eq 0 ]
}

@test "tmux close is a finding when kill-window fails" {
  [ "${DUX_BACKEND:-}" = tmux ] || skip
  ep="$(dux-backend open t11 "$DUX_HOME" "sleep 30")"
  FAKE_TMUX_FAIL=kill-window run dux-backend close "$ep"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: tmux kill-window failed for"* ]]
}

@test "report mirrors a status line to the herdr pane named by HERDR_PANE_ID, and is a no-op on tmux" {
  [ -n "${DUX_BACKEND:-}" ] || skip
  HERDR_PANE_ID=w1:p9 run dux-backend report t7 idle "done: PR https://example.invalid/pr/1"
  [ "$status" -eq 0 ]
  if [ "$DUX_BACKEND" = herdr ]; then
    grep -qF 'pane report-agent w1:p9 --source dux --agent dux-t7 --state idle --message done: PR https://example.invalid/pr/1' "$FAKE_HERDR_LOG"
  else
    [ ! -s "$FAKE_HERDR_LOG" ]
  fi
}

@test "title sets the herdr sidebar title" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  HERDR_PANE_ID=w1:p9 run dux-backend title "proj: ship the login screen"
  [ "$status" -eq 0 ]
  grep -qF 'pane report-metadata w1:p9 --title proj: ship the login screen' "$FAKE_HERDR_LOG"
}

@test "report without HERDR_PANE_ID is a finding on herdr" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  run env -u HERDR_PANE_ID dux-backend report t7 working "working: x"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: HERDR_PANE_ID is unset"* ]]
}
