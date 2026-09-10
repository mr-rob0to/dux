# Dux Milestone 7: A plan pauses, the operator answers, the same worker builds it

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-10, design-reviewed once (record at the bottom), awaiting the operator.
- Picks up from milestone 6 (`/ship` stands alone, PR #23) and the reviewer fallback
  (PR #24). Nothing in flight on `dux-project` or `dux-teardown` is touched.
- When this merges, a plan task pauses at `plan-ready`, the operator approves, changes,
  answers or drops it in the Dux session, and the same session implements and ships.

**Estimated diff:** ~1,900 added lines across 8 tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). The reviewer's estimate is 2,300 to 2,700 for the first draft;
the end-to-end test and `--fresh` moved to milestone 8 on that finding. Stop rule: if the
running total passes 2,300 before Task 7, Tasks 7 and 8 move to milestone 8 and this
header says so.

**Goal:** The operator talks to the Dux session and nothing else. A plan comes back to
that session instead of to a pull request they must find, they answer it there, and the
worker that wrote it goes on to build it in the same branch and pull request.

**Spec:** `docs/specs/2026-09-10-one-session-planning.md` sections 2, 3, 4, 6, 7, 10.
Every design decision this milestone needs is settled there and in the orchestrator
spec's pointers (sections 5.1, 5.3, 5.4, 5.5, 17).

## Design

Only what the spec leaves to the implementer.

- **Run kind** is one word in `state/<id>.result-context`: `kind=plan|implement|ship|scout`.
  The wrapper writes it from the ledger shape on a first run and, on a resume, from the
  round file's first line: `## Round n: approved` and `retry` give `implement`, `changes
  requested` gives `plan`, `answer` gives the kind recorded in the archived context of
  the run that asked. `dux-result` switches on `kind`; `shape` stays for messages.
- **Handoff line for a plan round:** `plan-ready: <path> tasks 1-K at <sha>`; the watcher
  parses it with the same `case` shape it uses for `done: PR `.
- **`state/<id>.plan`** is five `key=value` lines (spec section 4), written by the watcher
  with a temp file and one rename. `tasks/<id>/approved` is one line, `<iso> <sha>`.
- **Archive on resume:** `state/<id>.runs/<run>/` holds the previous run's `run`,
  `portal`, `pgid`, `result-context`, `pid`, `out`, and `ship-receipt` when present.
  Handoffs are not moved.
- **Frozen text** (spec section 7) is checked with `git show <sha>:<path>` against
  `HEAD:<path>` after `sed 's/\[ \]/[x]/g'` over the span from the first `## Task`
  heading; the spec files are compared by blob id.
- **Order:** Tasks 1 and 2 are the state and the proof; 3 and 4 the worker side; 5 and 6
  the answer path; 7 and 8 the operator side and the documents.

## Task 1: The `plan-ready` state and its state file

**Files:** `bin/dux-ledger`, `bin/dux-watch`, `tests/dux-ledger.bats`, `tests/dux-watch.bats`.

**Interface:** `valid_state` accepts `plan-ready`; `list --unacked` includes it.
`consume_handoff` on a status line `plan-ready: <path> tasks <a-b> at <sha>` writes
`state/<id>.plan` (version, id, path, tasks, sha) before it sets the ledger, with one
rename, and refuses to consume (returns 1, logs) when the path fails
`docs/plans/[A-Za-z0-9._-]+\.md` or the sha is not 40 hex. `read_handoff` accepts the
`plan-ready` status word and takes its receipt cross-check from the context's `kind`
(`ship` or `implement`) instead of its shape. `status_state` treats `plan-ready` as a
known word. `watched_ids` never lists a `plan-ready` task except to finish an
unconsumed handoff. `target_for` on a `plan-ready` ledger state with no handoff prints
`skip:plan-ready waits for the operator`.

**Acceptance:** a fake handoff with a `plan-ready` event moves the ledger to `plan-ready`,
raises exactly one event line, lists under `--unacked`, and leaves `state/<id>.plan` with
the five keys; a task in `plan-ready` with no pidfile is never marked `dead` over three
watcher passes; a malformed path leaves the handoff unconsumed and the ledger untouched;
a `done` handoff with `kind=implement` and no complete receipt is rejected.

**Steps**

- [ ] Ledger: the state; `--unacked`; a `set` and `list --state plan-ready` round-trip.
- [ ] Watcher: parse the line, write the state file atomically, guard the path and sha;
      the receipt cross-check by kind.
- [ ] Watcher: exclude `plan-ready` from liveness; keep the crash-replay path for its handoffs.
- [ ] Break-verify: remove the path guard, run, confirm the malformed-path test fails;
      restore. Break the `dead` exclusion, confirm the three-pass test fails; restore.
      Remove `plan-ready` from `--unacked`, confirm; restore. Paste all three failures
      into the commit body.

## Task 2: `dux-result` proves a run by its kind

**Files:** `bin/dux-result`, `tests/dux-result.bats`.

**Interface:** `load_run` reads `kind=` from the context (a missing kind is a finding).
`verify` for `kind=plan` runs spec section 4's seven checks in order and prints
`plan-ready: <path> tasks 1-K at <sha>`; each failure exits 1 with the reason wording the
spec gives, with no worker path repeated back when the path itself is what failed. The
pushed check compares `refs/remotes/origin/<branch>` with the tip through `dgit`.
`read_changes` learns the raw status letter so "added" is distinguishable from
"modified". `check_plan_tasks` gains a mode that requires at least one box, ticked or
not, per task, used by the plan proof; the ship proof keeps its all-ticked mode.
`verify` for `kind=implement` is the ship proof with `plan=` and `tasks=` read from the
context, plus the frozen-text check of spec section 7 over the plan and every
`docs/specs/*.md` the plan round changed (the set is Git's name-only diff between the
merge base and the approved sha, read at proof time). `record-ship` accepts
`kind=implement` as it accepts `ship`.

**Acceptance:** fixtures for: not pushed; a change outside `docs/`; no spec file; two
added plan files; a plan file in a subdirectory; a plan with tasks 1, 2, 4; a plan with
13 tasks; a task with no box; and the good case, which prints the exact line. For
`implement`: a receipt from another run is rejected; a task body reworded after approval
is rejected with the spec's reason; a spec file changed after approval is rejected; box
ticks and a header edit alone pass.

**Steps**

- [ ] Context `kind`; `verify` dispatch by kind; `record-ship` accepts `implement`.
- [ ] The pushed check; added-plan detection and the path character class; the task-count reader.
- [ ] The `implement` path with context-supplied plan and tasks; the frozen-text check.
- [ ] Break-verify: ticked-box mode swapped in for the plan proof, confirm the no-box
      fixture passes wrongly and the test fails; restore. Drop the remote-ref compare,
      confirm the not-pushed fixture's test fails; restore. Skip the frozen-text check,
      confirm the reworded-task test fails; restore. Paste all three.

## Task 3: A session id chosen by Dux, and a worker that can resume

**Files:** `bin/workers/claude.sh`, `bin/workers/codex.sh`, `bin/dux-spawn`,
`bin/dux-worker-wrap`, `tests/fakes/claude`, `tests/worker-adapter.bats`, `tests/dux-spawn.bats`.

**Interface:** `worker_cmd` and `worker_run` take
`<prompt-file> <model> <effort> <settings> <session> <first|resume>` and add
`--session-id <session>` for `first`, `--resume <session>` for `resume`; model and effort
are passed on both. `dux-spawn` writes `tasks/<id>/session` (mode 600, a UUID from
`uuidgen` or 32 hex from `/dev/urandom`) before the first `open`, and refuses when the
file exists on a first spawn. The wrapper reads it and passes `first`. The fake `claude`
records the two flags into its output so tests can assert them. Codex's adapter takes
the same arguments and ignores the last two; it stays refused at dispatch.

**Acceptance:** the adapter test shows the exact command line for both modes; a first
spawn creates the session file with mode 600; the wrapper's fake run shows
`--session-id <the file's value>`.

**Steps**

- [ ] Adapter signature and flags, both harness files, the shared adapter test.
- [ ] Session file at spawn; refusal on an existing one.
- [ ] Wrapper passes the session and mode; the fake records them.
- [ ] Break-verify: make the adapter pass `--resume` on `first`, confirm the adapter test
      fails; restore. Paste the failure.

## Task 4: The wrapper's plan round

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** The wrapper takes an optional second argument, the prompt file; absent, the
prompt is the brief. It writes `kind=` into the context per the Design section. In a
`plan` kind run, `plan-ready:` is a terminal proposal and `done:` is the violation
`the worker for <id> proposed done in a plan round`; in any other kind `plan-ready:` is the
violation `the worker for <id> proposed plan-ready outside a plan round`. A `plan-ready`
terminal goes through `prove_done`'s path with `dux-result verify`, and the proof's line
(or `ended:`) is what is published, with the event taken from its first word. The
refusal on an existing handoff directory becomes a refusal only when `next_handoff` finds
an unconsumed sequence. `DUX_SHIP_RECORD` and the ship-only environment are set for
`kind=implement` as for `ship`.

**Acceptance:** a fake worker writing `plan-ready: x` in a plan run publishes the proof's
line with event `plan-ready`; the same line in a ship run publishes a `failed:` handoff
with the violation; `done:` in a plan run does the same; a resume with a consumed handoff
present starts, and with an unconsumed one refuses; an implement run sees `DUX_SHIP_RECORD`.

**Steps**

- [ ] Prompt-file argument and `kind` in the context.
- [ ] Proposal rules by kind; the proof call and event for `plan-ready`.
- [ ] Unconsumed-handoff refusal; `implement` gets the ship environment.
- [ ] Break-verify: allow `done:` in a plan round, confirm its test fails; restore. Make
      the handoff refusal fire on a consumed sequence, confirm the resume test fails;
      restore. Paste both.

## Task 5: Round files

**Files:** `bin/dux-brief`, `templates/round.md`, `templates/brief.md`, `tests/dux-brief.bats`.

**Interface:** `dux-brief <id> --round approve|change|answer|retry [--answer-file <f>]`
renders `tasks/<id>/round-<n>.md` (n = existing rounds + 1) from `templates/round.md`,
whose first line is `## Round {{N}}: {{TITLE}}` with titles `approved`, `changes
requested`, `answer`, `retry`. Refusals, each a finding: the state does not fit the kind
(spec section 6); `change` or `answer` without `--answer-file`; an answer file containing
an `<untrusted-` fence; a second `approve`; a second `retry`; a ninth round; a round file
over 40 lines; a previous round not yet run (no `state/<id>.runs/` entry newer than it).
The approve round carries path, tasks and sha from `state/<id>.plan` and the frozen-text
sentence. The retry round carries the last five status lines and the failure tail from
`report.md`, cleaned and fenced as `dux-recover --retry` does. The `plan` shape's rules
line in `templates/brief.md` becomes: write markdown only, push, append `plan-ready: <one
line>` and exit; approval, changes or an answer return as your next prompt; never publish
an artifact or wait in-session. Its definition of done becomes the implement round's
`done: PR <url>`.

**Acceptance:** the four round files render with the fixed text and the right
substitutions; each refusal fires from its fixture; the brief test's plan-shape wording
assertions are updated and the 60-line cap still holds.

**Steps**

- [ ] Template and renderer; numbering; the four kinds.
- [ ] Refusals and caps; the fence check on the answer file.
- [ ] Brief rules and done line for the plan shape.
- [ ] Break-verify: lift the ninth-round cap, confirm its test fails; restore. Remove
      the fence check, confirm that test fails; restore. Paste both.

## Task 6: `dux-spawn --resume`, and a plan worktree made like a ship one

**Files:** `bin/dux-spawn`, `bin/dux-worktree`, `tests/dux-spawn.bats`, `tests/dux-worktree.bats`.

**Interface:** `dux-worktree create` uses the project's mechanism and copies env examples
for `plan` as it does for `ship` (`scout` keeps plain `git`). `dux-spawn <id> --resume
approve|change|answer|retry` follows spec section 6's eight steps, in order, each a
finding with the wording there; step 4 writes `tasks/<id>/approved` on approve and
nothing else. The container is closed and reopened through `dux-backend close` and
`open`; the ledger endpoint is updated. A plain `dux-spawn <id>` on a `plan-ready` task
keeps refusing as not `queued`. `--fresh` is not in this milestone; the flag is refused
with `--fresh arrives in milestone 8`.

**Acceptance:** with the fake backend and fake claude: approve from `plan-ready` archives
the old run under `state/<id>.runs/<run>/`, writes `tasks/<id>/approved`, opens a new
container, starts the wrapper with `--resume <session>` and the round file, and sets
`running`; change does the same without `approved`; answer from `needs-decision` starts
with the asking run's kind; retry from `failed` without `approved` refuses; a dirty
worktree refuses before anything is moved; an alive wrapper pid refuses; a `plan` task's
worktree on a `make` fixture project is created through `make worktree`.

**Steps**

- [ ] Worktree mechanism and env for `plan`.
- [ ] Resume preconditions; archive; container close and open; wrapper start; ledger.
- [ ] Break-verify: skip the dirty-worktree check, confirm its test fails and shows the
      archive happened; restore. Skip the pid check, confirm; restore. Paste both.

## Task 7: What the operator sees, and recovery's three fixes

**Files:** `bin/dux-notify`, `bin/dux-status`, `bin/dux-recover`, `tests/dux-notify.bats`,
`tests/dux-status.bats`, `tests/dux-recover.bats`.

**Interface:** `dux-notify` on `plan-ready` prints `Approve or change: <project> plan is
ready (<id>)`. `dux-status` counts `plan-ready` under `awaiting you` and, for each, prints
one indented line `plan <id>: https://github.com/<repo>/blob/dux/<id>/<path>` built from
the registry and `state/<id>.plan`; a project with no GitHub repository prints the path
alone. `dux-recover <id>` inspect on `plan-ready` prints that link, one link per other
document changed between the merge base and the proven sha (Git's name-only diff through
the hook-free call), the round count, and `next: dux-brief <id> --round approve|change
--answer-file <f>, then dux-spawn <id> --resume <kind>; or dux-recover <id> --classify
failed`; it prints no worker text. `--classify failed` accepts `plan-ready` and appends
`failed: plan dropped by the operator`. `ended` recovery publishes the handoff with the
event taken from the first word of the proof's line. `--retry` refuses a `plan` shape task
with `plan tasks resume; use dux-brief --round and dux-spawn --resume`.

**Acceptance:** each line asserted exactly; the status link is built from a registry
fixture, never from the status log; classify from `plan-ready` moves the ledger and leaves
the worktree; classify from `running` still refuses; an `ended` plan round re-proved by
recovery lands as `plan-ready`; `--retry` on a plan task refuses and creates no task.

**Steps**

- [ ] Notify line; status count and link; recover inspect with the document links.
- [ ] Classify from `plan-ready`; the `ended` event; the `--retry` refusal.
- [ ] Break-verify: build the status link from the status log's line instead of the state
      file, confirm the fixture test fails; restore. Publish the `ended` re-proof with a
      fixed `done` event, confirm the plan-round test fails; restore. Paste both.

## Task 8: The skills, AGENTS.md and the architecture file

**Files:** `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `AGENTS.md`,
`docs/ARCHITECTURE.md`, `tests/contract.bats`.

**Interface:** Task lifecycle in `AGENTS.md` gains `plan-ready` in the state line, in the
wake list, and one bullet: on `plan-ready`, push the notify line, give the operator the
links `dux-recover` prints, say approve, change or drop, and never read the plan. The
"Talking to the operator" push list gains `plan-ready`. `skills/dux-recover` gains the
four answers with their exact commands, the `ended` to `failed` to `retry` path, and the
sentence that Dux cannot answer questions about the plan's content. `skills/dux-dispatch`
says a plan task now ends with an implementation pull request, that its spawn can take as
long as a ship spawn, and what done looks like. `AGENTS.md` stays at most 150 lines;
`tests/contract.bats` asserts the new wake word is present. `ARCHITECTURE.md` gains the
state, the state files, the round files, the resume path in the component list, and the
`plan-ready` steps in the wake flow.

**Acceptance:** the contract test passes; `wc -l AGENTS.md` is at most 150; the
architecture file names every new file and flag this milestone added.

**Steps**

- [ ] AGENTS.md and the contract test.
- [ ] The two skills; ARCHITECTURE.md.
- [ ] Break-verify: remove the `plan-ready` wake bullet, confirm the contract test fails;
      restore. Paste the failure.

## Milestone acceptance

Constitution gates: bash 3.2 and shellcheck clean, every guard break-verified at its task,
no personal identifiers, ARCHITECTURE.md in the same pull request, `/ship` the only gate.
Specific to this milestone: a `plan-ready` task survives a Dux restart and a watcher
restart without an event; a docs-only `done:` from a plan worker never reaches `done`; a
plan whose task text changed after approval never reaches `done`.

## Risks

- The `--resume` behaviour of `claude -p` is tested here only through the fake. The
  first real plan task is the dry run; a resume the harness refuses costs one retry
  round, and until milestone 8's `--fresh`, a lost session costs the task.
- The archive step moves seven files; a crash between two moves leaves a run the
  wrapper refuses to start over. The refusal names the leftover, and the fix is a move.
- A plan spawn on a `make` project now runs the project's setup and takes minutes.

## Open questions for the operator

None. The spec's section 12 carries the recommendations already taken.

## Design review

One independent review, a fresh Fable session that had not seen the design, on
2026-09-10, against the spec, both plans and the scripts. Sixteen findings; every code
citation was checked against the file before it was acted on.

| # | Finding | Outcome |
|---|---|---|
| 1 | Critical: the implement proof bound only the plan's path, so a worker could rewrite task text under the same headings after approval and pass. | Accepted. Spec section 7 freezes task text and changed spec files; Task 2. |
| 2 | Important: the pushed check via `git ls-remote` under the hook-free Git call loses the credential helper and fails on private HTTPS remotes. | Accepted. The check compares `refs/remotes/origin/<branch>`, offline. |
| 3 | Important: `dux-worktree create` uses plain `git` for non-ship shapes, so an implement round on a `make` project runs in a worktree the project never set up. | Accepted, simplified: a `plan` worktree is made like a `ship` one; `dux-worktree env` dropped. |
| 4 | Important: `dux-recover`'s `ended` path publishes with a fixed `done` event, which the watcher rejects for a `plan-ready` proof. | Accepted. Task 7 takes the event from the proof line. |
| 5 | Important: `needs-decision` or `blocked` in an implement round would go through `--retry` and make a new task, losing branch and session. | Accepted. `answer` round added; `--retry` refuses `plan` tasks. |
| 6 | Important: a failed implement proof is `ended`, not `failed`, so retry's precondition was unreachable and two retry paths coexisted. | Accepted. Path documented in spec section 6; `--retry` refusal closes the second path. |
| 7 | Important: `dux-ledger list --unacked` enumerates states by name; `plan-ready` was missing, so a wake could be lost across a restart. | Accepted. Task 1. |
| 8 | Important: clause 3's file count gave the wrong answer for PR #24 and PR #21. | Accepted. File counts removed from the rule. |
| 9 | Important: clause 4 named `dux-result` outright, making every fix to it a plan; PR #13 shipped without one. | Accepted. Clause 4 reworded around what a guard accepts, with the failing-test-first exemption. |
| 10 | Important: milestone 7's estimate was low by this repository's test density. | Accepted. The e2e test and `--fresh` moved to milestone 8; stop rule tightened. |
| 11 | Important: the operator approved one file while the branch could change any document; those edits were never shown and shipped after approval. | Accepted. The links and the page cover every changed document; spec files are frozen after approval. |
| 12 | Minor: three wording claims about existing code were wrong (a box mode that did not exist, a `source-commit` meta that did not, the HTML allowance's reason). | Accepted, reworded. The HTML allowance stays because it reuses the existing rule unchanged; the reviewer's suggestion to drop it would cost a code change for no behaviour. |
| 13 | Minor: the model and effort a resume passes were unspecified. | Accepted. Spec section 2: the `plan` entry, every run. |
| 14 | Minor: the watcher's receipt cross-check keyed on shape, not kind. | Accepted. Task 1. |
| 15 | Minor: teardown, out of scope, leaves the new state files behind. | Accepted as a recorded chore, spec section 10. |
| 16 | Minor: `--fresh` and the renderer's block quotes and third list level were more than the goal needs. | Accepted in part: `--fresh` deferred to milestone 8 as a fallback that still has a user; quotes and the third level dropped; tables and two-level lists kept because the plans here use them. |

Hard rule 3: the reviewer found no new path by which worker text reaches Dux's context
or the operator unframed. Two pre-existing exposures are recorded in spec section 5.
