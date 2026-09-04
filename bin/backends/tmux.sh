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

_win() { local ep="$1"; echo "${ep##*:}"; }          # window id (@N)
_ses() { local ep="${1#tmux:}"; echo "${ep%%:*}"; }  # session name

backend_open() {  # id cwd cmd
  # Create the window first and turn remain-on-exit on before the command runs,
  # otherwise a command that exits quickly takes the window with it.
  local id="$1" cwd="$2" cmd="$3" ses wid
  ses="$(_session)"
  wid="$(_tmux new-window -d -t "$ses" -n "dux-$id" -c "$cwd" -P -F '#{window_id}')" \
    || finding "tmux could not open a window for $id"
  _tmux set-option -w -t "$wid" remain-on-exit on >/dev/null \
    || finding "tmux could not set remain-on-exit on $wid for $id"
  _tmux respawn-pane -k -t "$wid" -c "$cwd" "$cmd" >/dev/null \
    || finding "tmux could not start the command in $wid for $id"
  echo "tmux:$ses:$wid"
}

backend_exists() {  # endpoint
  local wid; wid="$(_win "$1")"
  _tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -q "^$wid$"
}

backend_find() {  # id: prints the endpoint of the window named dux-<id>, nothing when there is none
  # Never _session: that would start a server to answer a question about it.
  local id="$1" errfile out rc err n sock
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
    sock="$(_socket_path)"
    if [ ! -e "$sock" ] && [ ! -L "$sock" ]; then return 0; fi
    [ -S "$sock" ] || finding \
      "the tmux socket path $sock is not a socket, so nothing there can answer for dux-$id: ${err:-exit $rc}"
    case "$err" in
      *"no server running"*) return 0 ;;
    esac
    finding "tmux could not list windows while looking for dux-$id: ${err:-exit $rc}"
  fi
  [ -n "$out" ] || return 0
  n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  [ "$n" = 1 ] || finding "$n tmux windows are named dux-$id; close all but one before spawning $id"
  printf 'tmux:%s\n' "$out"
}

backend_tail() {  # endpoint n
  local wid; wid="$(_win "$1")"
  _tmux capture-pane -p -t "$wid" -S "-$2" 2>/dev/null | sed '/^$/d' | tail -n "$2"
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

backend_report() { :; }  # id state message: tmux has no agent state to mirror (spec section 9)
backend_title()  { :; }  # title
