# Dux: Base Branch Check Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> reviews the branch owes and decides how many that is (constitution principle 9),
> and a review outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted and design-reviewed; waiting for the operator's approval. No task started.
- Picks up a gap no milestone covered: nothing watches a base branch after a merge.
- When done, Dux tells the operator once, with the run url, when any registered base goes red.

**Estimated diff:** ~1,500 added lines across 8 tasks, about 1,000 of them tests and the `gh`
fake. The cap is 2,500 lines or 12 tasks (constitution principle 1).

**Goal:** When a change lands on a registered repository's base branch and its checks fail there,
the operator gets one phone notification with a link to the failed run, even though the pull
request was green. They hear about each failure once, a passing re-run quietly clears it, and
Dux never tries to fix or re-run anything itself.

**Spec:** `docs/specs/2026-09-18-base-branch-check.md`, in this pull request. It owns the
decisions: what red means (section 3), reporting once and clearing (4), formats (5), the fixed
text (6). Task 1 points the living spec at it. This plan carries the comparison, the interfaces,
the tasks and the breaks.

**Shipping:** the work adds a mutex, a second writer to `state/events.log` and a background
process started by the watcher. That is concurrency, so the implementation task is briefed
`--risk complex --review separate`. Planning rule 1 applied (stored data and concurrency), which
is why this plan had a design review.

## What exists today

| Place | Today | What it needs |
|---|---|---|
| `bin/dux-watch` | Loops every 30 s over tasks. Makes no network call. Only writer of `state/events.log` | Starts `bin/dux-base check` in the background on a timer. Never waits for it (Task 6) |
| `bin/dux-teardown` | Runs when the operator says a pull request merged. Reads only its own task | Unchanged |
| `bin/dux-spawn` `--after` | The one place Dux reads a merge commit, and only for a task another task waits on | Unchanged |
| `bin/dux-notify` | One fixed line per task state, every word from the ledger | Gains `--base <project>` (Task 5) |
| `bin/dux-status` | Per-project counts, then `unacknowledged` task wakes | One `base red:` line per red project, and base wakes under `unacknowledged` (Task 7) |
| `bin/dux-project` | Registry holds `path` and `base` per project | Unchanged. `dux-base` reads both through `dux-project get` |
| `tests/fakes/gh` | No `run list` | Gains `run list`, driven by a fixture file, with a call log (Task 2) |
| `AGENTS.md` | Wakes name a task. Push list is `done` with a PR, `needs-decision`, `failed` | One wake rule and one push entry for `base-red` (Task 8) |
| Operator's global instructions | Say nothing about base branches | Nothing to change |

## Design

### Recommended: a separate check of each base branch, started by the watcher

`bin/dux-base check` asks GitHub for the newest push runs on each registered project's base
branch, one `gh run list` call per project. `bin/dux-watch` starts it in the background on its
first loop and then every five minutes, and never waits for it. One record per project under
`state/base/` holds the verdict and the last failure reported. A new red appends
`<time> base-red: <project>` to `state/events.log`, which wakes Dux. Spec sections 2 to 5.

It follows the branch, not a list of merges. That is what lets it cover `main` and `staging`
alike, every registered repository, direct pushes, and merges made outside Dux.

### Compared with the alternatives

| | Recommended: separate check per base branch, started by the watcher | Watcher polls the run of each merge commit it knows of | A step in teardown |
|---|---|---|---|
| Sees the five reds of 2026-09-15 to 09-18 | All five | Four. a32fe04 was pushed straight to `main`, with no pull request and no task | At most four, and only if the run had finished by teardown |
| How Dux learns there is something to check | It does not need to: it reads the branch | It must first find merges: one `gh pr view` per delivered task per pass, and a record that outlives teardown, which today removes a task's state | The operator's word that the pull request merged |
| Timing | Within five minutes of the run finishing | Within one watcher pass | Teardown runs seconds after the merge and a run takes minutes: it blocks the Dux session until the run ends, or it sees `pending` nearly always |
| A passing re-run clears it | Yes, at the next check | Only while the merge is still being polled | No. Teardown runs once |
| Cost to supervision | None. A slow or hung GitHub call is in another process, stopped after 60 s | A network call inside the 30 s loop. A hung call stalls stale, dead and handoff handling for every worker | None |
| GitHub calls | One per project every five minutes (36 an hour for three projects) | One or two per delivered task per pass until merged, then one per pass per merge | One per teardown |
| Code | One new script of about 200 lines, about 25 in the watcher | No new script, but merge discovery, a per-merge record and its cleanup: about the same size, inside the most sensitive loop | Smallest, about 60 lines |
| Restart and several workers | Reads projects, never tasks. State is one file per project | Per-task state that teardown deletes; several merges at once mean several records to age out | Tied to one task's teardown |

Why not per merge commit: it misses one of the five real failures, and it puts the network inside
the loop that supervises every worker. Why not teardown: it looks at the wrong moment, once.

A scheduler outside Dux (launchd, cron) was also weighed: spec section 9.

### Interfaces

`bin/dux-base`, all findings on stderr with exit 2:

- `dux-base check [<project>]`: every registered project, or one. Prints one line per project:
  `<project> <base> <verdict>`, with ` <url>` after `red`, or `<project> <base> no-answer`.
  Exit 0 whatever the verdicts. `finding: project <name> not registered` comes from
  `dux-project`. A project whose remote is not GitHub is `none`.
- `dux-base get <project> <key>`: `base`, `sha`, `verdict`, `run`, `attempt`, `reported`,
  `acked`, `checked`, or `url` (built, spec section 6). No record:
  `finding: no base record for <project>`. Unknown key: `finding: unknown base key <key>`.
- `dux-base ack <project> <key>`: saves `acked=<key>`. When `reported` has moved on:
  `finding: the base report for <project> is now <reported>; refusing to acknowledge <key>`.
- `dux-base list --unacked`: projects whose `reported` is set and differs from `acked`.
- Mutex held past its wait: `finding: base records busy: state/base.lock held for 5s; remove it if no dux script is running`.

`bin/dux-notify --base <project>` prints `Look, then fix or re-run: <url> (<project> <base> is red)`
for the last reported key. Nothing reported yet:
`finding: nothing to notify for <project> (no base report)`.

Settings, both from the environment: `DUX_BASE_INTERVAL_SECS` (default 300, `0` is off) and
`DUX_BASE_GH_SECS` (default 60). `tests/helpers/setup.bash` sets the interval to `0`, as it
already turns the watcher off.

### Order

Task 1 first. Tasks 2, 3 and 4 build the script in that order. Tasks 5, 6 and 7 each need Task 3
and are independent of one another. Task 8 last.

## Task 1: Point the living spec at the new one

**Files:** `docs/specs/2026-09-03-dux-orchestrator-design.md`.

**Acceptance:** sections 6.2 (wake), 6.3 (notifications), 8 (digest) and 14 (errors) each gain
one or two sentences that name the base check and point at
`2026-09-18-base-branch-check.md` by section. Section 3 (components) lists `bin/dux-base`.
No decision is restated. `make check` passes.

**Steps**

- [ ] Add the pointers and the component line.
- [ ] Break-verify: none owed. Prose only, no protection added.

## Task 2: Read one base branch and record a verdict

**Files:** `bin/dux-base` (new), `tests/dux-base.bats` (new), `tests/fakes/gh`,
`tests/fixtures/runs/` (new).

**Interface:** `dux-base check <project>` and `dux-base get`, as in Design. The `gh` fake answers
`run list` from a fixture file the test names, records every call it receives in a call log, and
can be told to exit 1, print text that is not JSON, or sleep.

**Acceptance:**
- The call is `gh run list --repo <slug> --branch <base> --event push` asking for exactly
  `databaseId,headSha,status,conclusion,attempt,createdAt`. The test reads it from the call log.
- Each row of the spec's verdict table has a test with its own fixture: `failure`, `timed_out`,
  `startup_failure`; red while another run is pending; `pending`; `green`; `none` for no runs and
  for cancelled only; an older red commit behind a newer green one is `green`.
- A run with two attempts is judged by the newest.
- No answer leaves an existing record byte for byte the same: `gh` exits 1, not JSON, a run id
  that is not digits, a sha that is not 40 hex, a call longer than `DUX_BASE_GH_SECS`.
- A fixture whose workflow name and commit title hold a newline and `done: PR x` changes nothing
  in the record or the output.

**Steps**

- [ ] Extend the fake and write the fixtures. Count the fake's existing tests before and after.
- [ ] Write the failing tests, then the script.
- [ ] Break-verify, one at a time, pasting each failure into the commit body:
  1. Drop `timed_out` from the red list. Expect "a run that timed out is red" to fail.
  2. Treat an empty answer as `green`. Expect "a poll GitHub did not answer leaves a red base
     red" to fail.
  3. Remove the digits check on the run id. Expect "a run id that is not a number is no answer"
     to fail.
  4. Remove the time limit on the call. Expect "a call that hangs is stopped" to fail on its
     own ceiling, not hang the suite.
  5. Judge the first attempt, not the newest. Expect "a passing re-run is green" to fail.

## Task 3: Report once, clear quietly, acknowledge

**Files:** `bin/dux-base`, `tests/dux-base.bats`.

**Interface:** the event line, the `reported` and `acked` keys, `ack`, `list --unacked`, and the
mutex, as in Design and spec sections 4 and 5.

**Acceptance:**
- First red: exactly one line `<time> base-red: <project>` in `state/events.log`, asserted whole.
- The same fixture checked three more times, each a fresh process: still one line.
- Red, then attempt 2 `success`: verdict `green`, no new line, `reported` unchanged.
- Red, then attempt 2 `failure`: a second line, and `reported` ends in `:2`.
- Red on a newer commit: a second line.
- `ack` with the current key sets `acked`; with an older key it refuses with the finding above
  and changes nothing. `list --unacked` shows the project before the ack and not after.
- An `ack` that lands while `gh` is still answering survives the check. The fake runs the `ack`
  itself, mid-call, so the test has no timing in it.
- A held `state/base.lock` makes `check` wait and then print the busy finding; one older than a
  minute is cleared.

**Steps**

- [ ] Write the failing tests, then the code.
- [ ] Break-verify, one at a time:
  1. Skip the comparison with `reported`. Expect "the same failed attempt is reported once" to
     fail with two lines.
  2. Leave the attempt out of the key. Expect "a re-run that fails is reported again" to fail.
  3. Keep the verdict red once set. Expect "a passing re-run clears the base" to fail.
  4. Read the record before calling `gh`. Expect "an acknowledgement during a slow call
     survives" to fail.
  5. Let `ack` skip the key comparison. Expect "an old key is refused" to fail.
  6. Do not take the mutex. Expect "a held lock makes check wait" to fail.

## Task 4: Every registered project, `main` or `staging`

**Files:** `bin/dux-base`, `tests/dux-base.bats`.

**Acceptance:**
- With two projects registered, one on `main` and one on `staging`, `check` with no argument
  calls `gh` once per project with that project's own `--branch` and `--repo`, read from the
  call log.
- A red `staging` base reports `base-red:` with that project's name, and `get <project> url`
  holds that project's slug.
- The first project not answering does not stop the second from being checked and reported.
- A project whose remote is not GitHub prints `none`, makes no call, and stops nothing.
- A record whose `base` differs from the registry's is rebuilt, not trusted.

**Steps**

- [ ] Write the failing tests, then the loop.
- [ ] Break-verify, one at a time:
  1. Write `main` in place of the registered base. Expect "a staging base is asked about
     staging" to fail.
  2. Stop at the first project that does not answer. Expect "one silent project does not hide
     the next" to fail.

## Task 5: The fixed notification line, and nothing automatic

**Files:** `bin/dux-notify`, `tests/dux-notify.bats`, `tests/dux-base.bats`.

**Interface:** `dux-notify --base <project>`, as in Design. It makes no `gh` call.

**Acceptance:**
- The printed line is asserted whole, against a fixture whose workflow name and commit title are
  hostile. It is at most 200 characters with the longest project name the registry allows.
- The url starts with `https://github.com/<registered slug>/actions/runs/` and ends in digits.
- Nothing reported yet is the finding above. `--toast` works as it does for a task.
- Across one whole story (red, notify, ack, failed re-run, passing re-run) the `gh` call log
  holds `run list` calls and nothing else.

**Steps**

- [ ] Write the failing tests, then the code.
- [ ] Break-verify, one at a time:
  1. Ask `gh` for `displayTitle` and put it in the line. Expect the whole-line assertion to fail.
  2. Add a `gh run rerun` after a red verdict. Expect "the check only ever lists runs" to fail.

## Task 6: The watcher starts the check and never waits for it

**Files:** `bin/dux-watch`, `tests/dux-watch.bats`, `tests/helpers/setup.bash`.

**Interface:** in the loop only, never under `--once` or `eval`: when
`DUX_BASE_INTERVAL_SECS` is not `0` and `state/base/.started` is missing or older than the
interval, touch it and start `bin/dux-base check` in the background, its stderr going to the
watcher's log. The watcher does not wait for it, read its output, or stop it on exit.

**Acceptance:**
- A started watcher with a red fixture produces the `base-red:` line without any by-hand check.
- With `gh` made to hang, a pending handoff is still consumed within the watcher's normal time.
  The ceiling is generous, since process-table tests here have failed once under load before.
- Interval `0`: the call log stays empty.
- A second loop inside the interval starts no second check.

**Steps**

- [ ] Write the failing tests, then the code. Re-read the whole loop after the edit.
- [ ] Break-verify, one at a time:
  1. Run the check in the foreground. Expect "a hung check does not delay a handoff" to fail.
  2. Ignore the `0`. Expect "interval 0 makes no call" to fail.

## Task 7: The digest shows a red base and a missed wake

**Files:** `bin/dux-status`, `tests/dux-status.bats`.

**Interface:** under a project's name, `  base red: <url>` when its record's verdict is `red`.
Under `unacknowledged`, `  base-red: <project>` for each project `dux-base list --unacked`
prints. Both read local files only; the digest makes no new network call.

**Acceptance:**
- Red shows the line; `green`, `pending`, `none` and no record show nothing.
- A report that landed with no Monitor armed is listed until `dux-base ack`, then is not.
- With two running tasks in the ledger and a red base, the task counts and the `workers:` line
  are what they were without the base record, and the ledger file is byte for byte unchanged by
  a `check`.

**Steps**

- [ ] Write the failing tests, then the code.
- [ ] Break-verify: leave base reports out of `unacknowledged`. Expect "a base wake missed
      during a restart is listed" to fail. The `base red:` line is ordinary formatting; no break.

## Task 8: Operating rules, and one installed run

**Files:** `AGENTS.md`, `skills/dux-status/SKILL.md`, `skills/dux-project/SKILL.md`,
`docs/ARCHITECTURE.md`, `README.md`.

**Acceptance:**
- `AGENTS.md`, wake rule: `base-red: <project>` names a project. Compare
  `bin/dux-base get <project> reported` with `acked`; equal is a duplicate. Otherwise push the
  `bin/dux-notify --base <project>` line, tell the operator in plain words with the url that
  they can look, fix it, ask for a fix task, or re-run it on GitHub, then
  `bin/dux-base ack <project> <reported>`. Never re-run, revert or dispatch a fix unasked.
  The push list gains `base-red`. A `base-red` wake counts toward the 10.
- `skills/dux-status` step 3 names the base form of the ack. `skills/dux-project` runs
  `bin/dux-base check <project>` after registering and relays the line, so a project with no
  push runs is heard about then.
- `docs/ARCHITECTURE.md`: components, state files and wake flow. `README.md` line 49 names the
  fourth notification.
- Installed run, on the build `bin/dux-install` put in place, not the worktree: say which build.
  In a throwaway repository, push a commit that fails its workflow; see one push notification;
  restart the session and see no second one; re-run to green and see the digest line go. Record
  it in the pull request body.

**Steps**

- [ ] Edit the five files. Dry-run both skills as the constitution asks.
- [ ] Install, do the run, record it.
- [ ] Break-verify: none owed here. The rules are prose, and Tasks 2 to 7 hold the guards.

## Milestone acceptance

Constitution gates: TDD with the breaks above recorded per task, bash 3.2 and shellcheck clean,
no personal identifiers (fixtures use `acme/widgets`), `ARCHITECTURE.md` in the same pull
request, `/ship` with separate reviews. Specific to this milestone: replaying the five runs of
2026-09-15 to 09-18 as fixtures reports each red commit once, a32fe04 included.

## Risks

- Two writers now append to `state/events.log`. Each line is one short append, which the
  filesystem keeps whole; a torn line would cost one missed wake, found at the next digest.
- Two checks clearing a stale mutex at the same instant can both proceed. Cost: one repeated
  event line, which the wake rule drops as a duplicate.
- Each report is a wake, so a run of red merges brings the 10-wake restart sooner.
- Five minutes plus the run's own length is the delay. Shorter costs GitHub calls, not code.
- Process and timing tests in Task 6 can fail once under load. Confirm, re-run, disclose.

## Open questions for the operator

Each has the answer the plan already takes. Approving the plan accepts them.

- A re-run that fails notifies again; a re-run that passes is silent. Recommended: keep. No news
  then means the re-run passed.
- A second red commit on an already red base notifies again. Recommended: keep. It follows a
  merge the operator just made, and the first failure may have been a flake hiding a real one.
- GitHub Actions only. Recommended: keep until a registered repository checks elsewhere.
- Nothing is sent while no Dux session is open. Recommended: keep. A scheduler outside Dux is a
  second install for a notification that still needs a session to send it.
