# Dux simplification rollout plan

**Where this stands**
- Approved by the operator on 2026-09-15; this record does not claim any implementation task is complete.
- The token-efficiency baseline's two incomplete worker-through-CI exercises remain open; PR #46 retains feedback ownership.
- Four milestones deliver the approved changes; external policies activate only after their recorded supporting revisions are installed.

**Estimated diff:** 5,650–8,250 added lines across 36 tasks in four milestones. Each milestone remains limited to 12 tasks and 2,500 added lines. Estimates include code, tests, documentation, and patch artifacts.

**Goal:** Reduce repeated planning, unnecessary review passes, and worker restarts while keeping independently proved delivery. Dux owns repository routing and authorized sequencing; the operator supplies goals, consequential decisions, and merge approval.

**Spec:** [Dux simplification amendment](../specs/2026-09-15-dux-simplification-rollout.md). It settles the decisions inherited by this plan and amends the base orchestrator design and named earlier designs. Land the spec and this plan together under constitution principle 8.

**Deviations:** Milestone 1 narrows constitution principle 3 and changes principle 9's review policy through the required major amendment. Milestone 2 amends principle 1 for history-preserving feedback-round base merges. These changes activate with their supporting milestones, not merely when this record lands.

## Design

The paired spec owns design decisions. This plan owns execution state, exact file assignments, rollout evidence, external patch order, unavailable-feature notices, and rollback records.

Execute milestones in order. Within milestone 2, preserve PR #46's existing ownership and all nine tasks. Do not create a competing round implementation or move its same-PR update to a follow-up.

Tasks 3 to 8 land before Task 9 amends the constitution, so they owe the current rule: every assertion each of them adds is broken and seen to fail at that task. Spec section 4's narrower rule applies from Task 9's amendment onward.

Use this file's numbered task ranges when dispatching each milestone:

| Milestone | Task range | Estimated added lines | Actual added lines | Delivery evidence |
|---|---|---:|---|---|
| M1: Policy and review gate | 1–10 | 1,650–2,350 | Not recorded | Not recorded |
| M2: Amended PR #46 | 11–19 | 1,750–2,450 | Not recorded | Not recorded |
| M3: Answers, approval, sequencing | 20–30 | 1,750–2,450 | Not recorded | Not recorded |
| M4: Usage evidence and evaluation | 31–36 | 500–1,000 | Not recorded | Not recorded |

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
| R1 | All M1 acceptance requirements | Not recorded | Not recorded | Not applied by this record |
| R2 | All nine amended PR #46 tasks and M2 acceptance | Not recorded | Not recorded | Not applied by this record |
| R3 | All M3 acceptance requirements | Not recorded | Not recorded | Not applied by this record |
| R4 | M4 reporting support | Not recorded | Not recorded | No additional global patch |

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

- [ ] Make the next major constitution amendment and align the plan template's inherited testing/review instructions.
- [ ] Update current behavior and supersession notices without marking historical work complete. The superseded M7-M9 records are the three plan files named above, not specs.
- [ ] `AGENTS.md` is 130 lines against a 150-line cap `tests/contract.bats` enforces, and Tasks 19 and 29 add to it too. Point at the skills rather than restating routing, review and testing rules, and say in the PR what the file gained and lost.

## Task 10: Verify and deliver M1

**Milestone:** M1.  
**Files:** M1 test files, `tests/worker-adapter.bats`, this plan.  
**Acceptance:** M1 acceptance below is evidenced; this proof-changing milestone receives separate reviews.

- [ ] Complete integrated tests and required task-boundary break evidence; run `make check`.
- [ ] Invoke `/ship` for `make check-branch`, separate reviews, PR, and CI.
- [ ] Record delivery evidence and actual size; after operator merge, record R1 and installation evidence.

## Task 11: Qualify live prompting

**Milestone:** M2; PR #46 Task 1.  
**Files:** `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh`, existing backend tests.  
**Acceptance:** Live prompt, Stop hook, parking, and timeout behavior are qualified on both supported backends.

- [ ] Implement PR #46's prompt support and record real backend qualification.
- [ ] Test and break-verify important delivery and failure protections.

## Task 12: Move PR #46's shared helpers

**Milestone:** M2; PR #46 Task 2.  
**Files:** `bin/dux-env` and the existing callers and tests named by PR #46.  
**Acceptance:** The two existing helpers have one shared owner and preserve behavior.

- [ ] Move the two helpers according to PR #46.
- [ ] Compare declaration counts and run affected tests; record required break evidence.

## Task 13: Park delivered workers without losing receipts

**Milestone:** M2; PR #46 Task 3.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-watch`, `templates/worker-settings.json`, `tests/dux-worker-wrap.bats`, `tests/dux-watch.bats`.  
**Acceptance:** Positive Stop-only parking never removes evidence before watcher consumption.

- [ ] Add run-bound parking and retain each receipt through durable handoff application.
- [ ] Test delayed combined, separate, and legacy consumption and break-verify premature-removal protections.

## Task 14: Apply parking consistently to admission and teardown

**Milestone:** M2; PR #46 Task 4.  
**Files:** `bin/dux-env`, `bin/dux-spawn`, `bin/dux-teardown`, related tests.  
**Acceptance:** A positively parked wrapper and process group do not block solely because they remain alive; uncertain state still blocks.

- [ ] Apply the shared admission rule and preserve dirty or unpushed work on teardown refusal.
- [ ] Break-verify PID, process-group, uncertainty, and cleanup protections separately.

## Task 15: Activate rounds in place

**Milestone:** M2; PR #46 Task 5.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-env`, `tests/dux-worker-wrap.bats`.  
**Acceptance:** Every activation gets fresh identity; parking clears before prompting; pending handoffs prevent reuse.

- [ ] Implement the existing wrapper round design.
- [ ] Break-verify duplicate activation and pending-handoff protections.

## Task 16: Deliver the existing round command

**Milestone:** M2; PR #46 Task 6.  
**Files:** `bin/dux-round`, `templates/round.md`, `tests/dux-round.bats`.  
**Acceptance:** Feedback stays with its owner and the ninth feedback round is refused.

- [ ] Implement same-owner feedback and duplicate-request protection.
- [ ] Test and break-verify ownership, duplicate, and round-limit protections.

## Task 17: Prove each delivered round

**Milestone:** M2; PR #46 Task 7.  
**Files:** `bin/dux-result`, `bin/dux-watch`, `bin/dux-worker-wrap`, related tests.  
**Acceptance:** Each round proves its own run and final commit; consumed handoffs are not applied twice.

- [ ] Integrate mode-aware fresh proof and receipt retention with the watcher.
- [ ] Break-verify stale-run, stale-commit, and duplicate-consumption protections.

## Task 18: Update the same PR through shipping

**Milestone:** M2; PR #46 Task 8.  
**Files:** `skills/ship/SKILL.md`, related gate tests and evidence.  
**Acceptance:** Feedback completes `/ship` against the existing PR, with current classification, review, receipt, and CI.

- [ ] Implement existing-PR updates and history-preserving feedback base merging.
- [ ] Exercise a real feedback round through the same PR and CI; retain this task in M2.
- [ ] Break-verify: break the guard that keeps a round on its own PR, and the one that stops a feedback base repair from rewriting reviewed history, run, confirm two distinct failures, restore, paste both.

## Task 19: Activate feedback and complete the rehearsal

**Milestone:** M2; PR #46 Task 9.  
**Files:** `AGENTS.md`, `docs/constitution.md`, feedback policy skills, `bin/dux-notify`, `templates/brief.md`, PR #46 documents, `docs/ARCHITECTURE.md`, `README.md`, this plan.  
**Acceptance:** M2 acceptance below is proved; questions and approval remain unavailable. This milestone changes receipt and handoff integrity, so it receives separate reviews.

- [ ] Amend the constitution from M1's resulting version under its governance rule.
- [ ] Complete the previously failed timeout rehearsal through actual PR and CI proof and deliver through `/ship`.
- [ ] Record actual size and delivery evidence; after operator merge, record and install R2 before external M2 application.

## Task 20: Extend round purposes

**Milestone:** M3.  
**Files:** `bin/dux-round`, `templates/round.md`, `tests/dux-round.bats`.  
**Interface:** `feedback`, `answer`, and `approval` purposes under spec section 6.3.  
**Acceptance:** Each purpose enforces its own prerequisite; an ordinary answer never authorizes implementation.

- [ ] Add purpose validation.
- [ ] Break-verify waiting-state, delivered-PR, and approval distinctions.

## Task 21: Preserve owners at supported waiting states

**Milestone:** M3.  
**Files:** `bin/dux-worker-wrap`, `bin/dux-recover`, related tests.  
**Acceptance:** Supported questions and recoverable blockers preserve a live positively parked owner; failed or dead sessions use recovery.

- [ ] Extend waiting-state continuation through PR #46.
- [ ] Break-verify unsafe activation and mistaken-idle protections.

## Task 22: Add integrated task phases

**Milestone:** M3.  
**Files:** `bin/dux-brief`, `bin/dux-worker-wrap`, `templates/brief.md`, related tests.  
**Interface:** `ship` retains its shape and carries `planning|implementation` phase metadata.  
**Acceptance:** Only explicitly declared planning-phase work may start without a plan; it pauses for approval.

- [ ] Add phase metadata and planning briefs with Opus ownership throughout.
- [ ] Break-verify unauthorized implementation and plan-only worktree promotion protections.

## Task 23: Record committed-plan approval

**Milestone:** M3.  
**Files:** `bin/dux-round`, `bin/dux-recover`, related tests.  
**Acceptance:** Approval identifies the committed plan path, approved commit, and task range before implementation starts.

- [ ] Record and validate approval through the existing continuation mechanism.
- [ ] Break-verify missing, mismatched, and ordinary-answer authorization cases.

## Task 24: Permit progress edits without changing approval

**Milestone:** M3.  
**Files:** `bin/dux-result`, approval and continuation tests.  
**Acceptance:** Only checkbox state and the designated three-line status block may differ without renewed approval.

- [ ] Compare approved substance while allowing the specified progress edits.
- [ ] Test permitted edits and separately break-verify acceptance-criteria, task-range, and substantive-amendment rejection.

## Task 25: Prove approved task completion

**Milestone:** M3.  
**Files:** `bin/dux-result`, `tests/dux-result.bats`.  
**Acceptance:** Valid approval and completed boxes for the recorded range are both required.

- [ ] Extend completion proof without treating checked boxes as delivery evidence.
- [ ] Break-verify missing approval, changed substance, and incomplete-task protections.

## Task 26: Record one predecessor

**Milestone:** M3.  
**Files:** `bin/dux-task-new`, `tests/dux-task-new.bats`.  
**Interface:** Optional `--after <task-id>`; linear sequencing only.  
**Acceptance:** The dependent task owns its prerequisite reference.

- [ ] Add the single predecessor reference at creation.
- [ ] Test and break-verify invalid prerequisite input protections.

## Task 27: Verify prerequisites before dispatch

**Milestone:** M3.  
**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`, `tests/e2e-dispatch.bats`.  
**Acceptance:** Delivery proof, expected GitHub merge, fetched registered base, and named deployment or contract evidence are all checked.

- [ ] Store verified repository, PR, delivered head, and merge commit with the dependent task.
- [ ] Break-verify open, failed, wrongly targeted, unverifiable, and deployment-incomplete prerequisite refusals.

## Task 28: Preserve prerequisite evidence through its lifecycle

**Milestone:** M3.  
**Files:** `bin/dux-recover`, `bin/dux-teardown`, related tests.  
**Acceptance:** Needed delivery evidence survives predecessor teardown; retries revalidate it; dependent removal removes its record.

- [ ] Cover teardown, retry, restart, and removal.
- [ ] Break-verify lost-evidence and stale-prerequisite protections.

## Task 29: Activate supported continuation and sequencing policy

**Milestone:** M3.  
**Files:** `AGENTS.md`, `docs/constitution.md`, policy skills, affected specs, `docs/ARCHITECTURE.md`, `README.md`, this plan.  
**Acceptance:** Current instructions describe only installed support and preserve separate repository ownership.

- [ ] Align answer, approval, integrated planning, and prerequisite instructions.
- [ ] Retain explicit recovery for lost sessions and operator-only merge.

## Task 30: Verify M3 and stopped-run rollback

**Milestone:** M3.  
**Files:** Continuation, approval, routing, installation, policy, and adapter tests; this plan.  
**Acceptance:** M3 acceptance below is proved without two active implementation workers. This milestone changes approval authority and cross-repository ordering, so it receives separate reviews.

- [ ] Exercise integrated approval, two-repository sequencing, and the stopped-run rollback path.
- [ ] Deliver through `/ship`; record actual size and installed exercise evidence.
- [ ] After operator merge, record and install R3 before external M3 application.

## Task 31: Add the small usage report

**Milestone:** M4.  
**Files:** `templates/usage.md`, this plan.  
**Acceptance:** Spec section 8's phases, unknowns, failed-attempt attribution, and total rules are represented.

- [ ] Add the report template attached to existing task evidence.
- [ ] Check that unavailable fields remain explicit.

## Task 32: Inventory structured usage availability

**Milestone:** M4.  
**Files:** Existing task evidence and this rollout record.  
**Acceptance:** Available and unavailable numeric metadata are recorded without reading transcripts.

- [ ] Inspect supported structured metadata.
- [ ] Record availability and phase-separation limits for the installed harnesses.

## Task 33: Extract Claude usage only where supported

**Milestone:** M4.  
**Files:** `bin/workers/claude.sh`, `tests/worker-adapter.bats`, `docs/ARCHITECTURE.md` only if supported extraction exists.  
**Acceptance:** Extraction relies on independently exposed numeric metadata; unsupported extraction is recorded as unavailable.

- [ ] Qualify metadata availability and implement only the supported extraction.
- [ ] Test implemented behavior; record an unavailable result instead of adding transcript collection.

## Task 34: Extract Codex and review usage only where supported

**Milestone:** M4.  
**Files:** `bin/workers/codex.sh`, `skills/ship/SKILL.md`, relevant adapter tests, `docs/ARCHITECTURE.md` where supported.  
**Acceptance:** Cumulative totals and embedded reviewer totals are not counted twice.

- [ ] Add only qualified structured extraction.
- [ ] Test overlap and repeated-total cases; record unsupported fields as unavailable.

## Task 35: Close the installed delivery evidence gaps

**Milestone:** M4.  
**Files:** Existing task evidence and this rollout record.  
**Acceptance:** One bounded and one complex installed task complete `/ship`, independent proof, and real CI.

- [ ] Run both installed worker-through-CI exercises.
- [ ] Record each exact installed Dux revision and delivery evidence; do not substitute fake-backed tests.

## Task 36: Evaluate representative deliveries

**Milestone:** M4.  
**Files:** Usage summaries in existing task evidence, this plan, relevant documentation.  
**Acceptance:** Five to ten accepted deliverables cover bounded, ordinary complex, sensitive, feedback-round, and failed-attempt cases.

- [ ] Summarize measured usage, missing fields, retries, and remaining limits.
- [ ] Deliver applicable reporting changes through `/ship`; record actual size and R4 after operator merge.
- [ ] Evaluate only the deferred thresholds in the paired spec; do not treat the sample as proof against rare defects.

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
