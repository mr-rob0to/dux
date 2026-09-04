# bats file_tags=adapter
load helpers/setup

# Runs for whichever backend $DUX_BACKEND names. The Makefile runs it twice.
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

@test "herdr open is a finding when no shell prompt appears, and the command is never sent" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_NO_PROMPT=1
  run dux-backend open t6 "$DUX_HOME" "sleep 5"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no shell prompt in pane w1:p9"* ]]
  ! grep -q '^pane run ' "$FAKE_HERDR_LOG"
  grep -q '^pane close w1:p9' "$FAKE_HERDR_LOG"
}

@test "herdr close refuses when the focus state cannot be read" {
  [ "${DUX_BACKEND:-}" = herdr ] || skip
  export FAKE_HERDR_BAD_JSON=1
  run dux-backend close "herdr:w1:p9"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: herdr pane get returned no focus state"* ]]
  ! grep -q '^pane close ' "$FAKE_HERDR_LOG"
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
  ! grep -q '^pane close ' "$FAKE_HERDR_LOG"
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
