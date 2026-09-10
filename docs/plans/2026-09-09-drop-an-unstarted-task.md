# Let go of a task that never started

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, before the next
> task starts. Do not run a code review of your own work: `/ship` owns the branch's one
> review and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-09 by the orchestrator session, approved by the operator in
  conversation, no independent design review. Deviation recorded below, this change only.
- Both tasks done on 2026-09-10, branch `dux/dux-ship-20260910-mre`. Six breaks run
  and seen to fail, pasted into the task 1 commit.
- Other branches are in flight. Rebase on `origin/main` before the gate.

**Estimated diff:** ~90 changed lines across 2 tasks. Well under the cap.

**Goal:** A task that was created but never ran can be let go of. Today it cannot, and it
sits in the digest for good.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 5.6 (teardown).

**Deviations:** one, from the operator's rule that a design gets one independent review
before implementation. Waived on 2026-09-09 for this change only. Plan and code land in
one pull request; `/ship` still runs in full.

## What is wrong today

`bin/dux-teardown:13` treats only `done` and `failed` as terminal, so line 24 refuses
everything else:

```
finding: task dux-ship-20260909-pai is not terminal (ledger: queued)
```

That task was created and briefed, then superseded before it ever spawned. There is no
worktree, no branch, no run record and no pull request, and nothing to protect. It cannot
be removed, so it stays in `bin/dux-status` forever.

`dropped` has the same problem and is already reachable two ways: `bin/dux-intake:120`
drops a task whose GitHub issue was closed, and `bin/dux-recover:332` drops a retry whose
brief would not render. Neither can be cleaned up either.

## The decision

Teardown keeps its current meaning. Removing work that ran is a different act from
letting go of work that never did, and folding them into one verb would put the
uncommitted-work refusals on a path that has nothing to refuse.

Add `bin/dux-teardown --abandon <id>`. It accepts `queued` and `dropped` only, and only
when the task has never run. Never having run is proved from the filesystem, not from the
ledger: no run record, no pid file, no pgid file, no portal, no worktree. Any one of those
present is a finding that names it and says to use plain teardown. The ledger state alone
is not enough, because a crash between spawn and the first state write would leave a
running task reading `queued`.

On success it sets the state to `dropped`, removes the task folder, and prints one line.
It never touches a project repo, a branch, or a pull request.

**Why not widen `is_terminal`.** That would let plain `dux-teardown` accept a queued task
and walk the whole worktree and receipt path against a task that has none. Separate verb,
separate proof.

## Task 1: abandon a task that never ran

Files: `bin/dux-teardown`, `tests/dux-teardown.bats`.

- [x] Parse `--abandon` as a mode flag on `dux-teardown`, keeping the existing usage
      finding for anything else. Read the whole argument parsing block afterwards and
      confirm the plain path is unchanged.
- [x] In abandon mode, require the ledger state to be `queued` or `dropped`; anything
      else is a finding naming the state, as today.
- [x] Prove the task never ran by testing for each of the run record, pid file, pgid file,
      portal file, and worktree. Name the one that exists in the finding and say to use
      `bin/dux-teardown <id>` instead. Read `bin/dux-worker-wrap` around lines 15 and 79
      for the exact paths rather than guessing them.
- [x] On success set the ledger state to `dropped`, remove `data/tasks/<id>`, and print
      `abandoned <id>`. Use the same task id validation the other scripts use, so a path
      is never built from an unchecked id.
- [x] Tests: a queued never-spawned task is abandoned and leaves the ledger reading
      `dropped` with no task folder; a `dropped` task is abandoned the same way; a
      `running` task is refused; a `done` task is refused with the pointer to plain
      teardown; a queued task with a worktree present is refused and the worktree survives.
- [x] Break-verify, one break at a time, each failure pasted into the commit message as
      the run printed it:
      1. accept any state; the running and done refusal tests fail, two distinct failures.
      2. drop the worktree check; the "queued task with a worktree" test fails.
      3. skip the ledger write; the "leaves the ledger reading dropped" assertion fails.
      4. skip the folder removal; the "no task folder" assertion fails.

## Task 2: say so

Files: `skills/dux-dispatch/SKILL.md`, `docs/ARCHITECTURE.md`,
`docs/specs/2026-09-03-dux-orchestrator-design.md`, `README.md` if it lists teardown.

- [x] Dispatch skill, teardown section: plain teardown is for a task that ran and
      finished; `--abandon` is for one that never started, and the operator's word is
      still required before either.
- [x] Architecture map and spec section 5.6: one line each for the new mode and the
      never-ran proof.
- [x] Full suite green, shellcheck clean, `bin/dux-doctor` passing.
