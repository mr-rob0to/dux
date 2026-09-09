# Dux Milestone 6: `/ship` stands alone Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-08 on `plan/m6-ship-standalone` from `main` at ee4064e, reviewed once
  by a fresh independent session, all 18 findings folded in. Awaiting approval.
  0 of 4 tasks.
- Milestone 5 gave the gate a memory but left it wearing the operator's own reviewer
  command, model name and pull request habits, so a stranger who installs Dux cannot
  run it.
- When this merges `/ship` runs from a fresh clone on bundled defaults, its push is
  anchored and verified, and the pull request it writes fills the repo's own template
  and carries its own evidence.

**Estimated diff:** ~1,300 added lines across 4 tasks. The cap is 2,500 lines or 12
tasks (constitution principle 1). Sizing procedure: roadmap, "How a milestone is
sized". The roadmap estimated ~1,200; the difference is the bats file for the new
helper, which the roadmap counted as part of `tests/ship-config.bats` and which carries
a fake-checkout fixture the roadmap did not foresee.

**Goal:** Today `/ship` only works for one person. It names a reviewer model in its own
text, it opens pull requests with whatever `--fill` scrapes out of the commits, and it
pushes with a lease anchored to nothing. After this milestone the gate reads its
reviewers from config with bundled defaults, so a fresh clone runs it unchanged; it
fills whichever pull request template the repository actually has; the body carries the
evidence and a machine-readable record of which commit each phase saw; and the push
refuses to overwrite a commit this branch has never seen.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 11, changes 6 to
9, plus section 18's "the operator's global rules stay global". Three amendments land
in the same pull request as this plan and before any task starts, and are listed under
Design below. Section 12 is unchanged in what it says and gains a pointer to who calls
the lookup.

**Deviations:** constitution principle 2, "every script sources `bin/dux-env` and uses
its helpers". `skills/ship/ship-env` sources nothing, for the same reason
`skills/ship/ship-guard` does not: `dux-install` symlinks the skill directory and the
helper travels with it, and `/ship` runs inside a project worktree that knows nothing
about `DUX_HOME`. It defines its own `finding` and uses the same exit codes.

## Design

Only what the spec does not already say. The three spec amendments are the first three
bullets and are written before Task 1 starts.

- **Spec amendment, section 11 change 9: the lookup keeps its owner.** The spec said
  `/ship` needs its own copy of the pull request template lookup because it cannot call
  `bin/dux-project`. It can, once `ship-env` exists: `ship-env` resolves the Dux
  checkout before it answers anything, so `<root>/bin/dux-project pr-template <repo>` is
  reachable. `find_templates` therefore stays where it is, reviewed and tested, and
  `ship-env pr-template` delegates to it. One implementation, nothing moved, and no
  dependency from `bin/` into `skills/`.
- **Spec amendment, section 11 change 2: `ship-guard` gains a sixth verb, `attest`.**
  The attestation is derived from the guard file, and `ship-guard` is the only thing
  that knows that file's format. Building the JSON in prose would put the format in two
  places.
- **Spec amendment, section 11 change 8: what the attestation may claim.** It carries
  `head_sha`, `fix_passes`, and the three guard phases with the commit each recorded.
  It does not carry `pr` or `ci`: step 8 writes it before either has happened, and a
  record that claims a future step ran is worse than no record.
- **How the gate reaches the Dux checkout.** `ship-env` resolves its own directory with
  `cd "$(dirname "$0")" && pwd -P`, which follows `dux-install`'s directory symlink, and
  takes the checkout two levels up. A skill copied rather than installed lands somewhere
  that is not a Dux checkout, and the gate stops. `ship-guard` keeps working when
  copied, because it needs nothing but the repository it is run in; `ship-env` cannot,
  because everything it answers lives in the checkout.
- **What is already done.** `config/models` is read by `bin/dux-worker-wrap` and seeded
  by `dux-install` since milestone 2, and `/ship` does not use it. Task 1 leaves it
  alone; the roadmap row naming it is satisfied already.
- **Order.** Task 1 first: it creates `ship-env`, which Task 3 extends. Tasks 2 and 3
  both edit `skills/ship/SKILL.md` steps 8 and 9, so they run in order to keep their
  diffs from overlapping. Task 4 runs last and proves the other three from outside.

## Task 1: Reviewers into config

**Files:** `skills/ship/ship-env`, `tests/ship-env.bats`, `skills/ship/SKILL.md`
(steps 0, 6, 7, Tool notes), `tests/contract.bats`, `templates/config/reviewer`,
`templates/config/security-reviewer`, `Makefile` (`SHELL_FILES`),
`docs/ARCHITECTURE.md`.

**Interface:** `ship-env` runs from the installed skill directory and answers what the
gate needs from the Dux checkout it came from.

| Command | Prints | Exit |
|---|---|---|
| `ship-env reviewer` | the step 6 reviewer command line | 0; 2 on a finding |
| `ship-env security-reviewer` | `agent:<name>`, or a command line | 0; 2 on a finding |
| `ship-env --root` | the Dux checkout it resolved | 0; 2 on a finding |

A checkout is a resolved root whose `templates/config` is a directory; anything else is
refused. A value comes from `<root>/config/<key>`, falling back to
`<root>/templates/config/<key>`. No environment override: `bin/dux-worker-wrap:234`
unsets every `DUX_*` variable but three, so one would be live only by hand. A line
starting `#` is a note, a blank line is skipped, and the first line that is neither is
the value. Refusal text, exactly:

- `finding: unknown key '<k>' (reviewer, security-reviewer)`
- `finding: ship-env is not inside a Dux checkout: <root>/templates/config is not a directory`
- `finding: no value for <key> in <root>/config/<key> or <root>/templates/config/<key>`

Step 0 sets `SHIP_ENV="$(dirname "$SHIP_GUARD")/ship-env"` and stops when it is not
executable, so one override points both helpers at one checkout. Step 7 reads the two
value shapes: `agent:<name>` dispatches that agent, and a host that cannot stops and
names `config/security-reviewer` rather than quietly running a different reviewer;
anything else is a command line the audit prompt is appended to. The bundled defaults
keep today's values and gain note lines above them, including the one that used to live
in the skill: when the configured model is refused, fall back and say in the pull
request which reviewer ran.

**Acceptance:** `skills/ship/SKILL.md` contains no model identifier: nothing matching
`gpt-[0-9]` or `claude-[a-z]*-[0-9]`, asserted by test. A fake checkout with no
`config/` resolves both keys from `templates/config/`. Every refusal above has a test
that reaches it. `tests/contract.bats`'s reviewer-shape test still proves the
`## Findings` demand travels in the prompt step 6 sends, now that `codex exec` has left
that step. `make lint` passes with `ship-env` in `SHELL_FILES`. `docs/ARCHITECTURE.md`
lists `ship/ship-env`.

**Steps**

- [ ] Write `tests/ship-env.bats` first and see it fail. It builds a fake checkout per
      test, since two-levels-up from the real script is the operator's own checkout:
      both keys from `config/`, both from `templates/config/` with no `config/`, notes
      and blank lines skipped, each refusal, and resolution through a directory symlink.
- [ ] Write `skills/ship/ship-env`.
- [ ] Add note lines to `templates/config/reviewer` and `templates/config/security-reviewer`.
- [ ] Edit `SKILL.md`: step 0 resolves `$SHIP_ENV`; steps 6 and 7 take their reviewer
      from it and step 7 handles both value shapes; Tool notes lose the model names and
      the Sol fallback line.
- [ ] Re-point the step 6 prompt assertion in `tests/contract.bats`; add the
      no-model-identifier assertion; add `ship-env` to `SHELL_FILES`; update
      `docs/ARCHITECTURE.md`.
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

Every push, in step 8 and in step 9, becomes the same four lines:

1. `git fetch origin`, then read the fetched commit for this branch's remote ref.
2. **Stop unless that commit is an ancestor of `HEAD`**, or the ref does not exist yet.
   The remote holds work this branch has never seen, and a lease anchored to a value
   read after the fetch would match it and overwrite it. This ancestor test is the
   guard; the lease alone is not.
3. Push with `--force-with-lease=refs/heads/<branch>:<that commit>`, and with an empty
   expected value for a branch the remote does not have yet, which refuses if the ref
   appeared in between. One shape for both cases.
4. `git ls-remote origin refs/heads/<branch>` and compare its commit to `HEAD`. Not
   equal is a stop: something landed between the ancestor test and the push.

The stop table gains two rows: `The remote branch holds commits this branch does not`
and `The remote head is not the commit that was pushed`.

**Acceptance:** contract tests assert step 5 carries the evidence rule and its "or why
none" escape; that step 8 carries the ancestor test, `--force-with-lease=refs/heads/`,
the empty-expect case and the `ls-remote` comparison; that step 9's push carries the
same four lines; and that the stop table names both new rows. One dry run.

**Steps**

- [ ] Add the contract tests to `tests/contract.bats` and see them fail against today's
      `SKILL.md`.
- [ ] Edit `SKILL.md` steps 5, 8 and 9 and the stop table.
- [ ] Dry run G: against a throwaway repository, push a commit from a second clone, then
      run step 8's four lines in full, fetch included; confirm the ancestor test stops
      the gate rather than the lease accepting the fetched value. Paste the excerpt into
      the commit body.
- [ ] Break-verify: break each assertion this task added, one at a time, run, confirm N
      distinct failures, restore, paste them into the commit body.

## Task 3: The template lookup and the attestation

**Files:** `skills/ship/ship-env`, `tests/ship-env.bats`, `skills/ship/ship-guard`,
`tests/ship-guard.bats`, `skills/ship/SKILL.md` (steps 8, 9), `tests/contract.bats`,
`docs/ARCHITECTURE.md`.

**Interface:** `ship-env` gains two verbs and `ship-guard` gains one.

| Command | Prints | Exit |
|---|---|---|
| `ship-env pr-template <repo>` | one repo-relative path per line, nothing when the repo has none | 0; 2 on a finding |
| `ship-env pr-template-fallback` | the absolute path of the bundled `templates/PULL_REQUEST_TEMPLATE.md` | 0; 2 on a finding |
| `ship-guard attest` | the attestation comment line, from the guard file | 0; 2 on a finding |

`pr-template` runs `<root>/bin/dux-project pr-template <repo>` and turns its `none` into
no output. Any non-zero exit from it is a finding here, never empty output: empty means
"this repo has no template", and a lookup that failed must not be read as one.
`attest` refuses a phase that is not recorded or whose value is not forty hex
characters, and prints `<!-- dux-attestation:v1 {...} -->` carrying `head_sha`,
`fix_passes` and the three phases with the commit each recorded.

Step 8 stops using `gh pr create --fill`. It takes the first **file-form** path
`ship-env pr-template` prints, in the root, `docs/`, `.github/` order, and falls back to
`pr-template-fallback` when there is none or when every match is the folder form. GitHub
documents no precedence between the three directories, so the body says which template
was filled rather than implying GitHub would pick the same one. The gate fills the
sections, puts verbose material inside `<details>`, keeps the existing `Closes #<n>`
rule as the last line of prose, and appends the attestation comment after it. `--fill`
also supplied the title, so step 8 now passes `--title` explicitly: the title the
operator gave for this ship, else the subject of the branch's first commit after
`$BASE`. The body goes in with `--body-file`. Every push after a fix pass rebuilds the
body and runs `gh pr edit --title --body-file`, including step 9's, or the attestation
names a commit that is no longer the head.

**Acceptance:** `ship-env pr-template` returns the same paths as `dux-project
pr-template` for a repo with a template, with none, and with the folder form, and turns
a non-zero exit into a finding. `ship-guard attest` has a test for a complete guard file
and one for each missing and each malformed phase. A contract test asserts step 8 no
longer names `--fill`, and does name `--title`, `--body-file`, `<details>`,
`dux-attestation:v1` and the refresh after a fix pass, and that the four strings the
existing `Closes #<n>` test pins are unchanged. `docs/ARCHITECTURE.md` lists the three
new verbs.

**Steps**

- [ ] Add the `pr-template` and `attest` tests to `tests/ship-env.bats` and
      `tests/ship-guard.bats` and see them fail.
- [ ] Add the two verbs to `ship-env`, propagating a non-zero exit as a finding.
- [ ] Add `attest` to `ship-guard` and its usage line.
- [ ] Add the contract tests for step 8 and see them fail; edit `SKILL.md` steps 8 and 9.
- [ ] Dry run H: a throwaway repository with a template in `docs/`, then one with none,
      then one with only the folder form; confirm the fill, the fallback and that the
      body names which was used. Paste the excerpts into the commit body.
- [ ] Break-verify: break each assertion alone, run, confirm N distinct failures,
      restore, paste them into the commit body.

## Task 4: Fresh-clone dry run

**Files:** `tests/harness/ship.md`, `README.md`, `docs/ARCHITECTURE.md`.

**Interface:** a committed transcript of the gate run the way a stranger would run it.
Clone this branch into a temporary directory, do not seed `config/`, load the clone's
own `SKILL.md` by path and point `SHIP_GUARD` at the clone's helper so `SHIP_ENV`
derives from it, and run `/ship` end to end against a throwaway GitHub repository with a
one-line change in it. The transcript records, in order: the reviewer resolved from
`templates/config/`, the security reviewer resolved the same way, both reviews answering
with their headers, the template that was filled or the fallback that stood in, the
attestation line, the ancestor test, the anchored push and the `ls-remote` result, and
green CI. The throwaway repository is deleted when the task is done.

**Acceptance:** no operator path, account name or project name appears in the
transcript, which `make lint-identifiers` proves because the file is tracked. Reviewer
and model names do appear, because the default reviewer command carries one; every such
string is byte-equal to a line in `templates/config/`, checked by eye and stated in the
pull request, since no lint covers it. The run is green, so the milestone 5 guards that
only fire on a refusal are not exercised by it: `check`, `push-ok`, the fix-pass cap and
the missing-header stop were dry-run at milestone 5 and the transcript says so rather
than claiming coverage it does not have. `README.md` says the gate runs on bundled
defaults and names `config/reviewer` and `config/security-reviewer` as what to change.
`docs/ARCHITECTURE.md` drops milestone 6 from "planned for later".

**Steps**

- [ ] Create the throwaway repository and the clone; run the gate; capture the
      transcript into `tests/harness/ship.md`.
- [ ] Update `README.md` and `docs/ARCHITECTURE.md`.
- [ ] Delete the throwaway repository.
- [ ] Break-verify: the transcript asserts nothing on its own, so break the guard that
      protects it. Plant an operator home path in `tests/harness/ship.md`, run
      `make lint`, confirm `lint-identifiers` fails and names the file, remove it, paste
      the failure into the commit body.

## Milestone acceptance

- Every box above ticked and the "where this stands" block current.
- `make check-branch` green.
- Each task's break-verification failure is in a commit body, recorded at that task.
- Dry runs G and H are excerpted in the pull request, each naming the `SKILL.md` it
  loaded; `/ship` is prose and has no automated test (constitution principle 3, last
  bullet).
- `tests/harness/ship.md` is committed and the identifier lint is green over it.
- `docs/ARCHITECTURE.md` matches what exists.
- The pull request carries the actual added-line count against the ~1,300 estimate and
  the fix-to-feature commit ratio.

## Risks

- `/ship` now runs `bin/dux-project`, which sources `dux-env` and creates `data/`,
  `state/` and `config/` in the Dux checkout. All three are gitignored and any real
  install has them; in a fresh clone the gate creates them a little before the installer
  would.
- `--body-file` replaces `--fill`, so a body the gate assembles badly is worse than one
  scraped from the commits. The template sections are the check on that, and a thin
  section is a review finding.
- Rebuilding the body after a fix pass overwrites hand edits to the pull request body.
  Deliberate: the attestation has to name the commit that is actually out there.
- An existing install already has `config/reviewer` without the fallback note, because
  `dux-install` never overwrites a seeded file. The note reaches those installs only
  when the operator deletes the file and reinstalls. Said in the pull request.
- The ancestor test refuses in cases the bare lease accepted, which is the point. A
  branch legitimately behind its remote now stops the gate and the operator rebases.
- Task 4 needs a live reviewer and a real GitHub repository, so it cannot run offline.
  It is the last task for that reason.

## Open questions for the operator

None.
