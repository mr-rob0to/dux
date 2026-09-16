# A delivered pull request takes feedback in the same session

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, never at the ship
> gate. Do not run a code review of your own work: `/ship` owns the branch's one review
> and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-15 by a Dux plan worker. The brief asked for a new task that continues
  an old task's branch; the operator redirected it mid-flight to "the existing worker
  waits for feedback, sent through Dux". One independent design review the same day:
  fourteen findings, all taken, recorded at the bottom.
- Re-cut the same day, after the operator asked why the design was this large for what
  it does. The wrapper now stays alive across a park instead of exiting and being started
  again once per round. That removed a second wrapper process, the `start_wrapper`
  helper, the `--round` flag and every check that reattaching to a released session
  needed: about 275 lines, and the first critical review finding stops being reachable
  rather than being answered. Spec section 12 records the decision.
- Picks up the cost pull request #44 paid: a one-line correction needed a second task,
  worktree, gate and pull request (#45).
- Merges as one ship PR of nine tasks. When it merges, a worker with an open pull request
  waits in its tab; `bin/dux-round <id> --file <f>` sends the operator's feedback into it.
- **Amended 2026-09-15** by the [Dux simplification amendment](../specs/2026-09-15-dux-simplification-rollout.md),
  section 6.1, and delivered as milestone 2 of the
  [rollout plan](dux-simplification-rollout.md), tasks 11 to 19. All nine tasks below are
  retained, none moves to a follow-up, and this file keeps its own historical evidence:
  the review findings, the decisions and every box already ticked stand as written.

**Estimated diff:** ~1,625 added lines across 9 tasks, re-cut down from ~1,900. The cap
is 2,500 lines or 12 tasks (constitution principle 1). Sizing procedure: roadmap, "How a
milestone is sized". Per task, from this repository's density (the wrapper's bats file is
43 tests, spawn's 32): Task 1 ~120, Task 2 ~55 net, Task 3 ~300, Task 4 ~170, Task 5
~220, Task 6 ~300, Task 7 ~100, Task 8 ~60, Task 9 ~300. **Amended:** Task 8 does not
move to a follow-up. A round's `/ship` stops at `gh pr create` without it, so same-PR
updating is required support and cannot be deferred to meet a size limit. If the running
total passes 2,200 before Task 8, reduce incidental scope or obtain a revised split that
keeps all nine tasks together; do not drop Task 8.

**First, before Task 1 is written:** measure `herdr pane run` against a live Claude Code
session in a pane, not a shell (spec section 5, "Herdr, not measured"). Everything from
Task 3 on assumes the line reaches the session's prompt. If it does not, the Herdr half
of Task 1 becomes `herdr pane send-text` plus a separate Enter, or the milestone ships
tmux-only with a finding on the Herdr path, and this header records which.

**Goal:** After a worker opens its pull request, the operator can review it, say what to
change in the Dux session, and have the same worker make the change on the same branch
and pull request, as many as eight times, then merge and tear down once. No second task
is ever dispatched to correct a delivered pull request.

**Spec:** `docs/specs/2026-09-15-feedback-rounds-on-a-delivered-pr.md`, every section.
The pointers it adds to the orchestrator, interactive-sessions and one-session specs are
in this pull request. Every design decision is settled there; the tasks below point at
sections and add only what an implementer cannot derive.

**Deviations:** none. Constitution principle 6 gains one clause in Task 9, a PATCH.

## Design

Order matters. The adapter verb (1) and the moved helpers (2) are what everything else
calls. The park (3) leaves a `done` task with a live wrapper and a live process group,
which `dux-teardown` refuses and `dux-spawn` reads as a busy fleet, so the guard and
teardown changes (4) come straight after it and the tree is inconsistent for exactly one
task. Task 3 parks and waits; Task 5 fills in what the wait does when a round arrives, in
the same process, which is why they are the same script and not two. `dux-round` (6) is
the operator's end of it; proof (7) closes it; `/ship` (8) is what lets a round's gate
finish; the documents (9) go last with the constitution bump.

The fake harness (`tests/harness`) needs one new verb for Tasks 3, 5 and 6: `idle`, which
blocks until a line arrives and then replays the script named by
`FAKE_WORKER_ROUND_SCRIPT`. Under tmux the line arrives on stdin from `send-keys`; the
Herdr fake's `pane run` on a pane whose harness is idle appends the line to a per-pane
input file the fake harness reads. Task 3 adds the verb and both deliveries.

Run ids for rounds are `<channel nonce>r<n>`, alphanumeric, so every existing equality
check on `run=` holds without change.

## Task 1: `dux-backend prompt`

**Files:** `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh`,
`tests/fakes/herdr`, `tests/backend-adapter.bats`.

**Interface:** `dux-backend prompt <endpoint> <text>`. Sends `<text>` and Enter to the
pane's foreground process (spec section 5). Herdr: `herdr pane run <pane> <text>`, or
whatever the measurement in the header settled. tmux: `send-keys -t <target> -l --
<text>` then `send-keys -t <target> Enter`. Exit 0 on success; a backend that fails is
`finding: <backend> could not type into <endpoint>`. `own_endpoint` applies as for every
by-endpoint verb.

**Acceptance:** on both backends, a pane running a process that reads stdin receives
exactly `<text>` followed by a newline; a wrong-backend endpoint is the existing finding;
a failed send is a finding and not a silent success.

**Steps**

- [ ] Record the Herdr measurement from the header in the adapter's comment, as the
      other measured facts in that file are recorded.
- [ ] Write the adapter tests first: delivery to a foreground process on both backends,
      the finding on a failed send, the endpoint ownership refusal.
- [ ] Add `backend_prompt` to both adapters and the `prompt` case to `dux-backend`.
- [ ] Extend the Herdr fake's `pane run` to deliver to an idle fake harness (Design).
- [ ] Break-verify: drop the `send-keys Enter` call from the tmux adapter, run, confirm
      the delivery assertion fails because the reader never sees a line, restore, paste
      the failure into the commit body. Do not break `-l`: measured 2026-09-15 on tmux
      3.6a, a one-argument line that is not a key name is delivered literally with or
      without it, so that break would pass (spec section 5).

## Task 2: two helpers move into `dux-env`

**Files:** `bin/dux-env`, `bin/dux-spawn`, `bin/dux-worker-wrap`, `tests/dux-env.bats`.

**Interface:** `fleet_busy <id>` prints `<why> <other>` and returns 0 when another task's
worker may be alive, else returns 1: the body of `dux-spawn`'s `another_worker`, moved
verbatim, comments included. It moves because `dux-round` runs the same guard.
`stop_pgid <pgid>` is the wrapper's `stop_group` with the group as an argument, same
signals, grace and test-only switch; `dux-teardown` calls it in Task 4. Nothing else
moves. In particular `dux-spawn` keeps its wrapper start where it is, because it stays
the only thing that ever starts a wrapper.

**Acceptance:** `dux-spawn` and `dux-worker-wrap` call the helpers and keep every
refusal wording; every existing test in `tests/dux-spawn.bats` and
`tests/dux-worker-wrap.bats` passes unchanged; both functions have direct tests
in `tests/dux-env.bats`.

**Steps**

- [ ] Count the lines of each moved block before and after; the counts match.
- [ ] Move `another_worker` as `fleet_busy`; `dux-spawn` maps its answer to the same
      six findings.
- [ ] Move `stop_group` as `stop_pgid`; the wrapper calls it with `$pgid`.
- [ ] Break-verify: make `fleet_busy` skip the pgid read, run, confirm
      `tests/dux-spawn.bats:552`, "another task's live harness group refuses the start,
      and an unreadable one blocks it", fails, restore, paste.

## Task 3: the wrapper parks and waits after `done: PR <url>`

**Files:** `bin/dux-worker-wrap`, `templates/worker-settings.json`, `tests/harness`,
`tests/dux-worker-wrap.bats`, `tests/e2e-supervise.bats`.

**Interface:** spec section 3. A third hook in the settings template touches
`__CHANNEL__/stopped` on `Stop` only; `DUX_WRAP_IDLE_SECS` (default 60) bounds the wait
for that file. When the published line is `done: PR <url>` the wrapper does not exit. It
skips `stop_pgid` and `cleanup_channel`, **writes the run-bound parked marker only after
this run's `Stop` event and leaves `state/<id>.ship-receipt` where the watcher validates
it until that run's handoff is consumed** (amended; spec section 3), logs
`worker for <id> parked in its tab; feedback goes through dux-round` once, and then polls
once a second for
`data/tasks/<id>/round-<n>.md`, `n` one above its own count of rounds run. The poll
writes nothing to the log per pass. This task stops at the wait: the loop body is Task 5,
so here the loop returns and the wrapper exits 0 once the pass budget in the test-only
`DUX_WRAP_PARK_MAX_PASSES` runs out, which is empty and unbounded in production. On the
parking path the final import drops the "kept writing after its terminal status" and
"left a status line unfinished" rules. The result context gains `round=0` and
`since=<tip of refs/heads/dux/<id> at run start>`.

**Acceptance:** after a fake worker writes `done: PR <url>` and idles, the wrapper is
still running and `state/<id>.pid` still names it, the group is alive, the three
references exist, the receipt is at its delivered name, the handoff is published and the
watcher applies `done`; a worker that writes bytes after its terminal line still parks;
the park line is logged once and many poll passes add nothing after it; after
`done: report`, `failed:` or a violation the wrapper exits, the group is gone, the
channel is cleared and both rules still bite; the `stopped` wait ends early when the file
appears and at the bound when it does not, and the proof runs in both cases.

**Steps**

- [ ] Add the `Stop`-only hook to the settings template and the fake harness's `idle`
      verb and scripted `stopped` touch (Design).
- [ ] Write the tests: a live wrapper and group, parked references and renamed receipt
      after `done: PR`; a silent poll log; post-terminal bytes tolerated only on that
      path; unchanged endings for the other four; the early and bounded `stopped` wait;
      `round=0` and a forty-hex `since`.
- [ ] Implement: wait for `stopped`, prove, publish, then either park into the poll loop
      or stop, clean and exit.
- [ ] `tests/dux-teardown.bats:277` and the e2e teardown step now meet a live wrapper and
      group on a `done` task. Mark both `skip` with a one-line reason naming Task 4,
      which restores them. No other suite is expected to move.
- [ ] Break-verify: make the park branch also skip `publish_handoff`, run, confirm the
      "watcher applies done" assertion fails, restore, paste.

## Task 4: the guard and teardown know a parked session

**Files:** `bin/dux-env` (`fleet_busy`), `bin/dux-spawn`, `bin/dux-teardown`,
`tests/dux-spawn.bats`, `tests/dux-teardown.bats`, `tests/e2e-supervise.bats`.

**Interface:** spec sections 7 and 8. **Amended:** `fleet_busy` exempts the other task on
its run-bound parked marker, not on a ledger state of `done`, and the exemption covers the
wrapper pid and the pgid together. Every other reading is unchanged; an unreadable ledger,
an unreadable marker and a marker naming another run all still refuse. `dux-teardown` on a `done`
task ends two processes in order: the parked wrapper named by `state/<id>.pid`, with
`TERM`, then the harness group through `stop_pgid`. The wrapper goes first so it cannot
pick up a round file that arrives mid-teardown. Either one surviving is the existing
finding; on `failed` the refusal is unchanged. Teardown also removes
`state/<id>.ship-receipt.delivered`.

**Acceptance:** a spawn beside a parked task goes ahead; beside a parked task whose
ledger reads `running` it refuses as today; teardown of a parked task ends the wrapper
and the group, leaves nothing polling, removes the worktree, closes the pane and leaves
no delivered receipt; a round file dropped into the task folder during a teardown is
never acted on; teardown of a failed task with a live group refuses; the two tests Task 3
skipped are un-skipped and green.

**Steps**

- [ ] Un-skip the two tests from Task 3 and see them fail for the right reason.
- [ ] Reorder `fleet_busy`'s reads and add the `done` exemption.
- [ ] Add the wrapper stop, the group stop and the delivered-receipt removal to
      teardown's `done` path, in that order.
- [ ] Break-verify: make the exemption apply to every state, run, confirm the
      "parked task whose ledger reads running" test fails, restore, paste.
- [ ] Break-verify: stop the group before the wrapper, run, confirm the test that asserts
      nothing is left polling fails, restore, paste.

## Task 5: the wrapper runs a round in place

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** spec section 5. The poll loop from Task 3 gains its body. No flag is
parsed and no process is started: this is the same wrapper carrying on. On seeing
`data/tasks/<id>/round-<n>.md` it runs `kill -0` on the group it already holds, then
computes the run id `<channel nonce>r<n>`, writes a new `state/<id>.run` and
`state/<id>.result-context` carrying `round=<n>` and `since=<tip>`, rewrites the ship
recorder under `chmod 600`, write, `chmod 500` because that file is mode 500 and a plain
redirect onto it fails, seeks `accepted` and the report offset to the outboxes' current
sizes with both caps measured past `accepted`, copies the round file to
`<channel>/round-<n>.md` at mode 400, types `Read <channel>/round-<n>.md and follow it.`
through `dux-backend prompt`, and re-enters the import loop. A group that has gone
publishes `failed: the session for <id> was ended in its tab before round <n> could run`,
cleans up and exits. `done: PR <url>` parks again with the round count up by one;
anything else stops the group, clears the channel and exits.

**Acceptance:** with a parked fake harness, a round file appearing makes the wrapper type
the line, the fake replays `FAKE_WORKER_ROUND_SCRIPT`, and a `done: PR` there is proved
with a receipt for the new run id and parks again; the parked run's terminal line and
report are not read a second time; anything the worker wrote while parked is skipped, not
judged; `run=`, `round=<n>` and `since=` name the new run in both `state/<id>.run` and
the context; `state/<id>.pid` names the same process before, during and after the round;
two rounds in sequence each get their own run id and their own receipt; a status outbox
already near `STATUS_CAP` from earlier rounds does not trip the cap on a small round; a
group killed while parked produces the ended-in-its-tab failure.

**Steps**

- [ ] Tests first, one per acceptance clause.
- [ ] Implement the loop body in the order above, with the recorder rewrite and the
      outbox seek before the line is typed, never after.
- [ ] Break-verify: drop the `kill -0`, run, confirm the "ended in its tab" test fails,
      restore, paste.
- [ ] Break-verify: leave `accepted` where the parked run left it, run, confirm the
      "terminal line is not read again" test fails with the second-terminal violation,
      restore, paste.

## Task 6: `dux-round`

**Files:** `bin/dux-round`, `templates/round.md`, `tests/dux-round.bats`,
`docs/ARCHITECTURE.md` (component line only; the flow text is Task 9).

**Interface:** spec section 4, all eleven steps and the round file. Usage line:
`usage: dux-round <id> --file <path>`. Success prints `round <n> sent to <id>`. The
rendered file is refused over 40 lines. `dux-round` starts nothing and types nothing:
step 5 proves a live parked wrapper through `state/<id>.pid` alongside the pgid, portal
and endpoint checks, and step 10 moves the ledger to `running` and unacks it, then
renames `data/tasks/<id>/.round-<n>.tmp` onto `data/tasks/<id>/round-<n>.md`, which is
the trigger the parked wrapper is waiting for. A rename that fails puts the ledger back
to `done` and is a finding. The `gh` calls are `gh pr view <url> --json
state,headRefName,baseRefName`; the fake `gh`'s `FAKE_GH_PR_STATE` drives them.

**Acceptance:** every refusal in section 4 has a test that reaches it and asserts the
wording, the pending-handoff and the dead-wrapper refusals included; the happy path
renders `round-1.md` with the six tokens filled and the feedback verbatim, leaves the
ledger `running` with `acked=-`, and a wrapper parked in a real tmux window (as the
wrapper tests do) picks the file up and produces a second `done` event; the ledger is
`running` before the file exists, never after; no temporary file is left behind by any
refusal; a ninth round is refused with the file count at eight.

**Steps**

- [ ] Write `templates/round.md` (spec section 4, "The round file") and the tests.
- [ ] Implement the checks in the spec's order; nothing is written before all pass.
- [ ] Render to `.round-<n>.tmp`, move the ledger, then rename; put the ledger back if
      the rename fails.
- [ ] Break-verify: drop the `state/<id>.pid` liveness read from step 5, run, confirm the
      dead-wrapper refusal test fails, restore, paste.
- [ ] Break-verify: make the base-ancestry check pass unconditionally, run, confirm
      the "behind base" refusal test fails, restore, paste.

## Task 7: proof of a round

**Files:** `bin/dux-result`, `tests/dux-result.bats`.

**Interface:** spec section 6, **as amended**: a round's receipt carries its own review
mode and the phases that mode requires, not a fixed five, and a combined receipt never
satisfies a task classified separate. `verify` reads `round` and `since` from the result
context. `round` absent or `0`: unchanged. Otherwise `since` must be forty hex
characters (a finding, it is Dux's own file) and an ancestor of `refs/heads/<branch>`
(else `the round rewrote history the operator already reviewed on <branch>`, exit 1).
A round that adds no commit is not rejected. The rejection applies to `plan` and `ship`.

**Acceptance:** a ship context with `round=1` and `since` at the parent of the tip
proves; `since` equal to the tip proves, and the run parks again; `since` on a rewritten
branch is `ended` with the history reason; a `since` that is not forty hex characters is
a finding; `round=0` with a bad `since` still proves, because a first run's `since` is
recorded and not judged.

**Steps**

- [ ] Tests first, the five cases above, against the fixture repository the file
      already uses.
- [ ] Implement in `verify`, before `read_changes`.
- [ ] Break-verify: invert the ancestry test, run, confirm the rewritten-branch case
      proves when it should not, restore, paste.

## Task 8: `/ship` edits a pull request it finds

**Files:** `skills/ship/SKILL.md`, `tests/contract.bats`.

**Interface:** spec section 9. In "Opening it": look up an open pull request for the
current branch into `$BASE` with `gh pr list --head "$BRANCH" --base "$BASE" --state
open --json number --jq '.[0].number // empty'`; when one is found, `gh pr edit
<number> --body-file "$BODY"` with no `--title`; otherwise `gh pr create` as today. The
docs-only paragraph names the same lookup. One sentence says why: `gh pr create` refuses
a branch that already has one.

**Acceptance:** the contract test pins the lookup line and the no-title edit; the skill
is dry-run against a throwaway repository twice on one branch, and the second run edits
the first run's pull request; the excerpt goes in the pull request body.

**Steps**

- [ ] Pin the two lines in `tests/contract.bats` first; see them fail.
- [ ] Edit the skill.
- [ ] Dry-run twice on a throwaway repository; paste the excerpt into the PR body.
- [ ] Break-verify: change the pinned edit line to carry `--title`, run, confirm the
      contract test fails, restore, paste.

## Task 9: the documents, the brief, the notification

**Files:** `AGENTS.md`, `templates/brief.md`, `bin/dux-notify`, `tests/dux-notify.bats`,
`tests/dux-brief.bats`, `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`,
`docs/ARCHITECTURE.md`, `docs/constitution.md`, `tests/contract.bats`.

**Interface:** spec section 10. `dux-notify` for `done` with a url:
`Review, then merge or send feedback: <url> (<project> <shape>)`. The brief's terminal
rule and the plan and ship done lines say "wait at your prompt" as section 10 words
them; the rendered brief stays under 100 lines with two lines added. `AGENTS.md`: the
lifecycle line gains `done -> running` on a round, the wake rule for `done` names the
new notification, and a "Feedback" bullet names `feedback.md` and `bin/dux-round`;
under 150 lines. `skills/dux-dispatch` gains a "Feedback on a delivered pull request"
section and its teardown section says teardown ends the parked session.
`skills/dux-recover` says what a round that ends `failed` or `ended` leaves (spec
section 7). `ARCHITECTURE.md`: `dux-round` and `prompt` in the component list, the round
in the dispatch flow, the parked ending in "The terminal handoff" (its pinned sentences
kept), and `done` in the wake table. Constitution principle 6: after "neither reads it
nor relays it", one clause: the one thing Dux writes there is a fixed line per round
naming a file it rendered. **Amended:** the version is not prescribed here. Bump whatever
version milestone 1 of the rollout left, by the governance rule in force when this lands,
with Last Amended set to that day and a paragraph in the governance history like the
previous entry's. Do not write or restore 2.0.9 because this file once named it.

**Acceptance:** `tests/contract.bats` pins the new `AGENTS.md` wake wording and the
`dux-dispatch` feedback section; every existing pin still holds; `AGENTS.md` is under
150 lines; a rendered ship brief is under 100 lines and carries the wait rule.

**Steps**

- [ ] Update the notify and brief tests first, then the two scripts and the template.
- [ ] Edit `AGENTS.md`, both skills, `ARCHITECTURE.md`, the constitution.
- [ ] Add the contract pins for the wake wording and the feedback section.
- [ ] Break-verify: drop the feedback section from the dispatch skill, run, confirm the
      new contract pin fails, restore, paste.

## Milestone acceptance

The constitution's quality gates, plus: on a real Claude Code worker in a real tab on
this machine, one full loop: dispatch a bounded ship task in a throwaway project, let
it deliver, run `bin/dux-round` with a one-line feedback, watch the same session make a
commit and update the same pull request, get the second `done` wake, tear down and see
the tab close. `ps` before the round and after it must show the same wrapper pid, which
is the re-cut's whole claim. The transcript excerpt goes in the pull request body with
the added-line count against the estimate.

## Risks

- `herdr pane run` against a live Claude Code prompt is unmeasured. The header makes the
  measurement the first thing that happens and says what the milestone becomes if it
  fails. Everything from Task 3 on assumes it works.
- A parked session that the operator ends with `/exit` leaves a live wrapper polling for
  a round it could no longer run. `dux-round` refuses on the pgid check and names
  teardown; a round already in flight fails with the ended-in-its-tab line. Both are the
  right answer.
- A wrapper now lives as long as its task rather than as long as one run. A poll loop
  that spun instead of sleeping would burn a core for days rather than seconds. The loop
  is a `sleep 1` and a file test, and Task 3 asserts the log stays silent across many
  passes so a chatty loop is caught there.
- The idle wait reads a `Stop` hook. If it does not fire on this Claude Code, every
  delivery costs sixty seconds; the proof still runs.
- A round's `/ship` runs a full review of the whole branch for a ship task. That is the
  intended cost. A plan round runs no gate, as a plan first run runs none.
- A round that fails leaves the task off `done` and no further round is possible on it.
  Accepted, spec section 7.

## Open questions for the operator

None. The spec's section 12 records the decisions with the alternative each beat.

## Design review

One independent review on 2026-09-15 by a fresh session that had not seen the design,
against the spec, the plan, the constitution and the scripts they cite. **The reviewer
was Opus 5, not Fable:** Fable returned "You're out of usage credits" and the fallback
is recorded here rather than left silent. Fourteen findings; every code citation was
checked against the file before it was acted on, and the tmux half of finding 6 was
measured rather than argued. All fourteen were taken.

| # | Finding | Outcome |
|---|---|---|
| 1 | Critical: the round set the ledger to `running` before its wrapper existed, and nothing clears `state/<id>.pid` between runs, so a watcher pass would read the parked run's exited wrapper as a dead worker and emit a false `dead`; the undo path then could not put the task back. | Accepted, confirmed: only `dux-teardown:120` removes that file. The ledger now moves last, after the wrapper's pidfile is live, which is the order `dux-spawn` already uses (spec 4 step 11, Task 6). |
| 2 | Critical: any round not ending `done: PR` took the task off `done` and deleted the delivered `/ship` receipt, so the delivery could never be re-proved and no further round was possible; the "round added no commit" rejection made a correct answer trigger it. | Accepted in two parts. The no-commit rejection is dropped: it manufactured the worst case (spec 6). The receipt is renamed to `.delivered` at park rather than deleted, and spec 7 states plainly what a failed round leaves: the pull request open, mergeable, its url still in the ledger, and no further round. A recovery verb to republish `done` was considered and dropped as tidiness (spec 12). |
| 3 | Important: the beat file cannot mean "at the prompt" because `PostToolUse` touches it too, and whole-second mtimes hide a `Stop` in the same second. | Accepted. A third hook touches a `stopped` file on `Stop` alone, and the wait reads that (spec 3, Task 3). |
| 4 | Important: parking moved the stop after `import_proposals final`, so a live session's post-terminal bytes or unfinished line would turn a good delivery into `failed`. | Accepted. Both rules are off on the parking path only (spec 3). |
| 5 | Important: a handoff left unconsumed by a failed mid-consume write would be rejected forever once the round overwrote `state/<id>.run`, hiding every later handoff behind the gap. | Accepted. `dux-round` refuses when `next_handoff` prints anything (spec 4 step 3). |
| 6 | Important: the spec stated `herdr pane run` works against a live session as fact while the plan called it unmeasured. | Accepted. tmux measured here on 3.6a and written into spec 5 with the result; Herdr recorded as unmeasured, measured before Task 1, with the fallback in the plan header. |
| 7 | Important: the ship recorder is mode 500, so rewriting it in place returns `EACCES`. | Accepted. The `chmod 600` / write / `chmod 500` sequence is named in spec 5 and Task 5. |
| 8 | Important: `dux-result` calls `check_receipt` only for `ship`, so a plan round proves with no gate and spec 9's "one review per round" was false for half the shapes rounds accept. | Accepted, confirmed at `bin/dux-result:330` against `:402-408`. Specs 6 and 9 now say a plan round runs no gate, as a plan first run does not. |
| 9 | Minor: Task 2's break-verification named a test that does not exist. | Accepted. It now names `tests/dux-spawn.bats:552` by its real title. |
| 10 | Minor: Task 1's break-verification would have passed, which the constitution makes a finding of its own. | Accepted and measured: on tmux 3.6a a one-argument line that is not a key name is delivered identically with and without `-l`. The break is now the missing `Enter`, and the measurement is in spec 5 so nobody retries the `-l` break. |
| 11 | Minor: both outbox caps are measured over the whole file, so eight rounds would share one budget and tripping it is a violation. | Accepted. Both are measured over the region past `accepted` (spec 5, Task 5). |
| 12 | Minor: the accepted limit about the long-running mark was wrong in both directions. | Accepted, corrected in spec 13: a parked task is never marked, and a round on an old brief is marked at once. |
| 13 | Minor: the guard and teardown changes sat four tasks after the park, leaving the tree inconsistent in between, and the plan accounted only for the e2e test. | Accepted. They are now Task 4, straight after the park, and Task 3 names the two tests it skips and Task 4 un-skips. |
| 14 | Minor: the one-worker exemption assumes a parked session is idle while the brief invites the operator to type into it. | Accepted as a note, recorded in spec 8 and 13, with the `stopped` file named as what a later milestone could check instead. |

**Finding 1's answer was superseded the same day, by the re-cut.** The operator asked why
the design was this large. The answer was that most of it existed so a second wrapper
process could reattach to a session the first had let go, so the wrapper now stays alive
across a park instead (spec section 12). Finding 1 was real and the reviewer was right
about the code: `dux-teardown:120` is the only line that removes `state/<id>.pid`. But
the ordering fix it produced is gone, because there is no longer a moment when that file
names a process that has ended, so the watcher cannot read a gap that does not exist. The
finding stays recorded as it was raised; this paragraph is what replaced its answer.
Findings 7 and 11 still hold and moved with the recorder rewrite and the cap windows into
Task 5's new shape. Finding 13's ordering still holds. No other finding is touched, and
none of the re-cut's changes were reviewed independently: that is the one thing this plan
now carries unreviewed, and it is named here rather than left for the reader to notice.

Claims the reviewer confirmed against the code, which stand: the outbox accounting works
as designed; the new run id satisfies every `run=` equality unchanged; relaxing
teardown's refusal for `done` alone is right and a hand-killed session is caught by the
round's own check; `dux-doctor` looks at none of these files, so a parked task does not
fail session start; the end of a round cannot produce a false `dead`, because the
handoff is published before the wrapper moves on and `target_for` reads handoffs before
liveness, which the re-cut only strengthens, because the wrapper is alive throughout; `ship-guard` genuinely starts a round at zero phases; and the constitution
compliance of every task, including the 2.0.9 PATCH reading.
