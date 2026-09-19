load helpers/setup

tools() {  # the commands doctor looks for, so a test can fail on one thing only
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
}

# A checkout doctor can read that is not the one the suite runs from, so a test
# may write config/reviewer without touching the operator's own. ship-env
# resolves its root from its own path, so the file is copied rather than linked.
own_checkout() {
  local r="$DUX_HOME/root"
  mkdir -p "$r/skills/ship" "$r/templates/config" "$r/config"
  cp "$DUX_ROOT/skills/ship/ship-env" "$r/skills/ship/ship-env"
  cp "$DUX_ROOT"/templates/config/* "$r/templates/config/"
  ln -s "$DUX_ROOT/bin" "$r/bin"
  printf '%s' "$r"
}

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

@test "doctor fails when a held session has no watcher" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
  echo $$ > "$DUX_HOME/state/dux.lock"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL watcher: not running; run bin/dux-lock acquire (see state/watch.log)"* ]]
}

@test "doctor passes when watch.pid names dux-watch" {
  mkdir -p "$DUX_HOME/bin"
  for c in codex gh; do printf '#!/bin/sh\nexit 0\n' > "$DUX_HOME/bin/$c"; chmod +x "$DUX_HOME/bin/$c"; done
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
  echo $$ > "$DUX_HOME/state/dux.lock"
  w="$(stand_in dux-watch)"; echo "$w" > "$DUX_HOME/state/watch.pid"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]; [[ "$output" == *"ok watcher (pid $w)"* ]]
}

# ---- reviewers and the rollout stage --------------------------------------

@test "doctor names the reviewers it resolved and the stage this install is on" {
  tools
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok reviewer (codex)"* ]]
  [[ "$output" == *"ok security-reviewer (codex)"* ]]
  [[ "$output" == *"ok policy stage m1"* ]]
  [[ "$output" == *"policy: m1; unavailable: delivered-PR feedback rounds, same-session answers and approval, dispatch waiting on a predecessor, usage reporting; use existing recovery for those"* ]]
}

@test "doctor reports a host that cannot run a reviewer at all" {
  echo '- p path=/tmp base=main worktree=git issues=off (added 2026-09-03)' > "$DUX_HOME/data/projects.md"
  PATH="$DUX_ROOT/bin:/usr/bin:/bin" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL reviewer: no code reviewer on this host"* ]]
  [[ "$output" == *"FAIL security-reviewer: no security reviewer on this host"* ]]
}

@test "doctor reports a reviewer the operator pinned to a command this host lacks" {
  tools
  r="$(own_checkout)"
  printf 'my-reviewer --read-only\n' > "$r/config/reviewer"
  PATH="$DUX_HOME/bin:$PATH" DUX_ROOT="$r" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL reviewer: my-reviewer is not on PATH; it is named in $r/config/reviewer"* ]]
  # The one that was not overridden still resolves, so the report names the
  # broken half rather than both.
  [[ "$output" == *"ok security-reviewer (codex)"* ]]
}

@test "a stage this checkout does not implement is a failure, not a switch" {
  tools
  printf 'whenever\n' > "$DUX_HOME/config/policy-stage"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL policy stage: 'whenever' is not a rollout stage"* ]]
  # And nothing is reported as available on the strength of a value like that.
  [[ "$output" != *"policy: whenever"* ]]
}

@test "an earlier stage than this checkout implements is the operator's to state" {
  tools
  printf 'm1\n' > "$DUX_HOME/config/policy-stage"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok policy stage m1"* ]]
  # This checkout carries feedback rounds, so a stage that says so is accepted.
  printf 'm2\n' > "$DUX_HOME/config/policy-stage"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"policy: m2; unavailable: same-session answers and approval, dispatch waiting on a predecessor, usage reporting;"* ]]
  # And answers, approval and waiting on a predecessor, so m3 is too.
  printf 'm3\n' > "$DUX_HOME/config/policy-stage"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok policy stage m3"* ]]
  [[ "$output" == *"policy: m3; unavailable: usage reporting; use existing recovery for those"* ]]
  # This checkout carries usage reporting too, so m4 is accepted with nothing
  # left unavailable.
  printf 'm4\n' > "$DUX_HOME/config/policy-stage"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok policy stage m4"* ]]
  [[ "$output" == *"policy: m4; unavailable: nothing"* ]]
}

# ---- the worker limit -------------------------------------------------------

@test "doctor reports the worker limit from the operator's file, or the template's when there is none" {
  tools
  printf '# the operator says\n5\n' > "$DUX_HOME/config/max-workers"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ $'\n'"$output"$'\n' == *$'\nok worker limit 5\n'* ]]
  rm "$DUX_HOME/config/max-workers"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 0 ]
  [[ $'\n'"$output"$'\n' == *$'\nok worker limit 3\n'* ]]
}

@test "a limit that is not a whole number from 1 to 99 fails doctor with the reason" {
  tools
  printf 'lots\n' > "$DUX_HOME/config/max-workers"
  PATH="$DUX_HOME/bin:$PATH" DUX_BACKEND=herdr run dux-doctor
  [ "$status" -eq 1 ]
  want="FAIL worker limit: config/max-workers must be a whole number from 1 to 99, not 'lots'"
  [[ $'\n'"$output"$'\n' == *$'\n'"$want"$'\n'* ]]
  [[ "$output" != *"ok worker limit"* ]]
}
