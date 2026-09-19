# Dux simplification rollout: spec amendment

Status: approved by the operator on 2026-09-15. This document records settled design decisions. It does not establish that any milestone is implemented or installed.

Implementation and activation record: [Dux simplification rollout](../plans/dux-simplification-rollout.md).

## 1. Outcome and boundary

Reduce repeated planning, unnecessary review passes, and worker restarts while preserving evidence that a deliverable is ready to merge.

Dux remains a coordinator. One project worker owns one bounded deliverable in one repository and worktree. Dux handles routing and sequencing. The operator supplies goals, answers consequential questions, and decides when to merge.

Preserve:

- Project checks, test-first development, and targeted break-verification.
- Independent shipping review and separate security review for the sensitive changes named below.
- Completion proof against Git, GitHub, the reviewed commit, and the shipping receipt.
- Worktree isolation, green CI, verification of reviewer findings, and operator-only merge.
- The existing boundary around worker text. Dux never reads worker transcripts or terminal scrollback.
- Existing task shapes, registry, worker tool restrictions, status handoffs, and coordinator restart limits.

No parallel implementation, allowance scheduler, general workflow engine, usage database, or automatic global-configuration changes are authorized.

Note, 2026-09-18: the operator lifted the parallel-workers deferral. Dux now runs up to `config/max-workers` workers at once; see `docs/plans/2026-09-18-several-workers-at-once.md` and section 5.7 of the orchestrator spec.

The baseline records a successful second-worker refusal and later start. It also records repeated setup for small PR feedback. It does not measure the unique value or cost of a second shipping review, design-review overhead, or savings from narrower break-verification. Savings from those changes remain hypotheses.

The two incomplete installed worker-through-CI exercises in the token-efficiency plan remain incomplete until milestone 4 supplies the missing evidence. A local test or reviewer launch is not completed delivery.

## 2. Policy change 1: planning precedence

| Change | Written plan | Independent design review |
|---|---|---|
| Bounded: no unresolved consequential choice, no named interface or boundary change, at most three commit-sized steps | No, unless requested | No |
| Ordinary complex: several steps within settled architecture | Yes | Only if consequential decisions remain |
| Public contract, stored data, security boundary, concurrency, or cross-system ordering | Yes | Yes |
| Operator explicitly requests a plan | Yes | Apply the same design-review triggers |
| Human-only prose | When useful or requested | Apply the triggers to the proposed design |

A consequential decision is an unresolved choice about externally visible behavior, stored information, authority, ordering, or an expensive-to-reverse architectural choice. Naming, formatting, and routine choices within an established pattern do not qualify. Implementing already-settled behavior does not itself create an unresolved consequential choice.

Apply this order:

1. Named interface or boundary changes require a plan and design review regardless of size or whether the intended behavior is settled.
2. Other unresolved consequential choices require a plan and design review.
3. An explicit plan request requires a plan.
4. Otherwise use the bounded or ordinary-complex row.

A prose document proposing a consequential design still receives the required design review. Complexity and shipping sensitivity are separate decisions.

## 3. Policy change 2: shipping review and final-commit evidence

| Change | Required review |
|---|---|
| Bounded implementation | One independent combined review |
| Ordinary complex implementation | One independent combined review |
| Auth, permissions, secrets, migrations, data integrity, concurrency, or cross-repository ordering | Separate correctness and security reviews |
| Every changed file is human-only prose | Skip `/ship`; open or update the docs PR |

The combined review covers correctness, regressions, tests, compatibility, and relevant security concerns. It explicitly reports what it examined and any clean areas.

Operational instructions are not human-only prose. `AGENTS.md`, skills, templates, and agent/tool-consumed configuration do not qualify for the exception.

The human-only prose exception applies only when every changed file qualifies. Otherwise any named sensitive category requires separate reviews, regardless of size or planning classification. Combined review applies only after the whole-branch diff has been checked and classified as non-sensitive.

Dux records the initial classification and reason in the brief. `/ship` checks the actual whole-branch diff before launching reviewers. Sensitive changes escalate to separate reviews. Unknown or missing classification defaults to separate. Feedback rounds recheck classification and cannot silently downgrade the task. A combined receipt cannot satisfy a separate-review task.

Standalone `/ship` needs no Dux brief. It checks the same categories and records its classification and reason in local evidence before launching reviewers. If it cannot establish or record the classification, it uses separate reviews. This is an instruction and evidence requirement, not a new classifier.

| Example | Planning | Shipping |
|---|---|---|
| Small visible change implementing agreed wording; no named interface or boundary change | Bounded; no plan unless requested | Combined |
| Small visible change with an unresolved consequential behavior choice | Plan and design review | Combined unless sensitive |
| One-step public API change with settled behavior | Plan and design review | Combined unless sensitive |
| Small permissions fix or data migration | Plan and design review | Separate |
| Several steps within settled architecture; no named boundary change | Plan; no design review | Combined |
| Human-only design document proposing concurrency changes | Plan and design review | Docs PR; skip `/ship` |
| Standalone ordinary complex change with no brief | Planning rules still apply | Combined after recorded non-sensitive classification |
| Classification remains missing or uncertain | Planning requirements remain | Separate |
| Feedback adds a sensitive change | Apply planning triggers to the change | Escalate to separate |

Verify every finding against the code and a reachable failure or attack path. Verified Critical or High findings, including findings described as Important, block delivery. Fix lower findings or explicitly defer them with a reason. Proposed architectural changes go to the operator.

Fix commits receive scoped review sufficient to cover the changed code. Remove the Critical-only re-review exception. Each new operator feedback round receives the required whole-branch review. Further reduction of that repetition is deferred.

`/ship` owns the full pre-merge checks. Remove duplicate full checks immediately before the gate; retain task-level checks and required installed-path exercises.

Sol remains the named shipping reviewer. An HTTP 400 permits the existing Terra fallback once. Record the actual reviewer in local evidence and disclose the fallback to the operator. Keep commits and PR prose free of model attribution.

### 3.1 Review mode and receipt lifetime

Add `--review combined|separate` to `dux-brief`. Store the choice alongside existing task risk metadata and render it in the brief.

Update `ship-guard`, `dux-result`, and `dux-watch` together:

- Introduce a versioned receipt with explicit review mode.
- Combined phases: `checks`, `review`, `pr`, `ci`.
- Separate phases: `checks`, `review`, `security`, `pr`, `ci`.
- Never record an unperformed security phase as completed.
- Bind mode and phase evidence to the task, run, branch, and relevant commit.
- Reject missing, invalid, mismatched, stale, or incomplete evidence.
- Read legacy receipts only under their existing separate-review requirements.
- Clear required phase evidence on a fix pass and re-establish it before push and delivery.

The watcher's `receipt_complete()` and `read_handoff()` enforce the same version, mode, identity, commit, and phase requirements as completion proof.

A delivered run's completed receipt stays immutable and readable at the path the watcher validates until the watcher has validated and durably applied that run's handoff. Publication, a Stop event, and parking do not establish consumption.

Before consumption, the wrapper must not rename the receipt to `.delivered`, delete it, or overwrite it for another run. After consumption, it may archive the receipt as that run's `.delivered` evidence. A pending handoff blocks a new round. Watcher retries must not apply a consumed handoff twice.

These checks protect against accidental skipped reviews and stale evidence. They do not contain a deliberately hostile process running as the operator.

## 4. Policy change 3: targeted break-verification

| Protected behavior | Required evidence |
|---|---|
| Validation bypass, auth or permission failure, money error, data loss or corruption, concurrency failure, missed cleanup, security defect, or a previously observed bug | Test-first evidence and a deliberate break of the protected behavior |
| Ordinary formatting, layout, straightforward mapping, or happy-path behavior without those consequences | Normal test-first evidence |
| A mixed test | Break the important protected behavior; ordinary assertions do not each require mutation |

The unit is a distinct failure protection, not an assertion count.

For each important protection, record the behavior broken, the named test that failed, actual failure output, and restoration. Distinct protections require distinct observed failures. If a deliberate break leaves the test green, investigate before completing the task.

Required break-verification stays at the task boundary. Milestone 1 makes the next major constitution amendment because this narrows an existing testing principle.

## 5. Policy change 4: bounded delegation

| Work | Owner or mechanism |
|---|---|
| Implementation | Project worker; no nested parallel implementation |
| Required independent reviews | Fresh read-only sessions through explicit commands |
| Clearly independent, bounded read-only research | Optional when it answers a specific question and reduces useful work |
| Routine file reading or exploration without a defined question | No automatic delegation |
| Coordination | Dux dispatches, supervises, and reports; it does not implement project changes |

Retain the existing six Claude tools and empty MCP configuration. Do not add a general Agent tool to satisfy obsolete instructions.

## 6. Policy change 5: session boundaries and implementation models

A routine test failure is fixed by the owning implementation worker. Remove the blanket prohibition on debugging in the session that wrote the code.

A new deliverable, different repository, substantial milestone, or lost session requires a fresh worker and its own worktree.

Retain Sonnet medium for bounded implementation and Opus max for complex implementation. Standalone planning and required independent design reviews remain Fable high.

After R2 is installed, delivered-PR feedback uses PR #46's same-worker, same-task, same-worktree, same-PR round mechanism.

After R3 is installed:

- Questions and recoverable blockers within the deliverable continue the live owning worker.
- Approval of a plan created within the implementation deliverable continues that worker after approval is recorded.
- Integrated plan-and-build work uses Opus for both phases. There is no live model switch and no nested implementation.

Before those revisions are installed, use existing recovery. Approval of this design does not activate future runtime behavior.

### 6.1 PR #46 ownership and amendments

PR #46 retains ownership of the long-lived wrapper, live-tab feedback, `bin/dux-round`, `templates/round.md`, same-owner feedback, fresh run identity and completion proof per round, same-PR `/ship` updates, eight feedback rounds, and safe teardown. Do not open a competing implementation.

Its required amendments are:

| Existing provision | Settled amendment |
|---|---|
| Five phases and two reviews every round | Use section 3's review modes; retain fresh receipts, final-commit proof, and whole-branch review per delivered round |
| Rename receipt after handoff publication | Retain it until watcher consumption under section 3.1 |
| Parked-worker exemption | Require positive parking and apply it to both wrapper PID and process-group checks |
| Idle timeout | Timeout does not establish idle state or release capacity |
| Operator repairs outdated base | Dux assigns an ordinary merge from the fetched base to the owning feedback worker; stop for a consequential conflict decision |
| Task 9 prescribes constitution 2.0.9 | Amend the version resulting from milestone 1 under the governance rule; do not prescribe or restore 2.0.9 |
| Task 8 may move to a follow-up | Retain all nine tasks in milestone 2, including same-PR updating |

The earlier failed rehearsal is not delivery evidence. The current re-cut still requires its applicable review and a successful live rehearsal.

### 6.2 Positive parking and admission

Store a small run-bound parked marker only after the wrapper observes that run's Stop-only event.

Spawn and round activation use the same admission helper:

- Active or uncertain worker evidence blocks activation.
- A consistent parked marker exempts both the live wrapper and its process group.
- Claiming a round clears the exemption before prompting.
- Repeated requests and pending handoffs cannot start a second activation.
- Timeout or inconsistent evidence triggers recovery, never an assumption of idleness.

Parking does not consume a handoff or permit receipt removal.

The operator may watch a tab without exposing it to Dux. Managed feedback goes through Dux. Direct typing into parked tabs is outside the enforced one-active-worker guarantee.

### 6.3 Answers and committed-plan approval

Extend PR #46's round purposes to `feedback`, `answer`, and `approval`.

Feedback requires a proved delivered PR. An answer requires the matching waiting state and a live, positively parked owner. Approval additionally identifies the committed plan path, task range, and approved commit. An ordinary answer cannot authorize implementation.

Each resumed stretch receives fresh run identity and supervision. Failed or dead sessions use explicit recovery.

Integrated work retains the `ship` shape and adds `planning|implementation` phase metadata. Only an explicitly declared planning-phase ship task may start without an existing plan. It creates the plan and pauses at `needs-decision`. Recorded approval advances it to implementation.

Only these differences from the approved commit preserve approval:

- Checkbox state changes on existing task entries without changing text, identity, order, or membership.
- Progress-only updates inside the designated three-line “Where this stands” block.

All other plan changes invalidate approval, including acceptance criteria, task descriptions, constraints, membership, and substantive amendments. A changed approved task range also requires renewed approval.

Progress text cannot authorize new work. Recording a substantive amendment in the status block does not exempt it from renewed approval.

Completion proof compares the current plan with the approved commit, allowing only those progress differences, then checks completed boxes for the approved task range. Checkbox updates preserve authorization but do not replace delivery evidence.

Use one implementation worktree from the start. Never promote a plan-only worktree or change its permissions midway. The existing eight-round limit applies across continuations. Reaching it requires a clearer task boundary, not an automatic context reset.

## 7. Policy change 6: Dux-owned routing and verified sequencing

Dux selects a registered repository from registry facts when the goal clearly belongs there. Ask the operator only when repository intent is genuinely ambiguous.

Each new task gets an isolated worktree in its registered repository. Cross-repository deliverables use separate tasks and worktrees, executed sequentially.

The active-worker cap applies across all registered repositories and worker harnesses. Required reviewers work within the active deliverable and do not create another implementation owner.

When another worker is active, leave work queued. Dux dispatches the next authorized task after verified capacity release. Do not require the operator to manage capacity or launch a separate Herdr worker outside Dux.

Multiple positively parked sessions may remain open after R2. Activation still passes the global admission check. No capacity settings, reservations, repository-picker workflow, or parallel execution are introduced.

Note, 2026-09-18: the operator lifted the parallel-workers deferral. Tasks in one repository or several run at the same time up to `config/max-workers`, and rounds are not counted against it; see `docs/plans/2026-09-18-several-workers-at-once.md`.

### 7.1 Recorded prerequisites after R3

Add one optional `--after <task-id>` reference at task creation. Support linear sequencing only.

Before dependent dispatch:

1. Resolve the predecessor through Dux's recorded project and proved PR.
2. Verify its final delivery evidence.
3. Confirm the expected PR merged through GitHub.
4. Fetch the registered upstream base and verify the merge commit is present.
5. Store the verified repository, PR, delivered head, and merge commit with the dependent task.

Capture needed evidence before predecessor teardown removes receipts. A ledger state alone is insufficient.

If deployment is required, the brief names the existing deployment or contract check and its required result. A merge alone is insufficient. Do not invent a generic deployment checker.

Preserve API-first ordering and existing contract generation and synchronization commands.

The dependent task owns the prerequisite record. Retry preserves and revalidates it. Task removal removes it. Missing, failed, abandoned, or unverifiable predecessors leave the dependent queued.

Dux starts the next already-authorized task while handling verified completion or merge through existing events and task files. This does not add a background scheduling service.

## 8. Policy change 7: minimal usage evidence

After R4, attach one small usage summary to each accepted deliverable's existing task evidence.

Report planning, design review as a planning subcategory, implementation, correctness or combined review, separate security review, and retries or failed runs with their underlying phase identified.

Include exposed input, output, cache-read, and cache-write counts. Include a total only when entries are complete and non-overlapping.

Unknown is not zero. Do not repeatedly add cumulative session totals across rounds or count reviewer usage again when a harness total includes it. List-equivalent cost is not subscription allowance consumption. Attribute failed attempts to the eventual accepted deliverable.

When phases cannot be separated, report the session total and mark the phase split unavailable.

Start with a report template and existing structured metadata. Add adapter extraction only where the installed harness exposes numeric usage independently of transcript text. Do not scrape scrollback, prompts, or raw worker reports.

## 9. Milestones, ownership, and activation

The paired rollout plan owns exact file assignments, numbered tasks, revision records R1–R4, external patch application order, unavailable-feature notices, installation evidence, and rollback records.

| Stage | Settled scope | Tasks | Estimated added lines |
|---|---|---:|---:|
| M1 | Policy and review gate | 10 | 1,650–2,350 |
| M2 | All nine amended PR #46 tasks | 9 | 1,750–2,450 |
| M3 | Answers, approval, and repository sequencing | 11 | 1,750–2,450 |
| M4 | Usage evidence and measured evaluation | 6 | 500–1,000 |

Each milestone must be independently mergeable and usable within 12 tasks and 2,500 added lines. Estimates include tests, documentation, and patch artifacts. Stop before implementing an oversized milestone. Reduce incidental scope or obtain a revised usable split. Required same-PR support cannot be deferred to meet a size limit.

Ownership boundaries:

- The operator applies external policies and chooses installed links. Workers never edit those external files.
- The policy owner aligns repository instructions and prepares staged external patches.
- The gate owner changes classification, review selection, receipts, completion proof, and watcher validation together.
- The PR #46 owner supplies feedback and positive parking.
- The continuation owner extends that mechanism after M2.
- The routing owner maintains prerequisites across creation, dispatch, retry, teardown, and removal.
- The installer owner checks compatibility and availability without overwriting explicit local choices.
- The usage owner adds only supported structured reporting.
- Owners work sequentially where files overlap.

R1–R4 are placeholders until full merged commit IDs are recorded. Install that revision, or a descendant retaining its required support, before activating the corresponding policy.

Repository policies and linked skills follow the same stages as external patches. Before R2, feedback uses existing recovery. Before R3, answers and approval use existing recovery, integrated continuation is unavailable, and recorded prerequisite dispatch is unavailable.

## 10. Migration and rollback

Apply external patches through visible operator action. Compare current files, inspect symlink targets, save dated backups, review the complete diff, and apply the global patch once to the shared target. Apply the standalone ship patch or explicitly select the reviewed Dux skill link. Start fresh sessions and verify what each host loads.

Do not replace newer local files wholesale or silently unlink shared files.

Finish or explicitly stop active workers before changing linked skills or wrappers. Preserve dirty and unpushed work. Install only a merged, reviewed revision. Preserve explicit configuration, report incompatible reviewer overrides, detect conflicting copies and links, and show proposed physical-directory replacement before backup and replacement.

Render new briefs and settings only for new tasks. Keep legacy receipt requirements conservative.

Before rollback, stop new activation. Drain safely when possible. If completion is broken:

1. Preserve run identities, receipts, pending handoffs, approval and prerequisite records, feedback files, PR references, and worktrees.
2. Stop affected workers through explicit stop or recovery and verify both wrapper and worker processes stopped.
3. Record unfinished runs as incomplete and quarantine their pending handoffs without deleting evidence.
4. Restore the prior compatible runtime, linked skills, and policy backups.
5. Route preserved tasks through explicit recovery. Do not feed incompatible proof to the older reader or relabel it successful.

If shutdown cannot be verified, keep activation disabled and do not replace supervision.

Rollback never resets a dirty worktree or merges a PR. If continuation fails, use explicit fresh-task recovery. If combined review misses a serious defect caught by focused security review, restore separate reviews for that category immediately.

## 11. Supersession and deferred work

The base orchestrator design remains authoritative outside these named changes.

Retain the token-efficiency baseline's plan-free bounded shipping, risk-based models, one active Dux-managed worker, Sonnet coordinator, and restricted worker tools with qualified review. At the matching installed milestone, supersede universal separate security review, blanket deferral of minimal usage reporting, and operator-managed capacity retry.

Note, 2026-09-18: "one active Dux-managed worker" no longer holds; the operator lifted the parallel-workers deferral. See `docs/plans/2026-09-18-several-workers-at-once.md`.

Retain live terminals from the interactive-worker-sessions spec. Replace its pending resume-by-session-ID mechanism with PR #46's live-session continuation. Retain the one-session-planning spec's approval and bounded-context intent; supersede nested implementation delegation.

Do not revive M7–M9, their page generator, or a separate plan-to-implementation framework. Historical evidence and checkboxes remain intact; add short supersession notices.

Deferred thresholds:

| Work | Evidence required before proposing it |
|---|---|
| Narrower feedback-round review | Five to ten measured deliveries show whole-branch review dominates usage; retain final-commit coverage |
| More usage automation | At least ten deliveries with usable metadata and repeated collection costs above five minutes |
| Token limits or allowance scheduling | Serialized runs repeatedly exhaust allowance and harness data meaningfully relates usage to it |
| Parallel workers | Material measured queue delay after serialization and separate operator approval. Note, 2026-09-18: the operator lifted this deferral; see `docs/plans/2026-09-18-several-workers-at-once.md` |
| General dependency graph | Repeated workflows cannot fit a linear prerequisite chain |
| Transcript checkpoints or resumption after process loss | Multiple measured losses make bounded fresh recovery materially expensive |
| Further review removal | Matched evidence shows no unique important findings; a serious escaped defect reopens the decision |

Five to ten successful deliveries do not establish the absence of rare defects.

Rejected alternatives remain one global implementation agent, automatic parallel workers, universal two-review shipping, operator-managed repository routing, an allowance scheduler, policy-only receipt changes, a competing continuation design, automatic global-file installation, and broad nested delegation.

Note, 2026-09-18: parallel workers are no longer a rejected alternative; the operator lifted the deferral, bounded by `config/max-workers`. See `docs/plans/2026-09-18-several-workers-at-once.md`.

Fewer independent reviews may lose unique findings. That tradeoff remains subject to measured evaluation and rollback.
