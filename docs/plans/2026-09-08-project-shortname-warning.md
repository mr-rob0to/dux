# Short project name warning at registration

**Where this stands:** Approved 2026-09-08 including the skill relay clause, and Task 1
is implemented and break-verified on `feat/project-shortname-warning`. Next: `/ship`.
Blocked on: nothing.

**Divergence, 2026-09-08, during the ship gate:** the test asserts on `$stderr` via
`run --separate-stderr`, not on the merged `$output`, so a warning that moved to stdout
can no longer pass. Raised by the gate's code review as a Minor finding, and it makes a
fourth assertion, broken and seen to fail with the other three.

**Goal:** `dux-project add` tells the operator, at the moment they choose the name, when
that name is too short for the identifier lint to check.

**Approach:** Add one `log` line to the `add` branch of `bin/dux-project`, printed after
the registry line is written, when the chosen name is shorter than four characters. The
wording mirrors the line `bin/dux-install` already prints when it leaves the same name
out, in the future tense, because at registration nothing has been left out yet. Three
assertions in `tests/dux-project.bats` pin the behaviour, its remedy and its boundary:
three characters warns, the warning names `--name`, four characters does not warn.

Rejected: **a finding.** A refusal would strand an operator whose project really is
called `api`, and the registration itself is correct.

Rejected: **a shared threshold or a shared message helper in `bin/dux-env`.** Both
messages spell the number in words, "shorter than four characters", so a shared constant
`4` would not remove the second edit: changing the rule means rewriting both sentences
anyway. The two sentences must also differ in tense, so a shared string cannot be true in
both places. And both boundaries are already pinned by tests: the installer's at
`tests/dux-install.bats` (a three-character name left out, a four-character one kept),
this one by the new three/four test. What is left to share is a length comparison, which
is not one of the things `bin/dux-env` exists to stop scripts reinventing.

Rejected: **warning before the registry line is written.** The warning is only true of a
name that got registered; printed earlier it would also fire on paths that end in a
finding and register nothing.

**Assumptions:**
- The four-character rule stays written in two places, `bin/dux-install` and
  `bin/dux-project`, with a comment in the second naming the first as the decider.
- `bin/dux-install` keeps its own skip and its own log line unchanged. It is what
  actually decides the denylist contents; this warning only forecasts.
- The warning covers both name paths, the folder-derived name and `--name`, because it
  sits after both have been resolved.
- The other install-time skip, a project whose repository is the checkout being
  installed into, gets no warning here. Out of scope.
- **Accepted wart: Dux registered as a project of itself gets a warning it cannot act
  on.** The checkout is named `dux`, three characters, so this warning fires. At install
  time the self-skip runs first and drops the name anyway, so a longer name would change
  nothing. Detecting self here means copying `bin/dux-install`'s `git_home` comparison
  into a second script, which costs more than the wart. Accepted, not fixed.
- **Accepted wart: the remedy the message names cannot be run against the same path.**
  Re-running `dux-project add <same path> --name longer` hits the existing
  `path ... already registered as ...` finding, and there is no `dux-project remove` yet.
  The brief asks for the installer's wording, and drift between the two lines is the
  named risk, so the wording stays and the operator reads it as information.
- No `docs/ARCHITECTURE.md` change: no script, adapter, state file, or flow step is
  added, removed, or renamed.
- No `docs/constitution.md` change: v2.0.4 principle 2 already states the carve-out.

**Constraints:**
- bash 3.2: no associative arrays, no `mapfile`, no negative array indices.
- `shellcheck -s bash` clean, enforced by `make lint-shell`.
- Findings go to stderr as `finding: <one line>` with exit 2. This is not a finding:
  it is `log`, which prints `dux: <line>` to stderr and does not exit.
- `make lint-identifiers` greps tracked files. `tests/dux-project.bats` is tracked:
  no personal identifier and no real project name written bare in it.
- Registration MUST still succeed: exit status 0, registry line written.
- Installer wording to mirror, verbatim from `bin/dux-install`:
  `left $name out of the denylist: shorter than four characters, and the lint would
  match nearly every file; register it under a longer name with dux-project add --name`
- The exact line this plan adds, differing only in the opening clause:
  `$name will be left out of the denylist: shorter than four characters, and the lint
  would match nearly every file; register it under a longer name with dux-project add
  --name`
- Conventional Commits, subject at most 50 characters, imperative, lowercase.

**Risks:**
- A test elsewhere in the suite registers a short name and asserts on exact stderr; the
  new line would break it. `--name api` and `--name x` already appear in
  `tests/dux-project.bats`, so the whole suite must be re-run, not just the new test.
- The boundary is the only place this can be wrong. `-lt 4` versus `-le 4` decides
  whether a four-character name warns; the second assertion exists for exactly that.
- Blast radius is one log line on one code path. Nothing reads it, nothing branches on
  it, and no file contents change.

## Files
- Modify `bin/dux-project` — one length check and one `log` line in the `add` branch
- Modify `tests/dux-project.bats` — one test, three assertions and their boundary
- Modify `skills/dux-project/SKILL.md` — one clause on step 5 so Dux relays the warning
- Create `docs/plans/2026-09-08-project-shortname-warning.md` — this plan

## Task 1: warn when the registered name is shorter than four characters

**Files:** modify `bin/dux-project`, modify `tests/dux-project.bats`, modify
`skills/dux-project/SKILL.md`

**Interfaces:** consumes `log()` from `bin/dux-env` (`printf 'dux: %s\n' "$*" >&2`, no
exit). Produces no new function, variable, or file. Nothing later depends on it.

- [x] Write the test first, in `tests/dux-project.bats`, named
      "add warns that a name shorter than four characters is not linted".
      Make a repo at `$DUX_HOME/repoW`, then `run dux-project add "$DUX_HOME/repoW"
      --name abc`. Assert `[ "$status" -eq 0 ]`, assert the output contains
      `shorter than four characters`, assert the output contains
      `dux-project add --name`, and assert the registry holds `- abc `.
      Then make `$DUX_HOME/repoX` and `run dux-project add "$DUX_HOME/repoX"
      --name abcd`. Assert `[ "$status" -eq 0 ]` and that the registry holds `- abcd `
      before asserting the output does not contain `shorter than four characters`, so a
      registration that ended in a finding cannot pass the absence check vacuously.
      `abc` and `abcd` are not registered project names and can never reach either
      denylist: the installer drops names under four characters, and the whole-word list
      holds only the account and home directory names.
- [x] Run `make job/dux-project` and see the new test fail. Paste that failure into the
      commit body.
- [x] Add to `bin/dux-project`, immediately after
      `log "registered $name base=$base worktree=$wt issues=$issues"`, a check
      `if [ "${#name}" -lt 4 ]; then log "..."; fi` carrying the exact line from
      Constraints, and a one-line comment saying `bin/dux-install` is what decides the
      denylist contents.
- [x] Run `make job/dux-project`; the suite passes, 30 tests.
- [x] Break-verify assertion one, the warning fires at three characters: change `-lt 4`
      to `-lt 1`, run `make job/dux-project`, confirm the "contains `shorter than four
      characters`" assertion fails, restore. Copy the file aside first; never restore
      with `git checkout --` on an uncommitted file.
- [x] Break-verify assertion two, the message names the flag: restore `-lt 4` and change
      the message tail from `dux-project add --name` to `dux-project add`, run
      `make job/dux-project`, confirm the "contains `dux-project add --name`" assertion
      fails and the first assertion still passes, restore.
- [x] Break-verify assertion three, the boundary: change `-lt 4` to `-lt 9`, run
      `make job/dux-project`, confirm the four-character case fails, restore.
- [x] Confirm the three breaks produced three distinct failures, each naming a different
      line of the test. If any passed, that is a finding: stop and find out why the
      assertion never reached the check. All three failures go in the one commit body,
      each labelled with the line that was broken.
- [x] Add one clause to step 5 of `skills/dux-project/SKILL.md`, so Dux passes the
      warning on: without it the script warns and the operator never hears it, because
      nothing obliges Dux to relay a `dux:` line. Approved by the operator as review
      finding 10.
- [x] Dry-run the skill against a throwaway repo under a temporary `DUX_HOME`, as
      constitution principle 3 requires for a skill change, and paste the excerpt into
      the pull request body. Registering under a short name must print the warning;
      registering under a longer one must not.
- [x] Run `make check-branch` and confirm lint, the full suite, and the bash 3.2 matrix
      are green.

**Done when:**
- `make job/dux-project` prints `ok    dux-project                 30 tests`.
- `make check-branch` exits 0 with no `finding:` line.
- `dux-project add <repo> --name abc` exits 0, writes `- abc path=...` to the registry,
  and prints to stderr a line containing `shorter than four characters` and
  `dux-project add --name`.
- `dux-project add <repo> --name abcd` exits 0, writes `- abcd path=...`, and prints no
  such line.
- The commit body contains all three break failures as the runs printed them, each
  naming the line that was broken.

## Review findings

One independent design review, from a fresh session that did not write this plan. Twelve
findings; five accepted and folded in above, five confirmed the plan was already right,
one rewrote an argument, one is an operator decision below.

| # | Finding | Outcome |
|---|---|---|
| 1 | Dux is registered as a project of itself under a three-character name, so this warning fires on the one project every operator has, and a longer name would change nothing because the self-skip drops it first. | **Accepted, recorded not fixed.** Detecting self needs `bin/dux-install`'s `git_home` comparison copied into a second script. Written up as an accepted wart. |
| 2 | The remedy the message names cannot be run: `add <same path> --name` hits the existing "path already registered" finding, and no `dux-project remove` exists. The plan also never wrote the exact string down. | **Accepted.** Exact string now in Constraints. Wording still mirrors the installer, because the brief asks for that and drift is the named risk; the gap is recorded as an accepted wart. |
| 3 | The four-character assertion could pass vacuously: with no `status` check, a registration ending in a finding leaves `$output` as a `finding:` line, which also lacks the warning. | **Accepted.** The four-character run now asserts status 0 and the registry line before the absence check. |
| 4 | The plan claimed two assertions but described three; the `--name` assertion was never broken on its own, because break one removes the whole line. | **Accepted.** Three named assertions, three breaks, one of which alters the message rather than the threshold. |
| 5 | The stated reason for duplicating the rule was backwards: the digit is the behaviour, the sentence is cosmetic. The real reasons are that both messages spell "four" in words and both boundaries are already pinned by tests. | **Accepted.** Design unchanged, argument rewritten. |
| 6 | Placement after the registry write is correct; every finding path exits first, and both name paths are resolved by then. | Confirmed, no change. |
| 7 | `-lt 4` matches `bin/dux-install` exactly; the charset guard makes byte-versus-character moot. | Confirmed, no change. |
| 8 | No existing assertion in any bats file breaks: every short-name registration either ends in a finding or is not wrapped in `run`. | Confirmed, no change. |
| 9 | The plan left fixture names to the implementer, so the identifier-lint trap could not be checked at review. | **Accepted.** Fixtures named in Task 1, with why they are safe. |
| 10 | Nothing tells Dux to relay a `dux:` log line, so the operator may still hear nothing. `skills/dux-project/SKILL.md` step 5 lists what to report and the warning is not on it. | **Accepted, on the operator's word.** One clause added to step 5. A third file, outside the brief's list, approved 2026-09-08. |
| 11 | The break steps are distinct. | Confirmed, and a third added. |
| 12 | The out-of-scope claims hold: no `ARCHITECTURE.md` or constitution change is required, and `rename`/`remove` do not exist to keep in step. | Confirmed, no change. |

### The one decision, settled

The brief named `bin/dux-project` and `tests/dux-project.bats` as the target files. The
warning is a `dux:` log line, and nothing obliged Dux to pass a `dux:` line on:
`skills/dux-project/SKILL.md` step 5 told Dux to report the base branch, the worktree
mechanism, issue intake, and the PR template, and stopped there. So the script would warn
and the operator might never see it.

The operator approved adding the clause. `skills/dux-project/SKILL.md` is a third target
file, one line, recorded here as a divergence from the brief's file list.
