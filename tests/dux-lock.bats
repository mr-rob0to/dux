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
