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

@test "simultaneous acquires by six live pids let exactly one win" {
  pids=""; for i in 1 2 3 4 5 6; do sleep 30 3>&- & pids="$pids $!"; done
  wins=0
  jobs=""; for p in $pids; do DUX_SESSION_PID=$p dux-lock acquire >/dev/null 2>&1 & jobs="$jobs $!"; done; wait $jobs || true
  for p in $pids; do [ "$(cat "$DUX_HOME/state/dux.lock")" = "$p" ] && wins=$((wins+1)); done
  # every racer re-runs acquire: the holder exits 0, everyone else exits 3
  zero=0; for p in $pids; do DUX_SESSION_PID=$p dux-lock acquire >/dev/null && zero=$((zero+1)); done
  kill $pids
  [ "$wins" -eq 1 ]
  [ "$zero" -eq 1 ]
}

@test "simultaneous acquires over a stale lock let exactly one win" {
  echo 999999 > "$DUX_HOME/state/dux.lock"
  pids=""; for i in 1 2 3 4 5 6; do sleep 30 3>&- & pids="$pids $!"; done
  jobs=""; for p in $pids; do DUX_SESSION_PID=$p dux-lock acquire >/dev/null 2>&1 & jobs="$jobs $!"; done; wait $jobs || true
  h="$(cat "$DUX_HOME/state/dux.lock")"
  zero=0; for p in $pids; do DUX_SESSION_PID=$p dux-lock acquire >/dev/null && zero=$((zero+1)); done
  [ "$h" != 999999 ]; kill -0 "$h"
  kill $pids
  [ "$zero" -eq 1 ]
  [ ! -d "$DUX_HOME/state/dux.lock.reclaim" ]
}

@test "a lock file holding garbage is treated as dead and reclaimed" {
  echo 'not-a-pid' > "$DUX_HOME/state/dux.lock"
  run dux-lock status; [ "$output" = "held by pid not-a-pid (dead)" ]
  DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
}
