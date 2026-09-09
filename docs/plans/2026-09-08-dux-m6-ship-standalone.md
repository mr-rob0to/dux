# Dux Milestone 6: `/ship` stands alone Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-08 on `plan/m6-ship-standalone` from `main` at ee4064e. Not yet
  reviewed, not yet approved. 0 of 4 tasks.
- Milestone 5 gave the gate a memory but left it wearing the operator's own reviewer
  command, model name and PR habits, so a stranger who installs Dux cannot run it.
- When this merges `/ship` runs from a fresh clone on bundled defaults, its push is
  anchored and verified, and the pull request it writes fills the repo's own template
  and carries its own evidence.

**Estimated diff:** ~1,350 added lines across 4 tasks. The cap is 2,500 lines or 12
tasks (constitution principle 1). Sizing procedure: roadmap, "How a milestone is
sized". The roadmap estimated ~1,200. The difference is Task 3: moving the pull
request template lookup into one shared script costs a bats file the roadmap did not
count, and buys back the second copy it would otherwise have to maintain.

**Goal:** Today `/ship` only works for one person. It names a reviewer model in its own
text, it opens pull requests with whatever `--fill` scrapes out of the commits, and it
pushes with a lease that is not anchored to anything. After this milestone the gate
reads its reviewers from config with bundled defaults, so a fresh clone runs it
unchanged; it fills whichever pull request template the repository actually has; the
body carries the evidence and a machine-readable record of which commit each phase
saw; and the push is anchored to a fetched commit and checked against the remote
afterwards.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 11, changes 6 to
9, plus section 18's "the operator's global rules stay global". Three amendments land
in the same pull request as this plan and before any task starts, and are listed under
Design below. Section 12 is unchanged in what it says and gains a pointer to where the
lookup now lives.

**Deviations:** constitution principle 2, "every script sources `bin/dux-env` and uses
its helpers". `skills/ship/ship-env` sources nothing, for the same reason
`skills/ship/ship-guard` does not: `dux-install` symlinks the skill directory and the
helper travels with it, and `/ship` runs inside a project worktree that knows nothing
about `DUX_HOME`. It defines its own `finding` and uses the same exit codes.

## Design

Only what the spec does not already say. The three spec amendments are the first three
bullets and are written before Task 1 starts.

- **Spec amendment, section 11 change 9: one lookup, not two.** The spec says `/ship`
  "needs its own copy" of the pull request template lookup because it cannot call
  `bin/dux-project`. A second copy is a second thing to keep correct, and the rule it
  encodes is subtle enough that milestone 5's review found three separate edge cases in
  the first one. So the lookup moves out of `bin/dux-project` into
  `skills/ship/ship-env`, and `dux-project` calls it. One implementation, two callers,
  nothing to drift. `dux-project`'s observable output is unchanged, which its existing
  bats file proves. This is the one place this plan overrides the roadmap's wording.
- **Spec amendment, section 11 change 2: `ship-guard` gains a sixth verb, `attest`.**
  The attestation is derived from the guard file, and `ship-guard` is the only thing
  that knows that file's format. Building the JSON in prose instead would put the
  format in two places.
- **Spec amendment, section 11 change 8: what the attestation may claim.** It carries
  `head_sha`, `fix_passes`, and the three guard phases with the commit each recorded.
  It does not carry `pr` or `ci`: step 8 writes it before either has happened, and a
  record that claims a future step ran is worse than no record.
- **How the gate reaches the Dux checkout.** `ship-env` resolves its own directory with
  `cd "$(dirname "$0")" && pwd -P`, which follows `dux-install`'s directory symlink, and
  takes the checkout two levels up. A skill copied rather than installed lands
  somewhere that is not a Dux checkout, and the gate stops. Same trade as `ship-guard`:
  the gate does not run half-configured.
- **What is already done.** `config/models` is read by `bin/dux-worker-wrap` and seeded
  by `dux-install` since milestone 2, and `/ship` does not use it at all. Task 1 leaves
  it alone; the roadmap row naming it is satisfied already.
- **Order.** Task 1 first: it creates `ship-env`, which Task 3 extends. Tasks 2 and 3
  both edit `skills/ship/SKILL.md` step 8, so they run in order to keep their diffs
  from overlapping. Task 4 runs last and proves the other three from outside.

## Task 1: Reviewers into config

**Files:** `skills/ship/ship-env`, `tests/ship-env.bats`, `skills/ship/SKILL.md`
(steps 0, 6, 7, Tool notes), `templates/config/reviewer`,
`templates/config/security-reviewer`, `Makefile` (`SHELL_FILES`),
`docs/ARCHITECTURE.md`.

**Interface:** `ship-env` runs from the installed skill directory and answers what the
gate needs from the Dux checkout it came from.

| Command | Prints | Exit |
|---|---|---|
| `ship-env reviewer` | the step 6 reviewer command line | 0; 2 on a finding |
| `ship-env security-reviewer` | the step 7 reviewer, `agent:<name>` or a command line | 0; 2 on a finding |
| `ship-env --root` | the Dux checkout it resolved | 0; 2 on a finding |

A value is read from `$DUX_CONFIG/<key>` when `DUX_CONFIG` is set, else
`<root>/config/<key>`, and falls back to `<root>/templates/config/<key>`. A line
starting `#` is a note and a blank line is skipped; the first line that is neither is
the value. Refusal text, exactly:

- `finding: unknown key '<k>' (reviewer, security-reviewer)`
- `finding: ship-env is not inside a Dux checkout at <path>; the skill was copied rather than installed`
- `finding: no value for <key> in <dir>/<key> or <root>/templates/config/<key>`

`security-reviewer` has two value shapes and step 7 reads both: `agent:<name>` means
dispatch that agent on this host, anything else is a command line the audit prompt is
appended to. The bundled defaults keep today's values and gain note lines above them,
including the one that used to live in the skill: when the configured model is refused,
fall back and say in the pull request which reviewer actually ran.

**Acceptance:** `skills/ship/SKILL.md` contains no model identifier: nothing matching
`gpt-[0-9]` or `claude-[a-z]*-[0-9]`, asserted by test. A checkout with no `config/`
directory resolves both keys from `templates/config/`. Every refusal above has a test
that reaches it. `make lint` passes with `ship-env` named in `SHELL_FILES`.
`docs/ARCHITECTURE.md` lists `ship/ship-env`.

**Steps**

- [ ] Write `tests/ship-env.bats` first and see it fail: both keys from `config/`, both
      from `templates/config/` with no `config/` present, note and blank lines skipped,
      each refusal, and the resolution through a directory symlink.
- [ ] Write `skills/ship/ship-env`; bash 3.2, shellcheck clean, findings on stderr, exit 2.
- [ ] Add note lines to `templates/config/reviewer` and `templates/config/security-reviewer`.
- [ ] Edit `SKILL.md`: step 0 resolves `$SHIP_ENV` beside `$SHIP_GUARD` and stops when
      it is not executable; steps 6 and 7 take their reviewer from it; Tool notes lose
      the model names and the Sol fallback line.
- [ ] Add the no-model-identifier assertion to `tests/ship-env.bats`; add `ship-env` to
      `SHELL_FILES`; update `docs/ARCHITECTURE.md`.
- [ ] Break-verify: break each assertion alone, run, confirm N distinct failures,
      restore, paste them into the commit body (constitution principle 3).

## Task 2: Evidence, anchored lease, remote verify

**Files:** `skills/ship/SKILL.md` (steps 5, 8, 9, stop table), `tests/contract.bats`.

**Interface:** step 5 gains an evidence rule. A change a person can see, meaning UI,
command output, an API response or user-facing error text, needs a screenshot, a
recording or pasted output in the pull request body, or one line saying why there is
none. A change nobody sees needs the check command and its result, which step 8's body
requirement already asks for. This is a body requirement, not a new stop: a missing
screenshot is a review finding, not an unshippable branch.

Step 8 replaces the bare `--force-with-lease` with the anchored form, and every later
push in step 9 uses the same three lines:

1. `git fetch origin`, then read the fetched remote-tracking commit for this branch.
2. Push with `--force-with-lease=refs/heads/<branch>:<that commit>`. A branch the remote
   does not have yet has no commit to anchor to, so the first push is a plain
   `git push -u origin <branch>` and step 3 still runs.
3. `git ls-remote origin refs/heads/<branch>` and compare its commit to `HEAD`. Not
   equal is a stop: something landed between the lease check and the push.

The stop table gains one row: `The remote head is not the commit that was pushed`,
because somebody else pushed in between and the branch on the remote is not the one the
gate proved.

**Acceptance:** a contract test asserts step 5 carries the evidence rule and its "or
why none" escape; that step 8 carries `--force-with-lease=refs/heads/`, the `ls-remote`
check and the new-branch case; that the push in step 9 carries the anchored form too;
and that the stop table names the remote-head row. One dry run against a throwaway
repository where the remote moves between the fetch and the push, confirming the lease
refuses.

**Steps**

- [ ] Add the contract tests to `tests/contract.bats` and see them fail against today's
      `SKILL.md`.
- [ ] Edit `SKILL.md` steps 5, 8 and 9 and the stop table.
- [ ] Dry run G: push, move the remote branch from a second clone, fetch nothing, push
      again; confirm the anchored lease refuses. Paste the excerpt into the commit body.
- [ ] Break-verify: break the `ls-remote` assertion alone, run, confirm it fails,
      restore, paste the failure into the commit body.

## Task 3: One template lookup, and the attestation

**Files:** `skills/ship/ship-env`, `tests/ship-env.bats`, `bin/dux-project`,
`tests/dux-project.bats`, `skills/ship/ship-guard`, `tests/ship-guard.bats`,
`skills/ship/SKILL.md` (step 8), `tests/contract.bats`, `docs/ARCHITECTURE.md`.

**Interface:** `ship-env` gains two verbs and `ship-guard` gains one.

| Command | Prints | Exit |
|---|---|---|
| `ship-env pr-template <repo>` | one repo-relative path per line, nothing when the repo has none | 0; 2 on a finding |
| `ship-env pr-template-fallback` | the absolute path of the bundled `templates/PULL_REQUEST_TEMPLATE.md` | 0; 2 on a finding |
| `ship-guard attest` | the attestation comment line, from the guard file | 0; 2 on a finding |

`pr-template` is `find_templates` moved out of `bin/dux-project` unchanged, comments
included: the same three directories, the same character rule on a filename, the same
refusal to follow a symlinked directory. `dux-project` calls it and keeps its own
policy, so `dux-project pr-template` still prints `none` and `install_template` still
decides what to write. `attest` refuses a phase that is not recorded and prints
`<!-- dux-attestation:v1 {...} -->` carrying `head_sha`, `fix_passes` and the three
phases with the commit each recorded. No `pr`, no `ci`: neither has happened yet.

Step 8 stops using `gh pr create --fill`. It takes the first path `ship-env
pr-template` prints, in the root, `docs/`, `.github/` order, and falls back to
`pr-template-fallback` when there is none or when the only match is the folder form.
GitHub documents no precedence between the three directories, so the gate says in the
body which template it filled rather than implying GitHub would pick the same one. It
fills the sections, puts verbose material inside `<details>`, keeps the existing
`Closes #<n>` rule, appends `ship-guard attest` as the last line, and passes the file
with `--body-file`. Updating an open pull request uses `gh pr edit --body-file`.

**Acceptance:** `bin/dux-project` has one fewer function and `skills/ship/ship-env` one
more, counted before and after; `tests/dux-project.bats` passes untouched except for
the missing-script refusal added to it. `ship-guard attest` has a test for a complete
guard file and one for each missing phase. A contract test asserts step 8 no longer
names `--fill`, and does name `--body-file`, the lookup, `<details>`, and
`dux-attestation:v1`. `docs/ARCHITECTURE.md` lists both new verbs.

**Steps**

- [ ] Add the `pr-template` and `attest` tests to `tests/ship-env.bats` and
      `tests/ship-guard.bats` and see them fail.
- [ ] Move `find_templates` into `ship-env`. Count the functions in `bin/dux-project`
      before and after; re-read the whole moved region in its new file. Add the
      refusal `dux-project` gives when the script is missing.
- [ ] Add `attest` to `ship-guard` and its usage line.
- [ ] Add the contract test for step 8 and see it fail; edit `SKILL.md` step 8.
- [ ] Dry run H: a throwaway repository with a template in `docs/`, then one with none,
      confirming the fill and the fallback and that the body names which was used.
      Paste both excerpts into the commit body.
- [ ] Break-verify: break each new assertion alone, run, confirm N distinct failures,
      restore, paste them into the commit body.

## Task 4: Fresh-clone dry run

**Files:** `tests/harness/ship.md`, `README.md`, `docs/ARCHITECTURE.md`.

**Interface:** a committed transcript of the gate run the way a stranger would run it.
Clone this branch into a temporary directory, do not seed `config/`, point
`SHIP_GUARD` at the clone's helper, and run `/ship` end to end against a throwaway
GitHub repository with a one-line change in it. The transcript records, in order: the
reviewer command resolved from `templates/config/`, the security reviewer resolved the
same way, both reviews answering with their headers, the template that was filled or
the fallback that stood in, the attestation line, the anchored push and the `ls-remote`
result, and green CI. The throwaway repository is deleted when the task is done.

**Acceptance:** no operator path, account name, project name, reviewer name or model
name appears anywhere in the transcript, which `make lint-identifiers` proves because
the file is tracked. Every guard milestone 5 added still refuses during the run, or the
run says which were not exercised and why. `README.md` says the gate runs on bundled
defaults and names `config/reviewer` and `config/security-reviewer` as what to change.
`docs/ARCHITECTURE.md` drops milestone 6 from "planned for later".

**Steps**

- [ ] Create the throwaway repository and the clone; run the gate; capture the
      transcript into `tests/harness/ship.md`.
- [ ] Update `README.md` and `docs/ARCHITECTURE.md`.
- [ ] Delete the throwaway repository.
- [ ] Break-verify: the transcript asserts nothing on its own, so break the guard that
      protects it. Plant an operator home path in `tests/harness/ship.md`, run
      `make lint`, confirm `lint-identifiers` fails and names the file, remove it,
      paste the failure into the commit body.

## Milestone acceptance

- Every box above ticked and the "where this stands" block current.
- `make check-branch` green.
- Each task's break-verification failure is in a commit body, recorded at that task.
- Dry runs G and H are excerpted in the pull request, each naming the `SKILL.md` it
  loaded; `/ship` is prose and has no automated test (constitution principle 3, last
  bullet).
- `tests/harness/ship.md` is committed and the identifier lint is green over it.
- `docs/ARCHITECTURE.md` matches what exists.
- The pull request carries the actual added-line count against the ~1,350 estimate and
  the fix-to-feature commit ratio.

## Risks

- Moving `find_templates` edits a script that already shipped and is already reviewed.
  A branch dropped in the move changes registration silently, and no read path would
  show it. The count before and after, and `tests/dux-project.bats` passing untouched,
  are what catch it.
- `bin/dux-project` now depends on a file in `skills/ship/`. A checkout missing that
  skill breaks registration instead of only breaking the gate. It refuses with a
  finding rather than skipping the lookup.
- `--body-file` replaces `--fill`, so a body the gate assembles badly is worse than one
  scraped from the commits. The template sections are the check on that, and a thin
  section is a review finding.
- An existing install already has `config/reviewer` without the fallback note, because
  `dux-install` never overwrites a seeded file. The note reaches those installs only
  when the operator deletes the file and reinstalls. Said in the pull request.
- The anchored lease refuses in cases the bare form accepted, which is the point, and
  it will refuse on a stale remote-tracking ref after a fetch of only the base branch.
  Step 8 fetches before it reads the anchor.
- Task 4 needs a live reviewer and a real GitHub repository, so it cannot run offline.
  It is the last task for that reason.

## Open questions for the operator

None.
