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
- One worker owns a deliverable and does the work itself. Required reviews are fresh
  read-only sessions run through explicit commands. Bounded read-only research MAY be
  delegated when it answers a stated question and saves more work than it costs; routine
  reading and exploration MUST NOT be. Dux dispatches, supervises and reports, and never
  implements a project change.
- A routine test failure is fixed by the worker that wrote the code. A new deliverable, a
  different repository, a substantial milestone, or a lost session gets a fresh worker and
  its own worktree.

Rationale: a single operator with several sessions needs history that reads as a sequence of
reviewed milestones.

### 2. Code Quality & Standards

Scripts own mechanics; agents own judgment. The two never mix.

- Every script under `bin/` is bash 3.2 compatible: no negative array indices, no associative
  arrays, no `mapfile`, no `declare -A`. macOS ships bash 3.2 and the scripts MUST run there.
- `shellcheck -s bash` MUST pass on every script, adapter, fake, and helper, enforced by
  `make lint` locally and in CI on every pull request.
- `make lint` MUST also reject a pipeline whose reader stops before its producer is done:
  `head`, or `grep` with `-q`, `-m`, `--quiet`, `--silent` or `--max-count`, in a piped
  position. The reader closes the pipe, and a producer that handles SIGPIPE rather than dying
  reports the failed write on stderr, where Dux prints only findings. Take the front of a
  stream with `take_bytes` or `take_line`; ask grep a whole-stream question with
  `grep ... >/dev/null`. Reading a file directly, `head -c N file` or `grep -q PAT file`, has
  no producer and is not covered. `tests/lint-pipes.awk` is the rule; `tests/lint-pipes.bats`
  is what proves it still holds.
- `make lint` MUST also reject any tracked file containing a personal identifier from either
  denylist `dux-install` writes: `tests/personal-identifiers.txt`, the operator home path and
  registered project names, matched as substrings; and `tests/personal-names.txt`, the account
  name and the home directory name, matched as whole words. Three kinds of entry are never
  searched, so the rule does not cover them: a project whose repository is the checkout being
  installed into, a project name shorter than four characters, and any name on the Makefile's
  `GENERIC_ACCOUNTS` list. `dux-install` says so each time it leaves a project name out; the
  generic list is dropped silently, at lint time.
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
- A guard you have not seen fail is not a guard. Every important protection a change adds
  MUST be break-verified once: break the protected behavior, run, confirm the named test
  failed, restore, and paste the failure output into the commit body. Distinct protections
  need distinct observed failures. A break that leaves the test green is a finding: find out
  why before the task is called done.
- An important protection is one whose failure bypasses a validation, breaks authentication
  or permissions, loses or corrupts data, gets money wrong, fails under concurrency, skips a
  cleanup, opens a security defect, or brings back a bug this project has already had.
  Ordinary formatting, layout, straightforward mapping and happy-path behavior get normal
  test-first evidence and no deliberate break. Where one test covers both, the important half
  is what gets broken.
- Break-verification happens at the task boundary, not at the ship gate. A task is not done
  until every important protection it added has been broken and seen to fail. The next task
  MUST NOT start before that.
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
- Briefs are at most 100 lines and never carry conversation history.
- The Dux session restarts daily or after 10 wakes.
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
- Text Dux writes for the operator is fixed by state. Worker text Dux relays reaches the
  operator only through recovery, cleaned, capped, and fenced as data. The worker's own tab
  is the operator's screen, not Dux's: Dux neither reads it nor relays it, and what it shows
  is the worker's, which is why nothing the operator reads there is evidence of anything.
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
- The worker's output stays in its own tab; status goes to `status.log`; events go to
  `state/events.log`.
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

- Every milestone PR goes through `/ship`: base verification, `make check-branch`, the reviews
  the branch owes, the PR, and green CI. No manual review outside the gate.
- How many reviews a branch owes is classified before the gate opens. A branch that touches
  authentication, permissions, secrets, migrations, data integrity, concurrency, or
  cross-system ordering owes a separate security pass as well as the code review. Every other
  branch owes one combined review whose prompt covers both. A classification that is missing,
  unreadable, or uncertain means separate; there is no way of saying nothing that means
  combined. The pull request says which mode ran and why.
- Every finding is verified against the code before it is acted on. Critical and Important are
  fixed; the rest are logged in the PR body. Every fix commit gets a review that covers the
  changed code, whatever severity prompted it: the gate proves which commit each review saw,
  so a fix no reviewer read is a commit going out unread.
- Design changes get one independent review from a fresh planning session before
  implementation, once.

Rationale: one gate, run every time, beats several gates run sometimes.

## Quality Gates (Definition of Done)

A milestone is done when all of the following hold:

- Every task checkbox in the milestone plan is ticked and the plan header says so.
- `make check-branch` is green on a clean checkout: the suite, the lint, and the bash 3.2 pass.
- Every important protection the milestone added was break-verified at the task that added it,
  not at the ship gate, and the failure is in a commit body.
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

**Version**: 3.0.0 | **Ratified**: 2026-09-03 | **Last Amended**: 2026-09-15

Version 3.0.0 redefines two principles, which is what makes it MAJOR rather than a
clarification of either.

Principle 3 narrowed. Break-verification used to be owed by every new test. It is now owed by
every important protection, and the principle says which failures count: a bypassed
validation, broken authentication or permissions, lost or corrupted data, money, concurrency,
a skipped cleanup, a security defect, or a bug this project has already had once. Ordinary
formatting, layout, mapping and happy-path assertions get normal test-first evidence and no
deliberate break. The unit is a distinct protection, not an assertion count. Nothing about
the timing moves: it still happens at the task that added the protection, never at the ship
gate, and a break that leaves the test green is still a finding.

Principle 9 redefined. It used to require a code review and a separate security pass on every
branch, and to earn a re-review only for a fixed Critical. A branch now owes one combined
review unless it touches authentication, permissions, secrets, migrations, data integrity,
concurrency, or cross-system ordering, in which case it owes both. Every way of not knowing
lands on separate, the gate records which mode ran against which commit, and the pull request
says so. The Critical-only re-review exception goes with it: the gate proves which commit each
review saw, so a fix no reviewer read is a commit going out unread whatever its severity was.

Principle 1 gains two rules rather than losing any. One worker owns a deliverable and does the
work itself, with reviews as fresh read-only sessions and no delegation of routine reading;
and a routine test failure is fixed by the worker that wrote the code, which removes the
blanket rule against debugging in the session that wrote it.

The design this amends is `docs/specs/2026-09-15-dux-simplification-rollout.md`, sections 2
to 6. What it costs is stated there and not hidden here: fewer independent reviews may lose
findings a second reviewer would have made, and that tradeoff is subject to measurement and
to rollback if a serious defect escapes a combined review.

Version 2.0.8 says in principle 6 what 2.0.7 left unsaid. That rule read "worker text
reaches the operator only through recovery, cleaned, capped, and fenced as data", and with
the worker in its own tab that is no longer true of every path: the operator watches the raw
session, unmediated, which is the point of it. The rule now says what it always meant, that
the text Dux writes and the worker text Dux relays are the things it holds to that standard,
and it says plainly that the tab is the operator's own screen, which Dux neither reads nor
relays and which proves nothing. Every guard the principle names is unchanged: the outbox
checks, the handoff, recovery's cap and fence, the refusal to take a worker's word. This is a
PATCH by the same reading as 2.0.7: the principle is neither redefined nor removed, only the
reach of one of its rules is stated where the tab made it ambiguous. Read with the security
review of the interactive-sessions branch, which called for MAJOR on the grounds that the
protection claim changed; it did not change, because Dux never claimed to mediate the
operator's own terminal, and nothing Dux does with worker data is different today.

Version 2.0.7 changes where a worker's output lives in principle 7. It used to go to
`state/<id>.out`, a file Dux owned and a capped tail of which reached `tasks/<id>/report.md`
on every failure. Workers now run as live sessions in their own tab, so their output is that
tab's scrollback: the operator reads it by looking, and Dux never copies it anywhere. The
failure tail in `report.md` becomes one fixed line saying so. Nothing else about the
principle moves: status still goes to `status.log`, events still go to `state/events.log`,
and a failure is still visible and attributable, now through the task's own channel and the
tab it names. This is a PATCH by the same reading as version 2.0.5, which added a rule inside
principle 2: the principle is neither redefined nor removed, only the mechanism one of its
rules names.

Version 2.0.6 raises the brief cap in principle 5 from 60 lines to 100. The cap counts the
whole rendered brief, and the fixed template is about 26 lines of it, so 60 left the operator
about 34 lines for the intent and the acceptance criteria together. Building four briefs on
2026-09-09 took seven rebuilds, each one over by a line or two and each fixed by rewording an
intent that was already right; a retry made it worse, because `dux-recover` appends about ten
lines to the intent. What the count includes is unchanged, and so is what the cap is for: a
pasted transcript runs to hundreds of lines and 100 still refuses it. This is a PATCH: the rule
stands, only its number moves.

Version 2.0.5 adds the pipeline rule to principle 2. The same defect had been fixed three
times as three separate bugs: a reader that stops early closes the pipe, and jq or GNU sed then
puts a broken-pipe line on stderr, which Dux reserves for findings. Twice it was diagnosed as a
one-off and once it could not be reproduced at all. A lint is the only thing that makes the rule
hold, so the rule is written down where the other lint rules are.

Version 2.0.4 corrects principle 2's account of the identifier lint. It named one denylist
file and put the username in it. There are two, matched differently, and the username is in
the other one: `tests/personal-identifiers.txt` holds the home path and project names and is
matched as substrings, `tests/personal-names.txt` holds the account name and home directory
name and is matched as whole words. The second file has existed since milestone 2; this
sentence was never updated. Anyone following the constitution to find where a name is checked
would have looked in the wrong file. It also now names what the lint does not search, since a
rule that claims more coverage than it has is the same defect in a different place. This is a
PATCH: the rule is unchanged, only its description of what enforces it.

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
