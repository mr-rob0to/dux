# Make the PR template choice explicit, and say it once

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, before the next
> task starts. Do not run a code review of your own work: `/ship` owns the branch's one
> review and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-09 by the orchestrator session and approved by the operator from the
  published page, with no independent design review. That is a deliberate deviation,
  recorded under "Deviations" below, and it is scoped to this change only.
- Not started. No branch yet.
- When this merges, `bin/dux-project add` refuses to register a repo that has no pull
  request template until the operator has said install or skip, and every template
  outcome prints exactly one line.

**Estimated diff:** ~120 changed lines across 2 tasks, most of it one added flag on
existing test call sites. Well under the cap.

**Goal:** The operator is never silently not asked. Registering a repo that has no pull
request template stops with a finding naming the two choices, so the ask cannot be
skipped by a caller that forgets it. Registering a repo that already has one needs no
choice at all, because there is nothing to decide.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` sections 4 (registry) and 12
(PR template). Task 2 amends section 12 with the decision below.

**Deviations:** one, from the operator's own workflow rule that a design gets one
independent review before implementation. The operator waived it for this change on
2026-09-09 on the grounds that a two-task, ~120-line fix does not earn a plan PR plus a
ship PR. The plan and the code therefore land in the same pull request, and `/ship` still
runs in full. This waiver does not extend to any later change.

## What is wrong today

Registering `fitfights_api` printed this:

```
dux: no PR template found and none installed
no PR template found; none installed
dux: registered fitfights_api base=staging worktree=make issues=off
```

Two defects, one visible and one not.

- **The same sentence twice.** `install_template` writes its outcome to stderr through
  `log` and to stdout through `echo`. Only stdout is read by anything: the caller
  captures it into `template_msg` and prints it. The stderr copy is dead weight, and on a
  terminal the two merge into what looks like a stutter. The "existing template" branch
  has the same pair; the "installed" branch already prints once, so the three outcomes
  do not even agree with each other.
- **Nobody was asked.** `skills/dux-project/SKILL.md` step 3a already tells Dux to run
  `bin/dux-project pr-template <path>` and, when it prints `none`, to ask the operator
  once before passing `--pr-template install` or `--pr-template skip`. That step was
  skipped, and because the flag defaults to `skip` the script registered the project
  and said nothing that required an answer. A skill step is the only thing standing
  between the operator and a silent default.

## The decision

`--pr-template` stays, and it gains a third state: not passed at all.

| Repo has a template | Flag | Outcome |
|---|---|---|
| yes | any, or none | registers; prints where the existing template is; writes nothing |
| no | `install` | registers; writes `.github/PULL_REQUEST_TEMPLATE.md`; asks for a commit |
| no | `skip` | registers; writes nothing |
| no | not passed | **finding**; nothing registered, nothing written |

Two properties fall out of this, and both are the point:

- **A flag is needed only where a real choice exists.** A repo that already has a
  template has nothing to decide, so `bin/dux-project add <path>` with no flags is the
  normal, correct call for it. This is what the operator asked for when they asked
  whether the flags were needed at all.
- **A forgotten ask is loud.** The failure the operator hit becomes a stop with a message
  naming both choices, instead of a line in a scroll-back.

**Why not an interactive prompt instead of a flag.** Dux runs `dux-project add` through
its Bash tool. A prompt reading from the terminal would block the agent forever rather
than ask anyone, and there is no operator at that terminal to answer it. The flag is how
an answer given in the conversation reaches the script. Considered and rejected.

**Why `--pr-template ''` is treated as not passed.** An empty flag value is the same
statement as not deciding, and it reaches the same finding. Not worth a separate message.

## Task 1: stop when the choice was not made, and say each outcome once

Files: `bin/dux-project`, `tests/dux-project.bats`.

- [ ] In `install_template`, delete the `log "$msg"` call in the "existing template"
      branch and the `log "no PR template found and none installed"` call in the
      "nothing found" branch. Every outcome now prints exactly one line, on stdout,
      which is the line the caller relays. Nothing reads the stderr copies: confirm with
      a repository-wide search for both sentences before deleting them.
- [ ] Replace the one-line `[ "$2" = install ] || { ...; return; }` guard with a `case`
      over the three states: `install` falls through to the write, `skip` prints
      `no PR template found; none installed` and returns, and anything else is
      `finding "no PR template found in $1; ask the operator, then pass --pr-template
      install or --pr-template skip"`.
- [ ] Change the `add` default from `pr_template="skip"` to `pr_template=""`, and widen
      the validation `case` to accept `''` alongside `install` and `skip`. An unknown
      value keeps its existing finding.
- [ ] Confirm by reading `add` from `case "$cmd" in` to the end of the `add)` branch that
      `install_template` is still called before the `printf ... >> "$registry"` line, so
      a finding leaves nothing registered. The `finding` runs inside a command
      substitution; `|| exit $?` on that line is what carries the exit code out.

Tests, in `tests/dux-project.bats`:

- [ ] Split the existing `add without consent writes no template and still registers`
      test. The `repoAA` half becomes `add stops when the repo has no template and no
      choice was made`: status 2, output starts `finding: no PR template found in`,
      `.github/PULL_REQUEST_TEMPLATE.md` absent, and zero matching lines in
      `data/projects.md`. The `repoAB` half becomes its own test asserting that
      `--pr-template skip` registers, writes nothing, and prints the one line on stdout.
      Keep the `repoAE` half asserting the unknown-value finding.
- [ ] Add `a repo that already has a template registers with no choice at all`: a fixture
      with `.github/PULL_REQUEST_TEMPLATE.md`, `dux-project add` with no `--pr-template`,
      status 0, registered, stdout names the existing path.
- [ ] Add `no template outcome is printed twice`: run each of the three outcomes with
      `--separate-stderr` and assert `$stderr` contains neither `no PR template found`
      nor `existing PR template left alone`, while `$output` contains the right one.
- [ ] Break-verify, one break at a time, four distinct failures, each pasted into the
      commit message as the run printed it:
      1. delete the new `finding` line; the "stops when no choice was made" test fails.
      2. move the `install_template` call below the registry `printf`; the "nothing
         registered" assertion in that same test fails.
      3. restore one `log` call; the "printed twice" test fails.
      4. make the `skip` arm fall through to the write; the `--pr-template skip` test
         fails on the written file.

## Task 2: the callers catch up

Files: every `tests/*.bats` and `tests/helpers/setup.bash` that registers a fixture repo,
`skills/dux-project/SKILL.md`, `README.md`, `docs/ARCHITECTURE.md`,
`docs/specs/2026-09-03-dux-orchestrator-design.md`.

- [ ] Every existing `dux-project add` call on a fixture repo with no template now hits
      the new finding. Add `--pr-template skip` to each. About forty call sites across
      eleven files; `tests/helpers/setup.bash:191`, `tests/dux-worktree.bats:11` and
      `:18`, and `tests/dux-task-new.bats:5` are shared helpers and cover many callers
      between them. Constitution rule on mechanical edits applies: print the match count
      before and after and compare, edit in place rather than through one save at the
      end, and re-read at least one full changed region. Do not add the flag to the call
      sites that assert a finding before registration is reached (bad name, not a git
      repo, whitespace path, duplicate, unknown `--worktree`); adding it there hides what
      those tests check.
- [ ] `skills/dux-project/SKILL.md` step 3a: when `bin/dux-project pr-template <path>`
      prints paths, pass no `--pr-template` flag at all and tell the operator where the
      existing template is. When it prints `none`, ask once and pass the answer. Say
      plainly that `add` refuses to register until the answer is passed, so the step
      cannot be skipped. Update the step 4 usage line to match.
- [ ] `README.md` around line 239: say the flag is required when the repo has no
      template, and not needed when it has one.
- [ ] `docs/ARCHITECTURE.md` lines 39 to 40: `--pr-template install|skip`, required when
      the repo has no template.
- [ ] `docs/specs/2026-09-03-dux-orchestrator-design.md` section 12: one paragraph
      recording that registration stops rather than defaulting, per constitution
      principle 8. No version bump to the constitution; principle 6 already says the
      write is reported and left for the operator to commit, and that stays true.
- [ ] Full suite green, `shellcheck` clean, `bin/dux-doctor` passing.
- [ ] Break-verify the mechanical edit itself: remove `--pr-template skip` from one
      shared helper and confirm the tests that use it fail with the new finding rather
      than passing for some other reason. Paste that failure into the commit message.

## What this does not cover

- No interactive prompt. Named and rejected above.
- No new task shape for small fixes. The plan-then-ship path being heavy for a change
  this size is a real gap in Dux, and it is not this branch's problem to solve.
- The `dux-project pr-template` subcommand is untouched.
