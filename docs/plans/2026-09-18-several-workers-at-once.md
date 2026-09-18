# Dux: Several Workers at Once Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> reviews the branch owes and decides how many that is (constitution principle 9),
> and a review outside the gate is how the gate gets skipped.

**Where this stands**
- Approved and merged as PR #64; implementation under way on one branch. Tasks 1-3 done.
- Picks up what the rollout plan deferred: "Parallel workers: not met" in `dux-simplification-rollout.md`.
- When done, Dux starts up to `config/max-workers` workers at once, default 3, in any mix of repositories.

**Estimated diff:** ~900 added lines across 11 tasks, about 650 of them tests and test fakes. The cap is
2,500 lines or 12 tasks (constitution principle 1).

**Goal:** The operator gives Dux several goals and Dux starts a worker for each straight away,
in the same repository or in different ones, instead of holding all but one in the queue. One
number in one file says how many may run at once. Feedback, answers and approvals reach a
waiting worker no matter how many others are running.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md`, the one-worker guard passage
(near line 325) and section 5.5 (spawn). Task 1 amends it before any code changes.

**Deviations:** constitution principle 8 wants the spec amended in the same pull request as the
plan. This task's acceptance criteria say the pull request changes only the plan file, so the
spec amendment is Task 1 of the implementation instead. Every decision it needs is settled in
"Design" below, so the implementer copies decisions and makes none.

**Shipping:** this work changes concurrency, so the implementation task is briefed
`--review separate`. Planning rule 1 applied (a concurrency boundary changes), which is why
this plan had a design review.

## What assumes one worker today

The cap is one function, `fleet_busy` in `bin/dux-env`, with two callers. Everything a worker
owns is already kept per task under `state/<id>.*` and `data/tasks/<id>/`. The full list:

| Place | What it assumes | What it needs |
|---|---|---|
| `bin/dux-env` `fleet_busy` and its comment block | Any other task with a live wrapper, live group, unreadable evidence, or a pane while `running` blocks every start | Removed. Replaced by `worker_limit` and `fleet_running` (Design). `parked` stays |
| `bin/dux-spawn` lines 63-76 | Refuses the start when `fleet_busy` answers | Refuses only when the running count has reached the limit |
| `bin/dux-spawn` comment near line 202, own-task checks lines 49-61 | Comment says an untrusted-folder dialog "holds the one-worker slot". The own-task checks assume nothing about other tasks | Comment reworded. Own-task checks unchanged: they are what stops two workers on one task |
| `bin/dux-round` lines 130-142 | A round is refused while any other worker is live | Removed. A round reads only its own task. See Design, "Rounds" |
| `bin/dux-env` `parked` | Written as the exemption from the one-worker guard | Code unchanged. Still read by `dux-round` and `dux-teardown` for the task's own session. Comment reworded |
| `bin/dux-worker-wrap` comments near 418 and 503, refusals at 432 and 437 | "end it in the tab before starting another task": a leftover session blocks the next start | Reworded to "before starting $id again": a leftover session no longer blocks anything, it is just unsupervised |
| `bin/dux-recover` comment near 218 | A session left in a dead task's tab "holds the one-worker slot" | Comment reworded. The printed advice (end it in the tab, run recover again) is still right |
| `bin/dux-teardown` | Nothing. It reads only its own task | Unchanged. Covered by a two-task test in Task 8 |
| `bin/dux-watch` | Nothing. It loops every `running` and `stale` task and skips a task it cannot read | Unchanged. Gains two-task tests in Task 7 |
| `bin/dux-ledger` | Nothing. Every write takes the `backlog.md.lock` mutex | Unchanged. Gains a row-isolation test and one held-mutex test in Task 6 |
| `bin/dux-status` | Counts `running N` per project already. Says nothing about the limit | One new line: `workers: <n> running (limit <m>)` |
| `bin/dux-doctor` | Nothing | One new check: the limit file holds a usable number |
| `bin/dux-notify`, `bin/dux-result`, `bin/dux-lock`, `bin/dux-intake`, `bin/dux-task-new`, `bin/dux-brief`, backends, `bin/workers/claude.sh`, `skills/ship` | Nothing. Each is keyed by task id, and `/ship` uses `mktemp` for its scratch files | Unchanged |
| `templates/brief.md` Rules | "Stay inside the worktree above" does not say other workers may be next door | One added rule line (Task 10) |
| `AGENTS.md` Task lifecycle | "The next task stays queued until capacity is proved free". The wake rule never looks for queued work, and the digest is not run on a wake | Reworded, and the wake rule gains one step: after the ack, spawn what is queued and briefed |
| `AGENTS.md` Session start | "Restart this session daily or after 10 wakes" | Unchanged. Wakes arrive faster with several workers, so restarts come sooner. Stated in Risks |
| `skills/dux-dispatch` lines 16-23, 114-117 | Two repositories "run one after the other"; "One worker at a time"; rounds refuse "another active worker" | Reworded (Task 10) |
| `skills/dux-status` step 6 | Dispatch a queued task "when the digest shows no worker running" | Reworded: when the `workers:` line shows room |
| `skills/dux-recover` | Nothing about capacity | Unchanged. A retry that hits the limit relays spawn's finding like any other |
| `docs/ARCHITECTURE.md` lines 252-266 | Describes the whole-fleet refusal | Rewritten in the same pull request (constitution gate) |
| `docs/plans/dux-simplification-rollout.md` lines 1422-1423 and 1463; rollout spec lines 22, 220-222, 315, 328, 335 | Parallel workers deferred until queue delay is measured; "never run two active implementation workers" | A dated note under each saying the operator lifted the deferral on 2026-09-18 and naming this plan. History is not rewritten |
| Older specs (`interactive-worker-sessions` section 6, `feedback-rounds` section 8) | Describe the guard as built | Left as the record of what was built. The living spec points past them (Task 1) |
| `tests/` | `dux-env.bats` 227-261, `dux-spawn.bats` 319 and 493-640, `dux-round.bats` 330, `e2e-dispatch.bats` 251-255 (comment) and 286, `dux-worker-wrap.bats` 894-895 assert the old refusals. `tests/fakes/herdr` keeps one process, one working directory and one input file, so it can hold only one live worker | Rewritten in the task that changes the behavior. Test counts compared before and after. The fake is keyed by pane in Task 8 |
| Operator's global instructions | Six passages | Listed at the end of this plan for the operator to edit |

## Design

### The recommended design: one number, counted from the ledger

- `config/max-workers` holds one whole number from 1 to 99. The installer seeds it from
  `templates/config/max-workers`, which says 3. Example file content: a comment block, then `3`.
- `dux-spawn` counts the tasks the ledger holds as `running` or `stale`. If the count has
  reached the limit, it refuses before creating anything, and the task stays `queued`.
- A parked session (ledger `done`, `needs-decision` or `blocked`) is not `running`, so it never
  counts. No special exemption is needed.
- Nothing else reads other tasks. `dux-round` does not check the limit at all.
- Setting the file to `1` gives back today's one-at-a-time behavior. That is the rollback.

The limit is a spending brake, not a safety boundary. Safety between workers comes from each
task having its own worktree, branch, tab and state files (next section), and holds at any
count. That is why the count can be read from the ledger rather than from process evidence, and
why uncertain evidence about some other task no longer blocks the whole fleet.

**Interfaces** (all in `bin/dux-env`):

- `first_value <file>`: moved from `bin/dux-doctor` unchanged. First line that is not blank and
  not a `#` note.
- `worker_limit`: prints the limit. Reads `config/max-workers`, else
  `templates/config/max-workers`. Anything but `[1-9]` or `[1-9][0-9]` is
  `finding: config/max-workers must be a whole number from 1 to 99, not '<value>'`. No file in
  either place is `finding: no worker limit in config/max-workers or templates/config/max-workers`.
- `fleet_running`: prints how many tasks the ledger lists as `running` or `stale`. Returns 1
  when either list fails, printing nothing. It takes no id: the task asking is `queued`, which
  spawn has already proved, so it is never in the count.

**Refusals in `dux-spawn`**, in place of the six `fleet_busy` findings:

- `finding: <n> Dux workers are running and the limit is <m> (config/max-workers); <id> remains queued`
- `finding: cannot count the running Dux workers: the ledger did not answer; <id> remains queued`
- the two `worker_limit` findings above, with `; <id> remains queued` appended.

The check stays where the old one was: after the own-task checks, before the worktree is made,
so a refused task is untouched.

### Compared with the alternatives

| | Recommended: one setting, default 3 | Small fixed cap (2, written in the code) | No limit at all |
|---|---|---|---|
| What the operator gets | Several at once; one file to change the number; `1` is the rollback | Two at once; changing it is a code change through `/ship` | Every authorized task starts at once |
| Code | `fleet_busy` (55 lines plus 25 of comment) goes; about 30 lines come in | Same as recommended minus the file read, about 10 lines less | Least: `fleet_busy` goes and nothing replaces it |
| Tests | Limit, bad value, ledger failure: three protections to break-verify | One protection | None for admission |
| Spend | Bounded by a number the operator picks | Bounded at 2 | Unbounded. Eight labelled issues can mean eight Opus sessions and eight Codex reviews inside one subscription window |
| Machine load | Bounded. Matters because start checks are time-based (the 300 s pane wait, #61) and several builds at once slow them | Bounded at 2 | Unbounded. The likely failure is starts that time out under load, each one a `failed` wake to recover |
| Coordinator context | About 3 times the wakes per hour, so the 10-wake restart comes about 3 times sooner | About twice | Unbounded |
| Rollback | Edit one file | Revert a merge | Revert a merge |

Why not the fixed cap: it costs almost the same code and the first time 2 is wrong the fix is a
full `/ship` cycle. Why not no limit: the person it protects is the operator on a busy day, the
mistake is dispatching more than the subscription or the laptop carries, and the cost is several
half-finished workers stalled at once, each needing recovery. One file prevents that for about
30 lines.

Default 3 is a judgement, not a measurement: no record exists of how many sessions the
subscription sustains. It is one line to change, and Task 11 records what three real workers did.

### Worktree and branch isolation

Two live workers never share a worktree or a branch because both names come from the task id,
and the id is unique:

1. `dux-ledger add` refuses an id already in the ledger, under the ledger mutex.
2. The branch is always `dux/<id>`. `dux-worktree create` refuses when that branch already
   exists without a clean, untouched worktree of its own.
3. Git itself refuses to check one branch out in two worktrees, under every worktree mechanism
   (`git`, `make`, `script`).
4. `dux-worktree create` refuses a worktree path equal to the primary checkout.
5. `dux-spawn` refuses a task that is not `queued`, that has a live pidfile, or that has a
   container, and moves `queued` to `running` with a compare-and-set. So one task never gets
   two workers.
6. The wrapper supervises a harness only when its working directory is this task's worktree.
7. The pre-push hook is installed per worktree, from the task's own folder, and refuses a push
   to the base branch. It does not stop a push to another task's branch; the brief rule below
   covers that, and a worker has no reason to try.

None of this is new code. Task 8 adds the two-task tests that prove it with two workers live,
and re-breaks points 2 and 5.

**Two tasks that want the same repository both run.** Each gets its own worktree cut from
freshly fetched `origin/<base>`. Whichever pull request merges second is then behind its base,
and the existing feedback round already handles that: the round tells the worker to merge the
base in, and a real conflict stops at `needs-decision`. When the operator or Dux can see up
front that two goals change the same files, the second task is created `--after` the first,
which is the existing mechanism. No per-repository lock and no second setting.

A worker is trusted but not confined: nothing stops one from walking into a sibling worktree.
The brief gains one rule line saying other workers may be running beside it and their
worktrees and branches are not to be touched.

`dux-spawn` counts near its start and writes `running` at its end, and building a worktree in
between can take minutes. So spawns that overlap all count the same number and can all start,
past the limit. A spawn cut off after its wrapper started also leaves a live worker the ledger
still reads as `queued`, which the count misses until the watcher or a rerun settles it. Both
cost tokens, not correctness. The fix is a rule in `skills/dux-dispatch`, not a lock: one
`dux-spawn` at a time, never as parallel tool calls, never in the background, and wait for
`spawned` before the next. Overlapping spawns in one repository can also collide on the shared
`.git` fetch and refuse, which the same rule avoids.

### Rounds

A round (feedback, answer, approval) is never refused for capacity. It continues work that was
already admitted, the operator is usually waiting on it, and there is no queue for a refused
round, so refusing it would make Dux remember to resend it. The running count can therefore
pass the limit by however many parked sessions are woken. That is accepted and said in the spec.

### How shared records stay correct

| Record | Why it stays correct with several workers | Test and deliberate break |
|---|---|---|
| Ledger `data/backlog.md` | Every writing verb takes the `mkdir` mutex and replaces the file with one rename; readers see a whole file | Task 6 |
| `state/events.log` | One writer only: the single watcher, which `watch.pid` enforces. Each line names its task | Task 7 |
| Wakes and acknowledgements | A wake names its task; `ack` and `unack` rewrite only that task's row and compare that task's state | Tasks 6 and 7 |
| Handoffs | Kept per task under `state/<id>.handoffs/`, checked against that task's run id before anything is written | Task 7 |
| Parked markers | `state/<id>.parked` names that task's run, wrapper and group, and counts only while all three match that task's own files | Task 5 |
| Rounds | `dux-round` reads only its own task; the wrapper takes up only `data/tasks/<id>/round-<n>.md` | Task 4 |
| Worktrees and branches | Previous section | Task 8 |

### Order

Task 1 first (spec). Tasks 2, 3, 4, then 5: `fleet_busy` is removed only once nothing calls it.
Tasks 6, 7 and 8 add tests to unchanged code and can land in any order after 5. Task 9 needs 2.
Task 10 (wording) after the behavior it describes. Task 11 last, on the installed build.

No rollout stage is added. If the operator's global instructions change before this is
installed, spawn still refuses the second worker with today's finding. If this is installed
first, Dux just keeps dispatching one at a time. Neither order breaks anything.

## Task 1: Amend the specs

**Files:** `docs/specs/2026-09-03-dux-orchestrator-design.md`,
`docs/specs/2026-09-15-dux-simplification-rollout.md`, `docs/plans/dux-simplification-rollout.md`.

**Interface:** none.

**Acceptance:** the orchestrator spec carries the Design section above as a section named
"Several workers at once", and its one-worker guard passage points at it as superseded. The
rollout spec's section 11 row for parallel workers and the rollout plan's "Parallel workers: not
met" line each gain a dated note: the operator lifted the deferral on 2026-09-18, see this plan.
No earlier text is deleted.

**Steps**

- [x] Add the spec section: the limit, the ledger count, rounds exempt, isolation points 1-7,
      same-repository behavior, the shared-records table.
- [x] Mark the guard passage superseded, with a pointer.
- [x] Add the two dated notes to the rollout spec and plan.
- [x] No break-verification: prose only.

## Task 2: The limit and the count in `dux-env`

**Files:** `bin/dux-env`, `bin/dux-doctor` (loses `first_value`), `templates/config/max-workers`,
`tests/dux-env.bats`, `tests/dux-install.bats`.

**Interface:** `first_value`, `worker_limit`, `fleet_running` as in Design. The template file
holds a short comment (what it limits, that rounds are exempt, that 1 restores one at a time)
and the line `3`.

**Acceptance:** `worker_limit` prints 3 on a fresh install, prints the operator's number when
`config/max-workers` holds one, and gives the exact finding for `0`, `100`, `3x`, `-1`, an empty
file, and no file in either place. `fleet_running` counts `running` and `stale`, leaves out the
asking task and every other state, and returns 1 when the ledger cannot list. `dux-doctor`
still reads the policy stage exactly as before. The installer seeds the new file once and never
overwrites one the operator wrote.

**Steps**

- [x] Write the failing tests first.
- [x] Move `first_value`; count function declarations in both files before and after.
- [x] Add `worker_limit`, `fleet_running` and the template.
- [x] Break-verify 1: make `worker_limit` fall back to 3 on a bad value; the bad-value test fails.
- [x] Break-verify 2: make `fleet_running` ignore a failed `dux-ledger list`; the ledger-failure
      test fails. Paste both failures into the commit.

## Task 3: Spawn admits up to the limit

**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`, `tests/e2e-dispatch.bats`.

**Interface:** the four refusals in Design replace the six `fleet_busy` findings. Exit 2, task
left `queued`, no worktree, no tab.

**Acceptance:** with the limit at 3, a fourth start is refused with the exact count finding and a
third is not. With the limit at 1, the second start is refused. A parked task beside it does not
count. Another task's unreadable pidfile or pgid file no longer refuses anything. A bad limit
file and a ledger that cannot list both refuse. `e2e-dispatch.bats` near line 286 now expects
only the `waits on` finding for the `--after` task. Other tasks are put in `running` through the
ledger here; two really live workers are Task 8's, which first makes the test fake able to hold
them.

**Steps**

- [x] Rewrite the tests at `dux-spawn.bats` 319 and 493-640 first; record the test count before.
- [x] Replace the `fleet_busy` block; reword the comment near line 202.
- [x] Re-read the whole admission section of `dux-spawn` top to bottom after the edit.
- [x] Compare the test count after; account for every test removed or merged in the commit body.
- [x] Break-verify: change the comparison so the limit admits one more; the at-limit test fails.

## Task 4: Rounds no longer read other tasks

**Files:** `bin/dux-round`, `tests/dux-round.bats`.

**Interface:** lines 130-142 removed. No new output.

**Acceptance:** with task A parked and task B live, `dux-round A` prints `round 1 sent to A` and
none of B's state files change. The same holds when B's pidfile is unreadable and when the
running count is already at the limit. Every existing own-task refusal (not parked, group ended,
tab closed, pending handoff, ninth round) still refuses with its existing text.

**Steps**

- [ ] Replace the test at `dux-round.bats` 330 with the three cases above, failing first.
- [ ] Remove the block; re-read `dux-round` from the liveness checks to the ledger move.
- [ ] Break-verify: put a `fleet_running`-against-limit refusal into `dux-round`; the at-limit
      round test fails. Restore.

## Task 5: Remove `fleet_busy`, keep `parked` proved

**Files:** `bin/dux-env`, `tests/dux-env.bats`.

**Interface:** `fleet_busy` and its comment block deleted. `parked <id>` unchanged; its comment
says who reads it now (`dux-round`, `dux-teardown`).

**Acceptance:** `grep -r fleet_busy bin skills tests` finds nothing. The three `dux-env.bats`
tests that reached `parked` through `fleet_busy` now call `parked` directly and still cover: a
marker naming another run, another wrapper pid, another group, a dead wrapper, and a marker for
task A never reading as parked for task B.

**Steps**

- [ ] Re-home the tests first, green against the unchanged `parked`.
- [ ] Delete `fleet_busy`; `make check`.
- [ ] Break-verify, one at a time, three breaks and three distinct failures: drop the run
      comparison, drop the group comparison, drop the wrapper comparison. These tests were
      rewritten, so each is seen to fail again.

## Task 6: The ledger under several writers

**Files:** `tests/dux-ledger.bats` only.

**Interface:** none.

**Acceptance:** a test writes to task A's row with `set`, `set-if`, `ack` and `unack` and shows
task B's row, including its `acked` field, byte for byte unchanged after each. A second test
holds the mutex directory and starts `set-if` in the background: nothing is written after one
second, and the write lands once the mutex is released. The writers stay the coordinator's
scripts and the one watcher, and the held and stale mutex are already tested at
`dux-ledger.bats` 111 and 120, so one verb is enough.

**Steps**

- [ ] Add both tests. Green on first run is expected here; that is why the breaks matter.
- [ ] Break-verify 1: remove `lock_ledger` from `set-if`; the held-mutex test fails.
- [ ] Break-verify 2: make `write_field` match every row; the row-isolation test fails.

## Task 7: The watcher with two tasks in one pass

**Files:** `tests/dux-watch.bats` only.

**Interface:** none.

**Acceptance:** two tasks each publish a handoff before one `dux-watch --once`. Afterwards
`events.log` holds exactly two new whole lines, one naming each task; each ledger row holds its
own state and its own pull request url; each handoff is marked consumed; a second pass adds no
line. In a second test task A, added to the ledger before B so the watcher reaches it first, has a
handoff naming the wrong run: A is reported as a finding and left alone, and B is still applied
in the same pass. In a third, both tasks are `done` and
unacknowledged, acknowledging A leaves B listed by `dux-ledger list --unacked`.

**Steps**

- [ ] Add the three tests.
- [ ] Break-verify 1: make the rejected-handoff branch in `pass` stop the loop instead of
      moving on; the second test fails because B has no event.
- [ ] No second break. A line written twice is a crash-replay fault, which `dux-watch.bats`
      500-512 and 531-545 already cover; a finished task is not visited again, so a
      two-task test cannot reach it. Acknowledgement isolation is Task 6's row break.

## Task 8: Two live workers in one repository

**Files:** `tests/fakes/herdr` (and `tests/fakes/tmux` if it has the same shape),
`tests/dux-worktree.bats`, `tests/e2e-dispatch.bats`, `tests/dux-teardown.bats`.

**Interface:** none.

**Acceptance:** two tasks in one fake project, both spawned and live: their worktree paths
differ, their branches are `dux/<a>` and `dux/<b>`, each has its own pre-push hook
under its own task folder and each refuses the base branch, and `dux-status` reads `running 2`. `dux-worktree create` for a task whose branch
already has a worktree with a commit in it refuses as "not at origin/<base>" (the reuse path,
`dux-worktree` near line 158). A second `dux-spawn` of a running task
refuses. Tearing down finished task A while B is live removes only A's worktree, tab and state
files; every `state/<b>.*` file is unchanged.

**Steps**

- [ ] First key the fake's process id, working directory and input file by pane id, so two
      tabs hold two workers. Every existing test stays green with no edits to it.
- [ ] Add the tests. Fix the comment at `e2e-dispatch.bats` 251-255 ("Two workers never run at once").
- [ ] Break-verify 1: remove the not-at-base refusal on the reuse path in `dux-worktree create`;
      the refusal test fails.
- [ ] Break-verify 2: make `dux-spawn` write `running` with `set` instead of `set-if` and drop
      the `queued` check; the second-spawn test fails.
- [ ] If either timing-based test fails once under load and passes on a re-run, say so in the
      pull request; do not loosen the assertion.

## Task 9: Status and doctor show the limit

**Files:** `bin/dux-status`, `bin/dux-doctor`, `tests/dux-status.bats`, `tests/dux-doctor.bats`.

**Interface:** `dux-status` prints `workers: <n> running (limit <m>)` straight after the `watcher:` line,
which is always printed,
counting `running` and `stale` across all projects. With a bad limit file it prints
`workers: <n> running (limit unreadable)` and carries on. `dux-doctor` prints
`ok worker limit <m>` or `FAIL worker limit: <the worker_limit finding text>`.

**Acceptance:** both outputs match exactly in tests for a good file, a bad file, and no
operator file (template default). The digest still prints every project block when the limit
is unreadable.

**Steps**

- [ ] Tests first, then the two small additions.
- [ ] No break-verification: formatting and straightforward mapping. The protection behind the
      number is Task 2's.

## Task 10: Wording for workers, Dux and readers

**Files:** `bin/dux-worker-wrap` (two refusals, two comments), `bin/dux-recover` (comment),
`tests/dux-worker-wrap.bats` (894-895), `templates/brief.md`, `tests/dux-brief.bats`,
`AGENTS.md`, `skills/dux-dispatch/SKILL.md`, `skills/dux-status/SKILL.md`,
`docs/ARCHITECTURE.md`.

**Interface:** wrapper refusals end `end it in the tab before starting <id> again`. New brief
rule: `- Other Dux workers may be running in other worktrees of this repository. Never touch
their worktrees or their dux/ branches.` `AGENTS.md`: a queued task is dispatched while there is
room and what it waits on is proved merged; and the wake rule gains a last step: after the ack,
run `bin/dux-ledger list --state queued` and spawn each listed task that has a brief, one at a
time. Spawn is the check, so a refusal at the limit is relayed and the task waits for the next
wake. `dux-dispatch`: independent
tasks, in one repository or several, are dispatched together; `--after` is for work that needs
the other's merge, or that plainly changes the same files; one `dux-spawn` at a time, never as parallel tool calls, never in the background, waiting for
`spawned` before the next;
"another active worker" leaves the list of round refusals. `dux-status` step 6 reads the
`workers:` line. `ARCHITECTURE.md` lines 252-266 describe the limit instead of the fleet refusal.

**Acceptance:** `grep -rn "one-worker\|One worker at a time\|another Dux worker\|never run at once" bin skills tests AGENTS.md docs/ARCHITECTURE.md templates`
finds nothing. The brief stays within its 100-line cap. Wrapper tests assert the new wording.

**Steps**

- [ ] Print the grep's match count first, edit, print it again at zero.
- [ ] Update the two wrapper tests and the brief test.
- [ ] No break-verification: wording only.

## Task 11: Run it installed, then hand over the policy lines

**Files:** this plan (evidence block under "Where this stands" and ticked boxes).

**Interface:** none.

**Acceptance:** on the installed build, named by its commit: two real tasks in one registered
repository, the one most likely to clash on shared test services, and one in another run at the
same time; each delivers its own pull request from its
own branch; a feedback round reaches one of them while the others run; with `config/max-workers`
set to `1` a second spawn is refused with the exact count finding, and set back to 3 it starts.
The plan records the commit installed, the three pull request urls, the refusal as printed, and
how many wakes the coordinator session took.

**Steps**

- [ ] Install the build; say which commit.
- [ ] Run the three tasks and the round; force the refusal.
- [ ] Record the evidence. If three workers at once stalled on the subscription or failed a
      start check, say so and recommend a lower default rather than hiding it.
- [ ] Tell the operator the global-instruction lines below are ready to change.

## Milestone acceptance

`make check` and `/ship`'s `make check-branch` pass; bash 3.2 and shellcheck clean. Separate
correctness and security reviews (concurrency). `ARCHITECTURE.md` changes in the same pull
request. Every break-verification above is pasted into its commit, one failure per break. The
added-line count against the 2,500 cap goes in the pull request body. The installed run in
Task 11 is done before the milestone is called finished.

## Risks

- Three workers may be more than the subscription carries; several stall at once and each needs recovery. Cost: a noisy afternoon. Fix: lower one number.
- Several builds at once slow the machine and a time-based start check fails. Cost: a `failed` wake and a retry. Same fix.
- Two tasks in one repository change the same file. Cost: one feedback round to merge the base, or a `needs-decision` on a real conflict.
- A project whose tests share a port, database or simulator cannot run twice at once. Two registered projects use `worktree=make` for that reason, and Dux's own suite has load-sensitive tests. Cost: both gates flake and each needs recovery. `--after` is a poor cure: it waits for the first pull request to merge. See the open question.
- The coordinator takes about three times the wakes, so its 10-wake restart comes sooner. Cost: more session restarts per day.
- Spawns that overlap, or a spawn cut off after its wrapper started, put workers past the limit. Cost: tokens. Accepted, with the one-spawn-at-a-time rule in the skill.
- Two workers in one repository fetch into one `.git` at once and one fetch fails to lock a ref. Cost: a refusal to rerun, or one `/ship` step repeated.
- Woken parked sessions are not counted against the limit. Cost: the running count can pass the limit. Accepted.
- A task whose wrapper died while its session still sits in the tab reads `dead`, not `running`, and is not counted. Cost: one uncounted session until recovery tells the operator to end it.

## Open questions for the operator

1. Two workers in one repository whose tests share a simulator, port or database. Options:
   - Accept it, and run Task 11's same-repository pair on the repository most likely to clash,
     so the evidence decides.
   - Add one registry flag that keeps a project to one worker at a time, about 10 lines in spawn
     and one more test.
   Recommendation: accept for now. The flag is a second setting, and nothing yet shows the
   clash happens. Approving the plan as written means this option.
2. The default of 3 is a recommendation. Say another number at approval and it changes one
   line in Task 2.

## Global-instruction lines for the operator to change

The file is `~/.claude/CLAUDE.md`, section "One session, one task" and "Dux verified repository
prerequisites". Dux never edits it. Change these after Task 11, not before.

| Lines | Now | Change to |
|---|---|---|
| 162-163 | "Cross-repository deliverables use separate tasks and worktrees, executed sequentially." | "Cross-repository deliverables use separate tasks and worktrees. They run at the same time unless one needs the other's merge, which `--after` sequences." |
| 164-169 | "**When another worker is active, leave work queued.** Dux dispatches the next authorized task after verified capacity release. The cap applies across all registered repositories and worker harnesses. ... No capacity settings, repository-picker workflow, parallel execution, or reservations are introduced." | "**Dux runs several workers at once, up to the number in `config/max-workers` (default 3).** At the limit, work stays queued and Dux dispatches it when a worker finishes. The limit applies across all registered repositories. Every worker has its own worktree and branch. Required reviewers operate within their deliverable; they do not create another implementation owner. Do not launch a Herdr or tmux worker outside Dux for Dux-managed work. No repository-picker workflow or reservations are introduced." |
| 175-177 | "Spawn and round activation use the same admission check. A consistent parked marker exempts both the live wrapper and its process group; active or uncertain evidence blocks activation." | "A round goes only to a session whose parked marker is consistent; active or uncertain evidence about that session blocks the round. Rounds are not counted against the worker limit." |
| 190 | "Direct typing into parked tabs is outside the enforced one-active-worker guarantee." | "Direct typing into parked tabs is outside what Dux supervises and outside the worker limit." |
| 210-211 | "Activation still passes the global one-active-worker admission check." | "Activation still passes the worker limit." |
| 267-268 | "Separate repositories retain separate tasks and isolated worktrees, executed sequentially. The operator does not manage capacity or worktrees." | "Separate repositories retain separate tasks and isolated worktrees, sequenced only where one waits on another. The operator sets one number, the worker limit, and manages no worktrees." |

Lines that stay as they are: "One session, one task", "Implementation is owned by the project
worker; no nested parallel implementation" (that is about one deliverable, not the fleet), and
everything about the single coordinator lock.
