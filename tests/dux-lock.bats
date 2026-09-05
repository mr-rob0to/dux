bats_require_minimum_version 1.5.0
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
  jobs=""; for p in $pids; do
    ( DUX_SESSION_PID=$p dux-lock acquire >/dev/null 2>&1; echo $? > "$DUX_HOME/state/rc.$p" ) & jobs="$jobs $!"
  done; wait $jobs || true
  first_round_zero="$(cat "$DUX_HOME"/state/rc.* | grep -c '^0$')"
  for p in $pids; do [ "$(cat "$DUX_HOME/state/dux.lock")" = "$p" ] && wins=$((wins+1)); done
  # every racer re-runs acquire: the holder exits 0, everyone else exits 3
  zero=0; for p in $pids; do DUX_SESSION_PID=$p dux-lock acquire >/dev/null && zero=$((zero+1)); done
  kill $pids
  [ "$first_round_zero" -eq 1 ]
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

@test "acquire on an unwritable state dir is a finding, not a held lock" {
  chmod 555 "$DUX_HOME/state"
  DUX_SESSION_PID=$$ run dux-lock acquire
  chmod 755 "$DUX_HOME/state"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot write to $DUX_HOME/state"* ]]
}

@test "an in-flight temp file from the same session is never touched" {
  echo stray > "$DUX_HOME/state/dux.lock.$$.tmp"
  DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 0 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
  [ "$(cat "$DUX_HOME/state/dux.lock.$$.tmp")" = stray ]
}

@test "an empty lock file is never reclaimed" {
  : > "$DUX_HOME/state/dux.lock"
  DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: $DUX_HOME/state/dux.lock is empty"* ]]
  [ -f "$DUX_HOME/state/dux.lock" ]
  run dux-lock status; [ "$output" = "lock file empty" ]
}

@test "a hard-link failure with no holder is a finding" {
  mkdir -p "$DUX_HOME/bin"; printf '#!/bin/sh\nexit 1\n' > "$DUX_HOME/bin/ln"; chmod +x "$DUX_HOME/bin/ln"
  PATH="$DUX_HOME/bin:$PATH" DUX_SESSION_PID=$$ run dux-lock acquire
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: cannot create $DUX_HOME/state/dux.lock and no session holds it"* ]]
  [ ! -f "$DUX_HOME/state/dux.lock" ]
}

@test "same-session acquires in parallel all succeed and leave no temp files" {
  jobs=""; for i in 1 2 3 4 5 6; do
    ( DUX_SESSION_PID=$$ dux-lock acquire >/dev/null 2>&1; echo $? > "$DUX_HOME/state/rc.$i" ) & jobs="$jobs $!"
  done; wait $jobs || true
  [ "$(cat "$DUX_HOME"/state/rc.* | grep -c '^0$')" -eq 6 ]
  [ "$(cat "$DUX_HOME/state/dux.lock")" = "$$" ]
  [ -z "$(ls "$DUX_HOME"/state/dux.lock.*.tmp 2>/dev/null)" ]
}

@test "mine is true only for the holder" {
  DUX_SESSION_PID=$$ dux-lock acquire
  DUX_SESSION_PID=$$ run dux-lock mine; [ "$status" -eq 0 ]; [ -z "$output" ]
  DUX_SESSION_PID=424242 run dux-lock mine; [ "$status" -eq 1 ]
  rm -f "$DUX_HOME/state/dux.lock"
  DUX_SESSION_PID=$$ run dux-lock mine; [ "$status" -eq 1 ]
}

@test "acquire starts a watcher in its own process group" {
  DUX_WATCHER=on DUX_SESSION_PID=$$ run --separate-stderr dux-lock acquire
  [ "$status" -eq 0 ]
  w="$(cat "$DUX_HOME/state/watch.pid")"
  [ "$output" = "watcher started (pid $w)" ]
  ps -ww -o command= -p "$w" | grep -q dux-watch
  [ "$(ps -o pgid= -p "$w" | tr -d ' ')" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]
  [ -f "$DUX_HOME/state/events.log" ]; [ "$(cat "$DUX_HOME/state/wakes.base")" = 0 ]
}

@test "a same-session acquire replaces the watcher" {
  DUX_WATCHER=on DUX_SESSION_PID=$$ dux-lock acquire >/dev/null
  w1="$(cat "$DUX_HOME/state/watch.pid")"
  DUX_WATCHER=on DUX_SESSION_PID=$$ dux-lock acquire >/dev/null
  w2="$(cat "$DUX_HOME/state/watch.pid")"
  [ "$w1" != "$w2" ]; wait_until 5 bash -c "! kill -0 $w1 2>/dev/null"; kill -0 "$w2"
}

@test "release stops the watcher and removes its pidfile" {
  DUX_WATCHER=on DUX_SESSION_PID=$$ dux-lock acquire >/dev/null
  w="$(cat "$DUX_HOME/state/watch.pid")"
  DUX_WATCHER=on DUX_SESSION_PID=$$ run dux-lock release
  [ "$status" -eq 0 ]; wait_until 5 bash -c "! kill -0 $w 2>/dev/null"
  [ ! -e "$DUX_HOME/state/watch.pid" ]
}

@test "release by a non-holder leaves the watcher" {
  DUX_WATCHER=on DUX_SESSION_PID=$$ dux-lock acquire >/dev/null
  w="$(cat "$DUX_HOME/state/watch.pid")"
  DUX_WATCHER=on DUX_SESSION_PID=424242 dux-lock release
  kill -0 "$w"; [ -f "$DUX_HOME/state/watch.pid" ]
}

@test "an acquire blocked by a live holder leaves its watcher" {
  sleep 30 3>&- & other=$!
  DUX_SESSION_PID=$other dux-lock acquire >/dev/null
  w="$(stand_in dux-watch)"; echo "$w" > "$DUX_HOME/state/watch.pid"
  DUX_WATCHER=on DUX_SESSION_PID=$$ run dux-lock acquire
  kill "$other"
  [ "$status" -eq 3 ]; kill -0 "$w"; [ "$(cat "$DUX_HOME/state/watch.pid")" = "$w" ]
}

@test "acquire leaves a recorded stranger alone and reports it" {
  s="$(stand_in not-a-watcher)"; echo "$s" > "$DUX_HOME/state/watch.pid"
  DUX_WATCHER=on DUX_SESSION_PID=$$ run --separate-stderr dux-lock acquire
  [ "$status" -eq 0 ]; kill -0 "$s"
  [[ "$stderr" == *"names pid $s, which is not dux-watch; left alone"* ]]
  [ "$(cat "$DUX_HOME/state/watch.pid")" != "$s" ]
}

@test "DUX_WATCHER=off leaves no watcher and reports it" {
  DUX_WATCHER=off DUX_SESSION_PID=$$ run --separate-stderr dux-lock acquire
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [[ "$stderr" == *"watcher disabled by DUX_WATCHER=off"* ]]
  [ ! -e "$DUX_HOME/state/watch.pid" ]
}
