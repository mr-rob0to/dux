# Dux Simplification Plan: rollout record

**Where this stands**
- Approved by the operator 2026-09-15, after an independent design review whose six
  blocking findings are folded into the tables below rather than kept as a separate log.
- No milestone has started. This document is the docs-only landing of the plan itself;
  Milestone 1 is the next piece of work, in its own plan file when it starts.
- PR #46 (branch `dux/dux-plan-20260915-tyi`) is retained as-is for now. It owns the
  feedback-round mechanism this plan reuses in Milestone 2; the amendments this plan
  requires of it (below) land on its own branch before its implementation starts, not here.

**Goal:** Reduce repeated planning, unnecessary review passes, and worker restarts in Dux,
while keeping the independent evidence that a deliverable is actually ready to merge:
project checks, test-first development with targeted break-verification, independent
shipping review and a separate security review for named sensitive changes, completion
proof against Git/GitHub/the reviewed commit/the shipping receipt, worktree isolation,
green CI, verified reviewer findings, and operator-only merge.

**Explicitly out of scope:** parallel implementation, an allowance scheduler, a general
workflow engine, a usage database, automatic changes to global configuration.

**Spec pointers:** this plan amends, supersedes in part, or reconciles with —
`docs/specs/2026-09-03-dux-orchestrator-design.md` (remains authoritative outside the
named changes below), `docs/specs/2026-09-11-token-efficiency.md` (five delivered changes
retained, three items explicitly superseded once their milestone installs — see
Reconciliation), `docs/specs/2026-09-14-interactive-worker-sessions.md` (live-terminal
behavior kept, pending resume-by-session-id retired in favor of PR #46's live-session
continuation), `docs/specs/2026-09-10-one-session-planning.md` (approval and
bounded-context intent kept, planner-delegates-to-nested-workers superseded), and PR #46's
own spec for the feedback-round mechanism it owns. Each implementation owner amends the
spec it touches, with a short supersession note, in the same PR as its milestone's plan.

## Design

### Current behavior and measured problems

| Area | Current evidence | Change and measurement limit |
|---|---|---|
| Planning & model selection | Token-efficiency spec identifies concurrent long Fable/Opus runs and growing contexts as the measured problem. Main already supports plan-free bounded work and Sonnet/Opus risk routing. | Retain that implementation. Remove contradictory global instructions. Do not restart the baseline program. |
| Worker capacity | Baseline plan records an installed second-worker refusal and a successful later start. | Preserve one active worker globally. Dux handles the retry and routing. |
| Shipping reviews | Both global policies mandate two passes; local `ship-guard` requires three pre-push phases; `dux-result` and the watcher require five shipping phases. | Introduce combined and separate review modes across the gate, completion proof, and watcher. The baseline does **not** measure the unique value or cost of the second review; savings remain a hypothesis to test. |
| Design reviews | Global policy requires a review for every non-trivial plan; Dux already exempts bounded work. | Require design review only for the specified consequential decisions and interfaces. No isolated measurement of design-review overhead exists. |
| Break-verification | Global policy and constitution principle 3 require breaking every new assertion. | Narrow the requirement to important guards and regression tests. No measured savings from this change exist yet. |
| Continuation | Main ends interactive workers at terminal status; answers generally create another task. | Reuse PR #46's continuation mechanism, then extend it to questions and approval. Activate those instructions only when their supporting runtime is installed. |
| Feedback cost | PR #46 records a one-line correction after a 17-line change requiring another task, worktree, gate, and replacement PR. | Concrete evidence of repeated setup, not yet a quantified token-saving result. |
| Delegation | `bin/dux-brief` requires a design-review subagent; the Claude adapter exposes six tools without the Agent tool; global policy also broadly requests subagents. | Replace conflicting instructions with explicit review commands and optional bounded read-only research. |
| Usage | Baseline deferred accounting; interactive worker output lives in the terminal rather than stream-output files. | Report available structured usage and label missing usage. Do not revive transcript collection. |

The baseline plan explicitly leaves two installed worker-through-CI exercises incomplete.
This plan carries those limitations forward. A successful local test or reviewer launch is
not evidence of completed delivery.

### Reconciliation with existing designs

**Current main:** keep the existing task shapes, registry, worktree mechanisms,
risk-based implementation models, worker tool restrictions, status handoffs, completion
proof, and coordinator restart limits. The 2026-09-03 orchestrator design remains
authoritative outside the named changes here.

**Token-efficiency baseline:** retain the five delivered changes: plan-free bounded
shipping, bounded/complex implementation models, one active Dux-managed worker, Sonnet
coordinator default, restricted worker tools with qualified Codex security review.
Explicitly supersede, when the corresponding milestone installs: the requirement for a
separate security pass on every shipment; the blanket deferral of minimal usage
reporting; instructions making the operator retry dispatch after capacity frees up. All
other deferred systems remain deferred.

**PR #46: reuse, with named amendments.** PR #46 remains active design work. Its failed
rehearsal is not evidence its implementation works, and its earlier review record does not
establish review of its current re-cut. It retains ownership of: the long-lived wrapper
and live-tab feedback mechanism; `bin/dux-round` and `templates/round.md`; same-task,
same-worktree, same-PR feedback; fresh run identity and completion proof per round;
updating an existing PR through `/ship`; eight feedback rounds and safe teardown. Do not
open a competing implementation of these features.

Amendments required before PR #46's implementation starts (applied on its own branch, not
by this document):

| PR #46 section | Amendment |
|---|---|
| §§6, 9: five phases, two reviews every round | Use the review mode from Policy tables below. Preserve a fresh receipt, final-commit proof, and whole-branch shipping review per delivered round. The watcher accepts the same receipt modes as the gate and completion proof. |
| §3: receipt renamed to `.delivered` after publishing the handoff | Keep the completed, run-bound receipt readable at the path the watcher validates until the watcher has consumed and applied that run's handoff. Publishing or parking does not establish consumption. Archive only after consumption. |
| §8: parked-worker exemption | Require positive evidence the worker finished its turn and parked. Apply the exemption consistently to wrapper PID and process-group checks — main checks wrapper PID first, so exempting only the process group still blocks dispatch. |
| §3: idle timeout | A timeout must not establish a worker is idle or release its capacity slot. Keep it unavailable for another activation until recovery establishes its state. |
| §§4, 13: operator repairs an outdated base | Dux assigns the repair to the owning worker: an ordinary merge from the fetched base during a feedback round, preserving reviewed commits. Stop for a consequential conflict decision. |
| Implementation Task 9: constitution version 2.0.9 | Remove the prescribed patch version. Milestone 1 makes the major amendment the constitution's governance rule requires; Task 9 amends the resulting current version under that rule and must not restore or prescribe 2.0.9. |
| Implementation header: Task 8 may move to a follow-up | Remove that exception. All nine tasks belong to Milestone 2, including Task 8's existing-PR update — feedback rounds are not usable functionality until they can finish `/ship` against the same PR. |

Later continuation work extends PR #46's explicit exclusions for `needs-decision` and
recoverable `blocked` states; it does not rebuild its round mechanism.

**Older continuation plans:** keep the live terminal behavior from the interactive-worker
spec; retire its pending resume-by-session-id mechanism in favor of PR #46's live-session
continuation; retain the approval and bounded-context intent of the one-session-planning
spec; supersede that spec's planner-delegates-implementation-to-nested-workers design; do
not revive milestones 7–9, their page generator, or a separate plan-to-implementation
framework. Historical plans retain their original evidence and checkboxes; add short
supersession notices rather than rewriting history as completed work.

The policy tables below describe the final state. Rollout order (see below) controls when
each part activates. Until its supporting milestone is merged and installed, that
behavior remains explicitly unavailable and existing recovery instructions stay in force.

### Policy tables

**Planning**

| Change | Written plan | Independent design review |
|---|---|---|
| Bounded: no unresolved consequential choice, no named interface/boundary change, ≤3 commit-sized steps | No, unless requested | No |
| Ordinary complex: several steps, settled architecture | Yes | Only if consequential decisions remain |
| Public contract, stored data, security boundary, concurrency, or cross-system ordering | Yes | Yes |
| Operator explicitly requests a plan | Yes | Same design-review triggers apply |
| Human-only prose | Only when useful/requested | Apply design-review triggers to the proposed design |

A *consequential decision* is an unresolved choice about externally visible behavior,
stored information, authority, ordering, or an expensive-to-reverse architectural choice.
Naming, formatting, and routine choices within an established pattern do not qualify.
Implementing already-settled behavior does not itself create an unresolved consequential
choice.

Apply the table in this order: a named interface or boundary change requires a plan and
design review regardless of size or settledness; another unresolved consequential choice
also requires a plan and design review; an explicit plan request requires a plan;
otherwise use the bounded or ordinary-complex row. A prose document proposing a
consequential design still receives the required design review. Complexity and review
sensitivity are separate decisions — an ordinary complex change can use one shipping
review.

**Shipping reviews**

| Change | Required review |
|---|---|
| Bounded implementation | One independent combined review |
| Ordinary complex implementation | One independent combined review |
| Auth, permissions, secrets, migrations, data integrity, concurrency, or cross-repository ordering | Separate correctness and security reviews |
| Human-only prose | Skip `/ship`; open or update the docs PR |

The combined review covers correctness, regressions, tests, compatibility, and relevant
security concerns, and reports what it examined and any clean areas. Operational
instructions are *not* human-only prose: `AGENTS.md`, skills, templates, and
agent/tool-consumed configuration do not qualify for the exception.

Precedence: the human-only prose exception applies only when every changed file
qualifies; otherwise any named sensitive category requires separate reviews, regardless
of size, planning classification, or other overlapping categories. Combined review
applies only after the whole-branch diff has been checked and classified as non-sensitive.

Classification rules: Dux records the initial classification and reason in the brief;
`/ship` checks the actual whole-branch diff before launching reviewers; sensitive changes
always escalate to separate reviews; unknown or missing classification defaults to
separate reviews; feedback rounds recheck classification and cannot silently downgrade
the task; a separate-review task cannot satisfy its gate with a combined-review receipt.
For standalone `/ship` with no Dux brief, the gate establishes and records the
classification and reason in its own evidence the same way; a missing brief does not
prevent an explicit classification, and if the gate cannot establish one it uses separate
reviews.

Examples:

| Example | Planning outcome | Shipping outcome |
|---|---|---|
| Small visible change implementing agreed wording, no named interface/boundary change | Bounded; no plan unless requested | Combined |
| Small visible change with an unresolved consequential behavior choice | Plan and design review | Combined unless a sensitive category also applies |
| One-step public API change with settled behavior | Plan and design review | Combined unless a sensitive category also applies |
| Small permissions fix or data migration | Plan and design review | Separate |
| Several steps within settled architecture, no named boundary change | Plan; no design review | Combined |
| Human-only design document proposing a concurrency change | Plan and design review | Docs PR; skip /ship |
| Standalone ordinary complex change with no Dux brief | Planning rules still apply | Combined after /ship records a non-sensitive classification |
| Missing or uncertain classification after the gate checks the diff | Planning requirements not waived | Separate |
| Feedback adds a sensitive change to a previously combined-review task | Apply planning triggers to the new change | Escalate to separate |

Finding resolution: verify each finding against the code and a reachable failure or
attack path; verified Critical/High findings, including findings described as Important,
block delivery; lower findings are fixed or explicitly deferred with a reason; a proposed
architectural change goes to the operator; fix commits receive scoped review sufficient to
cover the changed code, with no "Critical fixes only" exception that contradicts
final-commit proof; a new operator feedback round gets the required whole-branch review;
removing that repetition is deferred pending evidence.

Sol remains the named shipping reviewer. An HTTP 400 permits the existing Terra fallback
once. Record the actual reviewer in local review evidence and disclose the fallback to the
operator; keep commits and PR prose free of model attribution.

**Break-verification**

| Test protects against | Evidence required |
|---|---|
| Validation bypass, auth/permission failure, money error, data loss or corruption, concurrency failure, missed cleanup, security defect, or a previously observed bug | Test-first evidence **plus** a deliberate break of the protected behavior |
| Ordinary formatting, layout, straightforward mapping, or happy-path behavior without those consequences | Normal test-first evidence |
| Mixed test containing both | Break the important protected behavior; ordinary assertions do not each require a mutation |

The unit is a distinct failure protection, not an assertion count. For each important
protection, record the behavior broken, the named test that failed, actual failure output,
and restoration. Distinct protections require distinct observed failures. If a deliberate
break leaves the test green, investigate before completing the task.

**Delegation**

| Work | Policy |
|---|---|
| Implementation | Owned by the project worker; no nested parallel implementation |
| Required independent reviews | Fresh read-only sessions through explicit commands |
| Clearly independent, bounded read-only research | Optional when it answers a specific question and reduces useful work |
| Routine file reading or exploratory work without a defined question | No automatic delegation |
| Dux coordinator | Dispatches, supervises, reports; does not implement project changes |

Keep the existing six Claude tools and empty MCP configuration. Do not add a general
Agent tool merely to satisfy old instructions.

**Session boundaries and models**

| Situation | Owner and session |
|---|---|
| Question or recoverable blocker within the deliverable | Continue the live owning worker, once Milestone 3 is installed |
| Approval of a plan created as part of the same implementation deliverable | Continue that worker after approval is recorded, once Milestone 3 is installed |
| Feedback on a delivered PR | PR #46 round, same worker, once Milestone 2 is installed |
| Explicit plan-only assignment | Fable planning worker; the plan is its deliverable |
| New deliverable, different repository, substantial milestone, or lost session | Fresh worker, own worktree |
| Routine test failure while implementing | Owning worker fixes it; the blanket "never debug in this session" prohibition is removed here |

Retain Sonnet medium for bounded implementation and Opus max for complex implementation.
For an integrated plan-and-build task, Opus owns both phases once Milestone 3 installs —
an explicit amendment to the global "Fable does all planning" rule, avoiding an unverified
live model switch and nested implementation. Standalone planning and required independent
design reviews remain Fable high. This model exception is an assumption to approve, not a
measured efficiency finding.

**Repository routing**

| Situation | Dux responsibility |
|---|---|
| Goal clearly belongs to a registered repository | Select it from registry facts |
| Repository is genuinely ambiguous | Ask which product/repository the operator intends |
| New task | Create an isolated worktree in its registered repository |
| Another worker is active | Leave work queued; dispatch the next authorized task after verified capacity release |
| Worker is positively parked | May remain open once Milestone 2 is installed; activation still passes the global admission check |
| Cross-repository deliverable | Separate tasks and worktrees, executed sequentially |
| Dependent repository change | Verify its recorded prerequisite before dispatch, once Milestone 3 is installed |

The cap applies across all registered repositories and worker harnesses. Required
reviewers operate within the active deliverable; they do not create another
implementation owner. No capacity settings, repository-picker workflow, parallel
execution, or reservations are introduced.

### Small runtime changes

**Review mode and proof.** Add `--review combined|separate` to `dux-brief`. Store it
alongside existing task risk metadata and render it in the brief. Update `ship-guard`,
`dux-result`, and `bin/dux-watch` together: a versioned receipt with explicit review mode;
combined sequence checks → review → pr → ci; separate sequence checks → review → security
→ pr → ci; never record a security phase as completed when it did not run; bind mode and
phase evidence to the task, run, branch, and relevant commit; reject missing, invalid,
mismatched, stale, or incomplete evidence; read legacy receipts only under their existing
separate-review requirements; clear required phase evidence on a fix pass and re-establish
it before push and delivery. The watcher's `receipt_complete()` and `read_handoff()` must
enforce the same version, mode, identity, commit, and phase requirements as completion
proof; a valid combined receipt must be accepted, and a combined receipt must not satisfy
a separate-review task.

For each delivered run, the completed receipt remains immutable and readable at the
receipt path the watcher checks until the watcher has validated and durably applied that
run's handoff. Publication, a Stop event, and parking do not count as consumption. The
wrapper must not rename it to `.delivered`, delete it, or overwrite it for a later run
before consumption; after consumption it may be archived as that run's `.delivered`
evidence. A new round stays blocked while the preceding handoff is pending, and its
receipt must not replace the preceding run's evidence. Watcher retries must tolerate
already-consumed handoffs without applying them twice. Test combined, separate, and legacy
receipts through watcher handoff processing, including rejected mismatches and delayed
watcher consumption after the worker has parked. This protects against accidental skipped
reviews and stale evidence; it does not claim to contain a deliberately hostile process
running as the operator.

**Questions and approval through PR #46.** Extend its round command with explicit
purposes: feedback, answer, and approval. Feedback requires a proved delivered PR; an
answer requires the matching waiting state and a live, positively parked owner; approval
additionally identifies the committed plan path, task range, and approved commit; an
ordinary answer cannot authorize implementation; every resumed stretch receives fresh run
identity and supervision; failed or dead sessions use the existing explicit recovery path.

For integrated plan-and-build work, retain `ship` as the task shape and add
`planning|implementation` phase metadata. A planning-phase ship task may start without an
existing plan only when explicitly declared as such: it creates the plan and pauses at
`needs-decision`. Approval records the exact committed plan and approved task range before
advancing to implementation; completion proof refuses delivery without valid approval and
completed plan criteria.

Separate approved substance from mutable progress through a narrow edit allowance.
Against the approved commit, only these changes preserve approval:

- Checkbox state changes on existing task entries, without changing task text, identity,
  order, or membership.
- Updates inside the plan's designated three-line "where this stands" block, treated only
  as progress reporting.

All other plan changes invalidate approval, including changed acceptance criteria, task
descriptions, constraints, task membership, or substantive amendments. A changed approved
task range also requires renewed approval, even when the plan file itself is unchanged.
Progress text cannot authorize new work or override the approved content. Substantive
amendments recorded in the status block still require a substantive plan change and
renewed approval before affected work proceeds.

Completion proof compares the current plan with the approved commit using only those
allowed progress differences, then checks the current completion boxes for the recorded
approved task range. Checkbox updates preserve authorization; they do not replace the
existing evidence that the work is complete. Use one implementation worktree from the
start — never promote a plan-only task's worktree or change its permissions midway. The
existing eight-round limit applies across continuations; reaching it requires a clearer
task boundary, not an automatic context reset.

**Positive parking and admission.** Store a small run-bound parked marker only after the
wrapper observes the Stop-only event for that run. Both spawn and round activation use the
same admission helper: active or uncertain worker evidence blocks activation; a consistent
parked marker exempts the worker's live wrapper and process group; claiming a round clears
the exemption before prompting; repeated requests and pending handoffs cannot start a
second activation; timeout or inconsistent evidence triggers recovery, never an idle
assumption. Parking does not consume a delivery handoff or permit removal of its receipt —
the receipt lifetime above applies even when the wrapper is positively parked. A tab
watched by the operator remains outside coordinator context; managed feedback goes through
Dux, and directly typing into parked tabs cannot be presented as part of the enforced
one-active-worker guarantee.

**Verified repository prerequisites.** Add one optional `--after <task-id>` dependency to
task creation, linear sequencing only. Before starting the dependent task: resolve the
predecessor through Dux's recorded project and proved PR; verify its final delivery
evidence; confirm the expected PR merged through GitHub; fetch the registered upstream
base and verify the merge commit is present; store the verified repository, PR, delivered
head, and merge commit with the dependent task. Capture the necessary delivery evidence
before predecessor teardown removes receipts — a ledger label alone is insufficient.
Without that stored evidence, teardown or a coordinator restart can leave a queued client
task with only a "done" label and no proof tying it to the API PR that actually merged.

If deployment is required, merged code is insufficient: the brief must name the existing
deployment or contract check and the required result; Dux does not invent a generic
deployment checker. For API/client work, preserve API-first ordering and the repositories'
existing contract generation and synchronization commands. The dependency record belongs
to the dependent task; retry preserves and revalidates it, task removal removes it.
Missing, failed, abandoned, or unverifiable predecessors leave work queued. Dux chooses
and starts the next already-authorized task when handling the predecessor's verified
completion or merge: coordinator policy using existing events and task files, not a
background scheduling service.

**Minimal usage evidence.** One small usage summary per accepted deliverable, attached to
its existing task evidence. Report separately: planning (design review as a subcategory),
implementation, correctness/combined review, separate security review, and
retries/failed runs with their underlying phase identified. Include exposed input, output,
cache-read, and cache-write counts; include a total only when entries are complete and
non-overlapping. Unknown is not zero; cumulative session totals must not be added
repeatedly across rounds; reviewer usage must not be added twice when a harness total
already includes it; list-equivalent cost is not subscription allowance consumption;
failed attempts remain attributed to the eventual accepted deliverable; if phase usage
cannot be separated, report the session total and mark the phase split unavailable. Start
with a report template and existing structured metadata; add adapter extraction only where
the installed harness demonstrably exposes numeric usage independently of transcript text.
Do not scrape scrollback, prompts, or raw worker reports.

### Exact files and ownership

Runtime names without a directory below are under `bin/`; template names are under
`templates/`; test names are under `tests/`.

| Owner | Files | Change |
|---|---|---|
| Operator, machine-local | `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md` symlink | Apply reviewed global policy changes at the matching milestone; preserve one shared file |
| Operator, machine-local | `~/.agents/skills/ship/SKILL.md` & installed links | Apply reviewed standalone gate update, or explicitly select Dux's linked gate |
| Dux policy worker | `AGENTS.md`, `docs/constitution.md` | Align planning, review, delegation, testing, routing, and session rules only as their supporting milestones become available |
| Dux policy worker | `skills/dux-dispatch`, `skills/dux-recover`, `skills/dux-status`, `skills/dux-project` | Internal routing, continuation, authorized sequencing, registration boundaries; staged activation |
| Dux policy worker | this rollout record and patch files in `docs/plans/patches/` for milestones 1–3 | External patch artifacts, application order, minimum merged revision records, and unavailable-feature notices |
| Gate worker | `skills/ship/SKILL.md`, `ship-guard`, `ship-env`, `dux-result`, `dux-watch` | Review classification, mode-aware proof and watcher validation, consistent reviewer selection |
| Gate worker | `dux-brief`, `dux-worker-wrap`, `templates/brief.md`, PR template | Render and carry policy and review evidence |
| PR #46 owner | `dux-round`, `templates/round.md`, `dux-worker-wrap`, `dux-env`, `dux-spawn`, `dux-teardown`, `dux-notify`, `dux-backend`, backends, `templates/worker-settings.json` | Existing feedback-round scope plus the named parking corrections |
| PR #46 owner, after gate changes | `dux-watch`, `dux-worker-wrap`, `dux-round`; the feedback-rounds spec | Receipt retention through handoff consumption; delayed watcher handling; all nine tasks retained; Task 9 constitution version reconciled |
| Continuation worker, after #46 | `dux-round`, `dux-recover`, `dux-brief`, `dux-worker-wrap`, `dux-result`, templates | Answers, committed-plan approval, permitted progress edits, phase metadata |
| Routing worker | `dux-task-new`, `dux-spawn`, `dux-recover`, `dux-teardown` | Single prerequisite reference, verification, lifecycle preservation |
| Installer worker | `dux-install`, `dux-doctor`, `templates/config/*` | Upgrade checks, truthful defaults, conflict reporting, milestone availability checks |
| Operator, untracked local state | `config/models`, `models-codex`, `reviewer`, `security-reviewer`, `worker-harness`, `backend` | Review conflicts; preserve explicit choices |
| Usage worker | `templates/usage.md`; `bin/workers/claude.sh`, `codex.sh`, ship skill where metadata exists | Minimal usage report; no transcript ingestion |
| Each implementation owner | `docs/ARCHITECTURE.md`, named specs/plans, `README.md`, this rollout record | Update current behavior, ownership, migration, minimum revision evidence, supersession notes, and matching rollback instructions |

**Tests, by area:**
- Gate: `ship-guard.bats`, `ship-env.bats`, `dux-result.bats`, `dux-brief.bats`, `dux-watch.bats`.
- Continuation: `dux-worker-wrap.bats`, `dux-recover.bats`, new PR #46 `dux-round.bats`, `dux-watch.bats`, backend and supervision tests.
- Approval: continuation tests and `dux-result.bats`, covering permitted progress edits and rejected substantive changes.
- Routing: `dux-task-new.bats`, `dux-spawn.bats`, `dux-teardown.bats`, `e2e-dispatch.bats`.
- Installation & policy: `dux-install.bats`, `dux-doctor.bats`, `contract.bats`, `worker-adapter.bats`, including staged availability and stopped-run rollback.

Owners work sequentially where files overlap. Retain `templates/worker-mcp.json`,
worktree isolation, and base-push protection; do not broaden their authority.

### Migration and installation

Project workers never edit the two external policy files
(`~/.codex/AGENTS.md` / `~/.claude/CLAUDE.md`, `~/.agents/skills/ship/SKILL.md`). The
policy deliverable contains focused before/after patches for the global instructions and
standalone `/ship` skill, plus a short checklist identifying each removed contradiction.
Patches are prepared together, but each is applied only at its activation stage.

This record names these minimum revisions:

- **R1** — the actual merged Dux commit containing all Milestone 1 acceptance requirements.
- **R2** — the actual merged Dux commit containing Milestone 2, including all nine amended PR #46 tasks.
- **R3** — the actual merged Dux commit containing all Milestone 3 acceptance requirements.
- **R4** — the actual merged Dux commit containing Milestone 4's reporting support.

These names are placeholders for recorded full commit IDs, not permission to apply a patch
against an unspecified revision. After each merge, record its actual commit ID here before
applying that stage's external patches. The installed revision must be that commit or a
descendant retaining the required support.

| Stage | External artifacts | Min. revision | Policy activated |
|---|---|---|---|
| Milestone 1 | `m1-global.patch`, `m1-ship.patch` | R1 | Planning precedence, review modes and classification, targeted break-verification, delegation, routine debugging, removal of duplicate full checks and Critical-only re-review, Dux-owned routing and capacity retry instructions |
| Milestone 2 | `m2-global.patch`, `m2-ship.patch` | R2 | Delivered-PR feedback in the owning session, positive parking, same-PR shipping updates, feedback-round base merging |
| Milestone 3 | `m3-global.patch` | R3 | Same-session answers and approval, integrated Opus planning and implementation, verified repository prerequisites and dependent dispatch |
| Milestone 4 | No additional global patch required | R4 | Usage reporting and supported structured extraction |

Repository policies and linked skills follow the same stages. Milestone 1 must not
instruct a worker to continue a question, approval, or feedback round its runtime cannot
support. Until R2 installs, feedback uses existing recovery. Until R3 installs, questions
and approval use existing recovery, integrated plan-and-build continuation is unavailable,
and recorded prerequisite dispatch is unavailable. Future sections here must say so
explicitly.

The operator applies each eligible patch explicitly: compare it with the current local
files; inspect actual symlink targets; save dated local backups and record the current
link targets; review the complete diff in an editor; apply the global patch once to the
shared target; either apply the corresponding standalone ship patch or explicitly replace
that installation with the reviewed Dux skill link; start fresh sessions and verify which
global file and ship skill each host loads. Never replace a newer local file wholesale
from a pasted snapshot. Never silently unlink either shared file.

The staged global patches resolve existing conflicts: duplicate full checks before and
inside `/ship`; universal subagent use; universal fresh-session debugging; universal
two-review shipping; "Critical-only" re-review versus changed-commit proof; automatic
Herdr worker creation outside Dux after a Dux-managed merge; mandatory rebasing of
feedback rounds whose history must be preserved.

**Existing Dux installations:** finish or explicitly stop active workers before changing
linked skills or wrappers; preserve dirty and unpushed worktrees; install only a merged,
reviewed Dux revision; preserve explicit `config/*` values and report incompatible
reviewer overrides rather than rewriting them; update stale bundled comments describing
obsolete reviewer fallbacks; show proposed physical-directory replacement before using the
installer's existing backup behavior; detect conflicting physical copies and links across
Claude and shared skill locations; render new briefs and settings only for new tasks,
never rewrite running workers' copies; read old receipts under old requirements, never
reinterpret an old receipt as combined review; legacy tasks without new metadata retain
conservative behavior.

The constitution amendment narrows an existing testing principle. Milestone 1 uses the
next major version under its governance rule rather than describing the amendment as a
clarification. PR #46 Task 9 starts from that resulting version and applies the
governance rule to its own changes; its old 2.0.9 instruction is superseded.

## Rollout order and acceptance criteria

Four independently mergeable and usable milestones, each within the existing 12-task and
2,500-added-line limits. Estimates below include code, tests, documentation, and patch
artifacts; they are planning estimates, not measured diff sizes. Record actual task counts
and added lines before implementation and as work lands.

| Milestone | Tasks | Est. added lines |
|---|---|---|
| 1 — Policy and review gate | 10 | 1,650–2,350 |
| 2 — PR #46 with required amendments | 9 | 1,750–2,450 |
| 3 — Answers, approval, and repository sequencing | 11 | 1,750–2,450 |
| 4 — Usage evidence and measured evaluation | 6 | 500–1,000 |

If sizing exceeds a limit, stop and report the overrun before implementing the oversized
milestone. Reduce incidental scope or seek a revised independently usable split. Do not
defer a required acceptance dependency, including PR #46 Task 8, while calling the
remaining milestone usable.

### Milestone 1 — Policy and review gate

1. Reconcile policy, table precedence, examples, and the named PR #46 amendments.
2. Prepare staged external patches, the activation record, and unavailable-feature notices.
3. Add brief review metadata and conservative legacy behavior.
4. Add versioned receipt modes to `ship-guard`.
5. Update `/ship` classification, standalone classification evidence, and reviewer instructions.
6. Update `dux-result` mode-aware completion proof.
7. Update watcher receipt and handoff validation for combined, separate, and legacy proof.
8. Add installer and doctor migration checks, including policy activation prerequisites.
9. Activate only Milestone 1 repository policy; make the major constitution amendment and update architecture documentation.
10. Complete integrated proof tests, targeted break-verification, and the shipping gate.

Acceptance: bounded work requires no plan or design reviewer; unresolved consequential
choices and named interface changes follow the stated precedence; ordinary complex work
launches one combined reviewer after classification; every named sensitive category
launches separate reviewers; standalone `/ship` records its own classification or defaults
to separate; combined evidence cannot satisfy a separate gate; missing mode defaults to
separate; a later commit invalidates stale evidence; watcher handoffs accept valid
combined, separate, and legacy receipts and reject mismatches; agent-consumed Markdown
runs the gate, human-only prose skips it; important proof guards are deliberately broken
and their tests fail; `make check` and `/ship`'s `make check-branch` pass.

Fresh sessions at this stage must still receive existing recovery instructions for
feedback, questions, and approval. Record R1 before applying the Milestone 1 external
patches. This milestone changes completion proof and therefore receives separate reviews.

### Milestone 2 — Deliver PR #46 through its existing ownership

Qualify the live prompt, Stop hook, parking, and timeout behavior on both supported
backends. Implement the amended PR #46 plan without a competing round implementation.

| PR #46 task | Milestone 2 scope and required amendment |
|---|---|
| 1: `dux-backend prompt` | Live prompt support and qualification on both backends |
| 2: Two helpers move into `dux-env` | Shared helpers used by the existing round design |
| 3: Wrapper parks and waits after `done: PR <url>` | Positive Stop-only parking; retain the run's receipt until watcher consumption; test delayed consumption |
| 4: Guard and teardown know a parked session | Consistent wrapper PID and process-group admission; uncertain state still blocks |
| 5: Wrapper runs a round in place | Fresh run identity; clear parking before activation; pending handoffs block reuse |
| 6: `dux-round` | Same-owner feedback, duplicate-request protection, existing round limit |
| 7: Proof of a round | Mode-aware fresh proof and final-commit coverage, including watcher integration |
| 8: `/ship` edits a pull request it finds | Required same-PR update; remains in this milestone with no follow-up exception |
| 9: Documents, brief, notification | Activate supported feedback policy, update the constitution from Milestone 1's version, record R2, and complete the live rehearsal |

Acceptance: feedback updates the same PR with the same worker and worktree; every round
proves its own run and final commit; a parked worker does not block another worker solely
because its wrapper remains alive; a worker without positive idle evidence still blocks
another activation; duplicate requests and pending handoffs do not activate twice;
combined, separate, and legacy delivery receipts remain readable during delayed watcher
consumption after parking; consumed handoffs are not applied twice; the ninth feedback
round is refused; the previously failed timeout rehearsal completes through actual PR and
CI proof; dirty or unpushed work is preserved on teardown refusal.

Same-session answers and approval remain explicitly unavailable at this stage. Apply only
the Milestone 2 external patches after R2 is recorded and installed.

### Milestone 3 — Answers, approval, and repository sequencing

1. Extend round purpose validation for feedback, answer, and approval.
2. Preserve a live, positively parked owner at supported waiting states.
3. Add planning and implementation phase metadata and planning-phase briefs.
4. Record approval of the committed plan path, commit, and task range.
5. Validate permitted checkbox and status-block edits while rejecting substantive changes.
6. Extend completion proof to require valid approval and completed approved tasks.
7. Add the single predecessor reference at task creation.
8. Verify predecessor delivery, merge, fetched base, and named deployment or contract evidence before dispatch.
9. Preserve prerequisite evidence through teardown and revalidate it on retry.
10. Activate matching coordinator and recovery instructions, repository policies, and the Milestone 3 external patch.
11. Complete integrated approval, sequencing, stopped-run recovery, and installed single-worker exercises.

Acceptance: a question and answer continue the same live task; an ordinary answer cannot
authorize implementation; checkbox-only and designated status-block updates preserve
approval; changed acceptance criteria, task ranges, and substantive plan amendments
invalidate approval; incomplete boxes fail completion proof; plan-only delivery remains
distinct from integrated planning and implementation; two registered repositories receive
separate isolated worktrees; an open, failed, wrongly targeted, or unverifiable
prerequisite prevents dependent dispatch; a merged prerequisite without required
deployment evidence remains insufficient; Dux starts the next authorized task without
asking the operator to manage capacity or worktrees; no test or installed exercise runs
two active implementation workers.

Record and install R3 before applying the Milestone 3 global patch. Exercise rollback with
a new-format run that cannot complete: it must remain incomplete, preserve its evidence
and worktree, and enter explicit recovery without being accepted by an incompatible proof
reader.

### Milestone 4 — Usage evidence and measured evaluation

1. Add the small usage report template and attribution rules.
2. Inspect existing structured metadata and record available and unavailable fields.
3. Add Claude adapter extraction only if independently exposed numeric metadata supports it.
4. Add Codex and review extraction only where supported, with overlap and cumulative-total checks.
5. Complete one bounded and one complex installed worker-through-CI exercise and record installed revisions.
6. Collect and summarize five to ten representative accepted deliverables, including feedback and failed attempts.

Unsupported extraction is recorded as unavailable, not replaced by transcript collection.
Acceptance: include bounded, ordinary complex, sensitive, feedback-round, and
failed-attempt cases; usage distinguishes phases and failed work where available; unknown
values remain explicit; repeated cumulative totals are not double-counted; the coordinator
never reads raw worker output; at least one bounded and one complex installed task
complete `/ship`, independent proof, and real CI, closing the baseline's outstanding
exercise gaps. For each installed exercise, record the exact Dux revision installed.
Fake-backed tests do not substitute for backend qualification or forge-dependent delivery.

## Rollback

Preserve the prior Dux revision, installer link targets, and local policy backups. Stop
new activation before rollback. Drain workers when the current runtime can finish safely,
and restore runtime, linked gate, and active policies as a compatible set. Keep worktrees,
PRs, feedback files, receipts, and delivery evidence intact.

If the new completion path is broken, do not require it to finish before reverting. Use
this stopped-run path:

1. Stop dispatch and round activation, including queued automatic activation.
2. Preserve each affected task's run identity, receipts, pending handoffs, approval and prerequisite records, feedback files, PR references, and worktree.
3. Stop the affected workers through the existing explicit stop or recovery procedure. Verify both wrapper and worker processes have stopped; a timeout or parked marker alone is insufficient.
4. Record each unfinished run as incomplete, with the rollback reason and preserved evidence location. Quarantine its pending handoff from automatic application without deleting the evidence.
5. Restore the prior compatible runtime, linked skills, and matching policy backups. Do not feed incompatible receipts or pending handoffs to the older proof reader.
6. Route preserved incomplete tasks through explicit recovery. Recovery inspects their state through the existing trusted boundary, preserves dirty and unpushed work, and starts an authorized fresh run or task with proof produced by the restored runtime.

If worker shutdown cannot be verified, keep activation disabled and report the unresolved
state. Do not replace supervision underneath a worker that may still be running. Preserved
new-format proof remains evidence for recovery, not a successful delivery under an older
reader — never relabel incomplete or incompatible proof as successful. If continuation
fails, stop activating rounds and use explicit fresh-task recovery. If combined review
misses a serious defect that a focused security review catches, restore separate reviews
for that category immediately. Rollback never resets a dirty worktree or merges a PR.

## Deferred work and evidence thresholds

These are decision thresholds, not promised statistical confidence.

| Deferred work | Evidence required before proposing it |
|---|---|
| Further reduction of feedback-round review scope | 5–10 measured deliveries show repeated whole-branch review dominates usage; any proposal retains reliable final-commit coverage |
| Usage automation beyond a small report | ≥10 deliveries with usable metadata, manual collection repeatedly >5 min per deliverable |
| Hard token limits or allowance scheduling | Serialized runs repeatedly exhaust allowance, and harness data can meaningfully relate observed usage to it |
| Parallel project workers | Measured queue delay remains material after serialization; separate operator approval required |
| General dependency graph or workflow engine | Repeated real workflows cannot be expressed as a linear prerequisite chain |
| Automatic transcript checkpoints / session resumption after process loss | Multiple measured losses make bounded fresh-task recovery materially expensive |
| Removing more review coverage | Matched evidence shows the removed pass adds no unique important findings; any serious escaped defect reopens the decision |

No claim is made that five to ten successful deliveries prove the absence of rare defects.

## Rejected alternatives

- **One global implementation agent** — mixes repository context and deliverable ownership, recreating the growing-context problem. Keep a small coordinator and bounded project workers.
- **Automatic parallel workers** — reintroduces contention against the measured shared-allowance problem. One active implementation worker remains.
- **Mandatory two-review shipping for every change** — lacks measured incremental value for ordinary changes. Separate passes remain mandatory for the named sensitive categories. Fewer independent reviews may lose unique findings; that tradeoff remains subject to measured evaluation and rollback.
- **Operator-managed repository routing** — makes the operator do registry and sequencing work Dux already has the facts to handle. Ask only when intent is ambiguous.
- **Token-budget scheduler** — usage availability and subscription accounting are insufficiently understood. Start with evidence.
- **Policy-only review simplification** — would leave runtime receipts and watcher validation requiring a security pass and make honest combined-review delivery impossible.
- **A second continuation design** — duplicates PR #46 and creates competing lifecycle rules.
- **Automatic global-file installation by workers** — hides changes affecting every project. Global rollout remains a human-reviewed local operation.
- **Broad nested delegation** — conflicts with bounded ownership and the deliberately restricted worker tools.

## Assumptions and open questions for the operator

These do not block producing this plan.

- "One active worker" permits multiple positively parked sessions once the supporting runtime is installed. Idle waiting does not grant permission to activate alongside another worker.
- Integrated plan-and-build work uses Opus throughout once Milestone 3 is installed; standalone planning remains Fable.
- The supplied external policy text is the review baseline; the operator checks for local drift before applying each staged patch.
- PR #46's current re-cut still needs review and a successful live rehearsal. Its lifecycle failure does not abandon its design ownership.
- Structured usage may be unavailable for interactive Claude sessions. Reporting that limitation satisfies the initial evidence requirement.
- Repository-specific deployment prerequisites use existing checks. Any missing check is a named prerequisite to resolve, not permission to build a workflow engine.
- R1–R4 receive actual merged commit IDs as milestones land. No external patch becomes eligible merely because its artifact exists.
- Milestone line estimates remain estimates until checked against the implementation. Required same-PR shipping support cannot be removed to meet a size limit.
