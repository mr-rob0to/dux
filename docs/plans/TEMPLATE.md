# Dux Milestone N: <name> Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> reviews the branch owes and decides how many that is (constitution principle 9),
> and a review outside the gate is how the gate gets skipped.

**Where this stands**
- <one line: drafted, reviewed, approved, or how many tasks are done>
- <one line: what the last merged milestone left open that this one picks up>
- <one line: what merges when this is done>

**Estimated diff:** ~N added lines across M tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). Sizing procedure: roadmap, "How a milestone is sized".

**Goal:** What the operator can do after this milestone that they could not before. Two or
three sentences, in plain English, no mechanics.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` sections <list>. Every design
decision this milestone needs is settled while the plan is written and amended into the spec
in the same pull request as the plan, so the implementer inherits decisions rather than making
them (constitution principle 8: spec first, then plan, then code). A plan handed over with a
design question still open is not ready.

**Deviations:** name any constitution principle this plan departs from, and why. Delete the
line when there are none.

## Design

Only what the spec does not already say, and only what an implementer cannot derive. New
interfaces as signatures, exit codes, output shapes and refusal wording. Data formats as one
example line each. No script bodies: the plan says what a script must do, the implementer
writes it. Ordering and dependencies between the tasks, when they are not obvious.

## Task 1: <name>

Task headings are `## Task N`, at this level. `bin/dux-result` reads them to prove the
milestone finished, and it matches `## Task N` only, never `### Task N`.

**Files:** the exact paths this task creates or edits.

**Interface:** signatures, flags, exit codes, and the exact text of each refusal. What the
script must do, not how.

**Acceptance:** what has to be true for this task to be done, checkable by someone who did not
write it.

**Steps**

- [ ] <one step>
- [ ] <one step>
- [ ] Break-verify: break <the protected behavior>, run, confirm the named test fails,
      restore, paste the failure into the commit body. A task is not done until every
      important protection it added has been broken and seen to fail, each one separately
      (constitution principle 3). Ordinary formatting, mapping and happy-path assertions
      need no break; say so rather than leaving it unsaid.

<!-- At most about 60 lines per task, this heading to the next. A task that will not fit is
     two tasks, or its design is unsettled and belongs in the spec first. Every box is ticked
     before the milestone ships: dux-result rejects a task with an unticked box, and a task
     with no boxes at all. -->

## Task 2: <name>

...

## Milestone acceptance

The quality gates from the constitution that this milestone must meet, plus anything specific
to it. Do not restate the constitution: name the gate and move on.

## Risks

One line each. What could go wrong, and what it costs.

## Open questions for the operator

One line each, with a recommendation. Empty is the goal: a plan with open questions is not
ready to hand to an implementer.

<!-- Not in a plan, ever:
     - script bodies or pasted diffs
     - blocks restating the constitution; it is loaded every session
     - decisions the spec already carries; point at the section instead
     - conversation history, exploratory discussion, or rejected options -->
