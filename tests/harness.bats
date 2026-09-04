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
