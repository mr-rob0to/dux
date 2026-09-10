# Dux Milestone 7: A worker that asks, or fails, is resumed, never respawned

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-10, design-reviewed twice (both records at the bottom), awaiting the
  operator. Supersedes the milestone 7 plan in pull request #26, whose plan-ready half
  is now milestone 8.
- Picks up from milestone 6 (`/ship` stands alone, PR #23), the reviewer fallback
  (PR #24) and the push-guard and brief-cap fixes (PR #29, #30). Nothing in flight on
  `dux-project` or `dux-teardown` is touched.
- When this merges, a worker of any shape that writes `needs-decision:`, `blocked:` or
  `failed:` is continued in its own session with the operator's answer, in the same
  worktree; `dux-recover --retry` is gone; a session the harness has lost has `--fresh`.

**Estimated diff:** ~1,500 added lines across 8 tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). Sizing procedure: roadmap, "How a milestone is sized". The
first draft's milestone 7 was estimated at 1,900 with a reviewer's range of 2,300 to
2,700; splitting the plan-ready half out is what brings this one under. Stop rule: if
the running total passes 2,000 before Task 7, Tasks 7 and 8 move to milestone 8 and this
header says so.

**Goal:** The operator's rule, applied: the existing worker is resumed for anything that
continues its own work. A one-word question no longer costs a whole new session and a
new worktree.

**Spec:** `docs/specs/2026-09-10-one-session-planning.md` sections 2, 4, 7, 8, 12.
Every design decision this milestone needs is settled there and in the orchestrator
spec's pointers (sections 5.3, 17).

## Design

Only what the spec leaves to the implementer.

- **Run kind** is one word in `state/<id>.result-context`: `kind=plan-only|ship|scout`
  in this milestone (`plan` and `implement` arrive in milestone 8; until then a `plan`
  shape task's kind is `plan-only` and its proof is today's). The wrapper writes it from
  the ledger shape on a first run and, on a resume, from the round file's first line:
  `## Round n: answer` and `## Round n: retry` keep the kind recorded in the archived
  context of the run that asked or failed. `dux-result` switches on `kind`; `shape`
  stays for messages.
- **Archive on resume:** `state/<id>.runs/<run>/` holds the previous run's `run`,
  `portal`, `pgid`, `result-context`, `pid`, `out`, and `ship-receipt` when present.
  Handoffs are not moved.
- **Round file first line** is the only thing the wrapper reads from it: `## Round n:
  answer|retry`. The rest is the prompt.
- **The retry round's fenced data** reuses `print_worker_data` from `dux-recover`
  (control characters stripped, `<>` to `[]`, 200 characters a line, at most 40 lines),
  moved into `bin/dux-env` so `dux-brief` can call it.
- **Order:** Tasks 1 and 2 are the session and the wrapper; 3 and 4 the round files and
  the resume; 5 is `--fresh`; 6 retires the old retry; 7 and 8 the operator surfaces and
  the documents.

## Task 1: A session id chosen by Dux, and a worker that can resume

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

## Task 2: The wrapper takes a prompt file, records the kind, and refuses only an unconsumed handoff

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** The wrapper takes an optional second argument, the prompt file; absent, the
prompt is the brief. It writes `kind=` into the context per the Design section, and on
a resume reads the kind from the newest archived context under `state/<id>.runs/`. The
refusal on an existing handoff directory becomes a refusal only when `next_handoff`
finds an unconsumed sequence. `DUX_SHIP_RECORD` and the ship-only environment are set
by kind (`ship`), not by shape, so milestone 8 can add `implement` with one word. A
`plan` shape's brief line `- Plan only: yes` (Task 3) is what makes the kind
`plan-only`; in this milestone every `plan` task has it.

**Acceptance:** a fake run with a prompt file shows the harness got that file, not the
brief; the context carries `kind=ship` for a ship task and `kind=plan-only` for a plan
task; a resume with a consumed handoff present starts, and with an unconsumed one
refuses; a resumed run's context carries the archived run's kind.

**Steps**

- [ ] Prompt-file argument; `kind` in the context, first run and resume.
- [ ] Unconsumed-handoff refusal; ship environment keyed on kind.
- [ ] Break-verify: make the handoff refusal fire on a consumed sequence, confirm the
      resume test fails; restore. Make the resume write `kind=` from the shape instead of
      the archive, confirm the archived-kind test fails; restore. Paste both.

## Task 3: Round files for an answer and a retry, and the plan-only line

**Files:** `bin/dux-brief`, `templates/round.md`, `templates/brief.md`, `bin/dux-env`,
`tests/dux-brief.bats`.

**Interface:** `dux-brief <id> --round answer|retry [--answer-file <f>]` renders
`tasks/<id>/round-<n>.md` (n = existing rounds + 1) from `templates/round.md`, whose
first line is `## Round {{N}}: {{TITLE}}` with titles `answer` and `retry` (`approved`
and `changes requested` arrive in milestone 8). The answer round carries the operator's
file verbatim and the instruction to continue the run that asked from the worktree as
it stands. The retry round carries the last five status lines and the failure tail from
`report.md`, through `print_worker_data` moved into `bin/dux-env`, and the instruction
to read `git status` and the plan's boxes first. Refusals, each a finding: the state
does not fit the kind (`needs-decision` or `blocked` for answer, `failed` for retry);
`answer` without `--answer-file`; an answer file containing an `<untrusted-` fence; a
second `retry`; a ninth round; a round file over 40 lines; a previous round not yet run
(no `state/<id>.runs/` entry newer than it). `dux-brief <id> --plan-only` writes
`- Plan only: yes` under the brief's project facts; the dispatch skill passes it for
every plan task in this milestone. The brief's rules line for every shape becomes: an
answer to `blocked` or `needs-decision` returns as your next prompt, in this session
and worktree.

**Acceptance:** both round files render with the fixed text and the right
substitutions; each refusal fires from its fixture; the brief test's wording assertions
are updated and the 100-line cap still holds; `print_worker_data` behaves identically
from its new home (the `dux-recover` tests that cover it stay green unchanged).

**Steps**

- [ ] Template and renderer; numbering; the two kinds; the fence helper moved.
- [ ] Refusals and caps; the fence check on the answer file.
- [ ] `--plan-only`; the brief rules line.
- [ ] Break-verify: lift the ninth-round cap, confirm its test fails; restore. Remove
      the fence check, confirm that test fails; restore. Paste both.

## Task 4: `dux-spawn --resume answer|retry`

**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`.

**Interface:** `dux-spawn <id> --resume answer|retry` follows spec section 7's eight
steps, in order, each a finding with the wording there; step 3 checks that the worktree
exists and is on `dux/<id>` and leaves it dirty; step 4 does nothing for these two kinds.
The container is closed and reopened through `dux-backend close` and `open`; the ledger
endpoint is updated. A plain `dux-spawn <id>` on a parked task keeps refusing as not
`queued`. `--resume approve|change` is refused with `arrives in milestone 8`.

**Acceptance:** with the fake backend and fake claude: answer from `needs-decision`
archives the old run under `state/<id>.runs/<run>/`, opens a new container, starts the
wrapper with `--resume <session>` and the round file, and sets `running`; the same from
`blocked`; retry from `failed` does the same; a dirty worktree is left dirty and the run
starts; a worktree on another branch refuses before anything is moved; an alive wrapper
pid refuses; a focused pane the fake backend refuses to close is a finding naming the
tab, and nothing is archived.

**Steps**

- [ ] Resume preconditions; archive; container close and open; wrapper start; ledger.
- [ ] Break-verify: skip the branch check, confirm its test fails and shows the archive
      happened; restore. Skip the pid check, confirm; restore. Paste both.

## Task 5: `--fresh`, for a session the harness can no longer find

**Files:** `bin/dux-spawn`, `bin/dux-worker-wrap`, `bin/dux-recover`,
`tests/dux-spawn.bats`, `tests/dux-worker-wrap.bats`, `tests/dux-recover.bats`.

**Interface:** `dux-spawn <id> --resume retry --fresh` writes a new session id over
`tasks/<id>/session`, keeps the old one in `tasks/<id>/session.<n>`, and starts the
wrapper with a prompt file staged at `tasks/<id>/round-<n>.fresh.md`: the brief, then
every `tasks/<id>/round-*.md` in order, then the retry round; the adapter is called with
`first`. It is refused when the previous run did not fail with the harness's exit code
(`--fresh is for a resume the harness refused; the last run ended <state>`). The wrapper
records the harness's exit code in the archived context so the refusal has something to
read. `dux-recover <id>` inspect on such a failure names the flag in its `next:` line.

**Acceptance:** with the fake claude made to exit 1 on `--resume`, a retry round without
`--fresh` fails and the inspect output names the flag; the same with `--fresh` starts
with `--session-id <new>` and the combined prompt in round order; `--fresh` after a
worker's own `failed:` refuses.

**Steps**

- [ ] The flag; the session rotation; the combined prompt.
- [ ] The refusal; the inspect hint.
- [ ] Break-verify: allow `--fresh` after a worker's own failure, confirm its test fails;
      restore. Paste the failure.

## Task 6: `dux-recover --retry` retired; classify and inspect follow the rounds

**Files:** `bin/dux-recover`, `tests/dux-recover.bats`, `bin/dux-teardown` is **not**
touched.

**Interface:** `--retry` is removed, with its `retry` and `retried-from` markers; a task
that carries either from before this milestone is inspected as today and never resumed
(`this task was retried into <new> before rounds existed`). Inspect on `needs-decision`
or `blocked` prints the fenced status tail as today and then `next: write the answer to
data/tasks/<id>/answer.md, then dux-brief <id> --round answer --answer-file <f>, then
dux-spawn <id> --resume answer`. Inspect on `failed` prints the saved failure and `next:
dux-brief <id> --round retry, then dux-spawn <id> --resume retry`, with `--fresh` added
when the archived context says the harness refused. `--classify failed` accepts
`needs-decision` and `blocked` as well as `ended` and appends `failed: dropped by the
operator`. `dead` still marks `failed` and releases the channel, as today. The
`already_settled` guard, `--stop` and `--retire-legacy` are unchanged.

**Acceptance:** every removed `--retry` test is replaced by a test of the `next:` line it
used to lead to; classify from `needs-decision` moves the ledger and leaves the
worktree; classify from `running` still refuses; a pre-milestone task with a `retry`
marker is refused by `dux-brief --round` and `dux-spawn --resume` with the sentence
above. Count the tests before and after the removal and record both numbers in the
commit body.

**Steps**

- [ ] Remove `--retry`; the legacy-marker refusal.
- [ ] `next:` lines; classify from the two parked states.
- [ ] Break-verify: make classify accept `running`, confirm its test fails; restore.
      Paste the failure.

## Task 7: What the operator sees

**Files:** `bin/dux-notify`, `bin/dux-status`, `tests/dux-notify.bats`, `tests/dux-status.bats`.

**Interface:** `dux-notify` on `failed` prints `Retry or drop: <project> worker failed
(<id>)` instead of today's line, since a failure is now a decision. `dux-status` counts
`needs-decision`, `blocked` and `failed` under `awaiting you` with the round count for
each (`round 2 of 8`), read from the number of `tasks/<id>/round-*.md` files, never from
worker text.

**Acceptance:** each line asserted exactly; the round count comes from a fixture of
round files and changes when one is added.

**Steps**

- [ ] Notify line; status count and round number.
- [ ] Break-verify: count rounds from the status log's lines instead of the files,
      confirm the fixture test fails; restore. Paste the failure.

## Task 8: The skills, AGENTS.md and the architecture file

**Files:** `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `AGENTS.md`,
`docs/ARCHITECTURE.md`, `tests/contract.bats`.

**Interface:** `AGENTS.md`'s task lifecycle says an answer or a retry resumes the same
worker, and that a parked worker is one whose state came from its own status line, never
from time. `skills/dux-recover` replaces the `--retry --answer-file` flow with the
`answer` and `retry` rounds, their exact commands, `--fresh`, and drop. `skills/dux-dispatch`
passes `--plan-only` for every plan task until milestone 8 and says so. `AGENTS.md`
stays at most 150 lines; `tests/contract.bats` asserts `--retry` is named nowhere in
`AGENTS.md` or the two skills. `ARCHITECTURE.md` gains the session file, the round
files, the archive directory, `--resume` and `--fresh` in the component list, and the
answer path in the wake flow.

**Acceptance:** the contract test passes; `wc -l AGENTS.md` is at most 150; the
architecture file names every new file and flag this milestone added.

**Steps**

- [ ] AGENTS.md and the contract test.
- [ ] The two skills; ARCHITECTURE.md.
- [ ] Break-verify: put `--retry` back into the recover skill, confirm the contract test
      fails; restore. Paste the failure.

## Milestone acceptance

Constitution gates: bash 3.2 and shellcheck clean, every guard break-verified at its task,
no personal identifiers, ARCHITECTURE.md in the same pull request, `/ship` the only gate.
Specific to this milestone: a `needs-decision` task survives a Dux restart and a watcher
restart without an event and without going `stale`; an answer round starts the harness
with `--resume` and the session Dux chose; no path in the repository makes a second task
from a first one.

## Risks

- The `--resume` behaviour of `claude -p` is tested here only through the fake. The
  first real answered question is the dry run; a resume the harness refuses costs one
  `--fresh` round, which is why `--fresh` is in this milestone and not the next.
- The archive step moves seven files; a crash between two moves leaves a run the
  wrapper refuses to start over. The refusal names the leftover, and the fix is a move.
- Removing `--retry` removes the only way to answer a task that was parked before this
  milestone merged. There are none in flight at the time of writing; if there are at
  merge time, answer them before merging.

## Open questions for the operator

None. The spec's section 14 carries the recommendations already taken.

## Design review

### First review, of the draft in pull request #26

One independent review, a fresh Fable session that had not seen the design, on
2026-09-10, against the spec, both plans and the scripts. Sixteen findings; every code
citation was checked against the file before it was acted on. The findings that shaped
the plan-ready half now live in the milestone 8 plan's tasks; they are kept here in
full because the spec's section 6 (the page) and 9 (the frozen text) came from them.

| # | Finding | Outcome |
|---|---|---|
| 1 | Critical: the implement proof bound only the plan's path, so a worker could rewrite task text under the same headings after approval and pass. | Accepted. Spec section 9 freezes task text and changed spec files; milestone 8 Task 2. |
| 2 | Important: the pushed check via `git ls-remote` under the hook-free Git call loses the credential helper and fails on private HTTPS remotes. | Accepted. The check compares `refs/remotes/origin/<branch>`, offline. |
| 3 | Important: `dux-worktree create` uses plain `git` for non-ship shapes, so an implement round on a `make` project runs in a worktree the project never set up. | Accepted, simplified: a `plan` worktree is made like a `ship` one; `dux-worktree env` dropped. |
| 4 | Important: `dux-recover`'s `ended` path publishes with a fixed `done` event, which the watcher rejects for a `plan-ready` proof. | Accepted. Milestone 8 Task 7 takes the event from the proof line. |
| 5 | Important: `needs-decision` or `blocked` in an implement round would go through `--retry` and make a new task, losing branch and session. | Accepted, then widened by the operator's rule: `--retry` is retired for every shape (this milestone, Task 6). |
| 6 | Important: a failed implement proof is `ended`, not `failed`, so retry's precondition was unreachable and two retry paths coexisted. | Accepted. Path documented in spec section 7; retiring `--retry` closes the second path. |
| 7 | Important: `dux-ledger list --unacked` enumerates states by name; `plan-ready` was missing, so a wake could be lost across a restart. | Accepted. Milestone 8 Task 1. |
| 8 | Important: clause 3's file count gave the wrong answer for PR #24 and PR #21. | Accepted. File counts removed from the rule. |
| 9 | Important: clause 4 named `dux-result` outright, making every fix to it a plan; PR #13 shipped without one. | Accepted. Clause 4 reworded around what a guard accepts, with the failing-test-first exemption. |
| 10 | Important: milestone 7's estimate was low by this repository's test density. | Accepted. The e2e test moved to the last milestone; the plan-ready half is now its own milestone. |
| 11 | Important: the operator approved one file while the branch could change any document; those edits were never shown and shipped after approval. | Accepted. The links and the page cover every changed document; spec files are frozen after approval. |
| 12 | Minor: three wording claims about existing code were wrong (a box mode that did not exist, a `source-commit` meta that did not, the HTML allowance's reason). | Accepted, reworded. The HTML allowance stays because it reuses the existing rule unchanged; the reviewer's suggestion to drop it would cost a code change for no behaviour. |
| 13 | Minor: the model and effort a resume passes were unspecified. | Accepted. Spec section 3: the shape's entry, every run. |
| 14 | Minor: the watcher's receipt cross-check keyed on shape, not kind. | Accepted. Milestone 8 Task 1. |
| 15 | Minor: teardown, out of scope, leaves the new state files behind. | Accepted as a recorded chore, spec section 12. |
| 16 | Minor: `--fresh` and the renderer's block quotes and third list level were more than the goal needs. | Accepted in part, then reversed for `--fresh` by the operator's rule: with `--retry` gone, a lost session has no other way out, so `--fresh` is in this milestone (Task 5). Quotes and the third level stay dropped. |

Hard rule 3: the reviewer found no new path by which worker text reaches Dux's context
or the operator unframed. Two pre-existing exposures are recorded in spec section 6.

### Second review, of this amendment

RECORDED_BELOW
