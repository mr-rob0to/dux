load helpers/setup

@test "dux-env exports paths under DUX_HOME and creates them" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; echo "$DUX_DATA $DUX_STATE $DUX_CONFIG $DUX_TASKS"; [ -d "$DUX_TASKS" ]'
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/data $DUX_HOME/state $DUX_HOME/config $DUX_HOME/data/tasks" ]
}

@test "DUX_HOME defaults to DUX_ROOT when unset" {
  mkdir -p "$DUX_HOME/fakeroot/bin"; cp "$DUX_ROOT/bin/dux-env" "$DUX_HOME/fakeroot/bin/"
  run bash -c 'unset DUX_HOME DUX_ROOT; source "'"$DUX_HOME"'/fakeroot/bin/dux-env"; echo "$DUX_HOME"'
  [ "$output" = "$DUX_HOME/fakeroot" ]
}

@test "finding prints to stderr and exits 2" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; finding "worktree is dirty" 2>&1 >/dev/null'
  [ "$status" -eq 2 ]
  [ "$output" = "finding: worktree is dirty" ]
}

@test "finding is not swallowed by command substitution" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; f() { finding "inner"; }; x="$(f)" || exit $?; echo "reached"'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: inner"* ]]
  [[ "$output" != *reached* ]]
}

@test "die prints to stderr and exits 1" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; die "boom" 2>&1'
  [ "$status" -eq 1 ]
  [ "$output" = "dux: boom" ]
}

@test "require_cmd dies naming the missing command" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; require_cmd jq definitely-not-a-cmd 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-cmd"* ]]
}

@test "now is UTC ISO-8601 seconds" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; now'
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "pid_runs matches a live pid and a whole command-line word" {
  run bash -c '
    source "$DUX_ROOT/bin/dux-env"
    fifo="$DUX_HOME/state/fifo"; mkfifo "$fifo"
    ( exec -a "dux-worker-wrap t1" cat ) <> "$fifo" >/dev/null 2>&1 & end=$!
    ( exec -a "dux-worker-wrap t1" sleep 30 ) >/dev/null 2>&1 & mid=$!
    # Wait until both processes are really showing the command line this test is
    # about. A fixed pause was here before, and it was long enough on a fast
    # machine and not on a slow one. The wait reads ps rather than calling
    # pid_runs, so it cannot make the answers below true by asking the same
    # question the test is asking.
    i=0
    until ps -ww -o command= -p "$end" 2>/dev/null | grep -q dux-worker-wrap &&
          ps -ww -o command= -p "$mid" 2>/dev/null | grep -q dux-worker-wrap; do
      i=$((i + 1)); [ "$i" -ge 100 ] && break
      sleep 0.1
    done
    pid_runs "$end" "dux-worker-wrap t1"; a=$?
    pid_runs "$mid" "dux-worker-wrap t1"; b=$?
    pid_runs "$end" "dux-worker-wrap t"; c=$?
    pid_runs "$end" "dux-worker-wrap t10"; d=$?
    pid_runs 999999 "dux-worker-wrap t1"; e=$?
    pid_runs "" "dux-worker-wrap t1"; f=$?
    endcmd="$(ps -ww -o command= -p "$end" 2>/dev/null)"
    midcmd="$(ps -ww -o command= -p "$mid" 2>/dev/null)"
    kill "$end" "$mid"
    echo "$a $b $c $d $e $f"
    echo "waited $i tenths of a second; end is [$endcmd] and mid is [$midcmd]"'
  # Said out loud rather than left to a bare comparison: when this failed on CI
  # the log showed only that the line did not match, so which of the six answers
  # was wrong, and what the process table actually held, cost a round trip.
  [ "${lines[0]}" = "0 0 1 1 1 1" ] || {
    echo "pid_runs answered ${lines[0]}, wanted 0 0 1 1 1 1"
    echo "${lines[1]}"
    return 1
  }
}

@test "pid_runs rejects a needle inside a prefixed command name" {
  watcher="$(stand_in not-dux-watch)"
  worker="$(stand_in 'not-dux-worker-wrap t1')"
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; pid_runs "$1" dux-watch' _ "$watcher"
  [ "$status" -eq 1 ]
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; pid_runs "$1" "dux-worker-wrap t1"' _ "$worker"
  [ "$status" -eq 1 ]
}

@test "mtime_epoch returns one portable timestamp" {
  touch -t 202001010000 "$DUX_HOME/f"
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; mtime_epoch "$DUX_HOME/f"'
  [ "$status" -eq 0 ]
  [ "$(wc -l <<< "$output" | tr -d ' ')" -eq 1 ]
  want="$(date -j -f %Y%m%d%H%M%S 20200101000000 +%s 2>/dev/null || date -d 2020-01-01T00:00:00 +%s)"
  [ "$output" = "$want" ]
}

@test "github_slug reads owner/name from ssh and https origins and refuses the rest" {
  for url in git@github.com:acme/widgets.git https://github.com/acme/widgets https://github.com/acme/widgets.git ssh://git@github.com/acme/widgets/; do
    d="$DUX_HOME/r-$RANDOM"; git init -q "$d"; git -C "$d" remote add origin "$url"
    run github_slug "$d"; [ "$status" -eq 0 ]; [ "$output" = acme/widgets ]
  done
  d="$DUX_HOME/gl"; git init -q "$d"; git -C "$d" remote add origin https://gitlab.example.invalid/acme/widgets.git
  run github_slug "$d"; [ "$status" -eq 1 ]; [ -z "$output" ]
  d="$DUX_HOME/none"; git init -q "$d"
  run github_slug "$d"; [ "$status" -eq 1 ]
  d="$DUX_HOME/deep"; git init -q "$d"; git -C "$d" remote add origin https://github.com/acme/widgets/extra
  run github_slug "$d"; [ "$status" -eq 1 ]
}

@test "github_slug refuses a host that only ends in github.com" {
  # A substring test reads these as the real acme/widgets on GitHub. Intake
  # would then list issues and comment on a repository the operator never
  # registered, with the operator's own token.
  for url in https://notgithub.com/acme/widgets git@evilgithub.com:acme/widgets \
             https://github.com.evil.example/acme/widgets \
             https://evil.example/x@github.com/acme/widgets; do
    d="$DUX_HOME/look-$RANDOM"; git init -q "$d"; git -C "$d" remote add origin "$url"
    run github_slug "$d"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
  done
  # A token in the url is still github.com, and still the same repository.
  d="$DUX_HOME/tok"; git init -q "$d"; git -C "$d" remote add origin https://tok@github.com/acme/widgets.git
  run github_slug "$d"; [ "$status" -eq 0 ]; [ "$output" = acme/widgets ]
}
