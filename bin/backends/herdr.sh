#!/usr/bin/env bash
# Herdr adapter. Sourced by dux-backend after dux-env. Endpoint: herdr:<pane_id>
# Exact pane ids from create responses only. Never workspace close. Spec section 9.
set -u

_pane() { echo "${1#herdr:}"; }

backend_open() {  # id cwd; opens the tab as a shell at its prompt
  local id="$1" cwd="$2" ws="${HERDR_WORKSPACE_ID:-}" out pane tab
  [ -n "$ws" ] || finding "HERDR_WORKSPACE_ID is unset; Dux is not running inside a Herdr pane"
  out="$(herdr tab create --workspace "$ws" --cwd "$cwd" --label "dux-$id" --no-focus)" \
    || finding "herdr tab create failed for $id"
  pane="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
  if [ -z "$pane" ]; then
    # The tab exists even with no pane to address it by, so close it by its own id.
    tab="$(printf '%s' "$out" | jq -r '.result.tab.tab_id // empty')"
    [ -n "$tab" ] || finding "herdr tab create returned neither a pane id nor a tab id for $id"
    herdr tab close "$tab" >/dev/null 2>&1 \
      || finding "herdr tab create returned no pane id for $id and herdr tab close failed for $tab"
    finding "herdr tab create returned no pane id for $id; tab $tab closed"
  fi
  # backend_run types into a live shell; without a prompt the command would be
  # lost, so the wait belongs here, before the endpoint is handed out. The class
  # carries the chevrons starship and oh-my-zsh draw as well as the four plain
  # shells use: a prompt this does not know times out every open.
  if ! herdr pane wait-output "$pane" --regex '[$%>#❯➜] ?$' --timeout 10000 >/dev/null 2>&1; then
    backend_close "herdr:$pane"   # fail-closed: a focused pane or a failed close is its own finding
    finding "no shell prompt in pane $pane for $id within 10s; pane closed"
  fi
  echo "herdr:$pane"
}

backend_run() {  # endpoint cwd(ignored: the tab was opened there) cmd
  local pane; pane="$(_pane "$1")"
  herdr pane run "$pane" "$3" >/dev/null || finding "herdr pane run failed on $pane"
}

# One line typed into the pane, submitted. `pane run` types its text and Enter
# into whatever holds the pane's terminal, which is a shell when a worker starts
# and the session itself once one is running. Measured 2026-09-16 against a live
# Claude Code 2.1.273 session in a Herdr 0.8.2 pane: the line arrived at the
# session's prompt and was submitted, so `send-text` and a separate Enter were
# not needed. The session's Stop hook fired once, when that turn ended, and not
# during a 20-second tool call inside it.
backend_prompt() {  # endpoint text
  local pane; pane="$(_pane "$1")"
  herdr pane run "$pane" "$2" >/dev/null 2>&1 || finding "herdr could not type into $1"
}

# The pane's foreground process whose command name is <name>, wherever it sits
# in the list: Claude Code runs a caffeinate child, which is listed before it.
# Measured 2026-09-14 against Herdr's own CLI: the reply nests under
# .result.process_info, foreground_processes is ordered innermost first, and a
# live Claude Code session reports argv0 "claude" with its version in .name, so
# the name is read from argv0 and never from .name.
#
# Only the three fields are printed. The same reply carries .cmdline, which
# holds the whole brief; nothing outside pid, group and cwd leaves this function.
backend_pid() {  # endpoint name; prints "<pid> <pgid> <cwd>", 1 when it is not there
  local pane name out line pid pgid argv0 cwd
  pane="$(_pane "$1")"; name="$2"
  out="$(herdr pane process-info --pane "$pane" 2>/dev/null)" \
    || finding "herdr pane process-info failed for $pane"
  printf '%s' "$out" | jq -e '.result.process_info | type == "object"' >/dev/null 2>&1 \
    || finding "herdr pane process-info returned no process information for $pane"
  line="$(printf '%s' "$out" | jq -r --arg n "$name" '.result.process_info
      | (.foreground_processes // []) as $f
      | ([$f[] | select(.argv0 == $n)] | first // empty) as $p
      | [($p.pid | tostring), (.foreground_process_group_id | tostring),
         $p.argv0, ($p.cwd // "-")] | join(" ")')" \
    || finding "herdr pane process-info is unreadable for $pane"
  [ -n "$line" ] || return 1
  pid="${line%% *}"; line="${line#* }"
  pgid="${line%% *}"; line="${line#* }"
  argv0="${line%% *}"; cwd="${line#* }"
  [ "$argv0" = "$name" ] || return 1
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  case "$pgid" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s %s\n' "$pid" "$pgid" "$cwd"
}

backend_exists() {  # endpoint: 0 present, 1 gone, finding when herdr did not answer
  local pane err rc code; pane="$(_pane "$1")"
  err="$(herdr pane get "$pane" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && return 0
  code="$(printf '%s' "$err" | jq -r '.error.code // empty' 2>/dev/null)"
  [ "$code" = pane_not_found ] && return 1
  finding "herdr pane get failed for $pane with ${code:-no error code}: $err"
}

backend_find() {  # id: prints the endpoint of the tab labelled dux-<id>, nothing when there is none
  # Not scoped to HERDR_WORKSPACE_ID: a tab the operator moved elsewhere still
  # holds a live worker, and "I looked in the wrong workspace" would read as "no".
  local id="$1" out tab n pane
  out="$(herdr tab list)" || finding "herdr tab list failed while looking for dux-$id"
  printf '%s' "$out" | jq -e '.result.tabs | type == "array"' >/dev/null 2>&1 \
    || finding "herdr tab list returned no tab array while looking for dux-$id"
  tab="$(printf '%s' "$out" | jq -r --arg l "dux-$id" '.result.tabs[] | select(.label == $l) | .tab_id')" \
    || finding "herdr tab list is unreadable while looking for dux-$id"
  [ -n "$tab" ] || return 0
  n="$(printf '%s\n' "$tab" | wc -l | tr -d ' ')"
  [ "$n" = 1 ] || finding "$n herdr tabs are labelled dux-$id; close all but one before spawning $id"
  # The listing carries no pane, and the endpoint is a pane, so ask for the panes.
  out="$(herdr pane list)" || finding "herdr pane list failed while looking for the pane of tab $tab"
  printf '%s' "$out" | jq -e '.result.panes | type == "array"' >/dev/null 2>&1 \
    || finding "herdr pane list returned no pane array while looking for the pane of tab $tab"
  pane="$(printf '%s' "$out" | jq -r --arg t "$tab" '[.result.panes[] | select(.tab_id == $t) | .pane_id] | sort | .[0] // empty')" \
    || finding "herdr pane list is unreadable while looking for the pane of tab $tab"
  [ -n "$pane" ] || finding "herdr tab $tab is labelled dux-$id but has no pane; close the tab before spawning $id"
  printf 'herdr:%s\n' "$pane"
}

backend_close() {  # endpoint. Closes only on a positive "not focused" reading.
  local pane out focused; pane="$(_pane "$1")"
  out="$(herdr pane get "$pane" 2>/dev/null)" || finding "herdr pane get failed for $pane; refusing to close"
  focused="$(printf '%s' "$out" | jq -r '.result.pane.focused' 2>/dev/null)"
  case "$focused" in
    true)  finding "refusing to close focused pane $pane" ;;
    false) ;;
    *)     finding "herdr pane get returned no focus state for $pane; refusing to close" ;;
  esac
  herdr pane close "$pane" >/dev/null 2>&1 || finding "herdr pane close failed for $pane"
}

backend_notify() {  # title body
  herdr notification show "$1" --body "$2" --sound "done" >/dev/null 2>&1 || true
}

# --source names who is reporting, so several reporters can set and clear their
# own metadata on one pane. It is required: measured 2026-09-15 against Herdr's
# own CLI, report-metadata without it exits non-zero and sets nothing, which is
# how the milestone acceptance run found every worker tab untitled.
backend_title() {  # endpoint text
  local pane; pane="$(_pane "$1")"
  herdr pane report-metadata "$pane" --source dux --title "$2" >/dev/null 2>&1 \
    || finding "herdr pane report-metadata failed for $pane"
}
