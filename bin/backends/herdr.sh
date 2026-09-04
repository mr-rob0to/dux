#!/usr/bin/env bash
# Herdr adapter. Sourced by dux-backend after dux-env. Endpoint: herdr:<pane_id>
# Exact pane ids from create responses only. Never workspace close. Spec section 9.
set -u

_pane() { echo "${1#herdr:}"; }

backend_open() {  # id cwd cmd
  local id="$1" cwd="$2" cmd="$3" ws="${HERDR_WORKSPACE_ID:-}" out pane
  [ -n "$ws" ] || finding "HERDR_WORKSPACE_ID is unset; Dux is not running inside a Herdr pane"
  out="$(herdr tab create --workspace "$ws" --cwd "$cwd" --label "dux-$id" --no-focus)" \
    || finding "herdr tab create failed for $id"
  pane="$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')"
  [ -n "$pane" ] || finding "herdr tab create returned no pane id for $id"
  # pane run types into a live shell; without a prompt the command would be lost.
  if ! herdr pane wait-output "$pane" --regex '[$%>#] ?$' --timeout 10000 >/dev/null 2>&1; then
    backend_close "herdr:$pane"   # fail-closed: a focused pane or a failed close is its own finding
    finding "no shell prompt in pane $pane for $id within 10s; pane closed, command not sent"
  fi
  herdr pane run "$pane" "$cmd" >/dev/null || finding "herdr pane run failed for $id on $pane"
  echo "herdr:$pane"
}

backend_exists() {  # endpoint
  herdr pane get "$(_pane "$1")" >/dev/null 2>&1
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
