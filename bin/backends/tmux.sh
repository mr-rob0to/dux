#!/usr/bin/env bash
# tmux adapter. Sourced by dux-backend after dux-env. Endpoint: tmux:<session>:<window_id>
set -u

_tmux() {
  if [ -n "${DUX_TMUX_SOCKET:-}" ]; then tmux -L "$DUX_TMUX_SOCKET" "$@"; else tmux "$@"; fi
}

_session() {
  if [ -n "${DUX_TMUX_SESSION:-}" ]; then echo "$DUX_TMUX_SESSION"
  elif [ -n "${TMUX:-}" ]; then _tmux display-message -p '#{session_name}'
  else
    _tmux has-session -t dux 2>/dev/null || _tmux new-session -d -s dux -x 120 -y 40
    echo dux
  fi
}

# The path tmux resolves this adapter's socket to: ${TMUX_TMPDIR:-/tmp}/tmux-<uid>/<name>,
# where <name> is what -L is given, or "default" when it is not.
_socket_path() { printf '%s/tmux-%s/%s\n' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "${DUX_TMUX_SOCKET:-default}"; }

# What the socket path is decides a failed listing, and tmux's error text only
# refines it once the path is a socket. The text differs between platforms for
# the same path, so it cannot safely decide whether a container is absent.
_absent_or_finding() {  # $1 what was being checked, $2 error text, $3 exit code
  local what="$1" err="$2" rc="$3" sock subject
  sock="$(_socket_path)"
  subject="${what#looking for }"
  if [ ! -e "$sock" ] && [ ! -L "$sock" ]; then return 0; fi
  [ -S "$sock" ] || finding \
    "the tmux socket path $sock is not a socket, so nothing there can answer for $subject: ${err:-exit $rc}"
  case "$err" in
    *"no server running"*) return 0 ;;
  esac
  finding "tmux could not list windows while $what: ${err:-exit $rc}"
}

_win() { local ep="$1"; echo "${ep##*:}"; }          # window id (@N)
_ses() { local ep="${1#tmux:}"; echo "${ep%%:*}"; }  # session name

backend_open() {  # id cwd; opens the tab as a shell at its prompt
  # Create the window first and turn remain-on-exit on before anything runs in
  # it, otherwise a command that exits quickly takes the window with it.
  local id="$1" cwd="$2" ses wid
  ses="$(_session)"
  wid="$(_tmux new-window -d -t "$ses" -n "dux-$id" -c "$cwd" -P -F '#{window_id}')" \
    || finding "tmux could not open a window for $id"
  _tmux set-option -w -t "$wid" remain-on-exit on >/dev/null \
    || finding "tmux could not set remain-on-exit on $wid for $id"
  echo "tmux:$ses:$wid"
}

backend_run() {  # endpoint cwd cmd; replaces the pane's shell with cmd
  local wid; wid="$(_win "$1")"
  _tmux respawn-pane -k -t "$wid" -c "$2" "$3" >/dev/null \
    || finding "tmux could not start the command in $wid"
}

# The pane's foreground process, when its command name is <name>. Measured on
# tmux 3.6a: respawn-pane starts the command in a session of its own, so its
# process group equals its pid, and `sh -c 'exec ...'` keeps the pid while the
# command name becomes the exec'd program's.
#
# The name comes from ps, not from #{pane_current_command}. Measured 2026-09-14
# with a real Claude Code 2.1.270 in a pane on macOS: tmux reported the pane's
# command as [2.1.270] while ps -o comm= read [claude]. tmux reads the kernel's
# short process name, which Claude Code sets to its version; ps reads argv[0],
# which stays claude. Matching the tmux field would have meant the wrapper never
# finding the harness it had just started, on every real run. ps is also where
# the Herdr adapter's argv0 comes from, so both adapters now answer the same
# question from the same place. Nothing the suite can start sets the two apart,
# so this one is held by that measurement and by the milestone's own run, not by
# a test. macOS pads the field and can print a path, hence the trim.
#
# #{pane_dead} is read first and on its own. Under remain-on-exit a dead pane
# keeps the pid of the process that exited, which the system is free to hand to
# something else, and #{pane_current_command} reverts to the pane's shell:
# measured, a dead pane reported [1] [32628] [sh] [] for a sleep that had gone.
backend_pid() {  # endpoint name; prints "<pid> <pgid> <cwd>", 1 when it is not there
  local wid name out rest dead pid cmd cwd pgid
  wid="$(_win "$1")"; name="$2"
  out="$(_tmux list-panes -t "$wid" -F '#{pane_dead} #{pane_pid} #{pane_current_path}' 2>/dev/null)" \
    || finding "tmux could not read the pane of $wid"
  rest="$(printf '%s\n' "$out" | take_line)"
  [ -n "$rest" ] || finding "tmux listed no pane for $wid"
  dead="${rest%% *}"; rest="${rest#* }"
  [ "$dead" = 0 ] || return 1
  pid="${rest%% *}"; cwd="${rest#* }"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  cmd="$(ps -o comm= -p "$pid" 2>/dev/null | sed 's/^ *//; s/ *$//')"
  [ "${cmd##*/}" = "$name" ] || return 1
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  case "$pgid" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s %s\n' "$pid" "$pgid" "$cwd"
}

backend_exists() {  # endpoint: 0 present, 1 gone, finding when tmux did not answer
  local wid errfile out rc err; wid="$(_win "$1")"
  errfile="$(mktemp "${TMPDIR:-/tmp}/dux-tmux-exists.XXXXXX")" || finding "cannot create a temp file to read tmux errors"
  out="$(_tmux list-windows -a -F '#{window_id}' 2>"$errfile")"; rc=$?
  err="$(cat "$errfile")"; rm -f "$errfile"
  if [ "$rc" -ne 0 ]; then _absent_or_finding "checking $1" "$err" "$rc"; return 1; fi
  printf '%s\n' "$out" | grep "^$wid$" >/dev/null
}

backend_find() {  # id: prints the endpoint of the window named dux-<id>, nothing when there is none
  # Never _session: that would start a server to answer a question about it.
  local id="$1" errfile out rc err n
  errfile="$(mktemp "${TMPDIR:-/tmp}/dux-tmux-find.XXXXXX")" || finding "cannot create a temp file to read tmux errors"
  out="$(_tmux list-windows -a -f "#{==:#{window_name},dux-$id}" -F '#{session_name}:#{window_id}' 2>"$errfile")"
  rc=$?
  err="$(cat "$errfile")"; rm -f "$errfile"
  if [ "$rc" -ne 0 ]; then
    # What the socket path is decides this, and tmux's error text only refines it
    # once the path is a socket. The text alone cannot decide: tmux says
    # different things on different platforms for the same path (a plain file at
    # the socket path is "Socket operation on non-socket" under tmux 3.6a on
    # macOS and "no server running" under tmux 3.4 on Linux), and reading the
    # wrong one as "nothing is running" lets a second worker start on a branch
    # that already has one.
    #   no path        no server has ever been reachable there, which is every
    #                  first spawn on a machine: no container.
    #   a socket       tmux looked through it, so "no server running" is the
    #                  stale socket an exited server left, a normal state a spawn
    #                  must not wedge on: no container. Every other failure there
    #                  is a question tmux did not answer, and a live server
    #                  holding the worker reads exactly the same way.
    #   anything else  something is wrong at the path and guessing is not allowed.
    # A worker in a server whose socket was removed outright reads as no
    # container here; dux-spawn's own pidfile check is the layer that catches it.
    _absent_or_finding "looking for dux-$id" "$err" "$rc"; return 0
  fi
  [ -n "$out" ] || return 0
  n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  [ "$n" = 1 ] || finding "$n tmux windows are named dux-$id; close all but one before spawning $id"
  printf 'tmux:%s\n' "$out"
}

backend_close() {  # endpoint. Closes only on a positive "not focused" reading.
  local wid state active attached; wid="$(_win "$1")"
  backend_exists "$1" || finding "tmux window $wid not found; nothing to close"
  state="$(_tmux display-message -p -t "$wid" '#{window_active} #{session_attached}' 2>/dev/null)" \
    || finding "cannot read tmux state for $wid; refusing to close"
  active="${state%% *}"; attached="${state#* }"
  if [ "$active" = 1 ] && [ "$attached" != 0 ]; then finding "refusing to close focused pane $1"; fi
  _tmux kill-window -t "$wid" 2>/dev/null || finding "tmux kill-window failed for $wid"
}

backend_notify() {  # title body
  _tmux display-message "$1: $2" 2>/dev/null || true
}

# The window name is what backend_find matches, so tmux has no separate title
# to set; the endpoint is taken and ignored so both adapters read the same.
backend_title() { :; }  # endpoint text
