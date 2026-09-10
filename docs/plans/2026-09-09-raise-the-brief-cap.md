# Give a brief room to say the thing

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, before the next
> task starts. Do not run a code review of your own work: `/ship` owns the branch's one
> review and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-09 by the orchestrator session, approved by the operator in
  conversation, no independent design review. Deviation recorded below, this change only.
- Not started. No branch yet.
- Three other branches are in flight, on `bin/dux-project`, `bin/dux-teardown`, and a
  docs-only plan. Rebase on `origin/main` before the gate.

**Estimated diff:** ~60 changed lines across 2 tasks. Well under the cap.

**Goal:** A brief has room for the intent and the acceptance criteria without the
operator rewriting them to fit. The cap still refuses a brief carrying conversation
history, which is what it is actually for.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` sections on the brief
(around lines 216, 243 and 996). `docs/constitution.md` line 126.

**Deviations:** one, from the operator's rule that a design gets one independent review
before implementation. Waived on 2026-09-09 for this change only. Plan and code land in
one pull request; `/ship` still runs in full.

## What is wrong today

Building four briefs on 2026-09-09 took seven rebuilds. Every one failed on the cap by
one to seven lines, and each failure meant rewording an intent that was already correct.

The count is the whole rendered brief. The fixed template is about 26 lines of it, so a
60-line cap gives the operator about 34 lines for the intent and the criteria together.
The finding says "the limit is 60", which is true of the file and misleading about the
budget.

## The decision

Raise the cap to 100 and leave everything else alone.

- **Why 100.** It roughly doubles the operator's real budget, from about 34 lines to
  about 74. It also leaves room for the ten lines dux-recover appends to an intent on a
  retry, which is why every retry of a near-cap brief failed on 2026-09-10.
- **Why not change what is counted.** Counting only the intent and the criteria would be
  more honest, but it changes what the number means everywhere it is written down, and
  the operator asked for the cap raised, not redefined. The boring version wins.
- **Why the cap stays at all.** It is a proxy for the rule it protects: a brief never
  carries conversation history. A pasted transcript runs to hundreds of lines and 100
  still catches it. What it should not do is refuse a well-written brief.

**This is a constitution amendment.** `docs/constitution.md` line 126 states the 60, so
the number cannot move in the code alone without the two disagreeing. Bump the
constitution version and say what changed and why.

## Task 1: the number

Files: `bin/dux-brief`, `tests/dux-brief.bats`.

- [ ] `bin/dux-brief:105`: raise the threshold to 100 and update the finding text so it
      names 100. Do not change what the `awk` counts or how the issue block is excluded.
- [ ] `tests/dux-brief.bats:64`, the over-cap test: rebuild its fixture so it crosses 100
      rather than 60, and keep it asserting both the finding and that no brief file is
      written. Read the test in full first; a fixture sized for the old cap will pass for
      the wrong reason under the new one.
- [ ] Add a test at the boundary: a brief that renders to exactly 100 lines succeeds, and
      one that renders to 101 is a finding. Build both from the same fixture so the only
      difference is the one line.
- [ ] Break-verify, one break at a time, each failure pasted into the commit message as
      the run printed it:
      1. set the threshold back to 60; the 100-line success test fails.
      2. change `-gt` to `-ge`; the exactly-100 test fails.
      3. remove the `rm -f "$tmp"` on the failure path; the "nothing is written"
         assertion in the over-cap test fails.

## Task 2: the documents agree

Files: `docs/constitution.md`, `docs/specs/2026-09-03-dux-orchestrator-design.md`,
`docs/ARCHITECTURE.md`, `skills/dux-dispatch/SKILL.md`.

- [ ] `docs/constitution.md` line 126: 100 rather than 60. Bump the version from 2.0.5 to
      2.0.6 and record the amendment wherever that file records them, in one line: the
      cap counts the rendered template as well as the operator's words, so 60 was giving
      about 34 lines of intent and criteria.
- [ ] `AGENTS.md` names the constitution version in its "Project Constitution" section.
      Update it in the same commit, or the two disagree.
- [ ] Constitution lines 190 and 224 also say "about 60 lines", but about a plan task and
      a milestone plan, not about a brief. Leave both alone and say so here so the next
      reader does not think they were missed.
- [ ] Spec lines 216, 243 and 996: 100 in each. Line 243's point about the issue block
      being excluded from the count is unchanged.
- [ ] `docs/ARCHITECTURE.md:156` and `skills/dux-dispatch/SKILL.md:36`: 100.
- [ ] Search the repository for `60` near "brief" once more before finishing; this plan
      lists what was found on 2026-09-09 and is not a promise that nothing else mentions
      it.
- [ ] Full suite green, shellcheck clean, `bin/dux-doctor` passing.
