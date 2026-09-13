# Dux focused token-efficiency plan

**Where this stands**
- Approved by the operator and being implemented as one five-task milestone.
- The earlier independent review and the later scope review are recorded below; no second review is planned.
- All five tasks landed 2026-09-13, `make check` green after each. `make check-branch` green,
  both passes. 1,576 added lines against `origin/main`, under the 2,500 cap.
- Two boxes stay open on purpose: the two that claim a worker's own task finished `/ship`
  with green CI. It did not, and the next section says exactly where it stopped.

**What the installed exercises did and did not reach**

- The second-worker refusal ran end to end on the installed scripts, real tmux, real git:
  the first task started, the second was refused with nothing created, and the same second
  task started once the first had finished and been torn down. Task 2's commit has the output.
- The PR 37-style bounded, plan-free task ran installed with a real Claude worker on
  2026-09-13. The brief rendered no `Plan`/`Tasks` lines and `- Risk: bounded`; the worker
  started on `claude-sonnet-5 --effort medium` with `--tools Bash,Read,Glob,Grep,Write,Edit
  --strict-mcp-config --mcp-config <repo>/templates/worker-mcp.json --no-chrome`; it made the
  change, met all three acceptance criteria, and followed the throwaway project's own
  `CLAUDE.md`, which the tool restriction therefore did not take away. It opened `/ship`,
  resolved the base, ran the checks phase and started the step 6 reviewer, which resolved to
  Codex `gpt-5.6-sol`.
- It did not finish `/ship`. The run ended while waiting on the background correctness
  reviewer, and **no ship receipt was written**, so no phase is provable from the repository.
  The throwaway project's origin is a local bare repository, so the pull request and CI phases
  could not have run either way. A Dux worker has no authority to create a repository on the
  operator's forge, so the forge-dependent half of these two boxes was not run at all. That is
  a limit of the exercise, not a result: nothing here evidences a green CI run on a worker's
  own pull request.
- The complex planned path through `/ship` with real CI is this milestone's own ship task:
  an Opus worker on a planned milestone, delivering through the gate this branch changed.
- Task 4's last box, the two installed workers through `/ship`, runs with the milestone's
  own installed exercises after Task 5. Task 4 takes the Agent tool away, and the security
  phase needs it until Task 5 routes that pass to Codex through Bash; run before Task 5
  the exercise would be measuring a gate the pair is halfway through replacing.

**Divergences from the approved plan**
- No `CHANGELOG.md` is written. The repository has never had one, and starting a changelog
  convention is work nobody asked for. Architecture and spec notes carry the same facts.
- `templates/config/models` loses its `ship=` entry rather than keeping it beside the new
  `bounded=` and `complex=` ones. A key nothing reads is a trap: an operator would edit it
  and see no change. Existing installs keep whatever they have; `dux-install` only ever adds.

**Estimated diff:** about 1,200 added lines across five tasks, including tests, fixtures,
architecture notes and changelog entries. The milestone stays below the 2,500-line and
12-task limits.

**Goal:** Stop the measured token waste with the smallest sound change: skip planning for
obvious work, use Sonnet for bounded implementation, run one Dux-managed Claude worker at
a time, trim unused worker tools, and move the security pass to qualified Codex Sol.

**Approach:** Keep the existing `plan`, `ship` and `scout` shapes. Dux applies a short
planning checklist; scripts enforce only a stored `bounded|complex` choice and the rule
that plan and task range are both present or both absent. A plan-free ship still runs the
unchanged `/ship` gate. `dux-spawn` refuses a second live worker instead of adding a queue
scheduler. The existing reviewed Sonnet operator change is absorbed here. The security
reviewer changes only after one fixture qualification succeeds.

**Rejected alternatives:** The prior usage database, allowance scheduler, pause/resume
state machine, operator accounting, plan-page generator, ship rewrite and benchmark
system do not have to exist to stop the measured waste. A new task shape adds lifecycle
branches for no gain. Parsing task prose or calling a classifier to decide whether a plan
is needed spends tokens and creates an unreliable control. Removing `/ship`, tests,
correctness review, security review or CI would lower quality and is not allowed.

**Assumptions:** All dispatched workers currently use Claude. Existing installations run
`dux-install` after this milestone so the two new model entries are present. Missing risk
on a legacy task means `complex`. Other Claude sessions and devices remain outside Dux's
view. An explicit request for a plan always wins.

**Constraints:** Bash 3.2; existing dependencies only; trusted local workers; no raw worker
text in operator context; no automatic merge. Every new assertion is broken and seen to
fail at its task boundary. The full build, tests, lint, installed-path exercise, `/ship`,
fresh Codex Sol correctness review, separate security pass and CI remain required. No AI
attribution is written to commits, pull requests or review comments.

**Risks:** Dux could label genuinely complex work as bounded; the checklist fails closed
on named triggers and `/ship` still gates delivery. A stuck worker can block later starts;
the refusal names it and the operator uses existing recovery before retrying the queued
task. Claude flags can behave differently from help text; Task 4 qualifies the real CLI
before changing the adapter. One security fixture run is limited evidence; that trade-off
is explicit and automated requalification stays deferred.

**Spec:** [Focused token-efficiency design](../specs/2026-09-11-token-efficiency.md).

## Files

| Area | Files changed |
|---|---|
| Direct shipping and routing | `AGENTS.md`, `skills/dux-dispatch/SKILL.md`, `bin/dux-brief`, `bin/dux-worker-wrap`, `bin/dux-result`, `bin/dux-recover`, `bin/dux-install`, `templates/brief.md`, `templates/config/models`, related bats tests |
| Worker serialization | `bin/dux-spawn`, `tests/dux-spawn.bats` |
| Sonnet operator | `.claude/settings.json`, `.gitignore`, `tests/contract.bats`, `docs/ARCHITECTURE.md` |
| Smaller worker environment | `bin/workers/claude.sh`, `templates/worker-mcp.json`, `tests/worker-adapter.bats` |
| Security reviewer | `skills/ship/ship-env`, `skills/ship/SKILL.md`, `tests/ship-env.bats`, three security-review fixtures |
| Shared documentation | `docs/ARCHITECTURE.md`, `CHANGELOG.md` |

## Task 1: Ship obvious work directly and route implementation by risk

**Files:** Modify `AGENTS.md`, `skills/dux-dispatch/SKILL.md`, `bin/dux-brief`,
`bin/dux-worker-wrap`, `bin/dux-result`, `bin/dux-recover`, `bin/dux-install`,
`templates/brief.md`, `templates/config/models`, `tests/dux-brief.bats`,
`tests/dux-worker-wrap.bats`, `tests/dux-result.bats`, `tests/dux-recover.bats`,
`tests/dux-install.bats`, `docs/specs/2026-09-03-dux-orchestrator-design.md`,
`docs/ARCHITECTURE.md`, `CHANGELOG.md`.

**Interfaces:** `dux-brief` accepts `--risk bounded|complex` for `ship`; omission defaults
to `complex`. It atomically writes mode-600 `data/tasks/<id>/risk`. Ship plan and task
range must be both present or both absent; the absent pair requires `bounded`. New model
keys are `bounded=claude-sonnet-5:medium` and `complex=claude-opus-5:max`. Plan and scout
routing stay unchanged. A legacy missing risk reads as `complex`.

- [x] Write failing tests for paired plan fields, plan-free bounded acceptance, complex
      refusal, invalid risk, atomic mode-600 risk, legacy fallback, both model routes,
      planned-task proof and plan-free receipt/CI proof.
- [x] Add the dispatch checklist: an explicit plan request wins; otherwise require a plan
      for a changed public interface, stored-data migration, security boundary, concurrency
      behavior, unresolved design choice, or more than three commit-sized steps. When none
      applies, dispatch one bounded ship task without a plan or design review.
- [x] Store and render risk without parsing intent text. Make `dux-result` skip only plan
      checkbox proof for the empty pair; receipt and green-CI proof remain unchanged.
- [x] Select the ship model by risk. Add missing model keys on install without overwriting
      any existing key. Preserve risk across the current new-task retry; teardown already
      removes it with the task folder.
- [x] Replace the shape-only Opus rule in `AGENTS.md` and the orchestrator design with the
      same bounded/complex rule. Do not leave a second routing authority behind.
- [x] Break each new assertion separately. The plan-free receipt assertion must fail when
      receipt proof is disabled, and the bounded route assertion must fail when risk is
      ignored. Restore each break before continuing.
- [ ] Exercise a PR 37-style asset-and-README change: no plan worker, no design review,
      bounded Sonnet implementation, rendered-output check, `/ship` and CI. **Not complete.**
      Everything up to the gate ran installed on 2026-09-13 and is recorded in the header.
      The gate half did not: no ship receipt was written and no pull request or CI run
      exists, because a worker cannot create a repository on the operator's forge. Left open
      rather than ticked, because a ticked box here would read as a proven green CI run.

**Done when:** `bats tests/dux-brief.bats tests/dux-worker-wrap.bats tests/dux-result.bats
tests/dux-recover.bats tests/dux-install.bats` exits 0; each new assertion has recorded
failure output; a bounded plan-free task proves all five ship phases and green CI; a planned
task still proves its boxes; and a legacy task routes to Opus rather than Sonnet.

## Task 2: Refuse a second live Dux-managed worker

**Files:** Modify `bin/dux-spawn`, `tests/dux-spawn.bats`, `docs/ARCHITECTURE.md`,
`CHANGELOG.md`.

**Interfaces:** Before worktree creation, `dux-spawn` checks the other registered tasks'
existing pid and backend liveness evidence. A live worker, or evidence whose liveness cannot
be determined safely, produces `finding: another Dux worker is active: <id>; <new-id>
remains queued`, exits 2 and changes no state. Old run records alone are not proof of life.
The operator reruns the same spawn after the active task stops.

- [x] Write failing tests for no-active start, live-pid refusal, live-backend refusal,
      inconclusive evidence, unchanged queued state and successful retry after exit.
- [x] Add one preflight check using the existing ledger, pid and backend helpers. Do not add
      a queue, reservation, mutex, timer, automatic start or foreign-process scan.
- [x] Break pid and backend detection separately and confirm each duplicate-start test fails.
      Break the ordering once and confirm a refused task no longer remaining queued is caught.
- [x] Run two installed tasks: the first starts, the second is refused without a worktree,
      then the same second task starts after the first has stopped.

**Done when:** `bats tests/dux-spawn.bats` exits 0 with every new guard break-verified, and
the installed two-task exercise leaves no duplicate worker or abandoned worktree.

## Task 3: Start the Dux operator on Sonnet

**Files:** Modify `.claude/settings.json`, `.gitignore`, `tests/contract.bats`,
`docs/ARCHITECTURE.md`.

**Interfaces:** The committed project setting is `"model": "claude-sonnet-5"`.
`.claude/settings.local.json` remains the operator's ignored override. Explicit worker
`--model` flags continue to win, so Tasks 1 and 4 are unaffected.

- [x] Implement the already reviewed plan at
      `docs/plans/2026-09-11-orchestrator-session-defaults-to-sonnet.md`; its exact contract
      assertion, local override, architecture note and manual CLI checks are inherited.
- [x] Break the new model assertion by changing the committed value to Opus, capture the
      failure while the existing hook assertion stays green, then restore it.
- [x] Start one installed operator session without `--model` and one worker with an explicit
      model. Confirm the operator reports Sonnet and the worker reports its routed model.

**Done when:** `bats tests/contract.bats` exits 0, both manual model checks print the expected
IDs, and the failure from the changed committed value is recorded.

## Task 4: Remove unused worker tools and connections

**Files:** Modify `bin/workers/claude.sh`, `tests/worker-adapter.bats`,
`docs/ARCHITECTURE.md`, `CHANGELOG.md`; create `templates/worker-mcp.json`.

**Interfaces:** Both Claude adapter entry points pass exactly
`Bash,Read,Glob,Grep,Write,Edit`, `--strict-mcp-config`, an empty MCP file and
`--no-chrome`. They retain the current settings file, project instructions, installed
skills, hooks, permissions and `/ship`. They do not use safe mode or settings-source
isolation.

- [x] Before editing, qualify the exact flags on the installed Claude CLI in a throwaway
      project. Prove subscription authentication, project instructions, task hooks and
      `/ship` still work. If any fails, mark this task blocked with the exact flag and stop
      the milestone rather than silently weakening the worker.
- [x] Write failing adapter tests that assert the exact six tools, strict empty MCP input,
      no Chrome, unchanged settings and absence of safe-mode/settings-source flags.
- [x] Add the flags once to the shared adapter command shape so printed and executed commands
      cannot drift.
- [x] Break the tool list, MCP flag and no-Chrome flag one at a time; capture three distinct
      failures, then restore them.
- [ ] Run one planned and one plan-free installed worker through `/ship` and confirm both
      retain their required instructions and tools. **Half done.** The planned half is this
      milestone's own ship task and is evidenced by this branch's own gate. The plan-free
      half ran installed on 2026-09-13 and kept its instructions and its six tools, but it
      did not finish `/ship`; the header says how far it got. Left open for that half.

**Done when:** qualification evidence is recorded, `bats tests/worker-adapter.bats` exits 0,
all new assertions are break-verified, and both installed paths complete `/ship`.

## Task 5: Qualify Codex Sol and use it for the security pass

**Files:** Modify `skills/ship/ship-env`, `skills/ship/SKILL.md`,
`tests/ship-env.bats`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`; create
`tests/fixtures/security-review/vulnerable.sh`,
`tests/fixtures/security-review/clean.sh`, and
`tests/fixtures/security-review/expected.md`.

**Interfaces:** Explicit `config/security-reviewer` still wins. Automatic security review
requires `codex` and returns the existing fresh, read-only `gpt-5.6-sol` command. If Sol
returns HTTP 400, `/ship` retries once with `gpt-5.6-terra` and tells the operator which
reviewer ran. No Codex command produces a finding; there is no automatic Claude fallback.
The fixture qualification is implementation evidence, not a runtime command or state file.

- [x] Add a small non-executed fixture with reachable shell injection and path traversal,
      a clean counterpart, and an expected report naming file, line, attacker, input and gain.
- [x] Run one fresh Sol review against both fixtures. Accept only all planted Important or
      Critical findings and no invented Important or Critical clean finding. On Sol HTTP 400,
      run the same qualification once with Terra and record that fallback. Any other miss
      stops this task for operator direction.
- [x] Write failing tests proving explicit config wins, automatic security chooses Sol,
      a host without Codex stops, and the project under review cannot select its own reviewer.
- [x] Change only reviewer selection and the security-step fallback instructions. Do not
      extract prompts, automate qualification, add expiry, collect usage, or change any other
      `/ship` step.
- [x] Break explicit preference, Sol selection and no-Codex refusal separately; capture each
      failure. Dry-run the changed ship skill against a throwaway repository.

**Done when:** the fixture report matches `expected.md`, `bats tests/ship-env.bats` exits 0,
every new assertion is break-verified, explicit configuration is unchanged, and one installed
automatic ship completes separate correctness and security passes with Codex.

## Milestone acceptance

All five task boxes are complete bar the two the header leaves open, both of which claim a
worker's own task reached green CI and neither of which is evidenced; `make check` stays green
after every task; the final installed run exercises one PR 37-style direct task up to the gate,
one complex planned task, and the second-worker refusal end to end;
the enclosing functions are reread after every control-flow edit; `make check-branch` is green;
the diff is below 2,500 added lines; then the implementer announces and invokes `/ship` once.

## Deferred scope and stop rule

No product code for token/cost capture, accounting, reports, benchmarks, allowance-aware
admission, automatic queueing, rate-limit pause/resume, operator request/context accounting,
checkpoint pipelines, plan-page rendering, full safe-mode profiles, mechanical `/ship`
helpers or automated reviewer requalification is authorized.

After five to ten representative tasks, inspect the existing Claude stream JSON manually. If
serialized risk-based work still exhausts allowance, plan only the smallest observed next fix.
If `/ship` itself dominates those runs, reconsider its mechanical rewrite then. Until that
evidence exists, these items remain unscheduled.

## Review record

The original Astra program received one fresh Codex Sol review. Its valid safety findings remain
historical for the systems they covered, but those systems were removed from this plan. The
operator-requested scope review then found that the program's telemetry, scheduling, lifecycle,
review pipeline, browser and benchmark systems were larger than the measured problem. This Fable
rewrite accepts that finding and keeps only the five changes above. The reviewer raised no
finding that was disputed. No second independent design review is authorized.
