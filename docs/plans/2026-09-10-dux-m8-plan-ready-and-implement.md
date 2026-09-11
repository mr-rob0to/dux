# Dux Milestone 8: A plan pauses, the operator answers, the same worker builds it

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-10, design-reviewed twice (the records are at the end of the milestone
  7 plan; from the first, findings 1, 3, 4, 7, 11, 14 shaped this one; from the second,
  findings 2, 5, 6, 8, 10, 18 and 22), awaiting the operator. This is the
  plan-ready half of the milestone 7 plan in pull request #26, moved behind the resume
  mechanism that milestone 7 now delivers on its own.
- Follows milestone 7 (`2026-09-10-dux-m7-resume-any-worker.md`), which lands the
  session id, the round files, `dux-spawn --resume` and `--fresh`. Every task here
  depends on it.
- When this merges, a plan task pauses at `plan-ready`, the operator approves, changes,
  answers or drops it in the Dux session, and the same session implements and ships.

**Estimated diff:** ~1,600 added lines across 7 tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). Sizing procedure: roadmap, "How a milestone is sized". Stop
rule: if the running total passes 2,100 before Task 6, Tasks 6 and 7 move to milestone
9 and this header says so.

**Goal:** A plan comes back to the Dux session instead of to a pull request the
operator must find, they answer it there, and the worker that wrote it goes on to build
it in the same branch and pull request.

**Spec:** `docs/specs/2026-09-10-one-session-planning.md` sections 3, 4, 5, 7, 9, 12.
Every design decision this milestone needs is settled there and in the orchestrator
spec's pointers (sections 5.1, 5.3, 5.4, 5.5, 17).

**Deviations:** constitution principle 6 says `.env` files are copied into worktrees only
for `ship` tasks. This milestone copies the project's committed examples for a `plan`
task that is not plan only too, because its worker goes on to implement (spec section
3). Task 7 amends the principle in the same pull request, as a PATCH: what may be copied
does not change, only which tasks get it.

## Design

Only what the spec leaves to the implementer.

- **Run kind** gains `plan` and `implement`. `dux-spawn` passes `plan` for a `plan`
  shape whose brief has no `- Plan only: yes` line and `plan-only` when it has one, on a
  first spawn; on a resume, from the round file's first line, where `dux-brief` writes
  `implement` for approve and `plan` for change, as milestone 7 built for answer and
  retry. The wrapper only copies it.
- **Handoff line for a plan round:** `plan-ready: <path> tasks 1-K at <sha>`; the watcher
  checks it where it checks a `done: PR ` line's grammar, and rejects it whole otherwise.
- **`state/<id>.plan`** is five `key=value` lines (spec section 5), written by the watcher
  with a temp file and one rename. The approve round file is the record of the
  approval; the wrapper copies the state file's `sha` into an implement run's context
  as `approved=`.
- **Frozen text** (spec section 9) is checked with `git show <sha>:<path>` against
  `HEAD:<path>` after `sed 's/\[ \]/[x]/g'` over the span from the first `## Task`
  heading; the spec files are compared by blob id.
- **Order:** Tasks 1 and 2 are the state and the proof; 3 the worker side; 4 and 5 the
  answer path; 6 and 7 the operator side and the documents.

## Task 1: The `plan-ready` state and its state file

**Files:** `bin/dux-ledger`, `bin/dux-watch`, `tests/dux-ledger.bats`, `tests/dux-watch.bats`.

**Interface:** `valid_state` accepts `plan-ready`; `list --unacked` includes it.
`read_handoff` accepts the `plan-ready` status word, and rejects the handoff whole
(`reject:`, which writes nothing, as a malformed `done: PR` line is rejected today) when
the path fails `docs/plans/[A-Za-z0-9._-]+\.md` or the sha is not 40 hex; it takes its
receipt cross-check from the context's `kind` (`ship` or `implement`) instead of its
shape. `consume_handoff` on an accepted `plan-ready: <path> tasks <a-b> at <sha>` line
writes `state/<id>.plan` (version, id, path, tasks, sha) with one rename, after the
event and before the ledger, marked as the other steps are so a crash replays it. `status_state` treats `plan-ready` as a
known word. `watched_ids` never lists a `plan-ready` task except to finish an
unconsumed handoff, exactly as it never lists `needs-decision` or `blocked` today.
`target_for` on a `plan-ready` ledger state with no handoff prints
`skip:plan-ready waits for the operator`.

**Acceptance:** a fake handoff with a `plan-ready` event moves the ledger to `plan-ready`,
raises exactly one event line, lists under `--unacked`, and leaves `state/<id>.plan` with
the five keys; a task in `plan-ready` with no pidfile is never marked `dead` over three
watcher passes; a malformed path is rejected with nothing written to the status log, the
events log or the ledger, and the watcher's next pass logs it once and writes nothing;
a `done` handoff with `kind=implement` and no complete receipt is rejected.

**Steps**

- [ ] Ledger: the state; `--unacked`; a `set` and `list --state plan-ready` round-trip.
- [ ] Watcher: reject a bad path or sha in `read_handoff`; parse a good line, write the
      state file atomically; the receipt cross-check by kind.
- [ ] Watcher: exclude `plan-ready` from liveness; keep the crash-replay path for its handoffs.
- [ ] Break-verify: remove the path guard, run, confirm the malformed-path test fails;
      restore. Break the `dead` exclusion, confirm the three-pass test fails; restore.
      Remove `plan-ready` from `--unacked`, confirm; restore. Paste all three failures
      into the commit body.

## Task 2: `dux-result` proves a `plan` round and an `implement` round

**Files:** `bin/dux-result`, `tests/dux-result.bats`.

**Interface:** `verify` for `kind=plan` runs spec section 5's seven checks in order and
prints `plan-ready: <path> tasks 1-K at <sha>`; each failure exits 1 with the reason
wording the spec gives, with no worker path repeated back when the path itself is what
failed. The pushed check compares `refs/remotes/origin/<branch>` with the tip through
`dgit`. `read_changes` learns the raw status letter so "added" is distinguishable from
"modified", and check 4 holds every changed path to `[A-Za-z0-9._-]+` per segment and
200 characters, since those paths are printed to Dux as links. `check_plan_tasks` gains a mode that requires at least one box, ticked or
not, per task, used by the plan proof; the ship proof keeps its all-ticked mode.
`verify` for `kind=implement` is the ship proof with `plan=`, `tasks=` and `approved=`
read from the context, plus the frozen-text check of spec section 9 over the plan and
every `docs/specs/*.md` the plan round changed (the set is Git's name-only diff between
the merge base and `approved=`, read at proof time), with reasons that name no path. `record-ship` accepts
`kind=implement` as it accepts `ship`. `kind=plan-only` keeps today's plan proof.

**Acceptance:** fixtures for: not pushed; a change outside `docs/`; no spec file; two
added plan files; a plan file in a subdirectory; a changed spec whose name holds a
space, rejected without the name in the reason; a plan with tasks 1, 2, 4; a plan with
13 tasks; a task with no box; and the good case, which prints the exact line. For
`implement`: a receipt from another run is rejected; a task body reworded after approval
is rejected with the spec's reason; a spec file changed after approval is rejected; box
ticks and a header edit alone pass. For `plan-only`: today's fixtures pass unchanged.

**Steps**

- [ ] `verify` dispatch for the two new kinds; `record-ship` accepts `implement`.
- [ ] The pushed check; added-plan detection and the path character class over every changed path; the task-count reader.
- [ ] The `implement` path with context-supplied plan and tasks; the frozen-text check.
- [ ] Break-verify: ticked-box mode swapped in for the plan proof, confirm the no-box
      fixture passes wrongly and the test fails; restore. Drop the remote-ref compare,
      confirm the not-pushed fixture's test fails; restore. Skip the frozen-text check,
      confirm the reworded-task test fails; restore. Skip the character class on
      changed paths, confirm the space-in-name test fails; restore. Paste all four.

## Task 3: The wrapper's plan round

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** In a `plan` kind run, `plan-ready:` is a terminal proposal and `done:` is
the violation `the worker for <id> proposed done in a plan round`; in any other kind
`plan-ready:` is the violation `the worker for <id> proposed plan-ready outside a plan
round`. A `plan-ready` terminal goes through `prove_done`'s path with `dux-result
verify`, and the proof's line (or `ended:`) is what is published, with the event taken
from its first word. `DUX_SHIP_RECORD` and the ship-only environment are set for
`kind=implement` as for `ship`, and for `implement` the context carries `plan=`,
`tasks=` and `approved=` copied from `state/<id>.plan`. The kind itself arrives as the
argument milestone 7 added; the wrapper reads no round file.

**Acceptance:** a fake worker writing `plan-ready: x` in a plan run publishes the proof's
line with event `plan-ready`; the same line in a ship run publishes a `failed:` handoff
with the violation; `done:` in a plan run does the same; an implement run sees
`DUX_SHIP_RECORD` and the copied `plan=` and `approved=`.

**Steps**

- [ ] Proposal rules by kind; the proof call and event for `plan-ready`.
- [ ] `implement` gets the ship environment and the plan from the state file.
- [ ] Break-verify: allow `done:` in a plan round, confirm its test fails; restore. Copy
      `plan=` from the brief instead of the state file, confirm the renamed-plan test
      fails; restore. Paste both.

## Task 4: Round files for approve and change, and the plan brief's rules

**Files:** `bin/dux-brief`, `templates/round.md`, `templates/brief.md`, `tests/dux-brief.bats`.

**Interface:** `--round approve|change` join milestone 7's `answer|retry`, with titles
`approved` and `changes requested` and kinds `implement` and `plan` in the first line. The approve round carries path, tasks and sha from
`state/<id>.plan`, the frozen-text sentence, the delegate-to-Opus instruction and the
`/ship` then `done:` ending. The change round carries the operator's file verbatim and
the instruction to revise the same plan file, push, and append `plan-ready:` again.
Refusals added: the state does not fit (`plan-ready` for both); `change` without
`--answer-file`; a second `approve`. The `plan` shape's rules line in
`templates/brief.md`, when the brief has no `- Plan only: yes` line, becomes: write
markdown only, push, append `plan-ready: <one line>` and exit; approval, changes or an
answer return as your next prompt; never publish an artifact or wait in-session. Its
definition of done becomes the implement round's `done: PR <url>`. With the line, the
rules and done stay today's.

**Acceptance:** both round files render with the fixed text and the right
substitutions; each new refusal fires from its fixture; the brief test asserts both
wordings of the plan shape and the 100-line cap still holds for both.

**Steps**

- [ ] The two kinds; refusals.
- [ ] Brief rules and done line, with and without plan only.
- [ ] Break-verify: allow a second `approve`, confirm its test fails; restore. Render the
      plan-and-build rules for a plan-only brief, confirm the wording test fails; restore.
      Paste both.

## Task 5: `dux-spawn --resume approve|change`, and a plan worktree made like a ship one

**Files:** `bin/dux-spawn`, `bin/dux-worktree`, `tests/dux-spawn.bats`, `tests/dux-worktree.bats`.

**Interface:** `dux-worktree create` uses the project's mechanism and copies env examples
for a `plan` task without the plan-only line, as it does for `ship` (`scout` and plan-only
keep plain `git`). `dux-spawn <id> --resume approve|change` follows spec section 7's
eight steps: step 3 also requires a clean worktree for these two kinds; step 4 writes
nothing, and a second approve is refused by `dux-brief` from the round files. The kind
passed to the wrapper comes from the round file's first line, `implement` for approve
and `plan` for change; a crash between
the archive and the wrapper start leaves the round unrun, and the same `--resume` is
run again, as milestone 7's step 1 allows.

**Acceptance:** with the fake backend and fake claude: approve from `plan-ready` archives
the old run, opens a new container, starts the wrapper with `--resume <session>`, the
round file and kind `implement`, and sets `running`; change does the same with kind
`plan`; the same approve run again after a simulated crash before the wrapper start
starts the round once, not twice; a dirty worktree refuses before anything is moved; a `plan` task's
worktree on a `make` fixture project is created through `make worktree`, and a plan-only
one is not.

**Steps**

- [ ] Worktree mechanism and env for `plan` without plan only.
- [ ] The two round kinds in `--resume`; the clean check.
- [ ] Break-verify: skip the dirty-worktree check, confirm its test fails and shows the
      archive happened; restore. Paste the failure.

## Task 6: What the operator sees, and recovery's two fixes

**Files:** `bin/dux-notify`, `bin/dux-status`, `bin/dux-recover`, `tests/dux-notify.bats`,
`tests/dux-status.bats`, `tests/dux-recover.bats`.

**Interface:** `dux-notify` on `plan-ready` prints `Approve or change: <project> plan is
ready (<id>)`. `dux-status` counts `plan-ready` under `awaiting you` and, for each, prints
one indented line `plan <id>: https://github.com/<repo>/blob/dux/<id>/<path>` built from
the registry and `state/<id>.plan`; a project with no GitHub repository prints the path
alone. `dux-recover <id>` inspect on `plan-ready` prints that link, one link per other
document changed between the merge base and the proven sha (Git's name-only diff through
the hook-free call; every path already held to the proof's character class, and
re-checked here before it is printed), the round count, and `next: dux-brief <id> --round approve|change
--answer-file <f>, then dux-spawn <id> --resume <kind>; or dux-recover <id> --classify
failed`; it prints no worker text. `--classify failed` accepts `plan-ready`. `ended`
recovery publishes the handoff with the event taken from the first word of the proof's
line.

**Acceptance:** each line asserted exactly; the status link is built from a registry
fixture, never from the status log; classify from `plan-ready` moves the ledger and leaves
the worktree; an `ended` plan round re-proved by recovery lands as `plan-ready`.

**Steps**

- [ ] Notify line; status count and link; recover inspect with the document links.
- [ ] Classify from `plan-ready`; the `ended` event.
- [ ] Break-verify: build the status link from the status log's line instead of the state
      file, confirm the fixture test fails; restore. Publish the `ended` re-proof with a
      fixed `done` event, confirm the plan-round test fails; restore. Paste both.

## Task 7: The skills, AGENTS.md and the architecture file

**Files:** `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `AGENTS.md`,
`docs/ARCHITECTURE.md`, `docs/constitution.md`, `tests/contract.bats`.

**Interface:** `docs/constitution.md` principle 6's sentence on env files becomes: copied
into worktrees only for `ship` tasks and for `plan` tasks that are not plan only, and
only the project's committed examples; version 2.0.7, a PATCH, with the reason in the
governance list (the header's deviation line). Task lifecycle in `AGENTS.md` gains `plan-ready` in the state line, in the
wake list, and one bullet: on `plan-ready`, push the notify line, give the operator the
links `dux-recover` prints, say approve, change or drop, and never read the plan. The
"Talking to the operator" push list gains `plan-ready`. `skills/dux-recover` gains the
approve, change and drop answers with their exact commands, the `ended` to `failed` to
`retry` path, and the sentence that Dux cannot answer questions about the plan's
content. `skills/dux-dispatch` stops passing `--plan-only` by default, asks for it when
the intent reads like a document the operator wants merged on its own, and says a plan
task now ends with an implementation pull request and that its spawn can take as long
as a ship spawn. `AGENTS.md` stays at most 150 lines; `tests/contract.bats` asserts the
new wake word is present. `ARCHITECTURE.md` gains the state, the state files, the two
round kinds and the approve path in the wake flow.

**Acceptance:** the contract test passes, including its principle 6 assertions against
the amended text; `wc -l AGENTS.md` is at most 150; the architecture file names every
new file and flag this milestone added.

**Steps**

- [ ] The constitution amendment; AGENTS.md and the contract test.
- [ ] The two skills; ARCHITECTURE.md.
- [ ] Break-verify: remove the `plan-ready` wake bullet, confirm the contract test fails;
      restore. Paste the failure.

## Milestone acceptance

Constitution gates: bash 3.2 and shellcheck clean, every guard break-verified at its task,
no personal identifiers, ARCHITECTURE.md in the same pull request, `/ship` the only gate.
Specific to this milestone: a `plan-ready` task survives a Dux restart and a watcher
restart without an event; a docs-only `done:` from a plan worker never reaches `done`; a
plan whose task text changed after approval never reaches `done`; a plan-only task still
ends at a docs-only pull request exactly as before.

## Risks

- The first real plan task through this loop is the dry run for approve and change;
  milestone 7's first answered question will already have exercised `--resume` itself.
- A plan spawn on a `make` project now runs the project's setup and takes minutes.
- A crash between the archive and the wrapper start leaves the approve round unrun.
  The same `--resume approve` is run again; nothing is refused and nothing is counted
  twice, because "has run" is a run record naming the round.

## Open questions for the operator

None. The spec's section 14 carries the recommendations already taken.

## Design review

Both reviews are recorded at the end of `2026-09-10-dux-m7-resume-any-worker.md`. From
the first: finding 1 (frozen text) is Task 2; findings 4 and 14 are Tasks 6 and 1;
finding 3 is Task 5; findings 7 and 11 are Tasks 1 and 6. From the second: finding 2
and 22 removed the `approved` file (Task 5, Design); 5 bounds every changed path (Task
2); 6 is the constitution amendment (Task 7 and the deviation line); 8 moved the kind
decision to `dux-spawn` (Design, Task 3); 10 moved the path check into `read_handoff`
(Task 1); 18 took the path out of the frozen-spec reason (Task 2).
