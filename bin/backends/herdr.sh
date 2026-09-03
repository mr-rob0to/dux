#!/usr/bin/env bash
# Herdr adapter. Sourced by dux-backend. Endpoint: herdr:<pane_id>
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
  # pane run types into a live shell; wait for a prompt so the command is not lost.
  herdr pane wait-output "$pane" --regex '[$%>#] ?$' --timeout 10000 >/dev/null 2>&1 || true
  herdr pane run "$pane" "$cmd" >/dev/null || finding "herdr pane run failed for $id on $pane"
  echo "herdr:$pane"
}

backend_exists() {  # endpoint
  herdr pane get "$(_pane "$1")" >/dev/null 2>&1
}

backend_tail() {  # endpoint n
  herdr pane read "$(_pane "$1")" --source recent-unwrapped --lines "$2" 2>/dev/null
}

backend_close() {  # endpoint
  local pane focused; pane="$(_pane "$1")"
  focused="$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane.focused // false')"
  [ "$focused" = true ] && finding "refusing to close focused pane $pane"
  herdr pane close "$pane" >/dev/null 2>&1 || finding "herdr pane close failed for $pane"
}

backend_notify() {  # title body
  herdr notification show "$1" --body "$2" --sound "done" >/dev/null 2>&1 || true
}
