# Start the orchestrator session on Sonnet

> **For the implementer:** one task, then `/ship`. Tick each `- [ ]` box as it lands and
> keep the "where this stands" block current: the plan file is the state of the work, not
> the conversation. Break-verify before calling the task done. Do not run a code review
> of your own work: `/ship` owns the branch's one review and its security pass
> (constitution principle 9).

**Where this stands**
- Implemented 2026-09-13 as Task 3 of `docs/plans/2026-09-11-token-efficiency-program.md`,
  and ships in that milestone's pull request rather than one of its own. The last box
  below is that milestone's `/ship`, run once after all five of its tasks.
- Drafted 2026-09-11 by a Dux plan worker. One independent design review by a fresh
  session; its findings are at the bottom.
- Picks up the operator's decision that the orchestrator session, which only dispatches
  and relays, has no reason to start on the highest-capability model.
- Merges as one ship PR of one task.

**Estimated diff:** ~8 changed lines across 1 task. Well under the cap.

**Goal:** Anyone who installs Dux and runs `claude` in the checkout gets an orchestrator
session on Sonnet, with no `/model`, no flag, and no environment variable. Workers keep
running on whatever `config/models` says for their shape.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 7, amended in this
pull request: the paragraph after the lock hooks names the key, the value, why workers
are unaffected, and how an operator overrides it for themselves.

## What is wrong today

`.claude/settings.json` is committed and carries only the two lock hooks. Claude Code
reads a committed project `.claude/settings.json` for any session opened in that
directory, so the model an orchestrator session starts on is whatever the operator's own
user settings or a flag says. A fresh install has no such setting and starts on the
harness default, which Dux never chose, for a session that never implements anything.

## The decision

Add one key to the committed file, `"model": "claude-sonnet-5"`, next to the hooks.

- **Why this key and this id.** Claude Code's settings reference lists `model` as the
  key that sets the model a session starts on, and `.claude/settings.json` as the
  "shared project" level, applied to everyone who opens the checkout. `claude-sonnet-5`
  is the full id, the same spelling `templates/config/models` uses for the scout shape;
  the alias `sonnet` also works but the full id leaves nothing to resolve.
- **Verified, not assumed, against Claude Code 2.1.269.** The repository pins no Claude
  Code version: `bin/dux-doctor` checks only that `claude` is on `PATH`, and no manifest
  names a version. 2.1.269 is the version installed where this plan was written, and
  the probes below were run against it. Each probe ran `claude -p` with
  `--output-format stream-json --verbose --max-turns 1` in a throwaway directory
  under `/tmp` and read `model` from the `init` message, which is the model the session
  actually started on:
  - project file `{"model":"claude-sonnet-5"}`, no flag: `claude-sonnet-5`
  - project file `{"model":"claude-opus-5"}`, no flag, user settings saying `sonnet`:
    `claude-opus-5`. The project file is read and applies over the user's own setting.
  - project file `{"model":"claude-sonnet-5"}`, `--model claude-opus-5`: `claude-opus-5`
  - the same, plus `--settings <deny-rules file>` exactly as a worker gets it:
    `claude-opus-5`
  - project file `{"model":"claude-opus-5"}`, `--model claude-sonnet-5`: `claude-sonnet-5`
- **Why workers are unaffected.** `bin/workers/claude.sh` `worker_run` execs
  `claude -p ... --model "$2" --effort "$3" ... --settings "$4"`, and
  `bin/dux-worker-wrap` refuses to start a worker whose shape has no model in
  `config/models`, so no Claude worker ever starts without `--model`. The flag wins for a
  documented reason, not by luck: the settings page puts the command line above the
  project local, shared project, and user files, and says `--model` overrides the `model`
  key from any of them. Only an organisation's managed settings sit above the flag, and
  no managed setting is part of Dux. The third, fourth
  and fifth probes above show that holding for 2.1.269 in both directions. A worker
  on a Dux task runs in a worktree of this very repository, so it does see this file,
  and still starts on its shape's model.
- **Why one contract assertion pins the value.** The ship-effort plan declined to pin
  `ship=...:high` because that value is a preference the operator edits in an untracked
  file. This one is different: the committed file is the mechanism, the acceptance
  criterion is that it says Sonnet, and `tests/contract.bats` already reads the same
  file to prove the hooks are there. One more line there guards the key the same way.
- **What an operator who wants Opus does.** Puts `"model"` in
  `.claude/settings.local.json`, which Claude Code applies over the committed file. Claude
  Code ignores that file in git only when it created it, so Task 1 adds it to
  `.gitignore` for the operator who writes it by hand. Or `/model` for one session. The
  spec paragraph says so.

## Task 1: the key, its proof, and the component map

**Files:** `.claude/settings.json`, `tests/contract.bats`, `docs/ARCHITECTURE.md`,
`.gitignore`.

**Interface:** none new. No script is edited.

**Acceptance:** `jq -r .model .claude/settings.json` prints `claude-sonnet-5`; the two
hook commands are unchanged; the contract suite proves both, in two separate tests; the
component map line for `.claude/settings.json` names the model; `.gitignore` lists
`.claude/settings.local.json`; the full suite is green; and a fresh `claude -p` in the
worktree, with no flag, reports `claude-sonnet-5` in its `init` line.

**Steps**

- [x] `tests/contract.bats`, a new test directly after "session hooks acquire and
      release the lock", named "the committed project settings start the session on
      Sonnet": `run jq -r .model "$DUX_ROOT/.claude/settings.json"` then
      `[ "$output" = claude-sonnet-5 ]`. Its own test, so the break below shows the
      hooks test green beside it. Run it and see it fail before the next step.
- [x] `.claude/settings.json`: add `"model": "claude-sonnet-5"` as a top-level key. Do
      not touch the `hooks` block. Confirm with `git diff` that the diff is one added
      line plus the comma that joins it.
- [x] `docs/ARCHITECTURE.md`, the `.claude/settings.json` line in Components: add
      `model claude-sonnet-5 for the orchestrator session` after the two hooks, wrapped
      onto a continuation line at the same column as the neighbouring entries.
- [x] `.gitignore`: add the line `.claude/settings.local.json`.
- [x] Manual check, recorded in the commit body as the commands printed it: from the
      worktree, `claude -p 'Reply with the single word ok.' --output-format stream-json
      --verbose --max-turns 1 | jq -r 'select(.subtype=="init") | .model'`. Expected:
      `claude-sonnet-5`. Then the same with `--model claude-opus-5`. Expected:
      `claude-opus-5`. Record `claude --version` beside them. The lock hooks fire for
      these runs: with no Dux session open they take and release the lock; with one open
      the output says `held by pid`, which is expected and changes nothing.
- [x] Break-verify, one break, the failure pasted into the commit body as the run printed
      it: change the value in `.claude/settings.json` to `claude-opus-5`, run the contract
      suite, see the new assertion fail and the hooks assertion still pass, restore.
- [ ] `make check` green, `bin/dux-doctor` passing, then `/ship`.

## Left as written

- `config/models` and `templates/config/models`: out of scope by the brief, and the
  worker path does not read the project file's `model` key.
- `README.md` "Run it" says `cd ~/dux && claude` and describes what happens next without
  naming a model. It stays true; the model is a fact the spec and component map own.

## Milestone acceptance

Constitution gates as usual: full suite green, shellcheck and identifier lint clean,
`bin/dux-doctor` passing, `/ship` the only gate. `docs/ARCHITECTURE.md` changes in the
same pull request because the line describing the file would otherwise be incomplete.

## Risks

- An operator whose user settings pick a different model now gets Sonnet in the Dux
  checkout until they add a local override. That is the intended effect, and the spec
  says where the override goes.
- Anthropic retires the `claude-sonnet-5` id. Claude Code would then refuse the session
  or fall back; the fix is the same one-line edit, and the contract test names the line.
- A future Claude Code version changes flag-over-file precedence. Unlikely and
  documented against; the worker adapter test would not catch it, so the manual check in
  Task 1 is the only evidence and is recorded in the commit.

## Open questions for the operator

None.

## Design review

One independent review by a fresh session on 2026-09-11, read-only. Findings are plain
bullets, not boxes: `bin/dux-result` counts every box below the last `## Task` heading as
that task's, and an unticked one here would fail the milestone.

- **Important, fixed.** The override advice said `.claude/settings.local.json` "stays
  out of git", but `.gitignore` had no such entry and Claude Code ignores the file only
  when it created it. Task 1 now adds the ignore line; the spec says `.gitignore` keeps it out.
- **Minor, fixed.** The spec and plan said `--model` beats the `model` key of "any"
  settings file; a managed policy beats the flag. Both now name the three file levels.
- **Minor, fixed.** Step 1 left "same test or a new one" open, and the break step relied
  on it being separate. Now a named new test.
- **Minor, fixed.** A line of task history about the previous attempt is gone.
- **Note, fixed.** The empty Deviations line is deleted, as the template says.
- **Note, fixed.** "The most expensive model" was unverifiable from the repo; now "which
  Dux never chose".
- **Note, fixed.** The component-map step now says to wrap like its neighbours.
- **Note, fixed.** The manual check step now says the lock hooks fire and what that looks
  like.

Everything else the reviewer checked held: the adapter and wrapper flags, the four
refusals that keep a worker from starting without a model, the id spelling in the models
template, the absence of a version pin, the contract test and the break design, the
`jq` filter for the `init` line, the README, the plan-reader's box counting, and that
the spec paragraph contradicts nothing in sections 5.1, 5.5, 13, or 19.
