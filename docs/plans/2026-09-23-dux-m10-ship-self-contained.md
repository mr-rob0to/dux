# Dux Milestone 10: Ship Is Read From the Checkout Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> reviews the branch owes and decides how many that is (constitution principle 9),
> and a review outside the gate is how the gate gets skipped.

**Where this stands**
- Approved 2026-09-23. Tasks 1 and 2 done; Task 3 next.
- Milestone 6 made the gate stand alone but left it installed by symlink into `~/.claude/skills`; the move of the checkout broke every link.
- When this merges, `bin/dux-install` touches nothing outside the checkout, workers read `skills/ship/SKILL.md` by path with `SHIP_GUARD` in their environment, and the Claude worker cannot invoke any global skill.

**Approval:** the operator approved this milestone, Tasks 1 to 7, on 2026-09-23, as
"Dux Milestone 10" of `docs/plans/2026-09-23-qed-ship-plugin.md` in the `agent-skills`
repository, after one independent review there. This file carries that text in this
repository's plan format; the tasks are unchanged except where Divergences says.
Milestone A of that plan is merged and installed: the `qed` plugin, version 0.1.1, in
Claude Code and Codex.

**Divergences:**
1. The plugin catalog is named `mr-rob0to`, not `agent-skills`: Claude Code reserves that
   name. Install is `qed@mr-rob0to`, and Codex invokes the skill as `$qed:ship`, not `$ship`.
   Task 6 and migration step 6 use these names.
2. Task 3 also ports the upstream fix at `agent-skills` commit c276f43: step 6 runs the
   reviewer with `< /dev/null`, because `codex exec` otherwise waits for input that never
   ends. Its test, "the gate gives the reviewer no input to wait for", goes in
   `tests/worker-adapter.bats`, where this repository's review-block tests already live.
3. Two files beyond the task lists, with no design change: Task 3 corrects the comments in
   `skills/ship/ship-env` that say the installer links the skill, and Task 5 tests the
   wrapper's new argument in `tests/dux-worker-wrap.bats`, beside its recorder tests.

**Estimated diff:** ~500 added lines, ~350 removed, across 7 tasks. Under the cap.

**Goal:** Dux ship tasks work again and keep working when you move the checkout or install
the global `qed` plugin. Nothing outside the Dux repo can change the gate a Dux worker runs.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 18 ("Install") and
section 11 (how the skill resolves its helper), both amended by Task 1 in this pull
request: install no longer links skills; operator skills load as project skills; the helper
is found by the five-step rule, whose exact block lives in section 11; the launcher exports
`SHIP_GUARD`; the worker learns the gate's path from the brief.

**Deviations:** none new. `ship-guard` and `ship-env` still source nothing (milestones 5 and 6).

## Design

- Task order: 1 (spec and plan), 2 (installer and symlinks), 3 (skill, guard, and the
  no-global-path test), 4 (brief and round), 5 (worker adapters), 6 (docs), 7 (dry run).
  Tasks 3 to 5 all change what a worker gets, so 7 runs last.
- The brief line is rendered by `bin/dux-brief`, which already sources `dux-env` and knows
  `DUX_ROOT`. The path names the live checkout; a `git pull` under a running worker changes
  the gate, as the symlink did, and the README's "finish any running task first" stands.
- `SHIP_GUARD` reaches the worker the way `DUX_SHIP_RECORD` does: `dux-worker-wrap` passes
  `$DUX_ROOT/skills/ship/ship-guard` to `worker_launcher` as an eighth argument, for ship
  tasks only, refusing a quote in it like the rest; the launcher exports it after the scrub.
  `codex.sh`'s `worker_run` gains the same export from a matching optional argument so the
  two adapters stay in step; it is tested, not dispatched (ARCHITECTURE line 110).
- `ship-guard` is copied from `agent-skills` byte for byte, at commit 9f46bc3. A contract
  test pins the two renamed strings so a stale copy fails here.

## Task 1: Spec amendments and this plan

**Files:** `docs/specs/2026-09-03-dux-orchestrator-design.md`,
`docs/plans/2026-09-23-dux-m10-ship-self-contained.md`.

**Acceptance:** section 18 no longer says skills are symlinked; section 11 carries the Step 0
block in full and the five-step rule it implements; the "operator's global rules stay
global" bullet is unchanged.

**Steps**
- [x] Amend the two sections; commit the plan.
- [x] Break-verify: not needed; prose.

## Task 2: Installer stops linking; operator skills become project skills

**Files:** `bin/dux-install`, `bin/dux-uninstall` (deleted), `.claude/skills/dux-dispatch`,
`.claude/skills/dux-project`, `.claude/skills/dux-recover`, `.claude/skills/dux-status`
(symlinks to `../../skills/<name>`), `tests/dux-install.bats`, `tests/contract.bats`,
`docs/ARCHITECTURE.md`.

**Interface:** `dux-install [--yes]` seeds config, adds missing model keys, writes the
denylist. It creates no link and reads no directory outside the checkout. `DUX_SKILLS_DIR`
and `DUX_SHARED_SKILLS_DIR` are gone. New contract test: every `skills/dux-*` has a matching
`.claude/skills/<name>` symlink pointing at `../../skills/<name>`.

**Acceptance:** `tests/dux-install.bats` keeps the config and denylist tests and drops the
linking tests (lines 28 to 154 today). `bin/dux-install` run from a fresh clone
leaves `~/.claude` untouched, proved by the test's throwaway `HOME`.

**Steps**
- [x] Add the symlink contract test; see it fail.
- [x] Edit the installer, delete the uninstaller, add the four symlinks, prune the tests.
- [x] Break-verify: point one symlink at the wrong target; confirm the contract test names
      it; restore; paste.

## Task 3: The skill finds its helpers beside itself; guard renames; no global path anywhere

**Files:** `skills/ship/SKILL.md` (Step 0, step 8, Tool notes), `skills/ship/ship-guard`,
`tests/ship-guard.bats`, `tests/contract.bats`.

**Interface:** Step 0's resolution block is the one spec section 11 now carries.
`ship-guard` is the `agent-skills` file: state at `$gitdir/ship-guard/`, marker
`ship-attestation:v1`. Step 8 names the new marker. Everything Dux-specific in `SKILL.md`
stays. New contract test, landing here because this task removes the last mention: no
tracked file under `bin/`, `skills/`, `templates/`, `tests/`, `AGENTS.md`, `README.md`,
`docs/ARCHITECTURE.md`, `docs/specs/` mentions `.claude/skills/ship`, `.agents/skills`,
`DUX_SKILLS_DIR`, or `DUX_SHARED_SKILLS_DIR`.

**Acceptance:** `tests/contract.bats` "stops rather than running unguarded" asserts
`SHIP_DIR:-`, `CLAUDE_SKILL_DIR`, and `export SHIP_GUARD or set SHIP_DIR`. The step 8 test
asserts `ship-attestation:v1`. `tests/ship-guard.bats` `state_file` and the two
`.git/dux-ship` lines move to `ship-guard`. The recorded dry run `tests/harness/ship.md` and
its test are left as they are; they describe a run at a named commit and hold neither
global path.

**Steps**
- [ ] Update the tests, add the no-global-path test; see them fail.
- [ ] Edit `SKILL.md`; copy `ship-guard` from `agent-skills` at its merged commit and name
      that commit in the commit body.
- [ ] Dry run: point `SHIP_GUARD` at a non-executable path and confirm Step 0 stops; unset
      `SHIP_GUARD`, `CLAUDE_SKILL_DIR` and `SHIP_DIR` and confirm the new finding; export
      `SHIP_GUARD` alone and confirm `SHIP_DIR` and `SHIP_ENV` resolve beside it. Paste all
      three.
- [ ] Break-verify: break the no-global-path test by planting `~/.claude/skills/ship/ship-guard`
      in `SKILL.md`; confirm; restore; paste.

## Task 4: The brief and the round name the gate by path

**Files:** `bin/dux-brief`, `templates/brief.md`, `templates/round.md`,
`tests/dux-brief.bats`, `tests/dux-round.bats`.

**Interface:** the Project section gains `- Ship gate: <DUX_ROOT>/skills/ship/SKILL.md`.
The ship rule reads: `- Deliver through the ship gate: read the file the Ship gate line
names and follow it; reading and following that file is invoking the gate. SHIP_GUARD is
set in your environment and points beside it. It is the only gate. Do not invoke any other
ship skill (/ship, $ship), even if one is installed. Never open a PR by hand.` Done lines
and `round.md` say "the ship gate" where they said `/ship`. The 100-line cap still holds:
one rule replaced, one Project line added.

**Acceptance:** `tests/dux-brief.bats:50` asserts the Ship gate line carries
`$DUX_ROOT/skills/ship/SKILL.md`; `:377` and `tests/dux-round.bats:184,428` carry the new
wording; a test asserts a scout brief has no Ship gate line.

**Steps**
- [ ] Update the tests; see them fail.
- [ ] Edit the script and the two templates.
- [ ] Break-verify: break the Ship gate line to a relative path; confirm the test fails;
      restore; paste.

## Task 5: The adapters hand over `SHIP_GUARD`; the Claude worker loses `Skill`

**Files:** `bin/workers/claude.sh`, `bin/workers/codex.sh`, `bin/dux-worker-wrap`,
`tests/worker-adapter.bats`, `docs/ARCHITECTURE.md`.

**Interface:** `worker_launcher path brief model effort settings dux_bin [ship_record]
[ship_guard]`; the launcher exports `SHIP_GUARD='<ship_guard>'` beside `DUX_SHIP_RECORD`
when given one, and refuses a quote in it. `dux-worker-wrap` passes
`$DUX_ROOT/skills/ship/ship-guard` for ship tasks and nothing otherwise. `codex.sh`
`worker_run brief model effort settings [ship_record] [ship_guard]` exports the same before
`exec`. `--tools 'Bash,Read,Glob,Grep,Write,Edit'`; the comment at lines 8 to 13 says why
the gate is read by path and why a global `/ship` must be unreachable.

**Acceptance:** `tests/worker-adapter.bats:69` asserts the six-tool list exactly and the
comment at lines 45 to 46 says six tools and why. New tests: a ship launcher exports
`SHIP_GUARD` at the given path; a launcher without a recorder exports none (mirroring lines
178 to 180); a quoted guard path is refused; the codex `worker_run` command line is
unchanged and its export is asserted through the fake `codex` dumping its environment.

**Steps**
- [ ] Update and add the tests; see them fail.
- [ ] Edit the two adapters and the wrapper.
- [ ] Break-verify: add `Skill` back and confirm the exact-match test fails; drop the export
      and confirm the launcher test fails; two failures; restore; paste.

## Task 6: Docs

**Files:** `README.md`, `docs/ARCHITECTURE.md`, `CONTRIBUTING.md`.

**Interface:** README "The `/ship` gate" says: for your own sessions install `qed@mr-rob0to`
and invoke `/qed:ship`; Dux carries its own copy for workers and reads it by path; the
drift policy in one paragraph (upstream is `agent-skills`; `ship-guard` copied byte for
byte; prose ported by hand; Dux-only hooks live only here). ARCHITECTURE lists the new
`.claude/skills` links, drops `dux-uninstall`, describes the brief's Ship gate line and the
`SHIP_GUARD` export, and updates line 108's tool list.

**Acceptance:** `docs/ARCHITECTURE.md` matches what exists.

**Steps**
- [ ] Edit the three files.
- [ ] Break-verify: not needed; prose.

## Task 7: Dry run with the branch's own Dux

**Files:** none tracked; excerpts in the pull request.

**Interface:** run from the worktree's `bin/` with `DUX_HOME` set to a throwaway directory:
`bin/dux-install` there, `bin/dux-project add` for a throwaway registered repo, then
dispatch one ship task with the Claude harness. Confirm from the worktree that
`.git/ship-guard/<branch>` exists, the PR body carries `ship-attestation:v1`, `dux-result`
proves the receipt, the launcher in the task channel exports `SHIP_GUARD`, and the worker's
transcript shows it read `skills/ship/SKILL.md` from the branch checkout and invoked no
skill. Tear down. Codex is not dispatchable (ARCHITECTURE line 110), so there is no Codex
run; Task 5's tests are its evidence.

**Acceptance:** the task reaches `done` with a proved PR; the excerpt names the file the
worker read and the `SHIP_GUARD` line from the launcher.

**Steps**
- [ ] Run it; paste excerpts.
- [ ] Break-verify: not needed; the guards were broken at Tasks 3 to 5.

## Milestone acceptance

- Every box ticked; `make check-branch` green; ARCHITECTURE matches; the PR carries the
  fix-to-feature ratio and the added-line count.
- Dry runs from Tasks 3 and 7 are in the PR.
- Reviews: separate correctness and security reviews. Worker tool permissions and the gate's
  resolution path change, and the change is ordered after the `agent-skills` milestone.

## Risks

- A worker that ignores the brief and opens a PR by hand was always outside the guard
  (principle 6). Removing `Skill` narrows the accidental path; it does not close the
  deliberate one.
- On Codex the brief rule is the whole isolation. The `qed` plugin installed into Codex makes
  `$qed:ship` visible to every Codex session, and once Codex workers become dispatchable that
  includes them. Acceptable under principle 6; said here so nobody reads "retired" as
  "unreachable".
- Dux-on-Dux tasks see the four project skills in their worktree, as they did through the
  global links. Unchanged exposure.
- A `git pull` under a running worker changes `skills/ship/SKILL.md` under it, as the symlink
  did. Finish running tasks before pulling, as the README already says.

## Open questions for the operator

None. After this merges, on the operator's machine: `git pull && bin/dux-install` in the
checkout, and one sentence in the global rules saying that, inside a Dux worker, reading and
following the file the brief names is invoking the gate (migration steps 5 and 6 of the
parent plan).
