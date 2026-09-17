# Dux simplification rollout plan

**Where this stands**
- Approved by the operator on 2026-09-15. Milestones 1 to 3, tasks 1 to 30, merged as pull requests #51, #52 and #54. Milestone 4, tasks 31 to 36, has landed and waits on the operator's merge; R4 is recorded after it.
- The token-efficiency baseline's two worker-through-CI exercises are closed by #45 and #51 (Task 35). Every task dispatched since R1 was installed has failed Dux's 120-second start check.
- Four milestones deliver the approved changes; external policies activate only after their recorded supporting revisions are installed.

**Estimated diff:** 5,650–8,250 added lines across 36 tasks in four milestones. Each milestone remains limited to 12 tasks and 2,500 added lines. Estimates include code, tests, documentation, and patch artifacts.

**Goal:** Reduce repeated planning, unnecessary review passes, and worker restarts while keeping independently proved delivery. Dux owns repository routing and authorized sequencing; the operator supplies goals, consequential decisions, and merge approval.

**Spec:** [Dux simplification amendment](../specs/2026-09-15-dux-simplification-rollout.md). It settles the decisions inherited by this plan and amends the base orchestrator design and named earlier designs. Land the spec and this plan together under constitution principle 8.

**Deviations:** Milestone 1 narrows constitution principle 3 and changes principle 9's review policy through the required major amendment. Milestone 2 amends principle 1 for history-preserving feedback-round base merges. These changes activate with their supporting milestones, not merely when this record lands. Milestone 4 keeps its evaluation in Task 36 instead of a usage summary per task folder: every count in the sample is unknown, and those folders are outside a worker's worktree.

## Design

The paired spec owns design decisions. This plan owns execution state, exact file assignments, rollout evidence, external patch order, unavailable-feature notices, and rollback records.

Execute milestones in order. Within milestone 2, preserve PR #46's existing ownership and all nine tasks. Do not create a competing round implementation or move its same-PR update to a follow-up.

Tasks 3 to 8 land before Task 9 amends the constitution, so they owe the current rule: every assertion each of them adds is broken and seen to fail at that task. Spec section 4's narrower rule applies from Task 9's amendment onward.

Use this file's numbered task ranges when dispatching each milestone:

| Milestone | Task range | Estimated added lines | Actual added lines | Delivery evidence |
|---|---|---:|---|---|
| M1: Policy and review gate | 1–10 | 1,650–2,350 | 2,259 | https://github.com/mr-rob0to/dux/pull/51 |
| M2: Amended PR #46 | 11–19 | 1,750–2,450 | 1,976 | https://github.com/mr-rob0to/dux/pull/52 |
| M3: Answers, approval, sequencing | 20–30 | 1,750–2,450 | 2,428 | Task 30's pull request |
| M4: Usage evidence and evaluation | 31–36 | 500–1,000 | 547 | Task 36's pull request |

Record actual task counts and added lines before implementation and as work lands. If a milestone exceeds a limit, stop before implementing it. Reduce incidental scope or obtain a revised independently usable split. Required acceptance dependencies stay together.

### Exact files and ownership

| Owner | Files | Responsibility |
|---|---|---|
| Operator, machine-local | `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md` symlink | Apply eligible global patches once to the shared target |
| Operator, machine-local | `~/.agents/skills/ship/SKILL.md`, installed skill links | Apply eligible standalone patches or explicitly select the reviewed Dux link |
| Policy owner | `AGENTS.md`, `docs/constitution.md` | Stage planning, review, testing, delegation, routing, and session rules |
| Policy owner | `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `skills/dux-status/SKILL.md`, `skills/dux-project/SKILL.md` | Routing, continuation, authorized sequencing, registration boundaries |
| Policy owner | `docs/specs/2026-09-15-dux-simplification-rollout.md`, `docs/plans/dux-simplification-rollout.md`, `docs/plans/patches/m1-global.patch`, `m1-ship.patch`, `m2-global.patch`, `m2-ship.patch`, `m3-global.patch` in that patch directory | Settled amendment, rollout record, staged external patches, activation evidence |
| Gate owner | `skills/ship/SKILL.md`, `skills/ship/ship-guard`, `skills/ship/ship-env`, `bin/dux-result`, `bin/dux-watch` | Classification, reviewer selection, receipts, proof, watcher validation |
| Gate owner | `bin/dux-brief`, `bin/dux-worker-wrap`, `templates/brief.md`, `.github/PULL_REQUEST_TEMPLATE.md` | Carry review policy and evidence |
| PR #46 owner | `bin/dux-round`, `templates/round.md`, `bin/dux-worker-wrap`, `bin/dux-env`, `bin/dux-spawn`, `bin/dux-teardown`, `bin/dux-notify`, `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh`, `templates/worker-settings.json` | Existing feedback design and required parking corrections |
| PR #46 owner after gate changes | `bin/dux-watch`, `bin/dux-worker-wrap`, `bin/dux-round`, PR #46's existing feedback spec and plan | Receipt retention, delayed consumption, all nine tasks, constitution reconciliation |
| Continuation owner after M2 | `bin/dux-round`, `bin/dux-recover`, `bin/dux-brief`, `bin/dux-worker-wrap`, `bin/dux-result`, `templates/round.md`, `templates/brief.md`, `templates/worker-settings.json` | Answers, committed-plan approval, permitted progress edits, phase metadata |
| Routing owner | `bin/dux-task-new`, `bin/dux-spawn`, `bin/dux-recover`, `bin/dux-teardown` | Single prerequisite and its complete lifecycle |
| Installer owner | `bin/dux-install`, `bin/dux-doctor`, `templates/config/*` | Compatibility, truthful defaults, conflicts, milestone availability |
| Operator, untracked state | `config/models`, `config/models-codex`, `config/reviewer`, `config/security-reviewer`, `config/worker-harness`, `config/backend` | Preserve explicit choices; resolve reported conflicts |
| Usage owner | `templates/usage.md`, `bin/workers/claude.sh`, `bin/workers/codex.sh`, `skills/ship/SKILL.md` where structured metadata exists | Minimal reporting without transcript ingestion |
| Each implementation owner | `docs/ARCHITECTURE.md`, `README.md`, this rollout record, affected existing specs and plans | Current behavior, migration, supersession, installed evidence, rollback |

Owners work sequentially where files overlap. Preserve `templates/worker-mcp.json`, worktree isolation, and base-push protection.

PR #46's existing spec and plan remain its owner documents. Task 1 names them by their actual paths on PR #46's branch; this record invents no replacement filenames.

### Test ownership

- Gate: `tests/ship-guard.bats`, `tests/ship-env.bats`, `tests/dux-result.bats`, `tests/dux-brief.bats`, `tests/dux-watch.bats`.
- Continuation: `tests/dux-worker-wrap.bats`, `tests/dux-recover.bats`, PR #46's `tests/dux-round.bats`, `tests/dux-watch.bats`, and its existing backend and supervision tests.
- Approval: continuation tests and `tests/dux-result.bats`.
- Routing: `tests/dux-task-new.bats`, `tests/dux-spawn.bats`, `tests/dux-teardown.bats`, `tests/e2e-dispatch.bats`.
- Installation and policy: `tests/dux-install.bats`, `tests/dux-doctor.bats`, `tests/contract.bats`, `tests/worker-adapter.bats`.

The approved source names test groups where existing files must be selected by their owner. It does not authorize a second backend or supervision suite.

### Minimum-revision record

| Record | Required contents | Full merged commit ID | Installed revision and verification | External application evidence |
|---|---|---|---|---|
| R1 | All M1 acceptance requirements | 423292b (PR #51) | `m1-global.patch` and `m1-ship.patch` applied 2026-09-17, verified by full-file read | Applied to the operator's `~/.codex/AGENTS.md` (symlinked from `~/.claude/CLAUDE.md`) and `~/.agents/skills/ship/SKILL.md` |
| R2 | All nine amended PR #46 tasks and M2 acceptance | 8d33657 (PR #52) | `m2-global.patch` and `m2-ship.patch` applied 2026-09-17, verified by full-file read | Applied to the same two operator files |
| R3 | All M3 acceptance requirements | 1e5dadd (PR #54) | `m3-global.patch` applied 2026-09-17, verified by full-file read | Applied to `~/.codex/AGENTS.md`; M3 defines no ship-skill patch |
| R4 | M4 reporting support | 877e6f7 (PR #55) | No global or ship-skill patch required; usage template and Codex/Claude extraction ship in the repo itself, verified by full-file read | No additional global patch |

Record the actual full merged commit ID after each merge. The installed revision must be that commit or a descendant retaining its required support. A placeholder, branch name, patch artifact, or approved plan is not an eligible installed revision.

### Application order and unavailable features

| Stage | Artifacts under `docs/plans/patches/` | Minimum installed support | Activated policy |
|---|---|---|---|
| M1 | `m1-global.patch`, `m1-ship.patch` | R1 | Planning precedence, review modes, classification, targeted break-verification, delegation, routine debugging, removal of duplicate full checks and Critical-only re-review, Dux-owned routing and capacity retry |
| M2 | `m2-global.patch`, `m2-ship.patch` | R2, retaining R1 | Delivered-PR feedback, positive parking, same-PR updates, feedback-round base merging |
| M3 | `m3-global.patch` | R3, retaining earlier support | Same-session answers and approval, integrated Opus planning and implementation, verified prerequisites and dependent dispatch |
| M4 | None | R4 | Usage reporting and supported extraction |

Until R2 is recorded and installed, same-session delivered-PR feedback is unavailable; use existing recovery.

Until R3 is recorded and installed, same-session answers and approval, integrated plan-and-build continuation, and recorded prerequisite dispatch are unavailable; use existing recovery.

Until R4 is recorded and installed, the new reporting support is unavailable. Do not claim usage fields that the installed harness does not expose.

Repository policies and linked skills follow these same stages.

### Operator application checklist

For each eligible stage:

1. Compare the patch with the current local file and account for any drift.
2. Inspect the actual global-file and skill symlink targets.
3. Save dated local backups and record link targets.
4. Review the complete proposed diff in an editor.
5. Apply the global patch once to the shared target.
6. Apply the corresponding standalone ship patch, or explicitly select the reviewed Dux skill link.
7. Start fresh sessions and verify which global file and ship skill each host loads.
8. Record the application and verification evidence in the revision table.

Never replace a newer local file wholesale from a snapshot or silently unlink a shared file.

The patches remove these contradictions:

- Full checks both before and inside `/ship`.
- Automatic delegation of routine reading.
- Mandatory fresh-session debugging for routine failures.
- Two shipping reviews for every change.
- Critical-only re-review despite changed-commit proof.
- Automatic Herdr worker creation outside Dux after a Dux-managed merge.
- Mandatory rebasing of feedback rounds whose reviewed history must be preserved.

### Installation constraints

Finish or explicitly stop active workers before changing linked skills or wrappers. Preserve dirty and unpushed worktrees. Install only a merged, reviewed revision.

Preserve explicit `config/*` values. Report incompatible reviewer overrides. Update stale bundled fallback comments. Detect conflicting physical copies and links across shared and Claude skill locations. Show proposed physical-directory replacement before the installer's existing backup behavior.

Render new briefs and settings only for new tasks. Never rewrite running workers' copies. Read old receipts under old requirements; never reinterpret them as combined review. Legacy tasks without metadata remain conservative.

## Task 1: Reconcile the approved policies

**Milestone:** M1.  
**Files:** Paired spec, this plan, and PR #46's `docs/specs/2026-09-15-feedback-rounds-on-a-delivered-pr.md` and `docs/plans/2026-09-15-feedback-rounds-on-a-delivered-pr.md`.  
**Acceptance:** Planning precedence, examples, and all seven PR #46 amendments match the approved source.

- [x] Reconcile references without changing historical evidence or completed boxes.
- [x] Retain all nine PR #46 tasks and remove its Task 8 deferral and prescribed 2.0.9 version.
- [x] Those two files exist only on PR #46's branch. Amend them there, or start M1 after PR #46 merges; never recreate them under other names on this branch.

**Done.** PR #46 merged before M1 started, so both files were amended in place on this
branch, never recreated. All seven amendments from spec section 6.1 are marked
**Amended** where the provision they change appears. Counted before and after: nine task
headings, thirty-nine unchecked boxes, fourteen review-finding rows, all unchanged.

## Task 2: Prepare staged external policy artifacts

**Milestone:** M1.  
**Files:** This plan, its five named patch files, `bin/dux-result`, `tests/dux-result.bats`.  
**Acceptance:** Patches use actual local source text, contain activation requirements, and do not activate future runtime behavior. A plan-shaped result may carry `docs/plans/patches/*.patch`.

- [x] Prepare all five patches and the revision/application record.
- [x] Check every before-text anchor against the current external files; identify source-detail gaps explicitly.
- [x] `plan_entry_ok()` in `bin/dux-result` accepts only `docs/*.md` and top-level `docs/plans/*.html`, so it rejects the patch artifacts and no plan task can deliver them. Add `docs/plans/patches/*.patch`.
- [x] Break-verify: after widening the shape, break it so a path outside `docs/` or an executable mode passes, run, confirm the test fails, restore, paste the failure.

**Anchor check, run against the live external files on 2026-09-15.** Every BEFORE block
in `m1-global.patch` (11 of 11) and `m1-ship.patch` (13 of 13) is exact current text in
`~/.codex/AGENTS.md` and `~/.agents/skills/ship/SKILL.md`. Three later-stage blocks do not
match yet: one in `m2-global.patch` and two in `m3-global.patch`. Each of those three is
text an earlier stage's patch introduces, which is the staged order working as designed,
not drift. Nothing in M1 depends on them.

**Source-detail gaps** stay marked in the artifacts themselves, one `INSUFFICIENT SOURCE
DETAIL` note each in `m1-global.patch`, `m1-ship.patch` and `m2-ship.patch`. Each names
the replacement the approved source did not spell out and what was written instead.

**The patches stay inert.** They are text for the operator to read and apply by hand.
Nothing in this repository applies one, and `plan_entry_ok()` only widened far enough to
let a plan task deliver the file: one flat directory, one extension, never executable.

## Task 3: Carry review classification in briefs

**Milestone:** M1.  
**Files:** `bin/dux-brief`, `bin/dux-worker-wrap`, `templates/brief.md`, `tests/dux-brief.bats`, `tests/dux-worker-wrap.bats`.  
**Interface:** `--review combined|separate`; conservative missing metadata.  
**Acceptance:** The stored mode and reason reach the worker; absent or invalid evidence cannot permit a combined gate.

- [x] Add metadata handling and rendering.
- [x] Test and break-verify the protections against invalid or missing review evidence.

**Landed as `fb5d6f2`.** `--review` and `--review-reason` are one pair, stored in
`data/tasks/<id>/review` at mode 600 and rendered into the brief beside Risk. Stating
neither means separate. `dux-worker-wrap` refuses to start on a review file it cannot
read. Break-verified, six breaks, six distinct failures, pasted in that commit;
`dux-brief.bats` 33 green, `dux-worker-wrap.bats` 79 green.

## Task 4: Add versioned review modes to the gate

**Milestone:** M1.  
**Files:** `skills/ship/ship-guard`, `tests/ship-guard.bats`.  
**Interface:** Spec section 3.1's mode-aware phase and commit requirements.  
**Acceptance:** Combined and separate modes enforce their required phases; later commits invalidate stale evidence.

- [x] Add mode-aware receipt handling and fix-pass invalidation.
- [x] Break-verify skipped-phase, mismatched-mode, and stale-commit protections separately.

**Landed as `8778940`.** The guard file is version 2 and holds the mode and its reason.
Combined owes `checks review`; separate still owes `checks review security`. A version 1
file reads as separate, and a mode that is neither word is a refusal rather than a
reading. A fix pass clears the mode's phases and keeps the mode. Break-verified, seven
breaks, seven distinct failures, pasted in that commit; `ship-guard.bats` 54 green.

## Task 5: Classify shipping and select reviewers

**Milestone:** M1.  
**Files:** `skills/ship/SKILL.md`, `skills/ship/ship-env`, `tests/ship-env.bats`, `.github/PULL_REQUEST_TEMPLATE.md`.  
**Acceptance:** Standalone and supervised gates follow spec section 3, record classification, and preserve final-commit review coverage.

- [x] Update classification, review instructions, evidence, fallback disclosure, and PR reporting.
- [x] Exercise combined, separate, uncertain, and agent-consumed Markdown cases; break-verify important selection protections.

**Landed as `91cd8d9`.** Step 0.5 reads the brief's classification and the whole-branch
diff and opens the gate on `ship-env review-mode`'s answer. That rule is not a classifier
and never reads the diff: combined needs a combined claim over a diff found clear, and
everything else, including both kinds of not knowing, is separate. Both pull request
templates report which mode ran and why. The Critical-only re-review exception is gone.
Break-verified, six breaks, six distinct failures, pasted in that commit; `ship-env.bats`
40 green, `contract.bats` 52 green.

## Task 6: Prove delivery by review mode

**Milestone:** M1.  
**Files:** `bin/dux-result`, `tests/dux-result.bats`.  
**Acceptance:** Valid combined proof passes; separate tasks reject combined proof; legacy proof retains its old requirements.

- [x] Add mode-aware completion proof.
- [x] Break-verify identity, phase, mode, and final-commit protections.

**Landed with this task.** The receipt is version 2 and records the mode the gate opened
in. The mode is fixed when the receipt is created and never afterwards, so what a gate
owes is settled before it records anything. A version 1 receipt keeps the five-phase
requirement it was written under. One combined review is the only claim that costs a
reviewer, so it is the only one checked back against the task's own classification, at
recording and again at proof; escalation to separate needs no permission. Break-verified,
five breaks, five distinct failures, pasted in the commit; `dux-result.bats` 72 green.

## Task 7: Align watcher handoff validation

**Milestone:** M1.  
**Files:** `bin/dux-watch`, `tests/dux-watch.bats`.  
**Acceptance:** Watcher and completion proof agree on version, mode, identity, commit, and phases.

- [x] Accept valid combined, separate, and legacy handoffs and reject mismatches.
- [x] Break-verify important handoff protections; retain the receipt-lifetime contract for M2.

**Landed with this task.** `receipt_complete()` asks the five questions completion proof
asks: version, identity, mode against the task's classification, that mode's phases in
order, and that the ci phase names a commit. It says which one failed, so the refusal
names the fact rather than the file. It deliberately does not read the branch tip again:
by the time a handoff is consumed an ordinary later commit has usually moved it, and
asking again would strand a delivery that was already proved. The receipt-lifetime
contract M2 needs is pinned by a test: consuming a handoff leaves the receipt at its path,
byte for byte, with no `.delivered` beside it. Break-verified, six breaks, six distinct
failures, pasted in the commit; `dux-watch.bats` 48 green.

## Task 8: Check migration and policy availability

**Milestone:** M1.  
**Files:** `bin/dux-install`, `bin/dux-doctor`, `templates/config/*`, `tests/dux-install.bats`, `tests/dux-doctor.bats`.  
**Acceptance:** Installation preserves explicit choices and reports incompatible configurations, links, and unavailable policy stages.

- [x] Add upgrade, conflict, and activation-prerequisite checks.
- [x] Test conservative legacy behavior and break-verify important migration protections.

**Landed with this task.** A new `templates/config/policy-stage` holds the rollout stage
this install may act on, seeded once and never edited afterwards. `dux-doctor` reads it,
refuses a stage this checkout does not implement rather than treating the value as a
switch, and prints what the stage leaves unavailable with the way through for each.
Doctor also resolves both reviewers the way `/ship` resolves them, so a pinned command
this host cannot run is reported before a gate runs instead of during one.

`dux-install` says what a real directory holds before it proposes replacing it, and
reports a conflicting copy of a skill in the shared skills directory without touching it:
a shared file is the operator's, and unlinking one silently is how a host loses a skill it
was relying on. The bundled reviewer comments now say what each reviewer does in a
combined gate. Break-verified, six breaks, six distinct failures, pasted in the commit;
`dux-install.bats` 28 green and `dux-doctor.bats` 10 green.

## Task 9: Activate only M1 repository policy

**Milestone:** M1.  
**Files:** `AGENTS.md`, `docs/constitution.md`, policy skills listed above, `docs/plans/TEMPLATE.md`, `docs/ARCHITECTURE.md`, `README.md`, affected existing specs, `docs/plans/2026-09-10-dux-m7-resume-any-worker.md`, `docs/plans/2026-09-10-dux-m8-plan-ready-and-implement.md`, `docs/plans/2026-09-10-dux-m9-plan-page-and-rule.md`, `tests/contract.bats`, this plan.  
**Acceptance:** M1 instructions agree; unsupported feedback, answers, and approval retain recovery instructions. `AGENTS.md` stays inside its tested 150-line cap.

- [x] Make the next major constitution amendment and align the plan template's inherited testing/review instructions.
- [x] Update current behavior and supersession notices without marking historical work complete. The superseded M7-M9 records are the three plan files named above, not specs.
- [x] `AGENTS.md` is 130 lines against a 150-line cap `tests/contract.bats` enforces, and Tasks 19 and 29 add to it too. Point at the skills rather than restating routing, review and testing rules, and say in the PR what the file gained and lost.

**Landed with this task.** Constitution 3.0.0, MAJOR because it redefines two principles:
principle 3 narrows break-verification from every new test to every important protection
and says which failures count, and principle 9 replaces two reviews on every branch with
a classified mode and replaces the Critical-only re-review with a review on every fix
commit. Principle 1 gains the delegation and session-boundary rules rather than losing
any. The governance note says what the change costs, so the tradeoff is weighable rather
than buried.

`AGENTS.md` went from 130 lines to 141, inside the 150-line cap. It gained review
classification at dispatch, repository routing with the queue held by Dux, and a line
naming what this stage does not carry yet. It lost the copy of the dispatch skill's
six-line plan test, which is now a pointer.

The three M7-M9 plans carry a supersession notice and are otherwise untouched: no box
moved in either direction, which is what keeps them a record. Ten contract tests pin the
new policy across the constitution, `AGENTS.md`, the two skills that carry it, the plan
template and the three superseded plans; four of them were confirmed against a deliberate
restoration of the rule they replaced.

## Task 10: Verify and deliver M1

**Milestone:** M1.  
**Files:** M1 test files, `tests/worker-adapter.bats`, this plan.  
**Acceptance:** M1 acceptance below is evidenced; this proof-changing milestone receives separate reviews.

- [x] Complete integrated tests and required task-boundary break evidence; run `make check`.
- [x] Invoke `/ship` for `make check-branch`, separate reviews, PR, and CI.
- [x] Record delivery evidence and actual size; after operator merge, record R1 and installation evidence.

**Landed with this task.** Tasks 3 to 9 each proved their own piece. What none of them could
prove alone is that the classification survives every hop between the operator and the ledger,
so this task adds three tests across that path and breaks each one:

- `tests/dux-worker-wrap.bats` proves the recorder passes on what the gate hands it. The
  recorder is a two-line shim ending in `"$@"`; forwarding only `"$1"` opened the receipt as
  separate and the test failed on `review=combined`.
- `tests/e2e-dispatch.bats` runs a combined ship task end to end: brief, recorder, receipt,
  proof, pull request, watcher, ledger. Two separate breaks, two different failures. Making
  the proof ask for the separate phases ended the task instead of completing it, at the
  handoff assertion. Making the watcher ask for them rejected a result the proof had already
  accepted, at the ledger assertion, with `it is not the combined gate's phases in order`.
- `tests/contract.bats` pins the mode onto the `checks` call, which is the call that creates
  the receipt. Removing it there opened every receipt as separate, and the four phases a
  correct combined gate files would never satisfy the five that receipt then wanted.

`tests/worker-adapter.bats` needed no change: the launcher exports the recorder's path and
never its arguments, and both directions of that are already pinned there.

The gate's own reviews then found one more protection this milestone owed. Step 0.5 has the gate
read the branch's diff to decide whether the change is sensitive, and nothing said that diff is
data. `skills/ship/SKILL.md` now says the diff is evidence and never instruction, and that a file
arguing for its own classification is a reason to escalate, and it says it before it says to read
the diff. `tests/contract.bats` pins the rule and its position: removing the rule and moving it
back below the read instruction each made that test fail, at different assertions.

Checks: `lint-shell`, `lint-pipes`, the unit files and the eight matrix jobs are green on
macOS and again on Ubuntu 24.04 as a non-root user, which is where this repository's
GNU-versus-BSD and inode-reuse defects have surfaced before. `lint-identifiers` fails on this
machine for the reason `docs/plans/2026-09-14-interactive-worker-sessions.md` already records:
the operator's denylist holds a project name that appears in historical documents this branch
does not touch, and it fails the same way on `main`. CI has no denylist and skips the check.

Size: 2,259 added lines against an estimate of 1,650 to 2,350 and a cap of 2,500.

Delivered as pull request #51, https://github.com/mr-rob0to/dux/pull/51, through `/ship` with the
separate reviews this milestone owes. Both passes ran and their findings, and what was done about
each, are in that pull request's body. The gate records its `ci` phase only when GitHub reports the
branch's checks green and not empty, so the receipt behind this delivery is the CI evidence. The
merged commit id and the installed-revision evidence go in the R1 row after the operator merges,
because neither exists before then.

## Task 11: Qualify live prompting

**Milestone:** M2; PR #46 Task 1.  
**Files:** `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh`, existing backend tests.  
**Acceptance:** Live prompt, Stop hook, parking, and timeout behavior are qualified on both supported backends.

- [x] Implement PR #46's prompt support and record real backend qualification.
- [x] Test and break-verify important delivery and failure protections.

**Landed with this task.** `dux-backend prompt <endpoint> <text>` types one line and submits
it: `send-keys -l` then Enter on tmux, `herdr pane run` on Herdr. Measured 2026-09-16 on this
machine against a live Claude Code 2.1.273 session, once in a tmux 3.6a pane and once in a
Herdr 0.8.2 pane, with the same script: both deliveries reached the session's prompt and were
submitted, so Herdr needs no `send-text` fallback and the milestone is not tmux-only. On both,
the `Stop` hook fired once per turn, at the end of it, and had not fired ten seconds into a
twenty-second tool call. Parking and the idle timeout are behaviour Tasks 13 and 15 add; the
live rehearsal in Task 19 qualifies them.

Three tests in `tests/backend-adapter.bats`, run under both backends, and four breaks, each
failing where it should:

- Dropping the tmux Enter: the delivery test failed with "the reader in the pane never received
  a line".
- Swallowing a failed tmux send, and separately a failed Herdr send: the failure test failed on
  its exit status each time, because the send reported success.
- Dropping `own_endpoint` from the `prompt` case: the ownership test failed on its finding text.

The Herdr fake now types into the process it started when that process is still alive in the
same pane, appending the line to a file it names to that process as `FAKE_HERDR_INPUT`. The
suites that start processes through it (`harness`, `dux-spawn`, `dux-recover`, `dux-result`,
`dux-worker-wrap` and both Herdr end-to-end files) pass unchanged.

## Task 12: Move PR #46's shared helpers

**Milestone:** M2; PR #46 Task 2.  
**Files:** `bin/dux-env` and the existing callers and tests named by PR #46.  
**Acceptance:** The two existing helpers have one shared owner and preserve behavior.

- [x] Move the two helpers according to PR #46.
- [x] Compare declaration counts and run affected tests; record required break evidence.

**Landed with this task.** `dux-spawn`'s `another_worker` is `fleet_busy <id>` in `bin/dux-env`,
and the wrapper's `stop_group` is `stop_pgid <pgid>` there too. Counted before and after: the
fleet block is 75 lines both times, its comments included, and the stop is 22. The fleet check
changed only its name and one `local` line, which now takes the id and the two script paths it
used to find in the caller. The stop changed only in taking the group as an argument, and its
"ignored TERM" log line no longer names the task, since the log it goes to is the task's own.
Spawn keeps all six refusal wordings, and the wrapper's `group_alive` went with the stop, which
was its only caller. Three direct tests in `tests/dux-env.bats`.

Break: `fleet_busy` skipping the group file made spawn's "another task's live harness group
refuses the start, and an unreadable one blocks it" fail at its first status check, because the
start went ahead beside a live group. The three direct tests were each broken on their own: the
pidfile never read as live, the group never read as live, and `stop_pgid` calling a survivor
stopped. Each failed at its own status check.

## Task 13: Park delivered workers without losing receipts

**Milestone:** M2; PR #46 Task 3.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-watch`, `templates/worker-settings.json`, `tests/dux-worker-wrap.bats`, `tests/dux-watch.bats`.  
**Acceptance:** Positive Stop-only parking never removes evidence before watcher consumption.

- [x] Add run-bound parking and retain each receipt through durable handoff application.
- [x] Test delayed combined, separate, and legacy consumption and break-verify premature-removal protections.

**Landed with this task.** A plan or ship run whose terminal line is `done: PR <url>` now waits
up to `DUX_WRAP_IDLE_SECS` (60) for `<channel>/stopped`, which a second `Stop` hook in the
settings template touches and nothing else does. Only a touch newer than the status outbox
counts, so a Stop from an earlier turn proves nothing. Running out of time is a log line and
the run ends as it always did. With the Stop seen and the result proved `done`, the wrapper
publishes, writes `state/<id>.parked` (run, wrapper pid, group) in one move, logs the park
line once, and waits silently. Once the watcher marks that handoff `consumed`, which it does
only after applying the state and the pull request, the receipt becomes
`state/<id>.ship-receipt.delivered`. A signal ends the wait: the marker goes, the group is
stopped and the channel cleared. Any other result after a Stop stops the group first and
ends as before, and a refusal now stops the group too.

Lines after the terminal line are held rather than refused on sight, and every ending except a
park still fails on them, through one check before the result. The result context gains
`round=0` and `since=<branch tip at run start>`. No change was needed in `bin/dux-watch`, so
delayed consumption is tested through the real watcher in `tests/dux-worker-wrap.bats`, and
`tests/dux-watch.bats` is unchanged. PR #46's `tests/harness` is `tests/fakes/claude`, which
gains an `idle` verb: it waits for a typed line and can then replay a round script. PR #46
expected a teardown test and the end-to-end teardown step to need skipping. Neither does,
because no fake touches `stopped` unless a script says so.

Four new tests and one extended; eight breaks, each failing on its own:

- Renaming the receipt at park time: the parking test failed at "receipt still in place" (line 983).
- Parking without publishing, PR #46's named break: the same test failed at "watcher applies done".
- A Stop from before the done line counting: the no-Stop test failed at its "did not stop" line.
- A timed-out wait parking: the same test failed at its exit status.
- Parking an unproved result: the proof test failed at its last output line.
- A refusal leaving the group: the refusal test failed at "group is gone".
- Dropping the late-line check: both the existing second-terminal test and the no-Stop test
  failed at their exit status.
- The `stopped` touch also on `PostToolUse`: the channel test failed at its hook count.

## Task 14: Apply parking consistently to admission and teardown

**Milestone:** M2; PR #46 Task 4.  
**Files:** `bin/dux-env`, `bin/dux-spawn`, `bin/dux-teardown`, related tests.  
**Acceptance:** A positively parked wrapper and process group do not block solely because they remain alive; uncertain state still blocks.

- [x] Apply the shared admission rule and preserve dirty or unpushed work on teardown refusal.
- [x] Break-verify PID, process-group, uncertainty, and cleanup protections separately.

**Landed with this task.** `bin/dux-env` gains `parked <id>`. A marker counts only while all
three of its names still hold: its run is the task's current run, its group is the one
`state/<id>.pgid` names, and its wrapper is the pid `state/<id>.pid` names and is still running.
`fleet_busy`, which `dux-spawn` already calls, then skips that task's pidfile and pgid file and
nothing else. Its ledger state and its pane still count, so a parked task whose result the
watcher has not applied still blocks. `bin/dux-spawn` needed no change.

`dux-teardown` on a `done` task whose marker holds stops the wrapper with TERM, waits up to 20
seconds for it, then stops the group. The existing checks run after that, so a survivor, a
dirty worktree or an unpushed branch is still a refusal with the work left on disk. Anything
short of a marker that holds is judged as before. Teardown also removes
`state/<id>.ship-receipt.delivered` and `state/<id>.parked`. Its group check now uses
`group_runs` instead of `kill -0`: on Linux a group teardown has just stopped can be nothing but
zombies for a while, and `kill -0` answers for those. macOS drops a zombie from its group, so
that break was verified in Docker.

PR #46's acceptance that a round file dropped in during teardown is never acted on needs rounds,
so it is tested with Task 15. Running one teardown test alone on macOS takes about five minutes,
because an existing fixture leaves a `sleep 300` holding bats' output open.

Three new tests; thirteen breaks, each failing on its own:

- PID exemption dropped: the fleet test failed at "a parked task goes through" (dux-env line 264),
  and the spawn test at its start after `done` (dux-spawn line 591).
- Group exemption dropped: the same two assertions.
- Exemption in every ledger state, PR #46's named break: the spawn test failed at "refuses while
  running" (line 587).
- Marker run, wrapper, group and wrapper liveness each unchecked: the fleet test failed at its
  stale-run, other-wrapper, other-group and wrapper-gone cases (lines 266, 267, 268, 271).
- Group stopped before the wrapper, PR #46's named break: the teardown test failed at "group
  still alive when the wrapper stopped" (line 335).
- Wrapper not stopped, group not stopped, delivered receipt kept: the teardown test failed at
  lines 334, 336 and 343.
- Teardown stopping a done task's processes without a marker: the existing live-pid refusal test
  failed because its worker had been killed (line 207).
- `kill -0` back in the group check: green on macOS; on Linux the teardown test failed at
  "uncommitted changes" (line 337) and passed unbroken.

## Task 15: Activate rounds in place

**Milestone:** M2; PR #46 Task 5.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-env`, `tests/dux-worker-wrap.bats`.  
**Acceptance:** Every activation gets fresh identity; parking clears before prompting; pending handoffs prevent reuse.

- [x] Implement the existing wrapper round design.
- [x] Break-verify duplicate activation and pending-handoff protections.

**Landed with this task.** The wrapper's supervision is now one loop, and a round goes back to
its top. A parked wrapper takes up only `data/tasks/<id>/round-<n>.md` for the next `n`, and
only after the watcher has consumed the parked run's handoff. So a result still waiting holds
the round back, and no round file runs twice. Taking it up removes the marker first, so the
session stops counting as idle, then checks that the group it holds still runs. A group that has
gone publishes `failed: the session for <id> was ended in its tab before round <n> could run`.
Otherwise the round becomes a run of its own, `<channel nonce>r<n>`, and all of this happens
before its line is typed:

- `state/<id>.run` and the result context are written again, with `round=<n>` and
  `since=<branch tip>`.
- The ship recorder is rewritten for the new run: `chmod 600`, write, `chmod 500`.
- Both outboxes are read from where they end, and both caps are measured from there. Nothing
  written while parked is judged or kept, and earlier rounds never push a small round over a cap.
- The round file is staged in the channel at mode 400, and
  `Read <channel>/round-<n>.md and follow it.` goes through `dux-backend prompt`.

Two changes from PR #46's text. The group check is `group_runs`, not `kill -0`, for the zombie
reason Task 14 found. And a run hands `dux-result` a report only when that run wrote one, so an
earlier run's report is never evidence for a later one. `bin/dux-env` needed no change.

Task 14's promised teardown test is here. A parked session whose result has been applied is torn
down, and teardown still refuses the unpushed branch. A round file written after that types
nothing and publishes nothing.

Three new tests; twelve breaks, each failing on its own:

- Group check dropped, PR #46's named break: the ended-in-its-tab test failed at its handoff
  status (line 1144).
- Status outbox left where the parked run stopped reading, PR #46's other named break: the round
  test failed waiting for the second park (line 1089). The wrapper logged "proposed a status line
  over 200 bytes", read from what was written while parked. PR #46 expected the second-terminal
  violation; this test's parked lines hit the line cap first.
- Status outbox read from its start: failed at "the round's working line relayed once"
  (line 1113), because the parked run's terminal line was read again and hid the round's.
- Round taken before its result was consumed: failed at "nothing typed yet" (line 1085).
- Marker kept while the round runs: failed at "the round began not parked" (line 1110).
- Always `round-1.md`: failed at "typed once" (line 1100), because round 1 ran twice.
- Cap measured over the whole outbox: second park (line 1089), "wrote more than 65536 bytes".
- Report base not moved: second park (line 1089), "--report is evidence for a scout task only".
- Report copied from its start: failed at "no report kept" (line 1111).
- Run id not renewed: failed at the second handoff's run (line 1091).
- Recorder not rewritten: second park (line 1089), "no /ship receipt for this task".
- Teardown's parked branch disabled: the teardown test failed at "wrapper stopped" (line 1165).

## Task 16: Deliver the existing round command

**Milestone:** M2; PR #46 Task 6.  
**Files:** `bin/dux-round`, `templates/round.md`, `tests/dux-round.bats`.  
**Acceptance:** Feedback stays with its owner and the ninth feedback round is refused.

- [x] Implement same-owner feedback and duplicate-request protection.
- [x] Test and break-verify ownership, duplicate, and round-limit protections.

**Landed with this task.** `dux-round <id> --file <path>` runs PR #46's checks in its order and
writes nothing until all pass: the wrapper named by `state/<id>.pid` running, a marker `parked`
accepts, a live group, the channel and the tab. Then the ledger moves `done` to `running`, the
acknowledgement is cleared, and `.round-<n>.tmp` is renamed onto `round-<n>.md` for the parked
wrapper, so a second request finds the task `running`. A failed rename puts back `done` and its
acknowledgement. Changes from PR #46's text: a branch behind its base gets a merge line in the
round file instead of a refusal, as amended, and the group check is `group_runs`, as in Task 15.
The fake `gh` answers `pr view` with JSON unless `-q` picks one field. Fourteen tests, one a real
parked wrapper delivering a second `done`. Nineteen breaks, each failing on its own:

- Pidfile read dropped (PR #46's named break): line 146, not-parked wording instead.
- Ancestry always passing (PR #46's other named break, as amended): merge line, line 243.
- Marker, group, channel, tab checks dropped: lines 122, 142, 126, 133.
- Head, base, `MERGED` read as open: lines 175, 177, 171.
- `running` accepted: line 224. Pending handoff ignored: line 100. Nine rounds: line 108.
- Renamed first, acknowledgement kept: lines 201, 202. No put-back: line 234.
- Fleet check, fence check, 41 lines, scout let through: lines 155, 93, 185, 79.

## Task 17: Prove each delivered round

**Milestone:** M2; PR #46 Task 7.  
**Files:** `bin/dux-result`, `bin/dux-watch`, `bin/dux-worker-wrap`, related tests.  
**Acceptance:** Each round proves its own run and final commit; consumed handoffs are not applied twice.

- [x] Integrate mode-aware fresh proof and receipt retention with the watcher.
- [x] Break-verify stale-run, stale-commit, and duplicate-consumption protections.

**Landed with this task.** `dux-result verify` reads `round` and `since` from the result context
before `read_changes`, for plan and ship: round absent or `0` is unchanged, otherwise `since` must
be forty hex characters (a finding) and an ancestor of the branch, or the result is ended with
`the round rewrote history the operator already reviewed on <branch>`. A round's receipt answers
to its own run and final commit under the mode rules M1 installed, so no new receipt code. The
watcher counts the newest `round-<n>.md` as activity: a task parked for days went stale the
moment `dux-round` moved it to running. The wrapper needed no change; it has written `round` and
`since` since Task 15. Five tests; eight breaks, each failing on its own:

- Ancestry inverted (PR #46's named break): the no-commit round refused (line 1133). Ancestry
  dropped: the rewritten branch proved (line 1138).
- `since` shape unchecked, and round `0` judged: lines 1150 and 1154.
- Stale run and stale commit accepted for a round: lines 1119 and 1115.
- `next_handoff` ignoring `consumed`: the first run's done applied again over the round's
  `running` (watch line 523). Round files not counted: the fresh round went stale (line 138).

## Task 18: Update the same PR through shipping

**Milestone:** M2; PR #46 Task 8.  
**Files:** `skills/ship/SKILL.md`, related gate tests and evidence.  
**Acceptance:** Feedback completes `/ship` against the existing PR, with current classification, review, receipt, and CI.

- [x] Implement existing-PR updates and history-preserving feedback base merging.
- [x] Exercise a real feedback round through the same PR and CI; retain this task in M2.
- [x] Break-verify: break the guard that keeps a round on its own PR, and the one that stops a feedback base repair from rewriting reviewed history, run, confirm two distinct failures, restore, paste both.

**Landed with this task.** Step 8's "Opening it" looks up the open pull request for the branch into
`$BASE` with PR #46's exact `gh pr list` line, edits its body without `--title` when there is one,
and creates one otherwise; the docs-only paragraph names the same lookup. Step 2 says a Dux
feedback round never rebases: it merges `origin/$BASE` in with an ordinary merge and stops at
`needs-decision` for a conflict, and the stop table carries both rows. Two contract pins.

Run on 2026-09-16 against a private throwaway repository with CI, the skill's own push and opening
blocks, copied verbatim: the first pass opened pull request 1 (CI run 35132095382 green), a second
commit on the same branch edited pull request 1 with its title kept and two commits (run
35132141898 green), and no second pull request existed. Breaks, each failing on its own: the
lookup without `--head` (contract line 473; live, round 2's body landed on pull request 2), the
edit with `--title` (line 474), a round allowed to rebase (line 479), the round file allowing a
rebase (line 480), and the push without its ancestor test (live, a rewritten branch
force-replaced reviewed commit `0f0fc0a`; intact, it stopped with the finding and exit 2). The
live worker round is Task 19's rehearsal: pull request 4 took a feedback round through the
installed `/ship`, CI green on both heads.

## Task 19: Activate feedback and complete the rehearsal

**Milestone:** M2; PR #46 Task 9.  
**Files:** `AGENTS.md`, `docs/constitution.md`, feedback policy skills, `bin/dux-notify`, `templates/brief.md`, PR #46 documents, `docs/ARCHITECTURE.md`, `README.md`, this plan.  
**Acceptance:** M2 acceptance below is proved; questions and approval remain unavailable. This milestone changes receipt and handoff integrity, so it receives separate reviews.

- [x] Amend the constitution from M1's resulting version under its governance rule.
- [x] Complete the previously failed timeout rehearsal through actual PR and CI proof and deliver through `/ship`.
- [x] Record actual size and delivery evidence; after operator merge, record and install R2 before external M2 application.

**Landed with this task.** The operator now hears `Review, then merge or send feedback: <url>`
for a delivered pull request. `AGENTS.md`, `skills/dux-dispatch` and `skills/dux-recover` say
what feedback does from stage m2: the operator's words go to `data/tasks/<id>/feedback.md`,
`bin/dux-round` sends them, nobody types into the tab, and a round that ends `failed` or
`ended` leaves the pull request open with no further round. The brief tells a worker to write
one terminal line per round and then wait at its prompt. `docs/ARCHITECTURE.md` carries
`prompt`, parking, the round, receipt retention until the watcher consumes the handoff, and
teardown of a parked session. Answers and approval are still not built, and the pins that say
so still hold. The constitution goes to 4.0.0, a MAJOR amendment: principle 1 narrowed so a
feedback round merges its base in and never rewrites reviewed commits, and principle 6 now
names the one line Dux types into a tab. `bin/dux-doctor` now says this checkout implements
m2, as its own comment asks the milestone that lands a stage to do; the default in
`templates/config/policy-stage` stays m1 until the operator installs this revision.

Eleven breaks, one at a time, each failing at its own assertion: the dispatch skill's feedback
section dropped (PR #46's named break, contract line 732), its teardown sentence (736), the
lifecycle arrow (729), the `dux-round` command in `AGENTS.md` (730), the old wake line (107),
principle 6's clause (126), version 3.0.0 (129), `AGENTS.md` citing v3.0.0 (715), the old
notification (notify lines 16, 62, 70), the old terminal rule (brief line 205), and stage m1
(doctor lines 101, 119).

**The live rehearsal**, on 2026-09-16, ran this branch's scripts against a scratch Dux home at
stage m2, a private throwaway repository with CI, a tmux server of its own and Claude Code
2.1.273. Each task was a bounded ship task on Sonnet with a combined review.

- Run 1 delivered pull request 3 with CI green, but the worker copied `/ship`'s blocks by hand
  and left out every `$DUX_SHIP_RECORD` line. The proof refused it: `ended: the result was not
  proved: no /ship receipt for this task; the gate did not run under Dux`. It was classified
  failed and torn down, and the pull request closed. Recovery's answer is a fresh task with
  the reason in its intent, and run 2 is that task.
- Run 2 recorded all four combined phases and opened pull request 4, CI green. The proof
  said `done`, the `Stop` hook fired inside the 60-second idle wait, and the wrapper parked:
  the marker named run `zh6ywBnj`, wrapper 61083 and group 61300. The receipt moved to its
  delivered name only after the watcher had consumed handoff 1.
- `bin/dux-round` with a one-line feedback printed `round 1 sent`, and the ledger read
  `running`. The same wrapper took it up as run `zh6ywBnjr1` with `round=1` and `since` at the
  delivered head `69217dd`. The same session committed `cc31717` on top, ran `/ship` again
  (review, push behind the ancestor test, `gh pr edit`), and CI passed on the new head. A second
  `done` came six minutes after the round was sent, and the session parked again.
- `ps` after the round showed wrapper 61083 and group 61300, the same processes 22 minutes
  on. Pull request 4 held two commits with `69217dd` an ancestor of the pushed head, and no
  second pull request existed. Handoffs 1 and 2 were each consumed once, each naming its own
  run.
- `bin/dux-teardown` ended the parked wrapper and then the group, removed the worktree and
  every state file for the task, and closed the tab, in three seconds. The ledger kept `done`
  and pull request 4's url.
- Run 3 set the idle wait to 1 second to force the timeout, and parked anyway: the `Stop` hook
  wrote its file 0.906 seconds after the terminal line. Its worker had typed the reviewer
  command without the skill's stdin redirect, and the reviewer waited for input until the
  rehearsal driver ended it 16 minutes on. The worker then ran the command as the skill writes
  it, the review came back clean, and pull request 5 went green. Teardown ended the parked
  session and closed the tab.
- Run 4 set the wait to 0 and took the timeout branch live. The wrapper logged `did not stop
  within 0s of its terminal status; it is not parked`, stopped the session, and still
  published the proved `done: PR` for pull request 6, CI green. It left no parked marker and
  no group file, and the receipt kept the name the watcher checks. `bin/dux-round` then refused
  with `the session for <id> is no longer in its tab (no wrapper is running for it)`, exit 2,
  wrote no round file and left the ledger at `done`.

Limits of that evidence. The round's `/ship` was the installed skill from `main`, because a
personal skill shadows a project one; that skill already edits the pull request on a later
push. This branch's edit-or-create lookup was proved in Task 18, by running the skill's own
blocks against the same repository. Each worker ran `/ship` by copying its blocks, and two left
a line out, as runs 1 and 3 show; the intents of runs 2 to 4 named what to keep. Each teardown
had the branch's upstream set by hand first, because `/ship` pushes without one and teardown
refuses a branch with none; that refusal predates this milestone. Dirty and unpushed teardown
refusals are proved by `tests/dux-teardown.bats`, not live.

Checks: `make check-branch`, so `lint-shell`, `lint-pipes`, the unit files and the eight matrix
jobs under bash 5 and again under bash 3.2 on macOS, and the suite on Ubuntu 24.04 as a non-root
user, are green apart from three failures `main` shares. The bash 3.2 pass first found that
`tests/dux-round.bats` did not parse there, and the gate fixed it. `lint-identifiers` fails on
this machine for the reason Task 10 records. On Ubuntu under a parallel run, two process tests
fail now and then: the TERM test in `tests/dux-worker-wrap.bats`, and one tmux `pid` wait in
`tests/backend-adapter.bats`. Both also fail on `main` in the same container under the same
load, and this branch's copies passed the same repeats.

Size: 1,976 added lines against the milestone's estimate of 1,750 to 2,450 and PR
#46's own ~1,625, under the 2,500 cap.

Delivered through `/ship` with the separate reviews this milestone owes, as the pull request
that carries this note. The merged commit id and the installed-revision evidence go in the R2
row after the operator merges.

## Task 20: Extend round purposes

**Milestone:** M3.  
**Files:** `bin/dux-round`, `templates/round.md`, `tests/dux-round.bats`.  
**Interface:** `feedback`, `answer`, and `approval` purposes under spec section 6.3.  
**Acceptance:** Each purpose enforces its own prerequisite; an ordinary answer never authorizes implementation.

- [x] Add purpose validation.
- [x] Break-verify waiting-state, delivered-PR, and approval distinctions.

**Landed with this task.** `dux-round` takes `--purpose feedback|answer|approval`, and feedback
is the default, so every M2 call is unchanged. Each purpose checks its own state first. Feedback
goes to a `done` task with a pull request, as before. An answer goes to a task parked at
`needs-decision` or `blocked`. Approval goes only to a `ship` task parked at `needs-decision`; a
`plan` task is refused, because it delivers its plan as a pull request. Only approval takes
`--plan`, `--tasks` and `--commit`, and it needs all three. An answer naming any of them is
refused with `this answer approves no plan`, and the answer round itself tells the worker that
work waiting for approval still waits. An answer or approval has no pull request to check, so
nothing is fetched and GitHub is not asked. A waiting task whose session is gone is sent to
`dux-recover --retry --answer-file`, not teardown, and a round that cannot be armed puts the
task back in the state it came from. `templates/round.md` marks each purpose's lines with a tag,
and the feedback round renders byte for byte as before. Task 23 checks what an approval names
against the repository. A scout takes no round of any purpose. Seven new tests; ten breaks, each
failing on its own:

- An answer accepted at `done` (line 81), feedback at `needs-decision` (86), approval at
  `blocked` (89).
- Approval without `--commit` (99), an answer carrying `--plan` (95), approval for a plan
  task (105).
- A waiting task's lost session sent to teardown (171). A round that cannot be armed putting a
  blocked task back to `done` (138).
- An answer that checks the pull request, with no origin and GitHub failing (114). The render
  ignoring purpose tags (164).

## Task 21: Preserve owners at supported waiting states

**Milestone:** M3.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-recover`, related tests.  
**Acceptance:** Supported questions and recoverable blockers preserve a live positively parked owner; failed or dead sessions use recovery.

- [x] Extend waiting-state continuation through PR #46.
- [x] Break-verify unsafe activation and mistaken-idle protections.

**Landed with this task.** A plan or ship run whose terminal line is `needs-decision:` or
`blocked:` now waits for its Stop the way a proved pull request does, and parks. The marker, the
one-worker exemption and teardown's stop work as they do for `done`, and the log says `parked in
its tab at <state>; an answer goes through dux-round`. A failure never waits. A wait that runs
out parks nothing, and neither does a Stop from an earlier turn. The answer round is taken up only
after the watcher has applied the stop, as feedback is. A gate that the question stopped part-way
keeps its receipt as `ship-receipt.unfinished` once the stop is applied, so the answer's run
records a receipt of its own; teardown removes that file. `dux-recover` names
`dux-round --purpose answer` for a waiting task still parked in its tab, and `--retry` for one
that is not. A retry now ends a live wrapper first, and refuses, writing nothing, while the
session's group still runs. Four new tests and one extended; eleven breaks, each failing on its
own:

- A wait that ran out taken as a stop (wrapper test line 1240). A Stop from before the line taken
  as this turn's (1247). A failure waiting to park (1254). A done the proof ended parking (1026).
- A question never waiting for its Stop (1206). The answer taken up before the stop was applied
  (1215). The stopped gate's receipt left in place, so the answer's gate was refused with `the
  /ship receipt for this task belongs to another run` (1221).
- `dux-recover` not seeing the parked session (recover test line 505). A retry leaving the parked
  wrapper running (524). A retry going ahead while the session's group ran (523: exit 2, but not
  this refusal).
- Teardown leaving the unfinished receipt (teardown test line 344).

Two older timing tests, a scout's rewritten outbox and `--stop` on a real wrapper, failed once
with four test files running at once and passed alone; neither parks.

## Task 22: Add integrated task phases

**Milestone:** M3.  
**Files:** `bin/dux-brief`, `bin/dux-worker-wrap`, `templates/brief.md`, related tests.  
**Interface:** `ship` retains its shape and carries `planning|implementation` phase metadata.  
**Acceptance:** Only explicitly declared planning-phase work may start without a plan; it pauses for approval.

- [x] Add phase metadata and planning briefs with Opus ownership throughout.
- [x] Break-verify unauthorized implementation and plan-only worktree promotion protections.

**Landed with this task.** `dux-brief --phase planning` briefs ship work to plan first. Such a
brief names no plan, refuses `--plan`, `--tasks` and `--risk bounded`, and takes no other phase.
Plan and scout briefs refuse `--phase`, and complex work with no plan now needs it. The phase is
stored beside the brief at mode 600, and the brief carries `- Phase: planning`, three plan-first
rules and its own definition of done. Every brief now says to stop and wait at the prompt after
`blocked` or `needs-decision`. The wrapper reads the phase at the start of every run and records it
in the run context. It refuses a phase on a plan or scout task, a phase file or brief line without
the other, an unknown phase, a first run already at implementation, and planning work on the
bounded model. A done while planning ends the run unproved, even one the repository and GitHub
would prove. Two brief tests added and two changed, four wrapper tests added; twenty breaks, each
failing on its own:

- A complex brief with no plan and no phase accepted (brief test line 364). A phase other than
  planning (388), a planning brief with a plan pair (384) or on bounded risk (386), and `--phase`
  on a plan or scout brief (395), each accepted.
- The phase file at mode 644 (368), or never moved into place (368). The phase line (371), the
  plan-first rules (373) and the planning done line (376) not rendered. The old exit rule put back
  (206).
- A done while planning proved: the pull request was proved and the session parked (wrapper test
  line 1287). A round not reading the phase again (1308). The context not recording it (1286,
  1302).
- A phase on a plan task not refused: the wrapper stopped on an unset variable and recorded nothing
  (1323). A phase file on work not briefed to plan first (1334), an unknown phase (1351), a first
  run at implementation (1355) and planning on the bounded model (1359), each starting the worker.
  A missing phase file refused only as an unknown phase (1348).

## Task 23: Record committed-plan approval

**Milestone:** M3.  
**Files:** `bin/dux-round`, `bin/dux-recover`, related tests.  
**Acceptance:** Approval identifies the committed plan path, approved commit, and task range before implementation starts.

- [x] Record and validate approval through the existing continuation mechanism.
- [x] Break-verify missing, mismatched, and ordinary-answer authorization cases.

**Landed with this task.** An approval round goes only to work briefed to plan first, and names
exactly what it approves. `dux-round` checks that the plan is a Markdown path inside the
repository, the tasks are one task or one upward range of at most 65, and the commit is 7 to 40
hexadecimal digits. It then checks that the commit is the tip of the task's branch, that the plan
is committed there, and that every task in the range has its heading in it. Before the round is
armed it writes `round-<n>.approval` at mode 600, naming the plan, the range and the full commit,
and moves the phase to implementation. A round that cannot be armed removes the record and puts
the phase back. An answer or feedback round removes any record left at its own round number and
never moves the phase. `dux-recover` names the approval command for work planning first that is
parked at a question, and a retry of such work is briefed to plan again. Two round tests added and
two changed, two recover tests added; nineteen breaks, each failing on its own:

- Approval to work not briefed to plan first (round test line 202). The plan path (207), the range
  spelling (211), a downward or longer range (211) and the commit spelling (215) not checked.
- A commit that is not the tip (226), a plan not committed there (220) and a task missing from it
  (222), each accepted.
- The record never moved into place (170), written at mode 644 (173), or written after the round
  (170). The phase not moved on (172).
- A round that cannot be armed leaving the record (235) or the phase at implementation (235).
- An answer leaving a stale record in place (120), or recording an approval itself (120).
- `dux-recover` showing the approval step for a blocker (recover test line 524) or never (519). A
  retry of planning work briefed without the phase (713: the brief was refused).

## Task 24: Permit progress edits without changing approval

**Milestone:** M3.  
**Files:** `bin/dux-result`, approval and continuation tests.  
**Acceptance:** Only checkbox state and the designated three-line status block may differ without renewed approval.

- [x] Compare approved substance while allowing the specified progress edits.
- [x] Test permitted edits and separately break-verify acceptance-criteria, task-range, and substantive-amendment rejection.

**Landed with this task.** Work briefed to plan first proves only under its approval. `dux-result`
takes the newest approval at or before the run's round and ends a run that has none. The record
must name a full commit and a plan path inside the repository. The plan on the branch is compared
with the plan at that commit, with box ticks and up to three lines under **Where this stands**
masked. Any other difference ends the run, and the reason names what changed: the tasks, the
acceptance criteria (an `Acceptance` paragraph, or a section under an acceptance heading), or
anything else. The task heading reader is now shared with the box reader. The wrapper test for the
round after approval writes the record and a real plan, and its round ticks the boxes. Five result
tests added and one wrapper test changed; fifteen breaks, each failing on its own:

- Box state (result test line 1304) or the lines under Where this stands (1308) not masked. A
  fourth line under it masked too (1356).
- Task headings (1317), an `Acceptance` paragraph (1335) or an acceptance section (1338) not told
  apart. Any plan passing the comparison (1316, 1334, 1346).
- Approved work skipping the approval (1316, 1334, 1346, 1372). An approval from a later round
  counted (1372). A run with no approval not refused (1372: it became a finding about the empty
  record). The commit spelling (1376) or the plan path (1380) not checked. A plan missing at the
  approved commit (1385) or gone from the branch (1393) read as empty.
- The wrapper test's round with no approval record: it ended with "has no approval to build"
  (wrapper test line 1319).

## Task 25: Prove approved task completion

**Milestone:** M3.  
**Files:** `bin/dux-result`, `tests/dux-result.bats`.  
**Acceptance:** Valid approval and completed boxes for the recorded range are both required.

- [x] Extend completion proof without treating checked boxes as delivery evidence.
- [x] Break-verify missing approval, changed substance, and incomplete-task protections.

**Landed with this task.** Approved work completes only when the tasks its approval names have
every box ticked. `dux-result` reads those boxes from the approved plan and range, after comparing
the plan with the approved commit, and still requires the receipt and green checks. The approval's
range must be one the box reader can read. The permitted-edit test no longer proves an unchanged
plan first, because its boxes are unticked. Two result tests added and one changed; seven breaks,
each failing on its own:

- Approved work never reading its boxes (result test line 1397). Boxes read for a range other than
  the approval's (1405). The approval's range not checked (1410).
- A run with no approval passing that step (1422): a later check still refused it, with the
  message that a plan with no name "is not committed at the commit its approval names". A changed
  plan passing once every box is ticked (1425).
- Approved work skipping its receipt (1430) or its checks (1435).

## Task 26: Record one predecessor

**Milestone:** M3.  
**Files:** `bin/dux-task-new`, `tests/dux-task-new.bats`.  
**Interface:** Optional `--after <task-id>`; linear sequencing only.  
**Acceptance:** The dependent task owns its prerequisite reference.

- [x] Add the single predecessor reference at creation.
- [x] Test and break-verify invalid prerequisite input protections.

**Landed with this task.** `dux-task-new --after <task-id>` names the one task a new task waits on.
The id must be well formed and in the ledger, and the task must deliver a pull request, so a plan
or ship task and never a scout. A second `--after` is refused, because sequencing is linear. The
reference is written to the new task's own `after` file before its queued line, so nothing can
dispatch it without seeing what it waits on, and the task it waits on is left untouched. Two
tests added; six breaks, each failing on its own:

- A second `--after` replacing the first (task-new test line 86). The id not checked (90: the
  ledger still refused it, with its own message). A task Dux does not know (95) or a scout (98)
  accepted. `--after` with nothing after it not refused (102: the script stopped on an unset
  variable instead).
- The reference never written (70).

## Task 27: Verify prerequisites before dispatch

**Milestone:** M3.  
**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`, `tests/e2e-dispatch.bats`.  
**Acceptance:** Delivery proof, expected GitHub merge, fetched registered base, and named deployment or contract evidence are all checked.

- [x] Store verified repository, PR, delivered head, and merge commit with the dependent task.
- [x] Break-verify open, failed, wrongly targeted, unverifiable, and deployment-incomplete prerequisite refusals.

**Landed with this task.** A task created with `--after` starts only once the task it waits on is
delivered and merged. After the capacity check, `dux-spawn` requires, in order:

- The task waited on is done in the ledger, and its pull request is in its own registered GitHub
  repository.
- Its delivery proof: the run record, the `/ship` receipt of that run, whose ci phase names the
  delivered commit, and the last handoff, consumed, from that run, for that pull request.
- GitHub reports the pull request merged into the registered base, from `dux/<id>`, at that
  delivered commit, with a merge commit, and the merge is on the base once fetched in that task's
  project.
- A check the waiting brief names with `dux-brief --after-check <name>`, such as a deployment, has
  succeeded on the merge. The name is stored in `after-check` beside the brief, like risk and phase.
  Only GitHub check runs are read, not commit statuses.

What was verified goes in the waiting task's `prerequisite` file: the task, repository, pull
request, delivered head, merge commit and check. Every refusal says the task remains queued and
writes nothing. `--after` now takes ship tasks only, because a plan task's pull request has no
receipt behind it. Five spawn tests, one brief test and one end-to-end test added, one task-new
test changed; 35 breaks, each failing on its own:

- Open (spawn test line 760), closed (761), running (754) and failed (757) predecessors starting.
- Wrongly targeted: the base (767), head branch (768), merged head (769) or repository (772) not
  compared. A project not on GitHub not refused (774: the repository check still refused it).
- Unverifiable: a receipt from another run read (784), no receipt required (782: the head
  comparison still refused it), the proved commit read from another phase (742), no run record
  required (787: the receipt check still refused it), an unconsumed handoff (790), one from another
  run (793) or for another pull request (796), a state GitHub did not give (798), a merge commit
  name that is not one (800), the base never fetched (742), the merge never looked for on it (802).
- Deployment-incomplete: the named check never asked (811), unfinished or failed (812), a check
  with another name counting (816), no answer from GitHub (818).
- The record never written (744) or without its check (822). `--after-check` on a task that waits
  on nothing (brief test line 565), blank, over 100 characters, or over two lines (558), its file
  at mode 644 (550) or never written (548), its line not rendered (546). A plan task accepted by
  `--after` (task-new test line 102). Spawn never reading what a task waits on (end-to-end test
  line 296).

## Task 28: Preserve prerequisite evidence through its lifecycle

**Milestone:** M3.  
**Files:** `bin/dux-recover`, `bin/dux-teardown`, related tests.  
**Acceptance:** Needed delivery evidence survives predecessor teardown; retries revalidate it; dependent removal removes its record.

- [x] Cover teardown, retry, restart, and removal.
- [x] Break-verify lost-evidence and stale-prerequisite protections.

**Landed with this task.** A delivery stays checkable after its task is torn down, and a waiting
task is checked again every time it starts. `dux-spawn` changed with the two named files, because
it is the reader.

- Teardown: before `state/` is cleared, a done task's run record, `/ship` receipts and last handoff
  are copied into `data/tasks/<id>/delivery/`, under the names `dux-spawn` reads. A copy that cannot
  be made is a finding, and the worktree and records stay. A failed task keeps nothing.
- Lost evidence: once the run record is gone from `state/`, `dux-spawn` reads that copy, and a lost
  copy leaves the waiting task queued.
- Restart and retry: a start that finds a `prerequisite` record, left by an earlier start that
  stopped after the check or carried by a retry, has to verify the same delivery again. Anything
  different leaves the task queued and the record untouched. A retry waits on the same task, under
  the same `--after-check`, and carries the record.
- Removal: abandoning a waiting task that never ran removes its folder and the record with it.

Two spawn tests, two teardown tests and one recover test added. The spawn refusal helper now also
checks that the record is left as it was and that no worktree remains. The teardown suite's stub
wrapper no longer keeps the test runner waiting five minutes after the last test. 17 breaks, each
failing on its own:

- Teardown keeping nothing (teardown test line 532), a failed copy not refused (532), the last
  handoff not copied (542), the first handoff copied instead (542), the archived receipt not copied
  (548), an earlier attempt's copy not replaced (551), a failed task's delivery kept (563).
- Spawn never reading the kept copy (spawn test line 798) or its handoff (798), a record that no
  longer matches not refused (helper line 685, called at 825), a refusal that rewrites the record
  (688, called at 825), a refusal after the worktree is made (690, called at 795), a carried record
  trusted without checking (recover test line 737).
- A retry dropping the task it waits on (736: the brief refused the check with nothing to wait on),
  the check (737: the start refused the record as no longer matching) or the record (741).
  Abandoning without removing the folder (spawn test line 821).

## Task 29: Activate supported continuation and sequencing policy

**Milestone:** M3.  
**Files:** `AGENTS.md`, `docs/constitution.md`, policy skills, affected specs, `docs/ARCHITECTURE.md`, `README.md`, this plan.  
**Acceptance:** Current instructions describe only installed support and preserve separate repository ownership.

- [x] Align answer, approval, integrated planning, and prerequisite instructions.
- [x] Retain explicit recovery for lost sessions and operator-only merge.

**Landed with this task.** The instructions now say what this checkout does, each from the
stage that carries it.

- `AGENTS.md`: from stage m3, an answer to `needs-decision` or `blocked`, and approval of a
  plan a worker committed under `--phase planning`, go to the parked session through
  `skills/dux-recover`, and an answer never approves a plan. Before that stage, or once the
  session is no longer in its tab, each is a fresh task through `skills/dux-recover`. Work in
  another repository is its own task, created `--after` the one it follows, and stays queued
  until capacity is free and what it waits on is proved merged; Dux dispatches it, not the
  operator. The file stays at 150 lines.
- `skills/dux-dispatch`: `--after` at creation, with the API change landing before its
  client; `--phase planning` only for work that needs a plan because of its size alone, since
  every other line of the plan test owes a design review that worker does not run;
  `--after-check` names an existing deployment or contract check and never invents one; a
  refusal ending `remains queued` is relayed, and a waiting task is spawned after the teardown
  of the task it waits on. Teardown's copy of the delivery, and abandon removing the record,
  are named.
- `skills/dux-recover`: the answer goes to `bin/dux-round --purpose answer` when the script's
  own `next:` line names it, and to a retry otherwise. Approval is the operator's explicit word
  on that plan, range and commit; the operator reads the plan in the worktree and this session
  does not. A retry of a waiting task waits on the same task and check. The paragraph on a
  feedback round that ends badly no longer says every other ending stops the session, since a
  question or a blocker now parks.
- `docs/ARCHITECTURE.md`, `README.md`, and status notes in the feedback-rounds and
  one-session specs carry the same. `bin/dux-doctor` now says this checkout implements m3, as
  its comment asks; the default in `templates/config/policy-stage` stays m1 until the operator
  installs R3.
- Operator-only merge is unchanged, and now pinned in `AGENTS.md` and the dispatch skill.
- The constitution needed no amendment. Principle 1's exception covers only a feedback round
  on an open pull request, and its rule that a different repository or a lost session gets a
  fresh worker is what this milestone implements. Principle 6's one fixed line per round is
  the line answer and approval rounds type.

25 breaks, one at a time, each failing at its own assertion. In `tests/contract.bats`: the old
lifecycle arrow (729); the stage m3 qualifier on answers (744); the sentence that an answer
never approves (745); the lost session left out of the fallback (746); `--purpose answer`
dropped (748); `--commit` dropped from the approval command (749); the recover skill's
sentence that an answer never starts the build (750); the plan read into the session (751);
the retry command dropped (752); `not built yet` restored (756);
`--after` dropped from `AGENTS.md` (763); the merge dropped from what a queued task waits on
(764); `--phase planning` dropped from the pair rule (765); `--after` dropped from the
`dux-task-new` usage (767); `--phase planning` dropped from the brief usage (768); any check
allowed (769); inventing one allowed (770); `remains queued` dropped (771); spawning after
teardown dropped (772); plan-first allowed for any plan (773); the design-review sentence
dropped (774); the retry of a waiting task (776); merge without the operator's explicit word
(780); the dispatch skill's merge line (781). In `tests/dux-doctor.bats`: the stage line back
at m2 (101 and 124).

## Task 30: Verify M3 and stopped-run rollback

**Milestone:** M3.  
**Files:** Continuation, approval, routing, installation, policy, and adapter tests; this plan.  
**Acceptance:** M3 acceptance below is proved without two active implementation workers. This milestone changes approval authority and cross-repository ordering, so it receives separate reviews.

- [x] Exercise integrated approval, two-repository sequencing, and the stopped-run rollback path.
- [x] Deliver through `/ship`; record actual size and installed exercise evidence.
- [ ] After operator merge, record and install R3 before external M3 application.

**Landed with this task.** Two end-to-end tests in `tests/e2e-dispatch.bats` take the milestone's
new paths through `bin/` on tmux and on the Herdr fake, with the fake worker, a fake GitHub and a
local bare remote. One worker runs at a time in each.

- Integrated approval. A ship task briefed `--phase planning` commits a plan and parks at
  `needs-decision`, and recovery names both rounds. An answer round runs in the same session,
  leaves the phase at planning with no approval record, and parks at the same question. The
  approval round names the plan, tasks 1 to 2 and a seven-digit commit; its record holds the full
  commit and the phase moves on. The same session ticks the boxes, rewrites the line under
  **Where this stands**, builds and runs the five phases, and its `done: PR` is proved and parks.
  The watcher records it done, and teardown removes the worktree and keeps the delivery.
- The stopped run. The same approval round is ended in its tab after all five phases, with both
  boxes open. The wrapper and the worker's group are gone, and the handoff is `ended`. The run
  record, receipt, approval record, phase, branch and worktree remain. Recovery proves and
  publishes nothing, because task 1 still has an unchecked box, and `--classify failed` records
  the task failed on the operator's word, with the worktree kept.
- Two-repository sequencing is Task 27's end-to-end test, run again on both backends. The task in
  the second repository stays queued while the first works, while its pull request is open, and
  until the named check passes on the merge; then it starts in its own worktree.

Ten breaks, one at a time, each failing on its own (end-to-end test lines): an answer moving the
phase on and writing an approval record (371), the approval record keeping the short commit
(378), recovery not naming the approval round (363), a question not parking (360, in the helper
at 348), a teardown whose delivery copy fails (386: it refuses, as Task 28 requires), a teardown
keeping nothing (387), the lines under **Where this stands** not exempt (381), the approved boxes
not checked (413), the receipt removed with the run's channel (409), and a classification that
does not record failed (418).

**The rollback rehearsal**, on 2026-09-16, was not committed. A scratch bats file drove this
branch's scripts to a stopped run, as in the second test, with a scout in a second repository
created `--after` it. It then followed spec section 10 on a tmux server of its own, and restored
`main` at 8d33657, milestone 2's merge, from `git archive`.

- Stopped and verified: once the session was ended in its tab, `ps` found neither the wrapper nor
  anything in its group. Handoff 2 read `ended: the session ended without a terminal status`,
  and this branch's watcher drained it.
- Recorded incomplete under this revision: its recovery proved nothing (`task 1 in
  docs/plans/p.md still has an unchecked box`), and `--classify failed` recorded it. The run
  record, context, receipt, handoffs 1 and 2, approval record, phase, the scout's `after` record,
  and the clean worktree with its plan and build commits all remained.
- Restored: with `main`'s scripts and stage m2, recovery printed the failure and offered a retry.
  The retry was refused (`a ship brief with no plan needs --risk bounded`) and its new task
  dropped, so a plan-first task comes back as a fresh task. The evidence stayed.

Two orderings matter, and the rehearsal showed each going wrong when ignored:

- Settle an `ended` plan-first run under this revision before `main`'s scripts return. In a copy
  of the home taken while it was `ended`, `main`'s recovery printed `proved <id>: done: PR
  https://github.com/acme/proj/pull/7; published as handoff 3`. Its brief names no plan, so that
  reader checks no boxes and no approval: the older reader accepting what this one refuses.
- `main` does not hold a task created `--after` another: its `dux-spawn` reads no such record, and
  it started the scout while the task it waited on was failed and never merged. Keep such tasks
  undispatched until R3 is installed again, or abandon them.

Limits: no live worker, real GitHub or CI ran in these exercises. Merging is the operator's, so no
real merge between two repositories was made, and milestone 4 owns the installed exercises that
reach real CI. The line a round types into a live session is milestone 2's, rehearsed in Task 19.

Checks: `lint-shell` and `lint-pipes` are green on macOS and on Ubuntu 24.04 as a non-root user.
The unit files and the eight matrix jobs are green under bash 5 and again under bash 3.2 on
macOS, with both end-to-end dispatch jobs at 14 tests. On Ubuntu the same run is green apart from
one tmux adapter wait in `tests/backend-adapter.bats`, the flake Task 19 records: test 36 failed
in the full parallel run and test 39 in an earlier one. Run alone, that job then passed nine times
on this branch and nine times on `main`. `lint-identifiers` fails on this machine for the reason
Task 10 records.

Size: 2,428 added lines against the milestone's estimate of 1,750 to 2,450, under the
2,500 cap.

Delivered through `/ship` with the separate reviews this milestone owes, as the pull request that
carries this note. The merged commit id and the installed-revision evidence go in the R3 row after
the operator merges.

## Task 31: Add the small usage report

**Milestone:** M4.  
**Files:** `templates/usage.md`, this plan.  
**Acceptance:** Spec section 8's phases, unknowns, failed-attempt attribution, and total rules are represented.

- [x] Add the report template attached to existing task evidence.
- [x] Check that unavailable fields remain explicit.

**Landed with this task.** `templates/usage.md` is the summary an accepted deliverable gets
from stage m4. It is copied to `data/tasks/<id>/usage.md`, beside the task's other evidence,
and filled from structured records only: a harness's own numeric usage output, or a record Dux
wrote. It has one row for each phase section 8 names: planning, design review under planning,
implementation, correctness or combined review, and the security review of a separate gate.
Each failed or retried run gets a row of its own naming the phase it failed in, and a total
comes last. Its rules carry the rest of section 8:

- Unknown is not zero, and a total that needs an unknown count is unknown.
- The four counts never overlap: a harness that counts cached tokens inside its input has them
  taken out first.
- A session's cumulative total is written once, never once per round.
- A reviewer that ran inside the worker's own session reads `in session total`.
- Phases that cannot be told apart get one `Session total` row and an unavailable phase split.
- A phase that did not happen reads `not run`, and list-price cost is not allowance used.

Checked by count, with awk over the table: seven rows, 28 count cells, all 28 `unknown`, so a
copy starts with nothing that reads as measured. `docs/ARCHITECTURE.md` lists the template and
the task file.

## Task 32: Inventory structured usage availability

**Milestone:** M4.  
**Files:** Existing task evidence and this rollout record.  
**Acceptance:** Available and unavailable numeric metadata are recorded without reading transcripts.

- [x] Inspect supported structured metadata.
- [x] Record availability and phase-separation limits for the installed harnesses.

**Inventory, taken on 2026-09-17** against Dux at `1e5dadd`, Claude Code 2.1.274 and
codex-cli 0.154.0. Each harness was probed with a one-line prompt, and only numeric fields and
key names were printed. No transcript, scrollback or worker report was opened.

| Record | Counts it gives | What they cover | Used |
|---|---|---|---|
| Codex `exec --json`, its `turn.completed` event | input with cached input inside it, cached input, cache write, output with reasoning inside it | one run; a resumed thread reports its running total | yes, task 34 |
| Claude Code `-p --output-format json`, its `modelUsage` | input, output, cache read, cache write, list cost, per model | one run, side calls included | no |
| Claude Code's status-line input | running: list cost, cache write, request count; last request only: all four counts | one interactive session | no |
| Claude Code's own config file, last-session totals | all four counts and list cost, per model | the last session to end in that repository | no |
| Dux's receipt, run, round, retry and ledger records | none | which phases ran, in which run and round, and which attempts failed | yes, for rows |

What the probes showed:

- Codex: one run that also ran a shell command wrote one `turn.completed`, input 55,813 with
  33,664 cached, output 132. A second thread ran once (input 28,384, output 5) and then
  `exec resume` ran it again: `thread.started` repeated the same id and the new total was input
  62,356, output 10. That is the running total with the first run inside it.
- Claude status line, two prompts in a scratch session: `total_input_tokens` read 9,720 and then
  18,105, which is the second request alone (10 input, 8,179 cache write, 9,916 cache read).
  Cache writes, 9,710 then 17,889, and list cost were running totals.
- Claude headless: the main loop's `usage` had input 10, `modelUsage` had input 909, so side
  calls appear only in `modelUsage`. Its cost basis is `list`.
- Last-session totals: after the probe ended in a worktree, the entry for the whole Dux
  repository held the probe's totals. Every session in that repository writes the same entry,
  the coordinator's included.

Availability for installed Dux:

- Worker sessions: unavailable. Workers run Claude Code interactively, which gives running
  totals only through a status-line command. Dux configures none, and the operator's own
  status line would lose its place in every worker tab. The last-session entry is overwritten
  by the next session to end in the same repository, so it cannot be tied to a task after the
  fact. Codex workers are refused.
- Reviews: available through `codex exec --json`, which both `/ship` passes resolve to on this
  host, once the gate asks for it. A Claude reviewer, chosen only on a host without codex, runs
  without JSON output, so its usage is unavailable.
- Planning and design review: unavailable. Plan workers are interactive sessions, and design
  reviews run by hand without JSON output.

Phase separation: one worker session holds planning for integrated work, implementation and
the gate's own steps. None of those can be split from the others, and rounds add to the same
running total. Each review is its own process, so its row separates cleanly. A reviewer
dispatched as an agent runs inside the worker's session and is counted there.

## Task 33: Extract Claude usage only where supported

**Milestone:** M4.  
**Files:** `bin/workers/claude.sh`, `tests/worker-adapter.bats`, `docs/ARCHITECTURE.md` only if supported extraction exists.  
**Acceptance:** Extraction relies on independently exposed numeric metadata; unsupported extraction is recorded as unavailable.

- [x] Qualify metadata availability and implement only the supported extraction.
- [x] Test implemented behavior; record an unavailable result instead of adding transcript collection.

**Unavailable, so nothing was built.** Task 32's probes are the qualification. A Dux worker is
an interactive Claude Code session, and the only numeric usage such a session exposes is the
input to a status-line command. Dux configures none, and adding one here would fail twice:

- It would replace the operator's own status line in every worker tab.
- Its copy would be deleted with the run's channel unless the wrapper kept it, and the wrapper
  is not this task's file.

Even kept, it would give running totals for list cost and cache writes only. Input, output
and cache reads are reported per request, so they would stay unknown. The last-session totals
in Claude Code's own config cannot be tied to a task. Headless JSON output is complete, but no
installed Dux path runs Claude headless on this host.

So `bin/workers/claude.sh` gains no extraction, and neither its tests nor
`docs/ARCHITECTURE.md` change. Worker, plan-worker and design-review counts stay `unknown` in
every usage summary, and nothing reads a transcript to fill them in. This task added no
protection, so there is nothing to break.

What would make two of those counts available is a status-line command that passes its input
on to the operator's own command and keeps a numbers-only copy, plus a wrapper change that
keeps the copy when the run ends. That is the operator's call.

## Task 34: Extract Codex and review usage only where supported

**Milestone:** M4.  
**Files:** `bin/workers/codex.sh`, `skills/ship/SKILL.md`, relevant adapter tests, `docs/ARCHITECTURE.md` where supported.  
**Acceptance:** Cumulative totals and embedded reviewer totals are not counted twice.

- [x] Add only qualified structured extraction.
- [x] Test overlap and repeated-total cases; record unsupported fields as unavailable.

**Landed with this task.** Reviews are the one place a count is available, so that is all
this task built:

- `worker_usage` in `bin/workers/codex.sh` reads a `codex exec --json` event stream. It
  prints input, output, cache read and cache write for the run, each a number or `unknown`.
- It reads only the usage field of top-level `turn.completed` events. Cached input is taken
  out of input, and reasoning is not added to output, because Codex counts both inside.
- A resumed thread counts its last running total once, and separate threads add up. A
  reviewer's events that a worker printed are text inside the worker's stream, so they are
  never counted there.
- Any count Codex did not give stays `unknown`, and so does any sum that needs it. So does
  input whenever a cache write is reported, because no probe showed whether input includes it.
- Steps 6 and 7 of `/ship` run a `codex exec` reviewer with `--json`, print its answer, then
  one `usage:` line. The pull request carries that line for every review run. Any other command
  reviewer prints `unknown`, and an agent reviewer is `in session total`.

Unavailable, and recorded as such: reasoning tokens on their own, which output already counts;
input for a run with cache writes; a reviewer not started as `codex exec`, such as one named by
full path; and every count of an agent or Claude reviewer. The `usage:` line reaches the pull
request through the worker that runs the gate, so it is as trustworthy as the gate's other
statements, such as which reviewer ran.

Run for real once on codex-cli 0.154.0, with a two-line prompt instead of a review. It printed
`usage: input=21794 output=10 cache_read=6528 cache_write=0`. It also showed that Codex writes
its answer with no final newline, which glued the usage line onto `No findings.`. The block
now ends every answer line, and the test's fake writes the answer the way Codex does.

Each protection was broken alone and its named test failed; the failure output is in the
commit that landed this task. Cached input left in input, reasoning added to output, every
total counted, only the last thread counted, no run read as zero, a malformed count read as
zero, a sum of only the known counts, a cache write ignored, events parsed out of transcript
text, a reviewer without counts read as zero, and the answer's last line left unterminated:
eleven breaks, eleven failures.

## Task 35: Close the installed delivery evidence gaps

**Milestone:** M4.  
**Files:** Existing task evidence and this rollout record.  
**Acceptance:** One bounded and one complex installed task complete `/ship`, independent proof, and real CI.

- [x] Run both installed worker-through-CI exercises.
- [x] Record each exact installed Dux revision and delivery evidence; do not substitute fake-backed tests.

**Evidence, taken on 2026-09-17 from Dux's own records.** This task dispatched nothing, because
a worker cannot start a Dux task. Both shapes had already run on installed Dux as real work, and
Dux proved each one. The installed revision is the Dux checkout's `HEAD` when the task was
dispatched, read from that checkout's reflog; any uncommitted edits it held then are not recorded.

| Shape | Task and pull request | Installed Dux at dispatch | `/ship` | Independent proof | Real CI |
|---|---|---|---|---|---|
| Bounded, plan-free | `dux-ship-20260915-d04`, [#45](https://github.com/mr-rob0to/dux/pull/45) | `8794cfb9b9b09784129cc58bc3870ab0aae7a8fb`, 2026-09-15T14:23:29Z | checks, review and security on `fe33a7e`, one fix pass | the watcher's `done` at 14:58:11Z, same revision | [run 34983872127](https://github.com/mr-rob0to/dux/actions/runs/34983872127), success |
| Complex, planned, tasks 1 to 10 | `dux-ship-20260916-i1g`, [#51](https://github.com/mr-rob0to/dux/pull/51) | `7d6952346c1810b1b4620f7df38fc550282774d7`, 2026-09-16T00:12:56Z | the same three phases on `c1fd3e3`, two fix passes | the watcher's `done` at 04:04:48Z, same revision | [run 35053183616](https://github.com/mr-rob0to/dux/actions/runs/35053183616), success |

The `/ship` column comes from each pull request's attestation comment and the proof column from
`state/events.log`. Both revisions' `bin/dux-result` requires a receipt and green checks.

What happened after R1 was installed:

- Every task dispatched since then failed Dux's 120-second start check: `dux-ship-20260916-pe3`
  and `-9my` on `423292b` (R1), `dux-ship-20260916-ufy` on `8d33657` (R2), and this task on
  `1e5dadd` (R3). The same check failed once before R1, for `dux-plan-20260915-tyi` on
  `8794cfb`. Each worker kept running in its tab with nothing supervising it.
- Two of those still delivered. [#52](https://github.com/mr-rob0to/dux/pull/52) and
  [#54](https://github.com/mr-rob0to/dux/pull/54) completed `/ship` and real CI
  ([run 35145890275](https://github.com/mr-rob0to/dux/actions/runs/35145890275),
  [run 35184544289](https://github.com/mr-rob0to/dux/actions/runs/35184544289)). Dux proved them
  later, outside the watcher: the ledger reads `done` at 2026-09-16T22:04:52Z and
  2026-09-17T14:34:00Z. The kept delivery for #54 holds a five-phase receipt on `85383ef` and the
  handoff that recorded the failed start.
- No bounded task has run on R1 or later. On the installed R3, a new exercise of either shape
  would start the same way: unsupervised, and proved only through recovery. That start check is
  the gap left open, and fixing it is not this milestone's work.
- This milestone's own delivery is the complex exercise on R3. It was dispatched at
  2026-09-17T14:53:23Z on `1e5dadd` and failed the start check at 14:55:54Z. It is delivered
  through `/ship` as the pull request that carries this note. Its proof and CI go in the R4 row
  after the operator merges.

## Task 36: Evaluate representative deliveries

**Milestone:** M4.  
**Files:** Usage summaries in existing task evidence, this plan, relevant documentation.  
**Acceptance:** Five to ten accepted deliverables cover bounded, ordinary complex, sensitive, feedback-round, and failed-attempt cases.

- [x] Summarize measured usage, missing fields, retries, and remaining limits.
- [x] Deliver applicable reporting changes through `/ship`; record actual size and R4 after operator merge.
- [x] Evaluate only the deferred thresholds in the paired spec; do not treat the sample as proof against rare defects.

**Evaluation, on 2026-09-17.** It uses the ledger, retry records, run records, receipts, each pull
request's attestation comment, and GitHub's own fields. No transcript, status text, report or
pull request prose was read.

| Deliverable | Case | Review | Attempts | Fix passes | Added lines | Tokens |
|---|---|---|---|---|---:|---|
| [#45](https://github.com/mr-rob0to/dux/pull/45) | Bounded, plan-free; replaced the delivered #44 on the operator's feedback, as a fresh task | Three phases, before review modes | 1 | 1 | 18 | unknown |
| [#43](https://github.com/mr-rob0to/dux/pull/43) | Complex, planned | Three phases, before review modes | 1 | 3 | 1,950 | unknown |
| [#50](https://github.com/mr-rob0to/dux/pull/50) | Planning: this plan and its spec, docs only | None | 4: three bounded attempts, blocked, needs-decision and ended with #49 still open, then a plan task that ended; the operator merged its pull request | none recorded | 1,720 | unknown |
| [#51](https://github.com/mr-rob0to/dux/pull/51) | Complex, planned: milestone 1 | Three phases, no mode recorded | 1 | 2 | 2,259 | unknown |
| [#52](https://github.com/mr-rob0to/dux/pull/52) | Complex, sensitive: milestone 2 | Separate | 2: the first failed at start and was retried | 0 | 1,976 | unknown |
| [#54](https://github.com/mr-rob0to/dux/pull/54) | Complex, sensitive: milestone 3 | Separate | 1 | 0 | 2,428 | unknown |
| This pull request | Complex, ordinary: milestone 4 | Combined | 1 | at the gate | see below | unknown |

Six are merged and this one waits on the operator. Task 35 has the proof and CI for each.

- **Measured usage:** none. No record gives a token count for any deliverable here. Workers ran
  as interactive sessions, which expose none (tasks 32 and 33). Every review ran before the gate
  asked Codex for its counts (task 34). A usage summary for any of them would be all `unknown`
  with the phase split unavailable, so none was written. A `data/tasks/<id>/usage.md` is also
  outside a worker's worktree.
- **Missing fields:** all four counts for implementation, planning and design review; review
  counts before this milestone; queue time; allowance used.
- **Retries:** the three bounded attempts behind #50 each stopped differently, and the plan task
  that followed ended as well. The retry behind #52 followed a start that failed Dux's start check. #44 was
  delivered, closed unmerged, and replaced by #45.
- **Cases not covered:** no feedback round has run on a delivered pull request, so the sample has
  no feedback-round delivery. #45 is the nearest: feedback on a delivered pull request, handled by
  a fresh task before rounds existed. The only ordinary complex delivery with a combined review
  is this one, not yet merged.
- **Remaining limits:** every task dispatched since R1 was installed failed the 120-second start
  check (task 35), so none was supervised or parked. A parked session is what a feedback round
  needs. Supervision and rounds stay unproved on the installed revision until that is fixed.

Deferred thresholds from spec section 11, and only those. None is met:

- **Narrower feedback-round review:** not met. No round has run, and no delivery has counts
  showing what whole-branch review costs.
- **More usage automation:** not met. No delivery has usable metadata yet, against the ten
  required, and collecting it by hand has no measured cost.
- **Token limits or allowance scheduling:** not met. No record here shows a run exhausting the
  allowance, and no harness relates usage to allowance (task 32).
- **Parallel workers:** not met. No record measures how long a task waited for the one worker
  slot.
- **General dependency graph:** not met. Every deliverable here sat in one repository, and none
  waited on another.
- **Transcript checkpoints or resumption after process loss:** not met. The sample has one start
  that failed the start check and was retried, and two attempts behind #50 that ended. None measured what a
  fresh recovery cost.
- **Further review removal:** not met. The sample has one combined-review delivery and no
  matched comparison of what each review found.

Seven deliveries do not show that rare defects are absent. A serious defect that escapes a
combined review reopens that decision, as section 11 says.

Delivered through `/ship` with the combined review its brief classified, as the pull request
that carries this note. The added lines are in the milestone table. The merged commit ID and the
installed-revision evidence go in the R4 row after the operator merges.

## Milestone acceptance

### M1

Bounded work follows planning precedence. Ordinary complex work receives one combined review after classification. Every named sensitive category receives separate reviews. Standalone classification is recorded or defaults to separate.

Combined evidence cannot satisfy a separate gate. Missing mode is conservative. Later commits invalidate stale evidence. Watcher handoffs accept valid combined, separate, and legacy receipts and reject mismatches.

Agent-consumed Markdown runs the gate; human-only prose skips it. Important proof guards have observed deliberate failures. `make check` and `/ship`'s `make check-branch` pass. Fresh sessions still use existing recovery for feedback, questions, and approval.

### M2

Feedback updates the same PR with the same worker and worktree. Every round proves its own run and final commit. Positive parking applies to wrapper and process-group admission; uncertain state blocks activation.

Duplicate requests and pending handoffs cannot activate twice. Receipts survive delayed watcher consumption after parking. Consumed handoffs are not applied twice. The ninth feedback round is refused.

The live timeout rehearsal reaches actual PR and CI proof. Teardown preserves dirty and unpushed work. Answers and approval remain unavailable.

### M3

Questions and answers continue the live owning task. Ordinary answers cannot authorize implementation. Permitted progress edits preserve approval; changed criteria, task ranges, and substantive amendments invalidate it. Incomplete boxes fail completion proof.

Plan-only delivery remains distinct from integrated work. Separate registered repositories receive separate worktrees. Unproved or incomplete prerequisites prevent dispatch, including missing required deployment evidence.

Dux starts the next authorized task after verified capacity and prerequisites. Installed exercises never run two active implementation workers.

Stopped-run rollback preserves evidence and worktrees, records incomplete status, and enters explicit recovery without acceptance by an incompatible reader.

### M4

Usage distinguishes phases and failed work where available. Unknown values stay explicit and totals do not overlap. No raw worker output enters coordinator context.

The bounded and complex installed exercises reach real CI and close the baseline gaps. Each records the exact installed revision. Representative accepted deliveries cover all required categories.

## Rollback record and procedure

Record before installation:

| Evidence | Value |
|---|---|
| Prior Dux revision | Not recorded |
| Prior installer link targets | Not recorded |
| Dated local policy backups | Not recorded |
| Affected runs and evidence locations | Not recorded |
| Verified worker shutdown | Not recorded |
| Restored compatible revision and policies | Not recorded |
| Explicit recovery disposition | Not recorded |

Spec section 10 owns the procedure: stopping activation, the order of preservation and shutdown, the verification that a worker really stopped, quarantine of pending handoffs, restoration, and what rollback must never do. Follow it there, including its two standing checks on unverified shutdown and on a defect combined review missed. This record owns the evidence table above and what each rollback actually did.

## Risks

- Fewer independent reviews may lose unique findings; measure accepted deliveries and retain category rollback.
- Receipt removal before watcher consumption can lose proved delivery; M2 must test delayed consumption.
- Policy activation ahead of runtime support gives workers unusable instructions; revisions and fresh-session checks control activation.
- Missing predecessor evidence can dispatch work against the wrong API state; preserve and revalidate it before teardown and retry.
- Missing structured usage can limit evaluation; report unavailable fields instead of collecting transcripts.
- Size estimates may be wrong; stop before implementing an oversized milestone.

## Open questions for the operator

None required to author this approved rollout. Local drift, incompatible installed choices, unavailable deployment checks, or failed backend qualification must be reported when encountered. They are not permission to expand scope.

Deferred work and its evidence thresholds are owned by spec section 11.
