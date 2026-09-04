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
  local id="$1" errfile out rc err n
  errfile="$(mktemp "${TMPDIR:-/tmp}/dux-tmux-find.XXXXXX")" || finding "cannot create a temp file to read tmux errors"
  out="$(_tmux list-windows -a -f "#{==:#{window_name},dux-$id}" -F '#{session_name}:#{window_id}' 2>"$errfile")"
  rc=$?
  err="$(cat "$errfile")"; rm -f "$errfile"
  if [ "$rc" -ne 0 ]; then
    # "no server running" is tmux having looked: positive evidence of no window.
    # "error connecting" is tmux not having looked, because the socket was not
    # there to ask through, which is also what a live server holding the worker
    # looks like once something removes its socket file. The two are not the same
    # answer. Any failure but the first is an unanswered question and must never
    # read as "nothing is running".
    case "$err" in
      *"no server running"*) return 0 ;;
      *) finding "tmux could not list windows while looking for dux-$id: ${err:-exit $rc}" ;;
    esac
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
