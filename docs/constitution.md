# Dux Constitution

## Core Principles

### 1. Development Workflow

All changes MUST follow trunk-based development on `main`.

- One milestone is one session, one branch, one pull request. Feature work happens in a
  worktree under `.worktrees/<branch>`; the plain checkout does base-branch work only.
- A milestone ships at most 2,500 added lines or 12 tasks, whichever comes first. A milestone
  estimated over either number MUST be split before its plan is written, at a seam where each
  half merges on its own. The estimate goes in the plan header and the actual number in the
  pull request body. How to estimate is in the roadmap's "How a milestone is sized".
- Branches MUST be cut from freshly fetched `origin/main` and rebased on it before review and
  merge. Pushes over an existing remote branch use `--force-with-lease` anchored to the fetched
  SHA, never bare `--force`.
- All commits MUST follow Conventional Commits (`<type>(<scope>): <subject>`): types `feat`,
  `fix`, `docs`, `test`, `refactor`, `chore`, `ci`; imperative subject, lowercase, no trailing
  period, at most 50 characters. Commits MUST be atomic.
- A commit message describes the diff, not the intent. Every claim in it MUST be checkable
  against the diff.

Rationale: a single operator with several sessions needs history that reads as a sequence of
reviewed milestones.

### 2. Code Quality & Standards

Scripts own mechanics; agents own judgment. The two never mix.

- Every script under `bin/` is bash 3.2 compatible: no negative array indices, no associative
  arrays, no `mapfile`, no `declare -A`. macOS ships bash 3.2 and the scripts MUST run there.
- `shellcheck -s bash` MUST pass on every script, adapter, fake, and helper, enforced by
  `make lint` locally and in CI on every pull request.
- `make lint` MUST also reject any tracked file containing a personal identifier from
  `tests/personal-identifiers.txt` (operator home path, username, project names).
- A script that meets a surprise MUST stop and print `finding: <one line>` to stderr with exit
  code 2. It MUST NOT guess, fall back, or degrade silently. Exit codes: 0 success, 1 unexpected
  error, 2 finding, 3 lock held.
- Every script sources `bin/dux-env` and uses its helpers; no script reinvents paths, logging,
  or exit codes.
- Names convey intent. A function or script that needs a comment to explain what it does is
  misnamed.
- Dependencies are bash, git, jq, gh, and the harness and backend CLIs. No package manager, no
  lockfile, no vendored binaries.

Rationale: an agent distro is read and modified by agents; small, strict, uniform scripts are
what they edit reliably.

### 3. Testing & Quality Assurance (TDD + Coverage)

Testing is non-negotiable for scripts and for guards.

- Test-Driven Development MUST be used: the bats test is written and seen to fail before the
  script is written.
- Every script under `bin/` MUST have a bats file. Every refusal path MUST have a test that
  reaches it.
- A guard you have not seen fail is not a guard. Every new test is break-verified once: break
  the guarded condition, run, confirm the failure, restore, and paste the failure output into
  the commit body. One break per commit; N breaks need N distinct failures.
- Break-verification happens at the task boundary, not at the ship gate. A task is not done
  until every assertion it added has been broken and seen to fail. The next task MUST NOT
  start before that.
- A suite that is green on its first run is a reason to look harder, not a reason to move on.
  The usual cause is an assertion that never reached the code under test.
- Fix commits outnumbering feature commits in a milestone is a stop signal: the tests were
  passing for the wrong reason. Say so and re-examine the design rather than opening another
  fix round.
- Tests assert on behavior, never on the fixture. A test that passes because a fake returned
  what the test put in is a defect.
- Tests MUST be deterministic and isolated: every test runs against a temp `DUX_HOME`; no test
  touches real `data/`, `state/`, or `config/`; backend tests use a named tmux server and a
  fake `herdr`.
- Coverage is by enumeration, not percentage: the checklist is "every script, every refusal,
  every adapter function on every backend and harness."
- Skills are prose and have no automated test; each skill is dry-run against a throwaway repo
  before its milestone closes, and the transcript excerpt is pasted into the pull request.

Rationale: the failure mode this project guards against is a check that passes while the
behavior is wrong. Catching it inside the task costs minutes; catching it at the ship gate
costs hours, and it never arrives alone.

### 4. Architecture & Design

Architecture MUST stay small, file-based, and restart-proof.

- The design authority is `docs/specs/2026-09-03-dux-orchestrator-design.md`.
  `docs/ARCHITECTURE.md` carries the current component diagram and the two main flows
  (dispatch, wake) and MUST be updated in the same pull request as any change that adds,
  removes, or renames a script, adapter, state file, or step in those flows.
- State lives in files under `data/` and `state/` and in the terminal backend. Conversation
  memory is never authoritative. Only scripts write `data/backlog.md`.
- Backends and worker harnesses are reached only through their adapter interfaces
  (`bin/backends/<name>.sh`, `bin/workers/<name>.sh`). No script calls `tmux`, `herdr`,
  `claude`, or `codex` directly outside an adapter.
- The public contract is the status protocol (`<state>: <line>` in `status.log`), the ledger
  line format in `data/backlog.md`, the registry line format in `data/projects.md`, and the
  `finding:` convention. These follow semantic versioning: a new state or field is MINOR and
  optional; renaming or removing one is MAJOR and requires a migration note in the changelog.
- `AGENTS.md` is the only always-loaded file and is capped at 150 lines by test. Everything
  else loads on demand.

Rationale: a system that reconciles from disk after any crash cannot afford hidden state or
hidden coupling.

### 5. Token Budget

Tokens are a cost the operator sees; the design keeps them bounded.

- Dux idle MUST cost zero: waiting is done by bash and the harness's event mechanism.
- Dux MUST NOT read worker output outside `dux-recover`, and then at most 40 lines.
- Briefs are at most 60 lines and never carry conversation history.
- The Dux session restarts daily or after 40 wakes.
- Any feature that adds an agent invocation to the idle path or to every wake MUST be opt-in.

Rationale: the point of an orchestrator is more outcomes per unit of attention and tokens.

### 6. Security & Compliance

The local worker is trusted with the operator's own authority. Everything it says is not.

- The operator-started worker, its harness, and the local commands it launches are trusted to
  act with the operator account's authority. They can reach the operator's files, shared Git
  metadata, terminal services, the network, credentials, and other same-user processes.
  Deliberate abuse of those rights is outside Dux's protection claim.
- Repository and issue content, worker status and report text, PR URLs, and result claims are
  untrusted application data. Dux checks grammar, size, ownership, shape, and outside evidence
  before any of it reaches canonical state or operator-facing text.
- A task nonce, a mode-600 file, a hidden path, a process id, or a same-user permission check
  prevents mistakes and stale writes. Each is a correctness check, not an authentication
  boundary against a worker that is deliberately hostile.
- A worker never declares its own completion. Terminal state is proved from registered project
  facts, exact Git and GitHub evidence, and a recorded `/ship` receipt, then published as one
  atomic handoff that the watcher consumes.
- Operator-facing text is fixed by state. Worker text reaches the operator only through
  recovery, cleaned, capped, and fenced as data.
- Prompt rules are never the guard. Workers get a settings file with deny rules and a
  `pre-push` hook refusing the base branch; both are break-verified under bypass mode before
  anything relies on them.
- Secrets and credentials MUST NEVER be committed. `.env` files are copied into worktrees only
  for `ship` tasks. Nothing under `data/`, `state/`, or `config/` is tracked.
- No personal identifiers in tracked files, enforced by lint.
- Dux never writes to a project repository. The one exception, installing a missing PR
  template, is reported and left for the operator to commit.
- Stronger isolation, such as a virtual machine or a container, is optional future work. If it
  is ever added it MUST fail closed: no isolation means no worker, never a silent fallback.

Rationale: an unattended agent running as the operator cannot be contained by file modes and
hidden paths, so Dux stops pretending otherwise and spends its guards where they work, on
everything the worker reports.

### 7. Error Handling & Observability

Failures MUST be visible and attributable.

- A refusal is a finding, never an obstacle to work around. Findings are relayed to the
  operator verbatim.
- Worker output goes to `state/<id>.out`; status goes to `status.log`; events go to
  `state/events.log`. Every failure leaves a tail in `tasks/<id>/report.md`.
- The watcher emits one event per state change and never for `working`. Silence is not
  success: stale and dead are events.
- Logging is line-oriented plain text, prefixed `dux:` on stderr. No JSON logging, no
  telemetry, nothing leaves the machine.

Rationale: the operator debugs from files after the fact, often from a different session.

### 8. Documentation

- The spec is the design authority; changes to behavior go to the spec first, then the plan,
  then code.
- Each fact has one owner document. `AGENTS.md` owns operating rules, `docs/constitution.md`
  owns standards, the spec owns design, `README.md` owns install and first run. Other
  documents point rather than restate.
- The plan file is the state of a milestone: checkboxes ticked as tasks land, a three-line
  "where this stands" block at the top.
- A plan task is at most about 60 lines: files, interfaces, acceptance criteria, and the
  break-verification the task owes. A plan MUST NOT carry script bodies, blocks that restate
  this constitution, or conversation history. A decision the plan settles is amended into the
  spec and then pointed at, never restated. This binds every plan from milestone 5 onward;
  the merged plans for milestones 1 to 4 are the record of what was built and stay as they
  are. The shape is `docs/plans/TEMPLATE.md`.
- Every pull request fills `.github/PULL_REQUEST_TEMPLATE.md`; verbose material goes in
  `<details>`.

Rationale: agents re-read documents every session; duplication is where drift starts.

### 9. Code Review

- Every milestone PR goes through `/ship`: base verification, `make check-branch`, one independent
  code review by Codex, one security pass, the PR, and green CI. No manual review outside the
  gate; no second review.
- Every finding is verified against the code before it is acted on. Critical and Important are
  fixed; the rest are logged in the PR body. Only a fixed Critical earns a re-review, scoped to
  the new commits.
- Design changes get one independent review from a fresh planning session before
  implementation, once.

Rationale: one gate, run every time, beats several gates run sometimes.

## Quality Gates (Definition of Done)

A milestone is done when all of the following hold:

- Every task checkbox in the milestone plan is ticked and the plan header says so.
- `make check-branch` is green on a clean checkout: the suite, the lint, and the bash 3.2 pass.
- Every new test was break-verified at the task that added it, not at the ship gate, and the
  failure is in a commit body.
- The pull request reports the milestone's fix-to-feature commit ratio, the time spent fixing
  after the code was written, and the added-line count against the 2,500-line cap.
- No task in the milestone plan exceeds about 60 lines, and the plan carries no script bodies
  and no restated constitution.
- Every skill touched was dry-run and the excerpt is in the PR.
- `docs/ARCHITECTURE.md` matches the scripts and flows that exist.
- The PR was opened by `/ship`, the reviews ran, CI is green, and the operator merged it.

## Governance

This constitution governs all work in the repository. Amendments are made by pull request
that edits this file, bumps the version, and updates Last Amended: MAJOR for a redefined or
removed principle, MINOR for a new principle, PATCH for a clarification. A plan that must
deviate from a principle says so in its header and names the principle.

**Version**: 2.0.3 | **Ratified**: 2026-09-03 | **Last Amended**: 2026-09-06

Version 2.0.3 puts a number on two rules that were already here in words. Principle 1 said a
milestone is one session; it now says how big a session may get, 2,500 added lines or 12 tasks.
Principle 8 said the plan file is the state of a milestone; it now says how long a task in it
may be and what it may not contain. Both were measured on 2026-09-06: four days of sessions
produced 3,114 lines of shell against 10,210 lines of plan, and milestone 3's pull request was
9,495 lines, three to four times what one session holds. This is a PATCH: no principle is
added, removed, or redefined, and the governance section offers no other level for putting a
number on an existing rule.

Version 2.0.2 names `make check-branch` where the gate used to say `make check`. The suite now
runs its files side by side, so `make check` is the loop to run after a task and
`make check-branch` adds the bash 3.2 pass once before `/ship`. No principle changes.

Version 2.0.1 redefines principle 6 and keeps the principle 3 clarification that break-
verification belongs to the task that added the assertion. Worker containment by file mode,
hidden path, and process id is replaced by a declared trust boundary: the local worker carries
the operator's authority, and everything it reports is checked against outside evidence before
it counts.
