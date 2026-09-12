# Salvage the terminal test helper from the abandoned worktree

> **For the implementer:** one task, then `/ship`. Tick each `- [ ]` box as it lands and
> keep the "where this stands" block current: the plan file is the state of the work, not
> the conversation. Break-verify before calling the task done. Do not run a code review
> of your own work: `/ship` owns the branch's one review and its security pass
> (constitution principle 9).

**Where this stands**
- Drafted 2026-09-11 by a Dux plan worker. One independent design review by a fresh
  session; its findings are at the bottom.
- Recommendation: do not dispatch Task 1 now. Nothing on `main` reads from a terminal, so
  the helper would land with no caller. What the abandoned worktree learned about the
  helper is preserved in the spec, which is what this pull request merges. The worktree
  itself still holds the feature's uncommitted work, which is out of scope here and the
  operator's call; teardown refuses until that is committed or given up.
- Task 1 is written in full so that, if the operator wants the helper on `main` today or
  when the terminal-prompt feature is re-dispatched, it lands without another plan.

**Estimated diff:** ~110 added lines across 1 task if Task 1 is dispatched. Zero if not.

**Goal:** The one fix the operator asked to salvage is no longer held only in an
abandoned worktree's unsaved changes. What a terminal test helper must do, what was
measured on both platforms, and how a landing proves it are written down where the next
plan that needs them will look.

**Spec:** `docs/specs/2026-09-11-terminal-prompt-tests.md`, new in this pull request. It
settles the helper's shape and its proof. Section 15 of the orchestrator design gains one
bullet pointing at it.

**Deviations:** one, from the brief. The brief asked for the helper with both halves of
the abandoned fix, wait for output before answering and hold the pipe open after. The
spec lands the hold and drops the wait: no measured case on either platform needs the
wait, so no break makes it fail, and it costs up to ten seconds on a command that reads
before it prints. Spec section 3 has the table. Keeping it anyway is one line, and the
operator can say so on this pull request.

## What is in the abandoned worktree

`git diff HEAD` in `.worktrees/dux-dux-ship-20260909-a81` touches sixteen files. Fifteen
of them are the terminal-prompt feature's own unfinished work: its plan's boxes ticked,
its docs, and a flag added at test call sites. Those are out of scope and untouched. The
sixteenth, `tests/helpers/setup.bash`, holds two unrelated changes.

- **Taken, as knowledge:** the reshaped `pty_feed` and `run_in_pty` in
  `tests/helpers/setup.bash`. The branch's committed helper hung on Linux; the
  uncommitted reshape passed on both platforms when re-run on 2026-09-11. Spec sections 2
  and 3 say what it got right, and one thing it got wrong: its comment's reason for the
  Linux hang does not hold outside bats.
- **Not taken:** the loop that unsets inherited `GIT_CONFIG_*` variables. Dead, superseded
  by pull request #29, which moved the push guard into the task worktree's own git
  configuration. This worker's environment carries none of those variables and
  `tests/dux-project.bats` runs green here without the loop.

The rest of that branch, the terminal-prompt feature and its plan, is out of scope and
stays where it is.

## The decision

**Nothing on `main` needs a `pty_feed`-style helper.** No script under `bin/` tests for a
terminal or reads an answer from one. The five tests that call `run_in_pty` exist only on
the abandoned branch and test a feature that is only there. They belong on `main` with
that feature, not ahead of it.

So the smallest honest landing is the spec: the helper's required shape, the measured
table, and the three breaks. That is this pull request. Landing the helper alone would
put about a hundred lines of test infrastructure on `main` that nothing calls, guarded by
a self-check of the helper itself, and spend review budget on it now rather than when
the feature that needs it arrives.

If the operator disagrees, or when the feature is re-dispatched, Task 1 is the landing.
Its self-check is what proves the hang fix: each break is seen to fail on the platform
that shows it, which is how a fix for a hang is proved rather than assumed.

## Task 1: land the helper and its self-check

**Files:** `tests/helpers/setup.bash`, `tests/pty.bats` (new), `docs/ARCHITECTURE.md`
(the `tests/` line names the new file).

**Interface:** the three functions in spec section 2, `require_pty`, `run_in_pty`, and
`pty_feed`, with the shape spec section 3 decides: answer, hold one second, exit. Exit
status comes from a file the command writes, never from `script`. No product script
changes. The `GIT_CONFIG_*` loop is not added.

**Acceptance:** `tests/pty.bats` passes on macOS and on Linux with its three tests: a
command that prompts and reads at once, one that prompts and reads two seconds later,
and one that reads without printing and exits 3, each asserting the answer arrived and
the last asserting status 3. Three breaks seen to fail as spec section 4 says. Full
suite, shellcheck, identifier and pipe lints green on both CI jobs.

**Steps**

- [ ] `tests/helpers/setup.bash`: add the three functions per spec section 2. The
      `script --version` probe picks the family; the command is wrapped so it records
      `$?` into a file in the session directory; the feeder is a process substitution
      on `script`'s stdin. shellcheck is clean on this shape without any disable line;
      the abandoned fix needed one only because its feeder read the session file.
- [ ] `tests/pty.bats`: the three tests, each starting with `require_pty`, using
      `/bin/sh -c` readers so the file depends on nothing in `bin/`. Confirm on macOS
      and in Docker (`ubuntu:24.04` with `bats git` installed, the Ubuntu release CI
      runs today) that all three pass on both.
- [ ] Break-verify the hold, on macOS: delete the one-second hold in `pty_feed`. Expected:
      all three tests fail, the session shows the prompt with no answer. Restore. Paste
      the failure into the commit body as bats printed it.
- [ ] Break-verify the close, on either platform under a sixty-second outside time limit:
      make `pty_feed` loop forever after the answer. Expected: the run does not finish
      and is killed at the limit. Restore. Paste the kill into the commit body.
- [ ] Break-verify the status, in Docker: return `script`'s status instead of reading the
      file. Expected: the exit-3 test fails with status 0. Restore. Paste the failure.
- [ ] `docs/ARCHITECTURE.md`: add `pty.bats` to the `tests/` line.
- [ ] `make check` green, `bin/dux-doctor` passing, then `/ship`.

## Milestone acceptance

Constitution gates as usual if Task 1 runs: full suite green on both CI jobs, shellcheck
and the two lints clean, bash 3.2 clean, `bin/dux-doctor` passing, `/ship` the only gate.
If Task 1 does not run, this pull request is docs-only and skips the gate.

## Risks

- The terminal-prompt feature never comes back and the spec describes a helper nobody
  builds. Cost: one document. Recommended anyway over test code nobody calls.
- The Linux hang under bats was reproduced but its mechanism was not pinned down (spec
  section 3). If a future bats changes it, the self-check's close break stops failing and
  the implementer of that day has to look again. Recorded, not fixed.
- A future command that discards typed-ahead input before reading would need the wait
  the spec drops. The test that finds it is where the wait gets added.

## Open questions for the operator

- Land Task 1 now, or leave it until a command that reads from a terminal is on its way?
  Recommendation: leave it. Merging this pull request without dispatching Task 1 is the
  drop, and nothing is lost.

## Design review

One independent review by a fresh session on 2026-09-11, read-only, which re-ran the
whole measurement table on both platforms and got the same cells. Findings are plain
bullets, not boxes: `bin/dux-result` counts every box below the last `## Task` heading
as that task's.

- **Important, fixed.** The plan said the abandoned worktree's diff "holds two unrelated
  changes". It touches sixteen files; fifteen are the feature's own unfinished work. The
  plan now says so, scopes them out, and no longer promises the worktree "can then go":
  teardown refuses until that work is committed or given up, which is the operator's call.
- **Important, fixed.** The spec kept a session-file argument on `pty_feed` and Task 1
  told the implementer to silence a shellcheck warning about it, though the decided shape
  never reads that file. The reviewer ran shellcheck on both shapes: the decided one is
  clean. `pty_feed` now takes the answer only and the disable step is gone.
- **Minor, fixed.** "Hung them on Linux CI": the branch was never pushed, so no CI ran.
  Now "on Linux".
- **Minor, fixed.** Section 3 argued from a shape that was not in the table. The
  committed shape is now a row: passes on macOS, hangs on Linux under bats.
- **Minor, fixed.** A stray empty `typescript` file, left at the worktree root by a
  `script` run, is deleted so it cannot be committed.
- **Minor, fixed.** Plain-English tags added for process substitution, the typescript
  file, and line endings.
- **Note, fixed.** The session shows `^D^H^Hy`, not `^Dy`; four stand-in commands, not
  three; the Docker image is the Ubuntu release CI runs, not "the CI image"; section 15
  gains one bullet, not one line.

Everything else the reviewer checked held: the six acceptance criteria, that nothing on
`main` reads from a terminal, that the `GIT_CONFIG_*` loop is dead and traced to pull
request #29, that each break fails on the platform named and passes on the other, the
plan reader's view of Task 1, and that no personal identifier or home path is in either
document.
