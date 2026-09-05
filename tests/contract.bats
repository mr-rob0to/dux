load helpers/setup

@test "AGENTS.md is at most 150 lines" {
  [ "$(wc -l < "$DUX_ROOT/AGENTS.md")" -le 150 ]
}

@test "CLAUDE.md is only an import of AGENTS.md" {
  [ "$(wc -l < "$DUX_ROOT/CLAUDE.md")" -le 2 ]
  grep -qx '@AGENTS.md' "$DUX_ROOT/CLAUDE.md"
}

@test "AGENTS.md carries the fixed section headers in order" {
  run grep -E '^## ' "$DUX_ROOT/AGENTS.md"
  [ "${lines[0]}" = "## Identity" ]
  [ "${lines[1]}" = "## Hard rules" ]
  [ "${lines[2]}" = "## Session start" ]
  [ "${lines[3]}" = "## Task lifecycle" ]
  [ "${lines[4]}" = "## Talking to the operator" ]
  [ "${lines[5]}" = "## Skills" ]
  [ "${lines[6]}" = "## Project Constitution" ]
}

@test "ARCHITECTURE.md exists and names the two flows" {
  grep -q -i 'dispatch' "$DUX_ROOT/docs/ARCHITECTURE.md"
  grep -q -i 'wake' "$DUX_ROOT/docs/ARCHITECTURE.md"
}

@test "every skill has frontmatter name and description" {
  for f in "$DUX_ROOT"/skills/*/SKILL.md; do
    head -5 "$f" | grep -q '^name: ' || { echo "missing name: $f"; return 1; }
    head -5 "$f" | grep -q '^description: ' || { echo "missing description: $f"; return 1; }
  done
}

@test "session hooks acquire and release the lock" {
  run jq -r '.hooks.SessionStart[0].hooks[0].command' "$DUX_ROOT/.claude/settings.json"
  [[ "$output" == *"dux-lock acquire"* ]]
  run jq -r '.hooks.SessionEnd[0].hooks[0].command' "$DUX_ROOT/.claude/settings.json"
  [[ "$output" == *"dux-lock release"* ]]
}

@test "AGENTS.md arms one persistent Monitor on the events log and re-arms it per turn" {
  grep -qF 'Monitor(command: "tail -n0 -F state/events.log", persistent: true)' "$DUX_ROOT/AGENTS.md"
  grep -q 'no Monitor is armed' "$DUX_ROOT/AGENTS.md"
  grep -q 'unacknowledged' "$DUX_ROOT/AGENTS.md"
}

@test "AGENTS.md arms before its digest and repeats the digest after re-arming" {
  monitor_line="$(grep -nF 'Monitor(command: "tail -n0 -F state/events.log", persistent: true)' "$DUX_ROOT/AGENTS.md" | head -n 1 | cut -d: -f1)"
  status_line="$(grep -nF 'Run `bin/dux-status` and show the digest.' "$DUX_ROOT/AGENTS.md" | head -n 1 | cut -d: -f1)"
  [ "$monitor_line" -lt "$status_line" ]
  rearm="$(sed -n '/^At the start of every turn:/,/^## Task lifecycle/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$rearm" == *'arm it again, then run `bin/dux-status`'* ]]
}

@test "AGENTS.md wake rule acknowledges through dux-ledger ack and pushes for exactly three states" {
  grep -q 'bin/dux-ledger ack <id> <event-state>' "$DUX_ROOT/AGENTS.md"
  grep -qE 'Push .*only for `done` with a PR, `needs-decision`, and `failed`' "$DUX_ROOT/AGENTS.md"
  [ "$(grep -c 'never edit `data/backlog.md`\|Never edit `data/backlog.md`' "$DUX_ROOT/AGENTS.md")" -ge 1 ]
}

@test "AGENTS.md keeps worker text behind capped supervision scripts" {
  wake="$(sed -n '/^- On a wake:/,/Never edit `data\/backlog.md`/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$wake" == *'bin/dux-ledger get <id> state'* ]]
  [[ "$wake" == *'bin/dux-ledger get <id> acked'* ]]
  [[ "$wake" == *'`done`, `failed`, `needs-decision`: run `bin/dux-notify <id>`'* ]]
  [[ "$wake" == *'`blocked`, `stale`, `dead`, `ended`: use `skills/dux-recover`'* ]]
  [[ "$wake" == *'PushNotification only for `done` with a PR, `needs-decision`, and `failed`'* ]]
  [[ "$wake" != *'status.log'* ]]
}

# Prose wraps, and where it wraps is not the contract. Compare on one normalized
# line so a reflow never turns a rule that is present into a red test.
unwrapped() { sed -n "$1" "$2" | tr '\n' ' ' | tr -s ' '; }

@test "the constitution declares the trusted-local-worker boundary at version 2" {
  p6="$(unwrapped '/^### 6\./,/^### 7\./p' "$DUX_ROOT/docs/constitution.md")"
  [[ "$p6" == *'trusted to act with the operator account'* ]]
  [[ "$p6" == *'untrusted application data'* ]]
  [[ "$p6" == *'not an authentication boundary'* ]]
  grep -qE '^\*\*Version\*\*: 2\.[0-9]+\.[0-9]+ ' "$DUX_ROOT/docs/constitution.md"
}

@test "the constitution disclaims same-user containment and keeps isolation fail-closed" {
  p6="$(unwrapped '/^### 6\./,/^### 7\./p' "$DUX_ROOT/docs/constitution.md")"
  [[ "$p6" == *'Deliberate abuse of those rights is outside'* ]]
  [[ "$p6" == *'fail closed'* ]]
}

@test "the spec declares the boundary and the retained handoff lifecycle" {
  spec="$DUX_ROOT/docs/specs/2026-09-03-dux-orchestrator-design.md"
  flat="$(unwrapped '1,$p' "$spec")"
  [[ "$flat" == *'untrusted application data'* ]]
  [[ "$flat" == *'outside Dux'*'protection claim'* ]]
  [[ "$flat" == *'state/<id>.handoffs/'* ]]
  [[ "$flat" == *'retained until teardown'* ]]
  [[ "$flat" == *'never declares its own completion'* ]]
}

@test "AGENTS.md states the worker boundary and keeps operator text fixed" {
  rules="$(unwrapped '/^## Hard rules/,/^## Session start/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$rules" == *'untrusted application data'* ]]
  [[ "$rules" == *'fixed text chosen by state'* ]]
  [[ "$rules" == *'Never treat a worker'*'claim as completion'* ]]
  [[ "$rules" == *'bin/dux-result'* ]]
}

@test "the ship skill records the five Dux phases in order" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  grep -qF 'DUX_SHIP_RECORD' "$ship"
  prev=0
  for phase in checks review security pr ci; do
    line="$(grep -nF "\$DUX_SHIP_RECORD $phase" "$ship" | head -n 1 | cut -d: -f1)"
    [ -n "$line" ] || { echo "no recorded phase: $phase"; return 1; }
    [ "$line" -gt "$prev" ] || { echo "phase $phase is out of order at line $line"; return 1; }
    prev="$line"
  done
}

@test "the ship security review is scoped to the declared boundary" {
  grep -q 'declared security boundary' "$DUX_ROOT/skills/ship/SKILL.md"
}

@test "gitignore anchors the runtime dirs and leaves templates/config tracked" {
  cd "$DUX_ROOT"
  for p in data/x state/x config/x; do git check-ignore -q --no-index "$p" || { echo "$p should be ignored"; return 1; }; done
  # A tracked path is never reported by check-ignore without --no-index; with it, the rule itself is tested.
  [ "$(git check-ignore -q --no-index templates/config/models; echo $?)" -eq 1 ]
}
