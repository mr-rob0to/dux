#!/usr/bin/env bash
# Herdr adapter. Sourced by dux-backend after dux-env. Endpoint: herdr:<pane_id>
# Exact pane ids from create responses only. Never workspace close. Spec section 9.
set -u

_pane() { echo "${1#herdr:}"; }

backend_open() {  # id cwd cmd
  local id="$1" cwd="$2" cmd="$3" ws="${HERDR_WORKSPACE_ID:-}" out pane tab
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
  # pane run types into a live shell; without a prompt the command would be lost.
  if ! herdr pane wait-output "$pane" --regex '[$%>#] ?$' --timeout 10000 >/dev/null 2>&1; then
    backend_close "herdr:$pane"   # fail-closed: a focused pane or a failed close is its own finding
    finding "no shell prompt in pane $pane for $id within 10s; pane closed, command not sent"
  fi
  if ! herdr pane run "$pane" "$cmd" >/dev/null; then
    backend_close "herdr:$pane"   # fail-closed, like the prompt path above
    finding "herdr pane run failed for $id on $pane; pane closed"
  fi
  echo "herdr:$pane"
}

backend_exists() {  # endpoint
  herdr pane get "$(_pane "$1")" >/dev/null 2>&1
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

backend_tail() {  # endpoint n
  herdr pane read "$(_pane "$1")" --source recent-unwrapped --lines "$2" 2>/dev/null
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

_own_pane() {  # the pane this process runs in; presentation only, so the id comes from the environment
  [ -n "${HERDR_PANE_ID:-}" ] || finding "HERDR_PANE_ID is unset; not inside a Herdr pane"
  echo "$HERDR_PANE_ID"
}

backend_report() {  # id state message
  local pane; pane="$(_own_pane)" || exit $?
  herdr pane report-agent "$pane" --source dux --agent "dux-$1" --state "$2" --message "$3" >/dev/null 2>&1 \
    || finding "herdr pane report-agent failed for $pane"
}

backend_title() {  # title
  local pane; pane="$(_own_pane)" || exit $?
  herdr pane report-metadata "$pane" --title "$1" >/dev/null 2>&1 || finding "herdr pane report-metadata failed for $pane"
}
