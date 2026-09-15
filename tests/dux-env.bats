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

# A group whose every member has exited but has not been waited on is a group
# that has gone. The shape built here is the one measured on Linux: a parent
# that never reaps, and a child in a group of its own, so the group holds one
# zombie and nothing else. The two systems do not read that group the same way
# and the context line says which one ran: kill -0 answers yes on Linux and no
# on macOS, which is why the wrapper trusted it for a year and why it then
# reported a harness it had killed as one that survived KILL.
@test "group_runs reads a group of nothing but zombies as gone" {
  run bash -c '
    source "$DUX_ROOT/bin/dux-env"
    # Line-buffered, or the pid stays in perl own buffer until it exits and the
    # reader below waits for a file that is never written.
    perl -MPOSIX -e '"'"'$| = 1; my $pid = fork();
      if ($pid == 0) { POSIX::setpgid(0, 0); exit 0; }
      print "$pid\n"; sleep 60;'"'"' > "$DUX_HOME/state/zpid" &
    parent=$!
    zombie() {  # $1 pid
      case "$(ps -o stat= -p "$1" 2>/dev/null)" in *Z*) return 0 ;; esac
      return 1
    }
    i=0; z=""
    until [ -n "$z" ] && zombie "$z"; do
      i=$((i + 1)); [ "$i" -ge 100 ] && break
      sleep 0.1
      z="$(cat "$DUX_HOME/state/zpid" 2>/dev/null)"
    done
    kill -0 -- "-$z" 2>/dev/null; k=$?
    group_runs "$z"; g=$?
    echo "context: [$z] is [$(ps -o stat= -p "$z" 2>/dev/null)] after $i tenths, kill0=$k"
    echo "answers: group_runs=$g"
    kill -KILL "$parent" 2>/dev/null
  '
  echo "$output"
  [[ "$output" == *"answers: group_runs=1"* ]]
  # The group has to have been a zombie one, or the reading above is about nothing.
  [[ "$output" == *"] is [Z"* ]]
}

@test "pid_runs matches a live pid and a whole command-line word" {
  run bash -c '
    source "$DUX_ROOT/bin/dux-env"
    fifo="$DUX_HOME/state/fifo"; mkfifo "$fifo"
    ( exec -a "dux-worker-wrap t1" cat ) <> "$fifo" >/dev/null 2>&1 & end=$!
    ( exec -a "dux-worker-wrap t1" sleep 30 ) >/dev/null 2>&1 & mid=$!
    # Wait until both processes are really running under the new name. A fixed
    # pause was here before, and it was long enough on a fast machine and not on
    # a slow one: the second process had not reached its sleep yet, so pid_runs
    # was asked about a shell. The match is anchored at the start of the command
    # line, because this script holds its own source and so its command line
    # contains the name too; an unanchored match answered yes straight away and
    # waited for nothing. It reads ps rather than calling pid_runs, so it does
    # not make the answers below true by asking the question the test is asking.
    renamed() {  # $1 pid
      case "$(ps -ww -o command= -p "$1" 2>/dev/null)" in
        "dux-worker-wrap t1"*) return 0 ;;
      esac
      return 1
    }
    i=0
    until renamed "$end" && renamed "$mid"; do
      i=$((i + 1)); [ "$i" -ge 100 ] && break
      sleep 0.1
    done
    renamed "$$"; g=$?
    pid_runs "$end" "dux-worker-wrap t1"; a=$?
    pid_runs "$mid" "dux-worker-wrap t1"; b=$?
    pid_runs "$end" "dux-worker-wrap t"; c=$?
    pid_runs "$end" "dux-worker-wrap t10"; d=$?
    pid_runs 999999 "dux-worker-wrap t1"; e=$?
    pid_runs "" "dux-worker-wrap t1"; f=$?
    endcmd="$(ps -ww -o command= -p "$end" 2>/dev/null)"
    midcmd="$(ps -ww -o command= -p "$mid" 2>/dev/null)"
    echo "answers: $a $b $c $d $e $f"
    echo "self: $g"
    echo "context: waited $i tenths of a second; end is [$endcmd] and mid is [$midcmd]"
    # Disowned before it is killed, and killed after the answers are printed.
    # A shell reports a background job that a signal ended, and it prints that
    # notice at the next command boundary, not where the kill was written. On
    # CI the notice landed above the answers and the test read it as the
    # answers. Disowning drops the job from the table so no notice is made, and
    # killing last means a notice from anywhere else cannot get in front.
    disown "$end" "$mid" 2>/dev/null
    kill "$end" "$mid" 2>/dev/null'
  # Each line is found by its own label rather than by its position, so any
  # stray line the shell adds is ignored instead of being read as an answer.
  answers="$(printf '%s\n' "$output" | sed -n 's/^answers: //p')"
  self="$(printf '%s\n' "$output" | sed -n 's/^self: //p')"
  context="$(printf '%s\n' "$output" | sed -n 's/^context: //p')"
  # Said out loud rather than left to a bare comparison: when this failed on CI
  # the log showed only that the line did not match, so which of the six answers
  # was wrong, and what the process table actually held, cost a round trip.
  [ "$answers" = "0 0 1 1 1 1" ] || {
    echo "pid_runs answered [$answers], wanted [0 0 1 1 1 1]"
    echo "$context"
    echo "whole output was:"
    echo "$output"
    return 1
  }
  # The wait must not accept a process whose command line only quotes the name.
  # This script is one: it carries its own source. That is what let the wait pass
  # instantly and hand pid_runs a shell that had not become a worker yet.
  [ "$self" = 1 ] || {
    echo "the wait accepted a process that only quotes the name"
    echo "$context"
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

# A reader that stops early closes the pipe under whatever is writing into it.
# The producer either dies on SIGPIPE or, if it handles the signal, reports the
# failed write on stderr, where Dux prints findings and nothing else. The
# producer here ignores SIGPIPE on purpose so the fault is deterministic rather
# than a race the test would lose most of the time; jq and GNU sed do the same
# thing in the real scripts. 200000 bytes is past any pipe buffer, so the write
# cannot land in one go.
@test "take_bytes gives back the bytes asked for and leaves nothing writing into a closed pipe" {
  run --separate-stderr bash -c 'source "$DUX_ROOT/bin/dux-env"
    trap "" PIPE; printf "%s" "$(printf "a%.0s" $(seq 1 200000))" | take_bytes 10'
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "producer wrote to stderr: $stderr"; return 1; }
  [ "${#output}" -eq 10 ] || { echo "wanted 10 bytes, got ${#output}"; return 1; }
}

@test "take_line gives back the first line and leaves nothing writing into a closed pipe" {
  run --separate-stderr bash -c 'source "$DUX_ROOT/bin/dux-env"
    trap "" PIPE; printf "first\n%s\n" "$(printf "a%.0s" $(seq 1 200000))" | take_line'
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "producer wrote to stderr: $stderr"; return 1; }
  [ "$output" = first ] || { echo "wanted 'first', got '$output'"; return 1; }
}
