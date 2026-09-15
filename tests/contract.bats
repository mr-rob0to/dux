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

# The worker's tab holds a live Claude Code session the operator reads and types
# to. Dux reads the status outbox and nothing else, so no Dux script may read
# what a pane has drawn. `dux-backend tail` was the one verb that did and it is
# gone; these are the two multiplexer commands that could bring it back. A grep
# at one point in time is an observation, and this is what makes it a rule every
# branch is held to.
@test "no Dux script reads a pane's contents" {
  local d hits
  for d in bin skills; do
    hits="$(grep -rn -e 'pane read' -e 'capture-pane' "$DUX_ROOT/$d" || true)"
    if [ -n "$hits" ]; then
      echo "a pane reader in $d/, which may not read a worker's tab:"
      echo "$hits"
      return 1
    fi
  done
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

# The orchestrator session only dispatches and relays, so it starts on Sonnet.
# The committed file is the mechanism: anyone who opens this checkout gets it
# without a flag. Its own test, so a change to the model shows up here and not
# as a second failure in the hooks test.
@test "the committed project settings start the session on Sonnet" {
  run jq -r .model "$DUX_ROOT/.claude/settings.json"
  [ "$output" = claude-sonnet-5 ]
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
  # The worker's tab is a path for worker text that Dux does not mediate at all,
  # so the rule about operator-facing text has to say so rather than claim every
  # path runs through recovery. The pane-reader test below is its other half:
  # this one keeps the prose true, that one keeps the code true.
  [[ "$p6" == *"worker's own tab is the operator's screen"* ]]
  [[ "$p6" == *'neither reads it nor relays it'* ]]
  grep -qE '^\*\*Version\*\*: 2\.[0-9]+\.[0-9]+ ' "$DUX_ROOT/docs/constitution.md"
}

# The constitution named one denylist file and put the account name in it, while
# the installer has written two since milestone 2 and matches them differently.
# Nothing read the sentence against the code, so it drifted for four milestones.
@test "the constitution names both denylist files and what each one holds" {
  p2="$(unwrapped '/^### 2\./,/^### 3\./p' "$DUX_ROOT/docs/constitution.md")"
  [[ "$p2" == *'tests/personal-identifiers.txt`, the operator home path and registered project names, matched as substrings'* ]]
  [[ "$p2" == *'tests/personal-names.txt`, the account name and the home directory name, matched as whole words'* ]]
  # The rule claimed more coverage than the lint gives until 2.0.4: three kinds
  # of entry are never searched, and one of the three is dropped without a word.
  [[ "$p2" == *'Three kinds of entry are never searched'* ]]
  [[ "$p2" == *'a project whose repository is the checkout being installed into'* ]]
  [[ "$p2" == *'a project name shorter than four characters'* ]]
  [[ "$p2" == *'GENERIC_ACCOUNTS` list'* ]]
  [[ "$p2" == *'the generic list is dropped silently'* ]]
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

@test "the README says a worker's word is not a result" {
  readme="$(unwrapped '1,$p' "$DUX_ROOT/README.md")"
  [[ "$readme" == *'never because a worker'*'said so'* ]]
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
  # The reviewer command left this file for config/reviewer, so the prompt is
  # the line that runs the resolved command, not the one that names a tool.
  prompt="$(sed -n '/^## Step 6\./,/^## Step 7\./p' "$ship" | grep -F '$REVIEWER "')"
  [ -n "$prompt" ] || { echo "step 6 sends no reviewer prompt"; return 1; }
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
  # open clears every phase and zeroes the count, so it is the same dodge by
  # another route and the skill has to say so where the refusal is read.
  [[ "$ship" == *'Opening the gate again mid-gate is'* ]]
}

@test "the ship skill refuses to carry a review that saw an older commit" {
  ship="$(unwrapped '1,$p' "$DUX_ROOT/skills/ship/SKILL.md")"
  # Step 6 lets a review run before the gate stand in for its own. Recording the
  # phase then claims that reviewer saw the commit going out, so the carry only
  # holds while nothing has landed since.
  [[ "$ship" == *'Carry it forward only if `HEAD`'* ]]
  [[ "$ship" == *'the gate runs its own review here'* ]]
  # "HEAD has not moved" is only a check if the skill says what to compare.
  [[ "$ship" == *'Name the commit that reviewer read and compare'* ]]
  [[ "$ship" == *'cannot say which commit it read'* ]]
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

@test "every mention of the bundled reviewer note is anchored to the ship-env root" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  # The gate runs with its working directory inside the repository under review,
  # and this one is a Dux checkout, so a bare templates/config/security-reviewer
  # is a file the branch being reviewed can write. Every mention has to resolve
  # through ship-env --root, which is the install the gate came from.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *'"$SHIP_ENV" --root'*) ;;
      *) echo "unanchored mention of the bundled note: $line"; return 1 ;;
    esac
  done <<EOF
$(grep -n 'templates/config/security-reviewer' "$ship" || true)
EOF
  # And the mentions are really there, so an empty grep cannot pass this.
  [ "$(grep -c 'templates/config/security-reviewer' "$ship")" -ge 2 ]
}

@test "the ship skill names no model and reads both reviewers from ship-env" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  # A model name in the gate's own text is the thing that stopped a stranger
  # running it: changing the reviewer meant editing the skill. Both reviewers
  # now come out of config, so no model identifier belongs in this file.
  run grep -nE 'gpt-[0-9]|claude-[a-z]*-[0-9]' "$ship"
  [ "$status" -ne 0 ] || { echo "SKILL.md still names a model: $output"; return 1; }
  [ -x "$DUX_ROOT/skills/ship/ship-env" ]
  zero="$(unwrapped '/^### Resolve the two helpers/,/^## Step 1\./p' "$ship")"
  [[ "$zero" == *'SHIP_ENV="$(dirname "$SHIP_GUARD")/ship-env"'* ]]
  [[ "$zero" == *'no runnable ship-env beside'* ]]
  six="$(unwrapped '/^## Step 6\./,/^## Step 7\./p' "$ship")"
  [[ "$six" == *'REVIEWER="$("$SHIP_ENV" reviewer)"'* ]]
  seven="$(unwrapped '/^## Step 7\./,/^## Step 8\./p' "$ship")"
  [[ "$seven" == *'SECURITY_REVIEWER="$("$SHIP_ENV" security-reviewer)"'* ]]
  # The agent: shape is the one that can degrade quietly, so the skill has to
  # say that a host without agents stops rather than picking another reviewer.
  [[ "$seven" == *'A host that cannot dispatch agents stops here'* ]]
  [[ "$seven" == *'config/security-reviewer'* ]]
}

@test "the ship skill demands evidence a person can see, or a reason there is none" {
  five="$(unwrapped '/^## Step 5\./,/^## Step 6\./p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$five" == *'screenshot'* ]]
  [[ "$five" == *'or one line saying why there is none'* ]]
  # It is a body requirement, not a new stop. Reading it as a stop would hold a
  # branch for a missing picture.
  [[ "$five" == *'not a stop'* ]]
}

# A lease anchored to a value read straight after a fetch matches whatever the
# remote holds, including a commit this branch has never seen. The ancestor test
# is the guard; the lease alone is not.
@test "every push tests the ancestor, anchors the lease, and verifies the remote" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  # One range per step, spelled out. An alternation in the end pattern was tried
  # and is a GNU extension: BSD sed never matched it, the step 8 range ran to the
  # end of the file, and step 9's push satisfied every assertion about step 8.
  # Breaking step 8 changed nothing, which is how that was found.
  for step in 8 9; do
    case "$step" in
      8) body="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$ship")" ;;
      9) body="$(unwrapped '/^## Step 9\./,/^## Stop and report/p' "$ship")" ;;
    esac
    [ -n "$body" ] || { echo "step $step is empty"; return 1; }
    # The range has to stop where the step does, or one step's push proves the
    # other's. sed prints the line the range ends on, so the marker checked here
    # is content from inside the next section, not its header.
    case "$step" in
      8) [[ "$body" != *'gh run watch'* ]] || { echo "the step 8 range ran into step 9"; return 1; } ;;
      9) [[ "$body" != *'you are rationalizing'* ]] || { echo "the step 9 range ran into the red flags"; return 1; } ;;
    esac
    [[ "$body" == *'git merge-base --is-ancestor "$REMOTE" HEAD'* ]] \
      || { echo "step $step has no ancestor test"; return 1; }
    [[ "$body" == *'--force-with-lease="refs/heads/$BRANCH:$REMOTE"'* ]] \
      || { echo "step $step does not anchor the lease"; return 1; }
    [[ "$body" == *'git ls-remote origin "refs/heads/$BRANCH"'* ]] \
      || { echo "step $step does not verify the remote after the push"; return 1; }
  done
  # An empty expected value is the same shape for a branch the remote does not
  # have yet, and it refuses if the ref appeared in between.
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$ship")"
  [[ "$eight" == *'empty'* ]]
  [[ "$eight" == *'refuses if the ref appeared'* ]]
  # A bare force never comes back.
  flat="$(unwrapped '1,$p' "$ship")"
  [[ "$flat" != *'git push --force '* ]]
}

@test "the stop table names the two ways a push can be wrong" {
  table="$(unwrapped '/^## Stop and report/,/^## Red flags/p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$table" == *'The remote branch holds commits this branch does not'* ]]
  [[ "$table" == *'The remote head is not the commit that was pushed'* ]]
}

@test "step 8 fills the repo's own template and passes a title and a body file" {
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$DUX_ROOT/skills/ship/SKILL.md")"
  [[ "$eight" != *'gh run watch'* ]] || { echo "the step 8 range ran into step 9"; return 1; }
  # --fill ignores the repository's template and scrapes the commits instead.
  # The prose explains why it is gone, so the assertion is on the command line
  # rather than on the step's text: a flat search for the flag matches the
  # sentence that retires it, and would pass with the old command still there.
  create="$(grep -n '^gh pr create' "$DUX_ROOT/skills/ship/SKILL.md")"
  [ -n "$create" ] || { echo "step 8 never opens the pull request"; return 1; }
  [[ "$create" != *'--fill'* ]] || { echo "gh pr create still uses --fill: $create"; return 1; }
  [[ "$create" == *'--title'* ]]
  [[ "$create" == *'--body-file'* ]]
  # The whole invocation, not a prefix of it: "$SHIP_ENV" pr-template is also
  # the first half of the fallback line, so a prefix assertion stayed green with
  # the lookup gone. Breaking the lookup changed nothing, which is how that
  # was found.
  [[ "$eight" == *'"$SHIP_ENV" pr-template "$(git rev-parse --show-toplevel)"'* ]]
  [[ "$eight" == *'"$SHIP_ENV" pr-template-fallback'* ]]
  # GitHub documents no precedence between root, docs/ and .github/, so the body
  # says which template was filled rather than implying GitHub would agree.
  [[ "$eight" == *'root, `docs/`, `.github/` order'* ]]
  [[ "$eight" == *'says which template'* ]]
  [[ "$eight" == *'folder form'* ]]
  [[ "$eight" == *'--title'* ]]
  [[ "$eight" == *'--body-file'* ]]
  [[ "$eight" == *'<details>'* ]]
  [[ "$eight" == *'"$SHIP_GUARD" attest >> "$BODY"'* ]]
  [[ "$eight" == *'dux-attestation:v1'* ]]
}

@test "a rebuilt body follows every push after a fix pass, step 9's included" {
  ship="$DUX_ROOT/skills/ship/SKILL.md"
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$ship")"
  nine="$(unwrapped '/^## Step 9\./,/^## Stop and report/p' "$ship")"
  [[ "$nine" != *'you are rationalizing'* ]] || { echo "the step 9 range ran on"; return 1; }
  # The attestation names the commit that is out there. A push that does not
  # rebuild it leaves the body naming a commit that is no longer the head.
  [[ "$eight" == *'gh pr edit'* ]]
  [[ "$nine" == *'gh pr edit --title'* ]]
  [[ "$nine" == *'--body-file'* ]]
  # The command, not the word. The prose above it says "attestation", so a
  # search for "attest" passed with the call itself deleted.
  [[ "$nine" == *'"$SHIP_GUARD" attest >> "$BODY"'* ]]
  # attest appends, so a body reused from step 8 gets a second attestation with
  # the stale one first, naming a commit that is no longer the head. Both steps
  # name the file before they append to it, and step 9 says rebuild is not
  # append. $BODY was never assigned anywhere in the skill until this was found.
  [[ "$eight" == *'BODY="$(mktemp'* ]]
  [[ "$nine" == *'BODY="$(mktemp'* ]]
  [[ "$eight" == *'Exactly one attestation per body'* ]]
  [[ "$nine" == *'Rebuild means rebuild, not append'* ]]
}

@test "the recorded dry run names the reviewers the bundled defaults hold" {
  t="$DUX_ROOT/tests/harness/ship.md"
  [ -f "$t" ] || { echo "no recording at tests/harness/ship.md"; return 1; }
  # The recording shows a fresh clone reading its reviewers with no config/ of
  # its own. If what a fresh clone resolves changes and the recording does not,
  # the recording is claiming something that is no longer true. Nothing else
  # checks that: it is prose, and the run it describes cannot be repeated.
  #
  # The bundled defaults name no command any more, so the value is asked of the
  # real ship-env on a stand-in host built like the one that made the recording:
  # codex on PATH and a security-reviewer agent defined. Reading the templates
  # for a command line instead would assert on nothing.
  c="$DUX_HOME/fresh"; stub="$DUX_HOME/fresh-bin"; agents="$DUX_HOME/fresh-home/.claude/agents"
  mkdir -p "$c/skills/ship" "$c/templates" "$stub" "$agents"
  cp "$DUX_ROOT/skills/ship/ship-env" "$c/skills/ship/ship-env"
  cp -R "$DUX_ROOT/templates/config" "$c/templates/config"
  printf '#!/bin/sh\nexit 0\n' > "$stub/codex"; chmod +x "$stub/codex"
  : > "$agents/security-reviewer.md"
  [ ! -d "$c/config" ]
  for key in reviewer security-reviewer; do
    value="$(env PATH="$stub:/usr/bin:/bin" HOME="$DUX_HOME/fresh-home" \
      CLAUDE_CONFIG_DIR="$DUX_HOME/fresh-home/.claude" "$c/skills/ship/ship-env" "$key")"
    [ -n "$value" ]
    grep -qxF "$value" "$t" \
      || { echo "tests/harness/ship.md does not carry '$value', what a fresh clone resolves for $key"; return 1; }
  done
  # Both reviews answered with the headers the skill demands. A recording of a
  # run that skipped either one is a recording of a gate that did not close.
  # Counted, not merely present: step 6 and step 7 each print one, and a single
  # `grep -q` stayed green with either review's header deleted.
  found="$(grep -cxF '## Findings' "$t")"
  [ "$found" -ge 2 ] || { echo "only $found '## Findings' headers; both reviews print one"; return 1; }
  grep -qxF '## Checked clean' "$t"
  # The three phases of the guard, the ancestor test, the anchored push and the
  # verify after it. These are the steps the milestone added; a recording that
  # does not show them is not evidence for it.
  grep -qF 'dux-attestation:v1' "$t"
  grep -qF 'merge-base --is-ancestor' "$t"
  grep -qF 'force-with-lease' "$t"
  grep -qF 'ls-remote' "$t"
}
