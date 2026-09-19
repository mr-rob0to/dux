# Dux: Steady Process-Timing Tests Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> reviews the branch owes and decides how many that is (constitution principle 9),
> and a review outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted and design-reviewed; waiting for the operator's approval.
- Picks up the "hardening pass" that the flaky-test notes have asked for since milestone 4.
- When done, the four tests below stop failing at random, and one wrong `dux-spawn` message is fixed.

**Estimated diff:** ~400 added lines across 6 tasks, about 310 of them tests and test helpers.
The cap is 2,500 lines or 12 tasks (constitution principle 1).

**Goal:** A red `check` on main means the code is wrong, not that the runner was busy. Today
about one run in five goes red on a test that passes when run again. After this, those tests
wait for the thing they actually care about, so a busy runner cannot fail them and a broken
guard still does.

**Spec:** `docs/specs/2026-09-14-interactive-worker-sessions.md`, the spawn start-check passage
(near line 172). Task 4 amends it in the same commit as the code.

**Deviations:** constitution principle 8 wants the spec amended in the same pull request as the
plan. This task's acceptance criteria say the pull request changes only the plan file, so the
spec amendment is part of Task 4. Every decision it needs is settled in "Design" below.

**Shipping:** Task 4 changes the order in which `dux-spawn` and the wrapper see each other,
which is concurrency, so the implementation task is briefed `--review separate` and
`--risk complex`. Planning rule 1 applied for the same reason, which is why this plan had a
design review.

## What was found

Nine failed `check` runs since 2026-09-15 were read, and each cause below was reproduced on
purpose, in an Ubuntu 24.04 container (4 CPUs, non-root, `--init`). The four tests share three
causes. Only one of the three is about speed.

| Test | Where it fails | Cause |
|---|---|---|
| `backend-tmux` 36, 38, 39 (prompt typing, pane handover, pane pid) | `wait_until 15 not_running "$pid"` | A |
| `dux-worker-wrap` 37 (TERM reaches the harness) | `run kill -0 -- "-$hg"` expects failure, line 784 | A |
| `e2e-dispatch-tmux` 1 and 2 | `dux-spawn` exits 2 | B |
| `e2e-supervise-herdr` 1 (silent worker goes stale once) | `dux-recover --stop` says "running, not stale" | C |

The intent lists `dux-worker-wrap` 37 as a `wait_until 15` failure. The log (main run
35413207102) shows the wait passed and the group check after it failed. It is cause A.

**Cause A: the test counts a dead process as alive.** The process is killed at once, but its
parent, the tmux server, sometimes does not collect it for more than 15 seconds. Until it is
collected it is a zombie (dead, not yet collected), and `kill -0` says yes to a zombie. The
tests ask `kill -0`. Production does not: `pid_runs` also matches the command line, and a
zombie's reads `[sleep] <defunct>`. Evidence: 5 failures in 25 runs of the three adapter tests
under 12 busy loops, and every one printed `STAT Zs ... [sleep] <defunct>` (or `[cat]`) at the
moment the wait gave up. Linux only, which matches CI. **A longer wait does not fix this.**

**Cause B: `dux-spawn` looks once a second, and a short run fits between two looks.** Spawn
decides "started" only if it sees the wrapper alive with its pidfile. Both failing tests use a
worker that exits at once, so the wrapper lives about 2.5 seconds. On a busy runner spawn's
one-second sleep stretches, the wrapper starts and finishes unseen, and spawn reports `the
wrapper for <id> refused before the harness started`. That message is false: the run started,
ended, and published its result. Evidence: stretching only spawn's sleep to 5 seconds
reproduces the CI finding word for word, first try. This is a product defect the tests
exposed. In real use it needs a session that dies within about two seconds of starting, so it
is a wrong message on a rare path, not lost work. The same cause explains `dux-spawn` test
"a settled task's leftover container does not block a new start" (PR #66 CI).

**Cause C: the test's 3-second silence limit is the same size as a slow start.** The watcher
counts silence from the wrapper's pidfile. On a busy runner the fake worker's first line lands
more than 3 seconds later, so the task goes stale before it has spoken. The first line then
moves it back to running with no event, and `dux-recover --stop` finds it running. Evidence:
a forced 3-second start delay reproduces it every time. The watcher log reads `stale` at
01:46:06, first status line at 01:46:08, then `resumed`. Herdr only, because its fake types
the launcher into a shell and starts slower than tmux. Production uses 1,200 seconds against
a start of a few seconds, so this cannot happen outside the tests.

Fixed sleeps that guard a "nothing more happened" check (`sleep 3`, then count events) were
checked and are not a cause. A slow runner makes them weaker, never red.

## Approaches weighed

| Approach | Fixes A | Fixes B | Fixes C | Cost |
|---|---|---|---|---|
| **Wait on the right condition (recommended)** | yes | yes | yes | 6 small tasks; one production change |
| Deadlines scaled from one knob | no | no | partly | suite gets slower; A still fails at any deadline |
| Retry a failed test once or twice | hides it | hides it | hides it | a guard that breaks some of the time passes on retry |
| Move the tests to a job that cannot block | hides it | hides it | hides it | a real break in dispatch or supervision merges green |

- **Recommended: wait on the right condition, one fix per cause.** Each cause turned out to be
  a wrong question, not a short deadline. Asking the right one removes the failure instead of
  making it rarer, and it costs no run time.
- **Scaled deadlines** are cheap (one multiplier in `wait_until`) but fix nothing here. The
  zombie in A outlives any deadline we would accept, B is in production code, and a larger
  limit in C only moves the race. Not built. If a future flake is truly a short deadline,
  this is a ten-line change then.
- **Bounded retry** (`BATS_TEST_RETRIES`) would turn CI green today. It breaks the rule this
  task was given: these tests guard ordering and cleanup, and a guard that fails one run in
  three would pass on retry. It would also have buried cause B, a real defect. Rejected.
- **Quarantine** makes the most important tests optional. Rejected for these four. It stays
  the right tool only for a test whose cause cannot be found, with an expiry date. None
  qualifies today.

## Design

**`gone <pid>`** (test helper, `tests/helpers/setup.bash`): true when `kill -0` fails, or
when `ps -o stat=` for the pid starts with `Z`. A `ps` that fails or prints nothing means not
gone, so the helper fails closed the way production does. `not_running` becomes a call to
it. `reap` and `wait_for_workers` use it in place of bare `kill -0`.

**`group_gone <pgid>`** (same file): `! group_runs "$1"`. `group_runs` already exists in
`bin/dux-env`, which the helper file sources. It already ignores zombies, fails closed, and
has its own tests in `tests/dux-env.bats`. Nothing new is built.

**Spawn start check** (`bin/dux-spawn`). Today: started means "pidfile names a live wrapper".
New rule, one added case: when the wrapper is gone, spawn sent it no TERM, and it published a
handoff, read the `status` file of handoff sequence `$seq_before`. That is the number spawn
recorded before it started the wrapper, so it is this run's first handoff and never an
earlier run's. If the line starts with `failed: wrapper: `, it is a refusal and today's
finding stands, unchanged. A missing, empty or multi-line `status` file is also a refusal,
so the check fails closed. Any other single line means the run started and ended inside the
window, so spawn carries on exactly as for a live wrapper (`set-if queued running`, the issue
comment, `spawned ...`). The watcher then applies the ending as it does for any run. When
spawn did send TERM (the window ran out with no pidfile seen), today's findings stand
whatever the handoff says: a run spawn stopped itself is never reported as spawned. A worker
can write `failed: wrapper: x` as its own terminal line and the wrapper lets it stand. That
is harmless: it earns only today's refusal finding, which is the safe direction. No new
file, so nothing new for teardown to clear.

**`DUX_SPAWN_LOOK_PAUSE_SECS`** (tests only, same pattern as `DUX_WRAP_FORK_PAUSE_SECS`):
when set, spawn sleeps that long before its first look. This makes cause B happen every time
instead of one run in ten, which is what lets its test be seen to fail.

**`age_task <id> <seconds>`** (test helper): sets the mtime of the task's `status.log` and
`state/<id>.pid` that many seconds into the past, with `perl -e utime`, which the suite
already depends on. `supervised_env` raises `DUX_STALE_SECS` from 3 to 3600, so a slow start
can never read as stale. Test 1 calls `age_task "$id" 3600` after the first status line
arrives. The test now decides when silence begins, and the watcher's next pass sees it.

**`tests/repeat`** (measurement tool): `tests/repeat <make-job> <runs> [burners]` runs one
make job that many times with that many busy loops beside it and prints one line,
`<job>: <failures> failures in <runs> runs`, plus the name of each test that failed and how
often. Exit 0 always: it measures, it does not gate. Logs go under `tests/tmp/`.

Order: Task 1 first so the "before" numbers exist. Tasks 2 to 5 are independent of each other.

## Task 1: Measure the failure rate before anything changes

**Files:** `tests/repeat` (new), `Makefile` (add it to `SHELL_FILES`), `CONTRIBUTING.md`.

**Interface:** as in Design. `CONTRIBUTING.md` gains the container recipe in five lines: image
`ubuntu:24.04`, `--init`, `--cpus 4`, non-root user, the repository copied in and not mounted.

**Acceptance:** the baseline table is in the commit body. Each job is run 25 times with 12
burners in the container, which is enough to show a rate near 20 percent: `job-m/backend-tmux`, `job/dux-worker-wrap`,
`job-m/e2e-dispatch-tmux`, `job-m/e2e-supervise-herdr`. On macOS under `check-bash32`,
`job-m/e2e-dispatch-tmux` is run 30 times. The 100-run pass is kept for the after table.

**Steps**

- [x] Write `tests/repeat` and a happy-path test in `tests/harness.bats` that it counts one
      failing and one passing stub job correctly.
- [x] Add the container recipe to `CONTRIBUTING.md`.
- [x] Run the baseline and paste the table into the commit body.
- [x] No break-verify owed: this is a counting tool, and the stub test covers the count.

## Task 2: A dead process no longer counts as alive

**Files:** `tests/helpers/setup.bash`, `tests/harness.bats`.

**Interface:** `gone <pid>` as in Design; `not_running`, `reap`, `wait_for_workers` use it.

**Acceptance:** a new test in `tests/harness.bats` makes a real zombie (a perl parent that
forks, prints the child's pid, and sleeps without collecting it) and shows `gone` is true for
the zombie, false for a live process, and true for a pid that does not exist.
`tests/repeat job-m/backend-tmux 100 12` in the container reports 0 failures.

**Steps**

- [ ] Write the zombie test first and see it fail against `kill -0`.
- [ ] Add `gone` and move the three helpers onto it.
- [ ] Break-verify: put `kill -0` back inside `gone`, confirm the zombie test fails, restore,
      paste the failure into the commit body.
- [ ] Break-verify that a survivor is still caught: in adapter test 39 make the pane command
      ignore TERM (`trap '' TERM`), confirm `wait_until 15 not_running` fails, restore, paste.

## Task 3: A group of dead processes no longer counts as alive

**Files:** `tests/helpers/setup.bash`, `tests/harness.bats`, `tests/dux-worker-wrap.bats`,
`tests/e2e-supervise.bats`.

**Interface:** `group_gone <pgid>` as in Design.

**Acceptance:** `dux-worker-wrap` test 37 and the two group checks in `e2e-supervise.bats`
(near lines 109 and 234) ask `group_gone`. The other inline `kill -0` checks are read once
each in the four files that hold the failing tests, and nowhere else. One is changed only
where it asserts that a pane's process is gone; the commit body lists which were changed and
which were left, with the count of each.
`tests/repeat job/dux-worker-wrap 100 12` in the container reports 0 failures.

**Steps**

- [ ] Add a test in `tests/harness.bats`: a group whose only member is a zombie is gone; a
      group with one live member is not.
- [ ] Add `group_gone` and move the three call sites onto it.
- [ ] Break-verify `group_gone`: make it always true, confirm the "one live member" test
      fails, restore, paste. Test 37's own group check cannot serve here: the wrapper stops
      the group before it publishes, so that line never sees a live group.
- [ ] Break-verify the protection test 37 guards: remove the group `kill -TERM` from the
      wrapper's INT/TERM trap, confirm test 37 fails at its `handoff_status` line (the run
      finishes as `done: report` instead of `ended`), restore, paste.
- [ ] Print the match count of `kill -0` in those four files before and after, and compare.

## Task 4: Spawn recognises a run that started and finished between two looks

**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`, `docs/ARCHITECTURE.md` (spawn, near line
314), `docs/specs/2026-09-14-interactive-worker-sessions.md` (near line 176).

**Interface:** the start-check rule and `DUX_SPAWN_LOOK_PAUSE_SECS` as in Design. No message
changes wording. No new exit code.

**Acceptance:** with `DUX_SPAWN_LOOK_PAUSE_SECS=5` and a worker that exits at once, spawn exits
0, prints `spawned ...`, and the ledger reads `running`. With the same pause and a wrapper
that refuses after its run record exists, spawn still exits 2 with `refused before the
harness started` and the task is still `queued`. With `DUX_SPAWN_START_SECS=0`, so that spawn
sends TERM, a run that then ends without the refusal prefix still gets today's finding and
exit 2. The spec and ARCHITECTURE say the new case.
`tests/repeat job-m/e2e-dispatch-tmux 100 12` in the container reports 0 failures, and 30
runs under `check-bash32` on macOS report 0.

**Steps**

- [ ] Write the three tests first. The first fails on today's code with the false finding.
- [ ] Add the pause knob and the rule. Re-read the whole start-check block afterwards: every
      undo path and every finding must still be reachable.
- [ ] Amend the spec passage and ARCHITECTURE in the same commit.
- [ ] Break-verify the new case: remove the added case, confirm the first test fails with
      the false finding, restore, paste.
- [ ] Break-verify the refusal guard: make the prefix match never true, confirm the second
      test fails because a refusal is reported as `spawned`, restore, paste.
- [ ] Break-verify the TERM guard: drop the "sent no TERM" condition, confirm the third test
      fails because a run spawn stopped is reported as `spawned`, restore, paste.

## Task 5: The supervise test decides when silence starts

**Files:** `tests/helpers/setup.bash`, `tests/e2e-supervise.bats`.

**Interface:** `age_task` as in Design; `DUX_STALE_SECS=3600` in `supervised_env`.

**Acceptance:** test 1 passes with `DUX_WRAP_FORK_PAUSE_SECS=5` exported, which fails it
every time today. Its assertions are unchanged: one stale event, ledger stale, the toast, one
ended event after `--stop`. `tests/repeat job-m/e2e-supervise-herdr 100 12` and the same for
`-tmux` in the container report 0 failures.

**Steps**

- [ ] Run test 1 with the 5-second start pause and record today's failure.
- [ ] Add `age_task`, raise the limit, call `age_task` after the first status line.
- [ ] Break-verify stale detection: in `bin/dux-watch` make the age comparison never choose
      `stale`, confirm test 1 fails at `count_is stale "$id" 1`, restore, paste.
- [ ] Break-verify "exactly once": remove the `[ "$target" != "$lstate" ] || continue` line,
      confirm test 1 fails at the event count after the sleep, restore, paste.

## Task 6: Measure again, and write down how to wait

**Files:** `CONTRIBUTING.md`.

**Interface:** a short "Waiting in a test" section, at most twelve lines: ask `gone` or
`group_gone`, never bare `kill -0`, when asserting a process has ended; when a test needs
time to have passed, move the clock with `age_task` instead of sleeping past a small limit;
a fixed sleep is fine only before a "nothing more happened" check.

**Acceptance:** the after table sits beside the baseline in the pull request body, same jobs,
same run counts. Every job reports 0 failures. The flaky-test list in the pull request body
names any test that still failed and what was seen.

**Steps**

- [ ] Run every measurement from Task 1 again and record the table.
- [ ] Write the `CONTRIBUTING.md` section.
- [ ] If any job is above 0, stop and report it; do not raise a deadline to reach 0.

## Milestone acceptance

- **Target rate:** 0 failures in 100 runs per job under load in the container, and 0 in 30
  on macOS. Zero in 100 means the true rate is very likely under 3 percent; the baseline for
  `backend-tmux` is about 20 percent. On main, none of the four tests fails in the next 20
  `check` runs; one that does reopens this plan, it is not re-run and forgotten.
- **A fixed test still fails when its guard is broken.** Nine deliberate breaks are named
  in Tasks 2 to 5, one per protection, each with its failure pasted into its commit
  (constitution principle 3). A break that leaves its test green stops the task.
- bash 3.2 and shellcheck clean, `make check-branch` green, ARCHITECTURE updated with Task 4.
- No deadline is raised and no retry is added anywhere in this milestone.

## Risks

- The macOS runner's load cannot be reproduced in a Linux container, so cause B is proved
  through the pause knob and 30 local runs, not by matching CI. Cost: one more CI failure
  would show it.
- With the watcher on, a run that ends within a second can have its ending applied before
  spawn's `set-if`, and spawn then exits with a finding naming the state that won. That is
  today's behaviour for a fast refusal and is left alone. Cost: a confusing message on a
  path nobody has hit.
- The wrapper's `refuse()` also runs after the harness has ended (proof and cleanup
  failures). A fast run that ends that way still reads `refused before the harness started`.
  Unchanged from today and left alone.
- The container recipe must keep `--init`: spawn's own `kill -0` on the wrapper is safe only
  because init collects the wrapper at once.
- Why tmux is slow to collect a dead pane process was not pursued. Production already
  ignores zombies, so nothing depends on the answer.
- Other tests may hold causes not seen yet (`e2e-supervise` test 7 on macOS, the adapter
  `tail` test on bash 3.2). Out of scope; `tests/repeat` is the tool for the next one.

## Open questions for the operator

None.
