# Ask before installing the PR template, and look where GitHub looks

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, before the next
> task starts. Do not run a code review of your own work: `/ship` owns the branch's one
> review and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-08 and reviewed once the same day by an independent session: seven
  findings, all verified, all folded in. The changes: a fixture whose order depended on
  the locale is rearranged; the symlink guard test now asserts on the finding; five Task 2
  assertions that no break reached now have breaks or are dropped; a directory named like
  a template file no longer counts; a miscount is fixed; the untouched constitution
  sentence and a `/ship` base-branch hint are recorded. Approved by the operator on
  2026-09-08, who chose option 3 below. No decisions are open.
- On branch `feat/pr-template-consent`, worktree `.worktrees/pr-template-consent`, based
  on `origin/main` at `fd0cb6c`. Tasks 1 to 3 not started.
- Picks up the one exception to hard rule 1, which `dux-project` has taken without asking
  since milestone 1, and the one-path template check the kickoff found.
- When this merges, `dux-project add` writes a PR template only with `--pr-template
  install`, only when the repo has none anywhere GitHub reads, and the skill asks first.

**Estimated diff:** ~350 added lines across 3 tasks, plus this plan. Well under the cap.

**Goal:** Registering a repo never writes the Dux pull request template without the
operator saying yes. A repo that already has a template, in any of the places GitHub reads
one from, keeps it, and the operator is told where it is. Registration succeeds either way.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` sections 4 (registry), 11
change 9 (the PR body `/ship` writes), and 12 (PR template). Task 3 amends sections 11 and
12 with the decision below, so milestone 6 inherits it rather than deciding it again.

**Deviations:** none from the constitution. Two files outside the kickoff's list are
touched: the spec, because principle 8 says a decision a plan settles is amended into the
spec, and `docs/plans/2026-09-03-dux-roadmap.md`, one row, so milestone 6's plan is written
from the amended wording. Both are prose.
`docs/constitution.md` principle 6 says the one exception "is reported and left for the
operator to commit". That stays true once the write also needs the operator's word, so it
was considered and deliberately not amended; no version bump.

## The decision, and why it is the operator's

The operator asked that an accepted template "always be the one GitHub uses, even if the
repo has others". That cannot be promised by placement.

- **Precedence is undocumented.** GitHub's docs say a template may live in the repository
  root, `docs/`, or `.github/`, in any letter case, with an extension such as `.md` or
  `.txt`, or as a `PULL_REQUEST_TEMPLATE/` folder of several. They do not say which wins
  when more than one exists. The common claim that `.github/` beats root beats `docs/` is
  third-party and unverified. This plan builds nothing on it.
- **Two different purposes.** (a) Pull requests a human opens in the browser: GitHub picks
  the template, and precedence would matter. (b) The file milestone 6 task 3 reads to
  build the body `/ship` passes with `gh pr create --body-file`: GitHub never sees a
  template for those, so precedence is irrelevant and the path is Dux's own choice.

The three options the kickoff named, costed:

| Option | What Dux writes | Cost |
|---|---|---|
| 1. Install to the location the repo already uses | Overwrites the operator's own file with Dux's content | A new class of write, replacing operator content. Undefined when two locations exist or the repo uses the folder form. Rejected. |
| 2. Install to `.github/` and report the others found | A second template beside the repo's own | Depends on the unverified ordering for (a). `/ship` would then need its own precedence rule for (b). The common case, an existing `.github/` file, is a no-op anyway. |
| 3. Leave an existing template alone; `/ship` reads whichever one the repo has | Nothing, unless the repo has none | Dux never creates a second template, so precedence never arises. Milestone 6 task 3 must locate the template by the same rule instead of one fixed path (about ten lines, recorded below). The operator who wants Dux's template in a repo that already has one copies it by hand. |

**Option 3 is what the operator chose**, on 2026-09-08, and it is what this plan builds.
It is the only one that makes the ordering question disappear instead of guessing at it,
and it keeps Dux's one write into a project as narrow as it is today. Option 2 was the
costed alternative: it would have changed one branch of Task 2 and added one question to
the skill. It was not taken.

A consequence of option 3: the kickoff's "when one exists, ask before doing anything to
it" has nothing to ask, because Dux does nothing to it. The skill reports the path and
moves on.

## Design

Two pieces, mirroring the precedent already in the skill: `resolve-base <path>` finds out,
the operator is asked, the answer goes back in as `--base`. Same shape here.

- `bin/dux-project pr-template <path>`, read-only. Prints every template GitHub would
  read, one repo-relative path per line, in the order root, `docs/`, `.github/`; a folder
  form ends in `/`. Prints the single line `none` when there is none. Exit 0. A path that
  is not a directory is `finding: no such directory: <path>`, exit 2.
  A match is an entry whose name, lowercased, is either `pull_request_template` alone and
  a directory (`-d`, the folder form), or `pull_request_template` followed by one dot and
  an extension and a regular file (`-f`). A directory named like the file form, say
  `PULL_REQUEST_TEMPLATE.md/`, is not a template to GitHub and is not a match. A dangling
  symlink passes neither test and is not a match, so the write path's symlink refusal
  still fires. Nothing else changes about what counts.
- `bin/dux-project add ... [--pr-template install|skip]`, default `skip`. The template step
  still runs before the registry line is written, so a failed write still registers
  nothing. Its one stdout line is one of:
  - `installed PR template; commit it in <path> before dispatching ship tasks`
    (flag `install`, nothing found; the existing wording, unchanged)
  - `existing PR template left alone: <path> [<path>...]` (something found, either flag,
    nothing written; the existing prefix, so the existing assertion still holds)
  - `no PR template found; none installed` (nothing found, flag `skip`)
  - `finding: --pr-template must be install or skip: <value>`, exit 2, nothing registered.
  The three existing refusals keep their exact wording: `refusing to write through a
  symlink at <.github>`, `cannot create <.github>`, `cannot write <template>`.
- Usage strings gain `[--pr-template install|skip]` and `pr-template`; the two exact usage
  assertions in the first test are updated to match.
- The implementer's trap: `find -maxdepth 1` on a symlinked `.github` does not descend
  (default `-P`), while a shell glob `"$dir"/*` does, and a glob on a missing `docs/` is
  simply an entry that fails `-e`. A glob loop with `tr '[:upper:]' '[:lower:]'` on the
  basename is bash 3.2 and BSD/GNU neutral. No `nullglob`, no `nocaseglob` needed.
- Glob order within one directory follows the locale, and nothing in the Makefile, the
  workflow or `tests/helpers/setup.bash` pins one: measured on this Mac, `en_US.UTF-8`
  puts `pull_request_template_old.md` before `pull_request_template.txt` and `C` puts it
  after. So the Task 1 fixture holds exactly one real match per directory, and its near
  misses sit in `.github/`, where both locales sort them after `PULL_REQUEST_TEMPLATE`.
  Output order then never depends on collation.

**Files**
- Modify `bin/dux-project`: one detection function, one subcommand, one flag.
- Modify `tests/dux-project.bats`: two new tests, one rewritten, six updated call lines,
  one assertion added to the dangling-symlink test.
- Modify `skills/dux-project/SKILL.md`: one new step, one clause on step 5, one Never line.
- Modify `AGENTS.md` hard rule 1, `docs/ARCHITECTURE.md` two lines, the spec sections 11
  and 12, the roadmap milestone 6 task 3 row.
- Create `docs/plans/2026-09-08-pr-template-consent.md`: this plan.

**Constraints**
- bash 3.2, `shellcheck -s bash` clean, findings on stderr with exit 2, GNU Make 3.81.
- `dux-project add` stays non-interactive: a flag, never a `read`. Registration exits 0
  and writes the registry line when the operator declines and when a template exists.
- Every other bats file calls `dux-project add` without the flag and will now register
  without writing a template. Verified safe: no script reads the installed file (`grep
  PULL_REQUEST_TEMPLATE bin/ skills/` hits `dux-project` and one base-branch hint in
  `skills/ship/SKILL.md` only).
- The identifier lint reads `tests/dux-project.bats`. Fixture repos are named `repoY`,
  `repoZ`, `repoAA`, `repoAB`, `repoAC`, `repoAD` in the existing style, under `$DUX_HOME`; no
  real project name, no home path, and `custom` as the only template content.
- Conventional Commits, subject at most 50 characters. Break failures pasted into the
  commit body, each labelled with the line broken.

## Task 1: find a template everywhere GitHub reads one

**Files:** modify `bin/dux-project`, modify `tests/dux-project.bats`

**Interface:** `dux-project pr-template <path>` as in Design. A new function, call it
`find_templates`, prints the repo-relative matches; the subcommand prints them or `none`.
Task 2 reuses the function. `install_template` is untouched in this task.

**Acceptance:** the subcommand lists root, `docs/`, and `.github/` matches in that order,
in any letter case and with any extension, lists a folder form with a trailing `/`, does
not list a near miss or a directory named like the file form, prints `none` for an empty
repo, and refuses a missing path.

**Steps**

- [ ] Write the test first: "pr-template lists every place GitHub reads a template from".
      Make `repoY` with nothing; `run dux-project pr-template "$DUX_HOME/repoY"`; assert
      (1) `[ "$output" = none ]`. Make `repoZ` with one real match per directory:
      `PULL_REQUEST_TEMPLATE.md` at the root, `docs/pull_request_template.txt`, and a
      directory `.github/PULL_REQUEST_TEMPLATE/` holding one file; plus the near miss
      `.github/pull_request_template_old.md`, which both locales sort after the folder
      (Design). Run the subcommand; assert (2)
      `[ "${lines[0]}" = PULL_REQUEST_TEMPLATE.md ]`, (3)
      `[ "${lines[1]}" = docs/pull_request_template.txt ]`, (4)
      `[ "${lines[2]}" = .github/PULL_REQUEST_TEMPLATE/ ]`, (5)
      `[ "${#lines[@]}" -eq 3 ]`. Then `run dux-project pr-template
      "$DUX_HOME/absent"`; assert (6) status 2 and
      `[[ "$output" == "finding: no such directory: "* ]]`. Then `repoAD` holding only
      a directory `docs/PULL_REQUEST_TEMPLATE.md/`; run; assert (8) `[ "$output" = none ]`.
- [ ] In the first test of the file, add `run dux-project pr-template` and assert (7) the
      usage finding `finding: usage: dux-project pr-template <path>`; update the catch-all
      usage string there to `add|list|get|resolve-base|pr-template`.
- [ ] Run `make job/dux-project`, see the new test and the usage test fail, paste that
      into the commit body.
- [ ] Add `find_templates` and the `pr-template` subcommand to `bin/dux-project`. Run
      `make job/dux-project` and `make lint-shell`; green.
- [ ] Break-verify, one at a time, restoring between each (copy the file aside first,
      never `git checkout --` an uncommitted file): (1) print nothing instead of `none`;
      (2) drop the root from the directory list; (3) drop `docs`; (4) drop the folder
      case so only files match; (5) widen the name match to `pull_request_template*`;
      (6) remove the directory check; (7) remove the argument-count check; (8) drop the
      `-f` requirement on the dotted form. Eight breaks, eight failures on eight different
      test lines, all in the commit body. Run the job twice for break (5), once under
      `LC_ALL=C` and once under the shell's own locale, and confirm it fails line (5) in
      both.

## Task 2: write only with `--pr-template install`, and only when nothing was found

**Files:** modify `bin/dux-project`, modify `tests/dux-project.bats`

**Interface:** the `add` flag, default, output lines and refusal from Design.
`install_template` calls `find_templates` first; anything found means nothing is written.

**Acceptance:** `add` without the flag registers and writes nothing; with `install` it
writes `.github/PULL_REQUEST_TEMPLATE.md` only when `find_templates` printed nothing; a
template anywhere else is left alone and named; the three existing refusals still fire
with the flag and still register nothing; an unknown value is a usage-style finding.

**Steps**

- [ ] Add `--pr-template install` to the six existing runs that must reach the write
      path: `repoE` (line 127), `repoF` (132), `repoI` (168), `repoJ` (178), `repoO`
      (235), `repoP` (245). Update the exact usage string on line 6. In the `repoJ` test
      add, right after the status check, assertion (14)
      `[[ "$output" == "finding: refusing to write through a symlink"* ]]`: today it
      checks only exit 2 and an unwritten file, which a usage finding also satisfies.
      Run the suite: the flag does not exist yet, so each of those runs ends in the
      unknown-flag usage finding and fails, `repoJ` on line (14). Paste that red run.
- [ ] Rewrite the test on line 125 as "add installs the PR template only on
      --pr-template install and leaves an existing one alone": `repoE` with the flag,
      assert (1) the file exists and holds `## How to review`; `repoF` with a custom
      `.github/PULL_REQUEST_TEMPLATE.md` and the flag, assert (2) content still `custom`
      and (3) output contains `existing PR template left alone:
      .github/PULL_REQUEST_TEMPLATE.md`.
- [ ] New test "add without consent writes no template and still registers": `repoAA`,
      `run dux-project add "$DUX_HOME/repoAA"`, assert (4) status 0, (5) the registry has
      `- repoAA `, (6) `[ ! -e "$DUX_HOME/repoAA/.github/PULL_REQUEST_TEMPLATE.md" ]`,
      (7) output contains `no PR template found; none installed`. Then `repoAB` with
      `--pr-template skip`, assert (8) status 0 and the file absent. Then
      `--pr-template yes` on a fresh repo, assert (9) status 2, output
      `finding: --pr-template must be install or skip: yes`, and nothing registered.
- [ ] New test "add leaves a template outside .github alone and says where": `repoAC`
      with `docs/pull_request_template.md` holding `custom`; `run dux-project add
      "$DUX_HOME/repoAC" --pr-template install`; assert (10) status 0, (11)
      `[ ! -e .../.github/PULL_REQUEST_TEMPLATE.md ]`, (12) output contains
      `existing PR template left alone: docs/pull_request_template.md`. No assertion on
      the docs file's content: nothing ever writes to `docs/`, so it would assert on the
      fixture. (10) is a precondition, so a finding cannot pass (11) vacuously.
- [ ] Run `make job/dux-project`, see the new and rewritten tests fail, paste. Implement
      the flag, the validation, and the `find_templates` call in `install_template`. Green.
- [ ] Break-verify, restoring between each, one failure per break, each labelled in the
      commit body with the assertion it hit:
      (1) make `install` behave as `skip`;
      (2) remove the `find_templates` gate so `install` always copies over `repoF`'s file;
      (4) make `skip` a finding, the kickoff's "declining still registers" rule;
      (6) make the default `install`; (7) change the `none installed` wording;
      (8) make `skip` behave as `install`; (9) drop the value check;
      (11) make `install_template` look only at `.github/PULL_REQUEST_TEMPLATE.md` again;
      (12) drop the path from the left-alone line, run the rewritten test and the new one
      separately (`bats --filter`) so its failure on (3) is seen as well as on (12);
      (14) delete the `[ -L "$t" ]` half of the symlink check on `bin/dux-project:49`.
      Ten breaks, ten failures. Assertions (3) and (5) are pinned by breaks (12) and (4),
      and say so in the body; (10) is a precondition, above. Thirteen assertions in all,
      (1) to (12) and (14).

## Task 3: the skill asks, and the documents say so

**Files:** modify `skills/dux-project/SKILL.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`,
`docs/specs/2026-09-03-dux-orchestrator-design.md` sections 11 and 12,
`docs/plans/2026-09-03-dux-roadmap.md` milestone 6 task 3 row.

**Interface:** prose. The skill step, in this order: run `bin/dux-project pr-template
<path>`; if `none`, ask the operator one question, whether Dux should install its pull
request template as one uncommitted file at `.github/PULL_REQUEST_TEMPLATE.md` for them to
commit, and pass `--pr-template install` on yes or `--pr-template skip` on no; if paths,
tell the operator the repo already has a template there, that Dux leaves it and adds no
second one, and pass `--pr-template skip`. Declining is a normal outcome.

**Acceptance:** the skill never runs `add` with `install` without a yes in this
conversation; step 5 reports installed, left alone at a named path, or not installed;
the Never list says no template is written without the operator's word and none is ever
overwritten. `AGENTS.md` hard rule 1 reads "on registration, on the operator's word".
`AGENTS.md` stays under 150 lines (116 today). `docs/ARCHITECTURE.md` lines for
`skills/dux-project` and `bin/dux-project` name `pr-template` and the flag. Spec section
12 carries the decision from this plan; section 11 change 9 and the roadmap row say
`/ship` fills whichever template the repo has, found by the `pr-template` rule, or the
bundled copy when it has none or only the folder form.

**Steps**

- [ ] Add the step as 3b after the issues question in `skills/dux-project/SKILL.md`, the
      clause on step 5, and the Never line.
- [ ] Amend `AGENTS.md` line 16, the two `docs/ARCHITECTURE.md` lines, spec sections 11
      and 12, and the roadmap row. Run `make job/contract` for the line cap.
- [ ] Dry-run the skill against a throwaway repo under a temporary `DUX_HOME`, three
      times: no template and the operator says no; no template and yes; a template at
      `docs/`. Paste the three excerpts into the pull request body (constitution
      principle 3). This is the prose guard's break-verification: the "no" run must show
      registration succeeded with no file written.
- [ ] Run `make check-branch`, inspect the diff, then invoke `/ship`.

## Milestone acceptance

Constitution quality gates, plus: `make job/dux-project` green with every existing refusal
test still present; eighteen break failures across Tasks 1 and 2 in commit bodies, eight
and ten; three skill dry-run excerpts in the PR; the M6 dependency below is in the spec.

## Milestone 6 dependency

Milestone 6 task 3 today reads "fills the repo's `.github/PULL_REQUEST_TEMPLATE.md`, or
`templates/PULL_REQUEST_TEMPLATE.md` when the repo has none". After this change:

- A template Dux installed is still at `.github/PULL_REQUEST_TEMPLATE.md`. No change.
- A repo where the operator declined has none. The bundled copy, as already written.
- A repo with its own template at the root, in `docs/`, in lowercase, as `.txt`, or as a
  folder is new. `/ship` must fill the file it finds by the same rule as `dux-project
  pr-template`, and fall back to the bundled copy for the folder form, which has no
  default. `/ship` runs in a project worktree with no `DUX_HOME` and cannot call
  `bin/dux-project`, so milestone 6 writes the lookup as prose in step 8 or as a
  `ship-guard` helper. About ten lines; it is milestone 6's, recorded in the spec by
  Task 3 so its plan inherits it.
- `skills/ship/SKILL.md` step 0 reads `.github/PULL_REQUEST_TEMPLATE.md` as one
  base-branch hint. A repo whose template is at the root or in `docs/` gives no hint from
  it; the other three signals still resolve the base. Pre-existing and harmless, noted so
  milestone 6 does not rediscover it.

## Risks

- Every other test file now registers without a template. No script reads the installed
  file, checked by grep, so nothing else changes; the whole suite is still run, not one job.
- A repo with only the folder form gets no default template for browser PRs and none from
  Dux. Reported, not fixed; the operator picks one by hand.
- Detection is by name, so a file named like a template that is not one is "found" and
  Dux installs nothing. The cost is one manual copy; the opposite mistake would write a
  second template, which is the bug being fixed.
- Ten breaks in Task 2 is the most this repo has done in one task. Each is a one-line
  change; the risk is a restore missed between breaks, which the copy-aside step covers.
- Glob order follows the locale. The fixture is arranged so no assertion depends on it,
  and break (5) is run under both `LC_ALL=C` and the shell's locale to prove that.

## Open questions for the operator

None. The one open question, option 2 or option 3, was answered on 2026-09-08: option 3.
