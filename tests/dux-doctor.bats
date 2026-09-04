load helpers/setup

@test "doctor passes with fakes, gh stub, and one project" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok claude"* ]] && [[ "$output" == *"backend: herdr"* ]] && [[ "$output" == *"lock: free"* ]]
}

@test "doctor fails and names a missing tool" {
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL codex"* ]]
}

@test "doctor fails on empty registry" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL registry"* ]]
}
