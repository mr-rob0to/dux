load helpers/setup

@test "dux-env exports paths under DUX_HOME and creates them" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; echo "$DUX_DATA $DUX_STATE $DUX_CONFIG $DUX_TASKS"; [ -d "$DUX_TASKS" ]'
  [ "$status" -eq 0 ]
  [ "$output" = "$DUX_HOME/data $DUX_HOME/state $DUX_HOME/config $DUX_HOME/data/tasks" ]
}

@test "DUX_HOME defaults to DUX_ROOT when unset" {
  mkdir -p "$DUX_HOME/fakeroot/bin"; cp "$DUX_ROOT/bin/dux-env" "$DUX_HOME/fakeroot/bin/"
  run bash -c 'unset DUX_HOME DUX_ROOT; source "'"$DUX_HOME"'/fakeroot/bin/dux-env"; echo "$DUX_HOME"'
  [ "$output" = "$DUX_HOME/fakeroot" ]
}

@test "finding prints to stderr and exits 2" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; finding "worktree is dirty" 2>&1 >/dev/null'
  [ "$status" -eq 2 ]
  [ "$output" = "finding: worktree is dirty" ]
}

@test "finding is not swallowed by command substitution" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; f() { finding "inner"; }; x="$(f)" || exit $?; echo "reached"'
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: inner"* ]]
  [[ "$output" != *reached* ]]
}

@test "die prints to stderr and exits 1" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; die "boom" 2>&1'
  [ "$status" -eq 1 ]
  [ "$output" = "dux: boom" ]
}

@test "require_cmd dies naming the missing command" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; require_cmd jq definitely-not-a-cmd 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-cmd"* ]]
}

@test "now is UTC ISO-8601 seconds" {
  run bash -c 'source "$DUX_ROOT/bin/dux-env"; now'
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
