# bats file_tags=worker
load helpers/setup

# Runs for whichever harness $DUX_WORKER_HARNESS names. The Makefile runs it twice.
setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log"; : > "$FAKE_WORKER_LOG"
  export DUX_STATUS_LOG="$DUX_HOME/state/status.log"; : > "$DUX_STATUS_LOG"
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script"
  printf 'the brief\n' > "$DUX_HOME/brief.md"
  echo '{"permissions":{"deny":[]}}' > "$DUX_HOME/settings.json"
}

adapter() {  # $@ function and args; runs inside a shell that sourced dux-env and the adapter
  bash -c 'source "$DUX_ROOT/bin/dux-env"; source "$DUX_ROOT/bin/workers/$DUX_WORKER_HARNESS.sh"; "$@"' _ "$@"
}

@test "worker_cmd prints one line naming the harness, model, effort, and brief" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip "DUX_WORKER_HARNESS unset"
  run adapter worker_cmd "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "$DUX_WORKER_HARNESS "* ]]
  [[ "$output" == *"model-x"* ]] && [[ "$output" == *"high"* ]] && [[ "$output" == *"$DUX_HOME/brief.md"* ]]
  case "$DUX_WORKER_HARNESS" in
    claude) [[ "$output" == *"--dangerously-skip-permissions"* ]] && [[ "$output" == *"--settings $DUX_HOME/settings.json"* ]] && [[ "$output" == *"--output-format stream-json"* ]] ;;
    codex)  [[ "$output" == *"--sandbox danger-full-access"* ]] && [[ "$output" == *"shell_environment_policy.ignore_default_excludes=true"* ]] ;;
  esac
}

@test "worker_run runs the harness with the model and effort and returns its exit code" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip
  printf 'status working: hi\nstatus done: report\nexit 4\n' > "$FAKE_WORKER_SCRIPT"
  run adapter worker_run "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json"
  [ "$status" -eq 4 ]
  [ "$(sed -n 2p "$DUX_STATUS_LOG")" = "done: report" ]
  grep -q "^$DUX_WORKER_HARNESS " "$FAKE_WORKER_LOG"
  case "$DUX_WORKER_HARNESS" in
    claude) grep -q -- '--model model-x --effort high' "$FAKE_WORKER_LOG" ;;
    codex)  grep -q -- '-m model-x' "$FAKE_WORKER_LOG"; grep -q -- 'model_reasoning_effort="high"' "$FAKE_WORKER_LOG" ;;
  esac
  grep -q -- 'the brief' "$FAKE_WORKER_LOG"
}

@test "worker_effort_ok accepts the harness's levels and rejects others" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip
  run adapter worker_effort_ok high; [ "$status" -eq 0 ]
  run adapter worker_effort_ok bogus; [ "$status" -ne 0 ]
  case "$DUX_WORKER_HARNESS" in
    claude) run adapter worker_effort_ok max; [ "$status" -eq 0 ]; run adapter worker_effort_ok minimal; [ "$status" -ne 0 ] ;;
    codex)  run adapter worker_effort_ok minimal; [ "$status" -eq 0 ]; run adapter worker_effort_ok max; [ "$status" -ne 0 ] ;;
  esac
}

@test "the fake dies on TERM while sleeping" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip
  printf 'sleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  "$DUX_WORKER_HARNESS" -p x > /dev/null & pid=$!
  sleep 1; kill -TERM "$pid"
  wait "$pid" || rc=$?
  [ "${rc:-0}" -eq 143 ]
  [ "$(grep -c done "$DUX_STATUS_LOG" || true)" -eq 0 ]
}
