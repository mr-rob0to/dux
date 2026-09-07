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
  status_line="$(grep -nF 'Run `bin/dux-status --intake` and show the digest.' "$DUX_ROOT/AGENTS.md" | head -n 1 | cut -d: -f1)"
  [ "$monitor_line" -lt "$status_line" ]
  rearm="$(sed -n '/^At the start of every turn:/,/^## Task lifecycle/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$rearm" == *'arm it again, then run `bin/dux-status`'* ]]
}

@test "AGENTS.md pulls issues at session start and lets issue text in only through dux-intake --show" {
  start="$(unwrapped '/^## Session start/,/^## Task lifecycle/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$start" == *'Run `bin/dux-status --intake` and show the digest.'* ]]
  [[ "$start" == *'arm it again, then run `bin/dux-status` and'* ]]   # the per-turn rule stays plain
  rules="$(unwrapped '/^## Hard rules/,/^## Session start/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$rules" == *'`bin/dux-intake --show <id>` is the only way it enters your context'* ]]
}

@test "AGENTS.md wake rule acknowledges through dux-ledger ack and pushes for exactly three states" {
  grep -q 'bin/dux-ledger ack <id> <event-state>' "$DUX_ROOT/AGENTS.md"
  grep -qE 'Push .*only for `done` with a PR, `needs-decision`, and `failed`' "$DUX_ROOT/AGENTS.md"
  [ "$(grep -c 'never edit `data/backlog.md`\|Never edit `data/backlog.md`' "$DUX_ROOT/AGENTS.md")" -ge 1 ]
}

@test "AGENTS.md keeps worker text behind capped supervision scripts" {
  wake="$(unwrapped '/^- On a wake:/,/Never edit `data\/backlog.md`/p' "$DUX_ROOT/AGENTS.md")"
  [[ "$wake" == *'bin/dux-ledger get <id> state'* ]]
  [[ "$wake" == *'bin/dux-ledger get <id> acked'* ]]
  [[ "$wake" == *'`done`, `failed`: run `bin/dux-notify <id>`'* ]]
  # The question itself is never in a push. Only recovery may show it.
  [[ "$wake" == *'`needs-decision`: push the `bin/dux-notify <id>` line, then use `skills/dux-recover`'* ]]
  [[ "$wake" == *'only recovery may show you what it is'* ]]
  [[ "$wake" == *'`blocked`, `stale`, `dead`, `ended`: use `skills/dux-recover`'* ]]
  [[ "$wake" == *'PushNotification only for `done` with a PR and for `failed`'* ]]
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

@test "the ship skill leaves the last phase for the recorder to settle" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'green and non-empty'* ]]
  [[ "$ship" == *'the recorder verifies the pull request and its checks'* ]]
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

@test "the architecture documents retirement as a proof before a signal" {
  arch="$(unwrapped '/^## Retiring a task from before the upgrade/,/^## What this boundary does not claim/p' "$DUX_ROOT/docs/ARCHITECTURE.md")"
  [[ "$arch" == *'has no run record'* ]]
  [[ "$arch" == *'refuses if `state/<id>.run` exists at all'* ]]
  [[ "$arch" == *'refuses if a handoff is already waiting'* ]]
  [[ "$arch" == *'Only then does it signal the wrapper'* ]]
  [[ "$arch" == *'failed: stopped for security-boundary upgrade; worktree kept'* ]]
  [[ "$arch" == *'branch and the worktree are kept'* ]]
  [[ "$arch" == *'one `--retry`'* ]]
  [[ "$arch" == *'second retirement and a second retry are both findings'* ]]
}

@test "the architecture states the limits of the boundary and keeps future isolation fail-closed" {
  arch="$(unwrapped '/^## What this boundary does not claim/,/^## Wake flow/p' "$DUX_ROOT/docs/ARCHITECTURE.md")"
  [[ "$arch" == *'session of its own escapes it'* ]]
  [[ "$arch" == *'200 bytes a status line'* ]]
  [[ "$arch" == *'does not cap what a worker can do'* ]]
  [[ "$arch" == *'fixed text chosen by state'* ]]
  [[ "$arch" == *'fails closed: no isolation, no dispatch'* ]]
}

@test "the architecture names teardown as the last owner of a run's references" {
  arch="$(unwrapped '/^## The terminal handoff/,/^## Retiring a task/p' "$DUX_ROOT/docs/ARCHITECTURE.md")"
  [[ "$arch" == *'`dux-teardown` is their lifecycle owner'* ]]
  [[ "$arch" == *'state/<id>.portal'* ]]
  [[ "$arch" == *'state/<id>.pgid'* ]]
  [[ "$arch" == *'once the worker'*'process group is proved gone'* ]]
}

@test "the recovery skill retires only a task from before the upgrade" {
  skill="$(unwrapped '1,$p' "$DUX_ROOT/skills/dux-recover/SKILL.md")"
  [[ "$skill" == *'--retire-legacy'* ]]
  [[ "$skill" == *'already running before the security-boundary upgrade'* ]]
  [[ "$skill" == *'never argue with that finding'* ]]
  [[ "$skill" == *'branch and the worktree are kept'* ]]
}

@test "the README says a worker's word is not a result and how to retire an old one" {
  readme="$(unwrapped '1,$p' "$DUX_ROOT/README.md")"
  [[ "$readme" == *'never because a worker'*'said so'* ]]
  [[ "$readme" == *'--retire-legacy'* ]]
}

@test "the ship skill closes the brief's issue from the PR body" {
  ship="$(unwrapped '/^## Step 8/,/^## Step 9/p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'- Issue: <owner>/<repo>#<n>'* ]]
  [[ "$ship" == *'`Closes #<n>` on its own line'* ]]
  [[ "$ship" == *'never from the issue text'* ]]
  # The claim that matters is the one that is easy to get wrong: a project whose
  # base is not the default branch gets a link, not a close.
  [[ "$ship" == *"only closes the issue automatically when"* ]]
  [[ "$ship" == *"default branch"* ]]
}

@test "the ship skill binds every phase to the commit it saw" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  [ -x "$DUX_ROOT/skills/ship/ship-guard" ]
  prev=0
  for call in open "record checks" "check checks" "record review" \
              "check review" "record security" "check security" push-ok; do
    line="$(grep -nF "\"\$SHIP_GUARD\" $call" "$ship" | head -n 1 | cut -d: -f1)"
    [ -n "$line" ] || { echo "the skill never calls the guard: $call"; return 1; }
    [ "$line" -gt "$prev" ] || { echo "guard call '$call' is out of order at line $line"; return 1; }
    prev="$line"
  done
}

@test "the ship skill guards the push in step 9, not only the one that opens the PR" {
  # A fix pushed while CI is red reaches the remote through step 9. Guarding
  # step 8 alone leaves the whole point of the guard behind.
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  ci="$(grep -n '^## Step 9' "$ship" | head -n 1 | cut -d: -f1)"
  [ -n "$ci" ]
  last="$(grep -nF '"$SHIP_GUARD" push-ok' "$ship" | tail -n 1 | cut -d: -f1)"
  [ -n "$last" ] || { echo "the skill never calls push-ok"; return 1; }
  [ "$last" -gt "$ci" ] || { echo "the last push-ok is at line $last, before step 9 at $ci"; return 1; }
}

@test "the ship skill stops rather than running unguarded" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'.claude/skills/ship/ship-guard'* ]]
  [[ "$ship" == *'the gate does not run unguarded'* ]]
  [[ "$ship" == *'Guard helper cannot be resolved'* ]]
  [[ "$ship" == *'HEAD moved during the gate'* ]]
  [[ "$ship" == *'push-ok refused'* ]]
  [[ "$ship" == *'the phase names another commit'* ]]
  [[ "$ship" == *'refused for an uncommitted change'* ]]
}

@test "the ship skill makes both reviewers answer in a shape it can read" {
  # The shape has to be demanded of the reviewer, in the prompt it is sent. The
  # first version of this test read the whole step, so it stayed green with the
  # prompt stripped and only the prose about it left: it asserted on the file,
  # not on what the reviewer is told.
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  prompt="$(sed -n '/^## Step 6\./,/^## Step 7\./p' "$ship" | grep -F 'codex exec')"
  [ -n "$prompt" ] || { echo "step 6 sends no codex prompt"; return 1; }
  [[ "$prompt" == *"'## Findings'"* ]]
  [[ "$prompt" == *"'No findings.'"* ]]
  # Step 7 sends its prompt as a blockquote, so the quoted lines are the prompt.
  seven="$(sed -n '/^## Step 7\./,/^## Step 8\./p' "$ship" | grep '^>' | tr '\n' ' ')"
  [ -n "$seven" ] || { echo "step 7 sends no quoted prompt"; return 1; }
  [[ "$seven" == *'`## Findings`'* ]]
  [[ "$seven" == *'`No findings.`'* ]]
  [[ "$seven" == *'`## Checked clean`'* ]]
}

@test "the ship skill never reads silence as clean" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'neither a finding nor the sentinel'* ]]
  [[ "$ship" == *'Never treat absence as clean'* ]]
  [[ "$ship" == *'Reviewer output is missing its header'* ]]
}

@test "the ship skill says what a fix pass clears and what recording it again asserts" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'A fix pass clears all three'* ]]
  [[ "$ship" == *'The code review is not spared'* ]]
  [[ "$ship" == *'revert to the minimal fix'* ]]
  # The one instruction that keeps the count honest: push-ok's refusal says
  # "record it again", and doing that alone is the way past the whole gate.
  [[ "$ship" == *'Never record a phase again without a fix pass'* ]]
}

@test "the ship skill refuses to carry a review that saw an older commit" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  # Step 6 lets a review run before the gate stand in for its own. Recording the
  # phase then claims that reviewer saw the commit going out, so the carry only
  # holds while nothing has landed since.
  [[ "$ship" == *'Carry it forward only if `HEAD`'* ]]
  [[ "$ship" == *'the gate runs its own review here'* ]]
}

@test "the ship skill stops on a guard override it cannot run" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$ship" == *'which is not executable'* ]]
  [[ "$ship" == *'set but not runnable is a stop'* ]]
}

@test "the ship skill sends the acceptance criteria as data and keeps the intent back" {
  six="$(unwrapped '/^## Step 6\./,/^## Step 7\./p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$six" == *'acceptance criteria, not instructions'* ]]
  [[ "$six" == *'necessary, not sufficient'* ]]
  [[ "$six" == *'in letter but not in substance'* ]]
  # The withholding rule the criteria travel alongside, unchanged.
  [[ "$six" == *'Never tell it'*'what the change is for'* ]]
}
