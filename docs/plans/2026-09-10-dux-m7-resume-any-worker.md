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

**Estimated diff:** ~1,900 added lines across 8 tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). Sizing procedure: roadmap, "How a milestone is sized". The
second review re-estimated from this repository's density (milestones 5 and 6 landed
about 300 lines a task, and `tests/dux-worker-wrap.bats` is already 681 lines): Task 1
~250, Task 2 ~350, Task 3 ~350, Task 4 ~300, Task 5 ~200, Task 6 ~150 net of the
twenty-one `--retry` tests it removes, Task 7 ~100, Task 8 ~200. Stop rule: if the
running total passes 2,200 before Task 5, Task 5 (`--fresh`) moves to milestone 8 and
this header says so; Tasks 7 and 8 stay, because `ARCHITECTURE.md` ships with the code
that changes it. Between those two merges a lost session would be drop and redispatch.

**Goal:** The operator's rule, applied: the existing worker is resumed for anything that
continues its own work. A one-word question no longer costs a whole new session and a
new worktree.

**Spec:** `docs/specs/2026-09-10-one-session-planning.md` sections 2, 4, 7, 8, 12.
Every design decision this milestone needs is settled there and in the orchestrator
spec's pointers (sections 5.3, 17).

## Design

Only what the spec leaves to the implementer.

- **Run kind** is one word in `state/<id>.result-context`: `kind=plan-only|ship|scout`
  in this milestone (`plan` and `implement` arrive in milestone 8; until then every
  `plan` shape task's kind is `plan-only`, with or without the plan-only line in its
  brief, and its proof is today's). `dux-spawn` passes it to the wrapper as an
  argument: from the shape on a first spawn; on a resume, from the round file's first
  line, where `dux-brief` wrote it at render time from `state/<id>.result-context`,
  which is still in place then. The wrapper copies the word into the context and writes
  `round=<n>` (the round file's number, `0` for the brief) into the run record. `dux-result` switches on `kind`; `shape` stays for
  messages.
- **Archive on resume:** `state/<id>.runs/<run>/` holds the previous run's `endpoint`,
  `portal`, `pgid`, `pid`, `out`, `ship-receipt` and `result-context` when present, and
  `run` last. Handoffs are not moved. "Round n has run" means a run record, live or
  archived, carries `round=n`.
- **Round file first line** is `## Round n: answer|retry, kind <kind>`, Dux's own text.
  `dux-spawn` reads that line and passes the prompt file, the kind and the round number
  to the wrapper as arguments; the wrapper reads nothing from the file. The whole file
  is the prompt.
- **The transcript check** is one adapter function, `worker_session_exists <worktree>
  <session>`, in `bin/workers/claude.sh`: true when
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<encoded worktree>/<session>.jsonl` is
  a file, the encoding being every character that is not a letter or digit replaced by
  `-`. Tests set `CLAUDE_CONFIG_DIR` to a scratch directory, and the fake `claude` writes
  the file on a `--session-id` run as the harness does.
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
`uuidgen`, or 32 hex from `/dev/urandom` formatted `8-4-4-4-12` with version nibble `4`
and variant nibble in `89ab`, because the harness refuses an undashed id) before the
first `open`. A first spawn that finds the file on a `queued` task with no run record
reuses it, so a spawn cut off before the wrapper started can be run again as the
dispatch skill says; with a run record present it refuses. The wrapper reads it and
passes `first`. The fake `claude`
records the two flags into its output so tests can assert them. Codex's adapter takes
the same arguments and ignores the last two; it stays refused at dispatch.

**Acceptance:** the adapter test shows the exact command line for both modes; a first
spawn creates the session file with mode 600 and in the dashed form (asserted with
`uuidgen` shadowed off `PATH`); a second first spawn on a queued task reuses it; the
wrapper's fake run shows `--session-id <the file's value>`.

**Steps**

- [ ] Adapter signature and flags, both harness files, the shared adapter test.
- [ ] Session file at spawn; the dashed fallback; reuse on a queued task, refusal after a run.
- [ ] Wrapper passes the session and mode; the fake records them.
- [ ] Break-verify: make the adapter pass `--resume` on `first`, confirm the adapter test
      fails; restore. Paste the failure.

## Task 2: The wrapper takes a prompt file, records the kind, and refuses only an unconsumed handoff

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** The wrapper takes three optional arguments after the id: the prompt file
(absent, the brief), the kind (absent, derived from the shape as a first spawn would)
and the round number (absent, `0`). It writes `kind=` into the context and `round=` into
the run record, and reads neither from any file. The refusal on an existing handoff
directory becomes a refusal only when `next_handoff` finds an unconsumed sequence.
`DUX_SHIP_RECORD` and the ship-only environment are set by kind (`ship`), not by shape,
so milestone 8 can add `implement` with one word. The brief's `- Plan only: yes` line
(Task 3) is written in this milestone and read in the next; here every `plan` shape is
kind `plan-only` regardless.

**Acceptance:** a fake run with a prompt file shows the harness got that file, not the
brief; the context carries `kind=ship` for a ship task and `kind=plan-only` for a plan
task with and without the plan-only line; a run started with a kind argument carries
that word and its run record carries the round number; a resume with a consumed handoff
present starts, and with an unconsumed one refuses.

**Steps**

- [ ] Prompt-file, kind and round arguments; `kind` in the context, `round` in the run record.
- [ ] Unconsumed-handoff refusal; ship environment keyed on kind.
- [ ] Break-verify: make the handoff refusal fire on a consumed sequence, confirm the
      resume test fails; restore. Make the wrapper ignore the kind argument and derive
      from the shape, confirm the kind-argument test fails; restore. Paste both.

## Task 3: Round files for an answer and a retry, and the plan-only line

**Files:** `bin/dux-brief`, `templates/round.md`, `templates/brief.md`, `bin/dux-env`,
`tests/dux-brief.bats`.

**Interface:** `dux-brief <id> --round answer|retry [--answer-file <f>]` renders
`tasks/<id>/round-<n>.md` (n = existing rounds + 1) from `templates/round.md`, whose
first line is `## Round {{N}}: {{TITLE}}, kind {{KIND}}` with titles `answer` and `retry`
(`approved` and `changes requested` arrive in milestone 8) and the kind read from
`state/<id>.result-context` at render time. The answer round carries the operator's
file verbatim and the instruction to continue the run that asked from the worktree as
it stands. The retry round carries the last five status lines and the failure tail from
`report.md`, through `print_worker_data` moved into `bin/dux-env`, and the instruction
to read `git status` and the plan's boxes first. Refusals, each a finding: the state
does not fit the kind (`needs-decision` or `blocked` for answer, `failed` for retry);
`answer` without `--answer-file`, or with one that is missing or empty; an answer file
containing an `<untrusted-` fence; a second `retry`; a `retry` whose last status line is
Dux's own `failed: dropped by the operator` or `failed: superseded by`; a ninth round; a
round file over 40 lines; a previous round that no run record, live or archived, names
in its `round=` line. `dux-brief <id> --plan-only` writes
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
      the fence check, confirm that test fails; restore. Accept a retry on a dropped
      task, confirm its test fails; restore. Paste all three.

## Task 4: `dux-spawn --resume answer|retry`

**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`.

**Interface:** `dux-spawn <id> --resume answer|retry` follows spec section 7's eight
steps, in order, each a finding with the wording there: step 1 also refuses to re-run a
round a run record already names, reads the kind from the round file's first line, and
makes the transcript check (Task 5); step 2 makes the three liveness checks (pidfile; process group when
`state/<id>.pgid` exists; the backend's `find` matching the recorded endpoint); step 3
checks that the worktree exists and is on `dux/<id>` and leaves it dirty; step 4 writes
nothing; step 5 archives with the run record last and skips absent files; step 6 closes
and reopens the container through `dux-backend close` and `open` and writes a new
`state/<id>.endpoint` as well as the ledger endpoint; step 7 starts the wrapper with the
round file, the kind and the round number. A resume that fails between steps 2 and 7 is
run again with the same command. A plain `dux-spawn <id>` on a parked task keeps
refusing as not `queued`. `--resume approve|change` is refused with `arrives in
milestone 8`.

**Acceptance:** with the fake backend and fake claude: answer from `needs-decision`
archives the old run under `state/<id>.runs/<run>/` with `run` present and `portal`
absent, opens a new container, writes the new endpoint file, starts the wrapper with
`--resume <session>`, the round file and the kind from its first line, and sets `running`; the
same from `blocked`; retry from `failed` does the same; a dirty worktree is left dirty
and the run starts; a worktree on another branch refuses before anything is moved; an
alive wrapper pid refuses; a container the fake backend `find`s under another endpoint
refuses; a round already named by a run record refuses; the same resume run again after
a simulated crash between two archive renames finishes the archive and starts; a
focused pane the fake backend refuses to close is the backend's finding, and nothing is
archived.

**Steps**

- [ ] Resume preconditions; archive; container close and open; endpoint; wrapper start; ledger.
- [ ] Break-verify: skip the branch check, confirm its test fails and shows the archive
      happened; restore. Skip the pid check, confirm; restore. Archive the run record
      first, confirm the crash-between-renames test fails; restore. Paste all three.

## Task 5: `--fresh`, for a session the harness can no longer find

**Files:** `bin/workers/claude.sh`, `bin/dux-spawn`, `bin/dux-recover`, `tests/fakes/claude`,
`tests/worker-adapter.bats`, `tests/dux-spawn.bats`, `tests/dux-recover.bats`.

**Interface:** Step 1 of every resume asks the adapter's `worker_session_exists` (Design
section); a missing transcript is the finding `the harness has no transcript for <id>'s
session; run the same round with --fresh to start a new one`, and nothing is spent.
`dux-spawn <id> --resume <kind> --fresh`, accepted with any round kind and whether or not
the transcript is missing, skips that check, writes a new session id over
`tasks/<id>/session`, keeps the old one in `tasks/<id>/session.<n>`, and starts the
wrapper with a prompt file staged at `tasks/<id>/round-<n>.fresh.md`: the brief, then
every `tasks/<id>/round-*.md` in order, this round last; the adapter is called with
`first`. `dux-recover <id>` inspect on a parked or failed task adds `--fresh` to its
`next:` line when the transcript is missing. The harness's exit code is never read: it
is 1 for a lost session and 1 for a crash.

**Acceptance:** the adapter test shows `worker_session_exists` true for a file at the
encoded path under `CLAUDE_CONFIG_DIR` and false without it; with no transcript, a
resume without `--fresh` refuses with the finding, leaves the round unrun (no run record
names it) and the inspect output names the flag; with the file present (the fake writes
it on a `--session-id` run) the resume starts; `--fresh` starts with `--session-id
<new>`, keeps the old id in `session.1`, and the combined prompt is the brief and the
rounds in order; `--fresh` on an answer round from `needs-decision` works the same.

**Steps**

- [ ] The adapter function; the fake's transcript; the check in step 1; the inspect hint.
- [ ] The flag; the session rotation; the combined prompt.
- [ ] Break-verify: skip the transcript check, confirm the no-transcript test fails;
      restore. Paste the failure.

## Task 6: `dux-recover --retry` retired; classify and inspect follow the rounds

**Files:** `bin/dux-recover`, `tests/dux-recover.bats`, `tests/e2e-supervise.bats`,
`docs/ARCHITECTURE.md`, `tests/contract.bats`; `bin/dux-teardown` is **not** touched.

**Interface:** `--retry` is removed, with its `retry` and `retried-from` markers; a task
that carries either from before this milestone is inspected as today and never resumed
(`this task was retried into <new> before rounds existed`). Inspect on `needs-decision`
or `blocked` prints the fenced status tail as today and then `next: write the answer to
data/tasks/<id>/answer.md, then dux-brief <id> --round answer --answer-file <f>, then
dux-spawn <id> --resume answer`. Inspect on `failed` prints the saved failure and `next:
dux-brief <id> --round retry, then dux-spawn <id> --resume retry`, with `--fresh` added
when the transcript is missing (Task 5). `--classify failed` accepts
`needs-decision` and `blocked` as well as `ended` and appends `failed: dropped by the
operator`. `dead` still marks `failed` and releases the channel, as today. The
`already_settled` guard, `--stop` and `--retire-legacy` are unchanged.

**Acceptance:** every removed `--retry` test is replaced by a test of the `next:` line it
used to lead to; the two `--retry` calls in `tests/e2e-supervise.bats` become an answer
round through the real scripts; the sentence on `--retry` in `ARCHITECTURE.md` and the
contract assertion that quotes it are replaced here, so the suite is green at this task
boundary and not only after Task 8; classify from `needs-decision` moves the ledger and
leaves the worktree; classify from `running` still refuses; a pre-milestone task with a
`retry` marker is refused by `dux-brief --round` and `dux-spawn --resume` with the
sentence above. Count the tests before and after the removal and record both numbers in
the commit body.

**Steps**

- [ ] Remove `--retry`; the legacy-marker refusal; the e2e, architecture and contract lines.
- [ ] `next:` lines; classify from the two parked states.
- [ ] Break-verify: make classify accept `running`, confirm its test fails; restore.
      Paste the failure.

## Task 7: What the operator sees

**Files:** `bin/dux-status`, `tests/dux-status.bats`.

**Interface:** `dux-notify` is not touched: its `failed` line already reads `Retry or
drop`. `dux-status` counts `needs-decision`, `blocked` and `failed` under `awaiting you`,
keeping today's exclusion of a failed task whose endpoint is already `-` (torn down),
with the round count for each (`round 2 of 8`), read from the number of
`tasks/<id>/round-*.md` files, never from worker text.

**Acceptance:** each line asserted exactly; the round count comes from a fixture of
round files and changes when one is added.

**Steps**

- [ ] Status count and round number.
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
`AGENTS.md`, the two skills or `ARCHITECTURE.md` (the assertion that quoted it was
replaced in Task 6). `ARCHITECTURE.md` gains the session file, the round
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

- The `--resume` behaviour of `claude -p` is tested here only through the fake, and so
  is the path it keeps a transcript at. The first real answered question is the dry run
  for both; a wrong path shows as a refusal naming `--fresh` on a session that exists,
  which costs nothing but the operator's attention. A harness that refuses a transcript
  that exists exits 1, as a crash does, and is not told apart: that run fails, the
  retry is plain, and the way out after that is drop.
- The archive step moves up to eight files, the run record last; a crash between two
  moves leaves the run record, which the wrapper refuses on, and the fix is running the
  same resume again.
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

The worker that wrote this amendment ran a design review and died before it could act
on the result; that review's output is lost, and nobody knows whether the amendment
answered it. This is a second review, on 2026-09-10, by a fresh reader who did not
write the amendment, not a confirmation of the first. Twenty-five findings, every code
citation checked against the file before it was acted on. The two findings that changed
the design are 4 (the `--fresh` gate) and 5 (a path into Dux's context); the rest tighten
the resume steps or the plans.

| # | Finding | Outcome |
|---|---|---|
| 1 | Important: the `uuidgen` fallback, 32 undashed hex, is refused by the harness (`Invalid session ID. Must be a valid UUID`). | Accepted. Spec section 7 and Task 1: the fallback is written `8-4-4-4-12` with the version and variant nibbles set; the adapter test asserts the dashed form. |
| 2 | Important: a crash after `tasks/<id>/approved` was written could not be recovered; the plan's advice (`--classify failed`, then `retry`) resumed a `plan` kind and never delivered the approval, and a `--resume` was not re-runnable after a failure at steps 4 to 8. | Accepted. The `approved` file is gone (finding 22); the wrapper writes `round=<n>` into the run record, "has run" means a run record names the round, and the same `--resume` is run again after any failure between steps 2 and 7. Spec section 7, Task 4, milestone 8 Task 5. |
| 3 | Important: step 2 cited a process-group check a first spawn does not make, and the check it does make (the backend's `find`) would refuse every resume, since the parked pane is still there. | Accepted. Step 2 names three checks: the pidfile as spawn does, the process group as teardown does, and the found container matching the recorded endpoint. |
| 4 | Important: `--fresh` was gated on "the harness's exit code", which is 1 for a lost session and 1 for a crash (checked on 2.1.268), and the plan recorded that code in a context the wrapper never archives and `dux-result` hashes. | Accepted in part. The gate is gone. Dux looks for the transcript before it starts, through one adapter function that knows the harness's path; a missing file is a finding that names `--fresh` and spends nothing. `--fresh` is accepted on any round, since the only cost of using it needlessly is the operator's own to spend. The reviewer's proposal to gate on the wrapper's own `failed:` line was not taken: it still cannot tell a lost session from a crash. A transcript that exists but a harness upgrade cannot read is recorded as a limit, not built for. Spec section 7 and 8, Task 5. |
| 5 | Important: the changed-document paths `dux-recover` prints as links on `plan-ready` reach Dux's context unbounded; Git quotes only control bytes and quotes, so a file named with a sentence passes. Hard rule 3. | Accepted. Spec section 5 check 4 holds every changed path to the plan path's character class and 200 characters before the proof passes, with a reason that names no path. Milestone 8 Task 2. |
| 6 | Important: copying env examples for a `plan` worktree breaks a MUST in constitution principle 6, and no plan amended it or recorded a deviation. | Accepted. Milestone 8 Task 7 amends principle 6 (PATCH) in the same pull request as the worktree change, and the milestone 8 header carries the deviation line the template asks for. Spec section 12. |
| 7 | Important: refusing a first spawn when `tasks/<id>/session` exists breaks the documented rerun of a spawn cut off before the wrapper started. | Accepted. A `queued` task with no run record reuses the file. Spec section 7, Task 1. |
| 8 | Important: the run kind was decided in two places (the spec said Dux, the plan said the wrapper from "the newest archived context"), and "newest" was undefined for random run ids. | Accepted. One chain: `dux-brief` writes the kind into the round file's first line while the previous run's context is still in place, `dux-spawn` passes it as an argument, the wrapper copies it. Nothing reads an archived context, so the reviewer's renumbering of the archive directories was not needed; `round=` in the run record answers "has this round run" without ordering. Spec section 7, Design, Tasks 2 to 4. |
| 9 | Important: a round the harness never ran consumed its number and, for `retry`, the one retry. | Accepted in part. A round no run record names is re-run by the same command at no cost (finding 2). A wrapper refusal after the run record is written is an ordinary failure; it is Dux's own leftover, and step 5's ordering is what keeps it from happening, so no counting rule was added for it. |
| 10 | Important: validating the `plan-ready` path in `consume_handoff` would leave the status line written and the handoff unconsumed, and the watcher would pick it up every pass. | Accepted. The path and sha are checked in `read_handoff` as a `reject:`, which writes nothing, as a malformed `done: PR` line is today. Spec section 5, milestone 8 Task 1. |
| 11 | Minor: `--round retry` accepted a task the operator had dropped, which section 3 calls an end. | Accepted. A retry refuses when the last status line is Dux's own drop or supersede text. Spec section 7, Task 3. |
| 12 | Minor: step 5 renamed files the wrapper removes at the end of a normal run, and its crash guarantee held only for the files the wrapper checks. | Accepted. Absent files are skipped and the run record goes last, so any crash leaves the one file the wrapper refuses on. Spec section 7 step 5, Design, Task 4. |
| 13 | Minor: step 6 updated the ledger endpoint but not `state/<id>.endpoint`, whose age anchors the watcher's starting grace, so a resumed run could read as `dead` on the first pass. | Accepted. The old file is archived in step 5 and step 6 writes a new one. Task 4 asserts it. |
| 14 | Minor: section 4 said the pane is reused and step 6 said it is replaced; "names the tab" is not what either backend prints. | Accepted. Replaced, and the finding is the backend's own line. |
| 15 | Minor: Task 7's notify change was a no-op (`dux-notify` already prints `Retry or drop`), and adding `failed` to "awaiting you" was in the plan but not the spec. | Accepted. The notify change is dropped; section 4 says `failed` is counted and a torn-down one stays excluded. |
| 16 | Minor: Task 6 missed `tests/e2e-supervise.bats`, which calls `--retry`, and the `--retry` sentence in `ARCHITECTURE.md` that a contract assertion quotes was left to Task 8, two tasks later. | Accepted. All three files move to Task 6 so the suite is green at that task boundary. |
| 17 | Minor: the frozen-text check makes a stop rule impossible under an implement round, and nothing said so. | Accepted. Spec section 9: the range is fixed at approval; a milestone that cannot be estimated is dispatched plan only. |
| 18 | Minor: `<spec path> changed after approval` put a second worker-chosen path into an `ended:` reason, beyond the one section 6 records. | Accepted. The reason names no path. |
| 19 | Minor: a plan brief rendered before this milestone merges has no plan-only line, and this milestone had no `plan` kind to give it. | Accepted. The wrapper does not read the line until milestone 8; every `plan` shape is `plan-only` here. Spec section 3, Task 2. |
| 20 | Minor: section 13 gave drop from `needs-decision` and `blocked` to milestone 8 while Task 6 here delivers it. | Accepted. Section 13 says which milestone owns which drop. |
| 21 | Minor: an empty answer file was not refused, though `dux-recover` refuses one today. | Accepted. Added to the refusals in the spec and Task 3. |
| 22 | Minor: `tasks/<id>/approved` duplicated the approve round file and added a crash window and a leftover. | Accepted. Dropped; the approve round is the record, and the wrapper copies the approved commit from `state/<id>.plan` into the implement run's context as `approved=`. |
| 23 | Minor: this plan shipped with a literal placeholder where the second review belonged. | Accepted. This table. |
| 24 | Minor: 1,500 lines for 8 tasks is low by this repository's density, about 300 lines a task on milestones 5 and 6. | Accepted in part. Re-estimated per task to about 1,900, recorded in the header. The reviewer's suggestion to move `--fresh` out now was not taken: with `--retry` gone, a lost session between the two merges would have no way out but drop. The stop rule moves it only if the total passes 2,200 before Task 5. |
| 25 | Minor: milestone 9 Task 5 put the "copy an empty plan into a retry run" rule in the round file, which carries no plan; the wrapper carries the context. | Accepted. Reworded. |

Hard rule 3: the reviewer found one new path by which worker text reaches Dux's
context unframed, the changed-document links (finding 5), now closed by the proof.
Nothing else new; the two pre-existing exposures stay recorded in spec section 6.
