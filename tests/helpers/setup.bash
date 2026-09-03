# Sourced by every bats file via `load helpers/setup`.
DUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUX_ROOT

setup() {
  DUX_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")"
  export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_HERDR_LOG="$DUX_HOME/state/fake-herdr.log"
  export FAKE_HERDR_OUTPUT="$DUX_HOME/state/fake-herdr.out"
  : > "$FAKE_HERDR_LOG"
  : > "$FAKE_HERDR_OUTPUT"
}

teardown() {
  [ -n "${DUX_HOME:-}" ] && rm -rf "$DUX_HOME"
}
