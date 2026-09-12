# Seed new installs with the ship effort the operator already runs

> **For the implementer:** one task, then `/ship`. Tick each `- [ ]` box as it lands and
> keep the "where this stands" block current: the plan file is the state of the work, not
> the conversation. Break-verify before calling the task done. Do not run a code review
> of your own work: `/ship` owns the branch's one review and its security pass
> (constitution principle 9).

**Where this stands**
- Drafted 2026-09-11 by a Dux plan worker. One independent design review by a fresh
  session, six findings, all fixed; each is at the bottom.
- Picks up a drift the operator noticed: the live `config/models` runs ship workers at
  high effort, the tracked template still seeds max.
- Merges as one ship PR of one task.
- Task 1 implemented 2026-09-12 on `dux/dux-ship-20260912-v31`: template token changed,
  seeding proof added, break-verified. Awaiting `/ship`.

**Estimated diff:** ~4 changed lines across 1 task. Well under the cap.

**Goal:** A fresh Dux install starts its ship workers at the effort the operator chose,
high, instead of the old default, max. Nothing changes for the install the operator is
running today: its `config/models` already says high and install never overwrites an
existing file.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 5.1, amended in this
pull request: the ship row now names the default, and a paragraph under the table says
the template tracks the operator's live choice.

**Deviations:** none.

## What is wrong today

`templates/config/models` is one line:
`plan=claude-fable-5-1:high ship=claude-opus-5:max scout=claude-sonnet-5:medium`.
`bin/dux-install` copies each file under `templates/config/` into `config/` when no file
of that name exists yet, so the template is what a fresh install runs until the operator
edits it. The operator edited the live file to `ship=claude-opus-5:high` and the template
did not follow. The next fresh install would run ship workers at max, an effort the
operator has already moved away from.

One correction to the brief: the template seeds `config/models` once per Dux install, on
`dux-install`, not once per registered project. Registering a project does not touch it.
The fix is the same either way.

## The decision

Change the one token and leave everything else in the file alone.

- **Why only the token.** `plan` and `scout` are not in question and the brief rules them
  out. The file format, the seeding loop, and how the wrapper reads the file are all
  untouched.
- **Why no test pins the value.** A test asserting `ship=claude-opus-5:high` would turn
  the operator's next change of mind into a two-file edit and would guard a preference,
  not a mechanism. The repository's convention for template-seeding coverage is the
  install test's byte-for-byte `cmp` of the seeded file against the template
  (`tests/dux-install.bats`, the reviewer line). This plan extends that to `models`, so
  what is proved is that a fresh install runs exactly what the template says. The value
  itself is checked by reading the template, and once more by hand at the task boundary.
- **Why the spec carries the default now.** Section 5.1 said "effort per the operator's
  rule", which is true of the live file and says nothing about what a fresh install gets.
  It now names the default and the rule that the template follows the live choice, so the
  next drift has a sentence to be measured against.

## Task 1: the token and its seeding proof

**Files:** `templates/config/models`, `tests/dux-install.bats`.

**Interface:** none new. `bin/dux-install` and `bin/dux-worker-wrap` are not edited.

**Acceptance:** `templates/config/models` reads
`plan=claude-fable-5-1:high ship=claude-opus-5:max scout=claude-sonnet-5:medium` with
`max` replaced by `high` and no other byte changed. A fresh install's `config/models` is
byte for byte the template. The full suite is green.

**Steps**

- [x] `templates/config/models`: `ship=claude-opus-5:max` becomes `ship=claude-opus-5:high`.
      Confirm with `git diff --word-diff` that the diff is that one word.
- [x] `tests/dux-install.bats`, the test that already runs `cmp -s` on `reviewer`: add
      one line, `cmp -s "$DUX_ROOT/templates/config/models" "$DUX_HOME/config/models"`,
      next to it. `cmp` rather than a grep for the value, so the test proves seeding
      without pinning a preference; see "The decision".
- [x] Manual check, recorded in the commit body as the commands printed it: run
      `dux-install --yes` against an empty `DUX_HOME` the way the install test's setup
      does, then `grep -o 'ship=[^ ]*' "$DUX_HOME/config/models"`. Expected output:
      `ship=claude-opus-5:high`.
- [x] Break-verify, one break, the failure pasted into the commit body as the run printed
      it: in `bin/dux-install`'s seeding loop, make the `models` copy write something else
      (for instance `printf 'ship=x\n' > "$DUX_CONFIG/$n"` when `$n` is `models`). The
      new `cmp` line fails and the reviewer `cmp` still passes, which shows the new line
      watches `models` and not the loop as a whole. Restore.
- [x] `make check` green, `bin/dux-doctor` passing, then `/ship`.

## Left as written

- `docs/plans/2026-09-03-dux-m1-skeleton.md` line 1535 lists the template with `max`. It
  records what milestone 1 built and is left alone, as the brief-cap plan left the M2
  plan and the roadmap.
- `docs/specs/2026-09-10-one-session-planning.md` line 431 says the approve brief tells a
  plan worker to delegate code to "Opus, max effort" subagents. That is the model the
  plan worker's own subagents run, not the `ship` entry of `config/models`, and the brief
  puts the model-selection mechanism out of scope. Noted here so the next reader does not
  take it for a miss; if the operator wants that lowered too, it is its own task.
- `tests/dux-worker-wrap.bats` line 476 copies the template into `config/models` and then
  asserts a PATH finding. `high` is a valid Claude effort (`bin/workers/claude.sh`,
  `worker_effort_ok`), so that test is unaffected.

## Milestone acceptance

Constitution gates as usual: full suite green, shellcheck and identifier lint clean,
`bin/dux-doctor` passing, `/ship` the only gate. `docs/ARCHITECTURE.md` names no model
or effort value, so it does not change.

## Risks

- None to the running install: `dux-install` skips a `config/models` that exists.
- A fresh install on a machine where the operator wanted max now gets high and must edit
  `config/models`, which is the same edit they made to get here.

## Open questions for the operator

None.

## Design review

One independent review by a fresh session on 2026-09-11, read-only. Findings are plain
bullets, not boxes: `bin/dux-result` counts every box below the last `## Task` heading as
that task's, and an unticked one here would fail the milestone.

- **Important, fixed.** The spec paragraph said a "project registered later" starts on the
  template default, the very misconception this plan corrects. Now "a fresh install".
- **Important, fixed.** The rule "changes to the same value in the next pull request that
  touches it" had no clear referent and, read literally, only fired when some other PR
  touched the template. Now: the template is changed to match, as its own docs change or
  in the next pull request.
- **Minor, fixed.** The spec amendment said the same thing twice and cited this plan from
  the spec, inverting constitution principle 8. The table cell is now the default and the
  file; the paragraph is two sentences; the plan citation and the untracked sentence are
  gone (line 1136 already owns the gitignored fact).
- **Minor, fixed.** Task 1 borrowed the reviewer line's reason for `cmp`, which is about
  `auto` and note lines and does not apply to `models`. The step now gives this plan's
  reason.
- **Minor, fixed.** "Milestone acceptance" justified leaving `docs/ARCHITECTURE.md` alone
  with a fallback rule that belongs to the ship gate, not the wrapper. Now it says only
  that no value is named there.
- **Minor, fixed.** This section's findings could have been written as boxes and become
  Task 1's. The first paragraph above says why they are not.
- **Note, out of scope.** The spec's layout listing at line 130 names `config/models-codex`
  but not `config/models`. Pre-existing, its own docs task if the operator wants it.

Everything else the reviewer checked held: the template bytes, the seeding semantics, that
no test pins the value today, the per-install correction, the break design, the three
"Left as written" citations, and that `high` is a valid effort.
