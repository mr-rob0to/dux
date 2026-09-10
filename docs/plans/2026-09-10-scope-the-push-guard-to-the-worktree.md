# Scope the worker's push guard to its own worktree

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, before the next
> task starts. Do not run a code review of your own work: `/ship` owns the branch's one
> review and its security pass (constitution principle 9).

**Where this stands**
- Task 1 landed 2026-09-10: the hooks path is now the worktree's own git configuration
  and the two shared-config layouts are refused. Tasks 2 and 3 next.
- Drafted 2026-09-10 by a Dux plan worker. One independent design review by a fresh
  session; its findings and what was done with each are at the bottom.
- Picks up the defect that makes every worker's `make check` red: 107 fixture pushes
  refused by a guard that reached every repository the worker touched.
- Merges as one ship PR of three tasks, run in a plain session rather than by a Dux
  worker. "How this ships" says why.

**Estimated diff:** ~150 changed lines across 3 tasks. Well under the cap.

**Goal:** A worker is still refused when it pushes its task worktree to the project's
base branch, and the project's own hooks still run there. Every other repository the
worker touches, the throwaway repositories the test suite builds included, pushes as if
Dux were not there. Every worker's `make check` goes green again.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 5.5, amended in
this pull request.

**Deviations:** none from the constitution. One from how Dux work is usually run: the
ship task is not dispatched as a Dux worker. Reason under "How this ships".

## What is wrong today

`bin/dux-worker-wrap` points every git the worker runs at the task's hooks directory
through `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0=core.hooksPath` and `GIT_CONFIG_VALUE_0`.
An environment setting is process-wide, so it applies in every repository the worker
touches, and `templates/hooks/pre-push` refuses `refs/heads/<base>` without knowing
which repository it runs in.

`make_repo` in `tests/helpers/setup.bash` builds a throwaway repository for almost every
test and pushes it to its own `main`. Inside a worker that push is refused. Measured in
this plan task's own worker on 2026-09-10: 107 failures, every one of them this line,

```
finding: refusing to push to main from a Dux worktree
```

across nine test files, and `make` stopped before the remaining files ran, so 107 is a
floor. Reproduced standalone: the same push succeeds without those three variables and
fails with them.

## The decision

**Mechanism: the hooks path lives in the worktree's own git configuration.** Git keeps a
configuration file per worktree once `extensions.worktreeConfig` is on (git 2.20 or
newer): `git config --worktree` writes to the file `git rev-parse --git-path
config.worktree` names, git reads it only for commands run in that worktree, from any
directory inside it and through `git -C`, and `git worktree remove` deletes it with the
worktree. `dux-worktree create` turns the extension on in the worktree's repository and
writes `core.hooksPath` = `tasks/<id>/hooks` there. The wrapper hands the worker nothing
about git: `GIT_CONFIG_*` stays scrubbed from its environment and nothing is put back.

**The guard still holds in the worktree.** The worktree's file outranks the shared
`.git/config`, so the task hooks directory is what git runs there: the rendered
`pre-push` refuses `refs/heads/<base>` and otherwise runs the project's own `pre-push`
with the same stdin and arguments. The template is untouched. The guard is now on for
the worktree's whole life, from create to teardown, where before it was on only while
the worker ran.

**Everything else is untouched.** No environment variable reaches the worker's git, so a
repository beside the worktree, a fixture under `/tmp`, or the primary checkout each run
their own hooks. Whether a push goes to `refs/heads/main` there is nobody's business but
that repository's.

**What is written into the project.** One line, `extensions.worktreeConfig = true`, in
the shared `.git/config` of the worktree's repository, once, idempotent, left in place.
Section 5.5 said nothing is written there; it now says this one line is. It changes
nothing for the primary checkout except in two layouts git documents: `core.worktree`
set, or `core.bare = true`, in the shared config, which the extension would apply to
every worktree. Both are refused with a finding before the line is written. A project
whose `make worktree` or script makes a clone rather than a linked worktree gets the
same two writes in the clone's own config; the registered repository is not touched.

**The channel no longer stages hooks.** The wrapper copied `tasks/<id>/hooks` into the
run's channel so that the worker's environment named no path under `data/`. The path is
now readable from the worktree's git config either way, and the worker already learns
the Dux home and its task id from `DUX_STATUS_LOG`; the ledger and `status.log` are
protected by proof (spec 2.1), not by a path nobody has said aloud. Pointing the
worktree at the channel for the run and back afterwards would be two more writes and a
dangling path after a refused run. Fewer states wins.

**Bypasses.** `--no-verify`, `git -c core.hooksPath=`, `GIT_CONFIG_*` in the environment
(which outranks every file, so the deny rule on it stays), and the forge API are what
they were and match the deny rules in `templates/worker-settings.json`. `git config
--worktree` is denied by rule only when the command names `core.hooksPath`; removing the
`core` section, or the worktree's config file itself, is not, and is denied by the
brief alone. That is the same class as unsetting the environment was before: a worker
has to set out to do it, and one that does is outside what Dux claims to contain (spec
2.1). No new deny rule.

**Alternatives not chosen.**
- The hook decides by directory: render the worktree path into `pre-push` and pass
  through elsewhere. Fixes `pre-push` only. The override would still replace every
  other hook in every other repository, so the project's `pre-commit` runs in the
  fixtures and the fixtures' own hooks never do, and the pass-through would have to
  find the hook the override just hid.
- `core.hooksPath` in the shared `.git/config`: applies to the primary checkout and
  every worktree, so the operator's own push to `main` is refused.
- Scrub `GIT_CONFIG_*` in the test helper: hides the defect the tests found and leaves
  every worker pushing fixtures through the guard. The brief refuses this.
- A `git` shim on the worker's `PATH`: anything that calls `/usr/bin/git` skips it.

## How this ships

The ship task cannot be a Dux worker. The wrapper that spawns it is the one on `main`
today, so the worker's environment carries the override this change removes, its
`make check` is red on the same 107 pushes, and `/ship` refuses a red check. Run the ship
task in a plain session, in a worktree of this repository cut from freshly fetched
`origin/main`, through the operator's usual tab and kickoff. Nothing else about the gate
changes: `make check-branch`, the one review, the security pass, the PR, CI.

**Do the 107 go green here, and how is that proved.** In the ship session they are
green, but that proves nothing: that session never had the override. The proof that the
fix cures workers is Task 2's worker-environment test, which performs `make_repo`'s
exact operation, a throwaway repository pushed to its own `main`, from inside an
environment the new wrapper built, and passes only when no override reached it. After
merge, pull the plain checkout to the merged `main`; no restart is needed beyond that,
the wrapper is read from there at each spawn. The first worker dispatched after that is
the field confirmation, and its `make check` shows zero refusals.

## Task 1: the guard lives in the worktree's own git config

**Files:** `bin/dux-worktree`, `tests/dux-worktree.bats`.

**Interface:** `install_hooks` takes the worktree path. The read of the project's own
hooks source stays on `git_repo`, as today; on reuse a read through the worktree would
answer with the task hooks directory itself. Before writing anything, it reads the shared
config of the worktree's repository: the directory `git -C <wt> rev-parse
--git-common-dir` prints, resolved from `<wt>` the way the hooks source already is,
because a primary checkout or a clone prints a relative `.git`. `core.bare` is read with
`--bool`. `core.worktree` set is
`finding: <repo> shares core.worktree with its worktrees; move it to the main worktree's
config.worktree (git help worktree, CONFIGURATION FILE) before Dux can scope its hooks`;
`core.bare` true is the same line with `core.bare`. Then it sets
`extensions.worktreeConfig` to `true` in that shared config and `core.hooksPath` to
`tasks/<id>/hooks` in the worktree's own config; either write failing is
`finding: cannot scope the hooks path for <wt>`. Both the fresh-create path and the
clean-reuse path call it, as today.

**Acceptance:** after `dux-worktree create`, `git -C <wt> config --worktree
core.hooksPath` prints the task hooks directory, `git -C <repo> config core.hooksPath`
prints nothing, and the primary checkout still pushes to `main`. The existing hook tests
push from the worktree with no environment help at all. Both refusals are reached.

**Steps**

- [x] Tests first. Delete the `hooks_env` helper and every `env $(hooks_env ...)` prefix
      in `tests/dux-worktree.bats`; the three hook tests ("refuses the base branch and
      allows the task branch", "chains the project's own pre-push", "the rendered hook
      never re-evaluates") push plainly from the worktree. Add to the scout create test:
      the worktree config names the task hooks directory, the registered repository's
      own `core.hooksPath` is unset, and a push from the registered repository to `main`
      succeeds. Add two refusal tests: a repository with `core.worktree` set, and a
      linked worktree registered as the project whose repository is a bare clone *of*
      the fixture origin (`git clone --bare`, so `create`'s fetch of `origin/<base>` has
      a remote to reach; `core.bare = true` sits in its shared config); each is refused
      with the finding above and no config written.
- [x] Run them and see the base-branch test push succeed (that is the defect) and the
      new assertions fail.
- [x] Implement in `install_hooks`, in the order the interface gives: read, refuse,
      enable, write. Use `git -C <wt>` for both writes, never `git_repo`: for a clone
      mechanism the shared config is the clone's.
- [x] Break-verify, one at a time, each failure pasted into the commit body:
      1. skip the `core.hooksPath` write: the base-branch push succeeds, the refusal
         test fails.
      2. skip the extension write: `--worktree` refuses, create fails with the
         cannot-scope finding, the scout create test fails.
      3. write `core.hooksPath` with `git_repo config` instead of `--worktree`: the
         registered repository's push to `main` is refused, that assertion fails.
      4. drop the `core.worktree` check: its refusal test fails.
      5. drop the `core.bare` check: its refusal test fails.

## Task 2: the wrapper hands the worker no git configuration

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`, `tests/e2e-dispatch.bats`.

**Interface:** `scrub_worker_env` keeps unsetting `GIT_CONFIG_*` and puts nothing back.
The channel no longer holds `hooks/`; the `no hooks dir` refusal stays, since the
worktree's config names that directory. Nothing else in the wrapper changes.

**Acceptance:** the worker's environment holds no `GIT_CONFIG_` name and exactly the two
`DUX_` names it had. From inside that environment a throwaway repository pushes to its
own `main`, the worktree is refused on `refs/heads/main` with origin unmoved, and the
worktree's task branch pushes with the project's own `pre-push` seeing the same refs.

**Steps**

- [ ] Tests first, in `tests/dux-worker-wrap.bats`. "the worker inherits its task
      interfaces and nothing else of Dux's": the `GIT_CONFIG_` count becomes 0. "the
      worker's status log is its own channel outbox": the three `GIT_CONFIG_` greps
      become one count-0 assertion. "the channel holds the worker's own copies": no
      `hooks` entry in the listing. In `tests/e2e-dispatch.bats`, "a worker gets its own
      channel and nothing of Dux's own session": the same flip.
- [ ] New test, "a worker's git guard stops at its worktree". Install a marker
      `pre-push` in the project before `dux-worktree create`, as the dux-worktree
      chaining test does. The fake worker's script, through its `run` verb, does three
      things and leaves each exit code in a file: build a throwaway repository beside
      the worktree the way `make_repo` does and push it to its own `main`; push the
      worktree's head to `refs/heads/main`; push the worktree's task branch with
      upstream. Assert: first exit 0 and the throwaway origin's `main` moved; second
      non-zero, the project origin's `main` unmoved, and the finding line in
      `state/<id>.out`; third exit 0 and the marker file holding the task branch ref.
- [ ] Run and see the new test fail on its first assertion (the fixture push is
      refused) and the count assertions fail on 3.
- [ ] Remove the `GIT_CONFIG_*` export from `scrub_worker_env`, and the `cp -R` of the
      hooks into the channel with its two `chmod` lines. Re-read `scrub_worker_env` and
      the channel block whole afterwards.
- [ ] Break-verify, one at a time, each failure pasted into the commit body:
      1. put the export back: the count-0 assertions fail and the fixture push is
         refused.
      2. export the same three names with the value `/dev/null`: the worktree push to
         `main` succeeds and the marker is missing; the fixture push still passes.
      3. put the channel staging back: the channel listing assertion fails.

## Task 3: say so

**Files:** `docs/ARCHITECTURE.md`, `bin/workers/codex.sh`.

- [ ] Architecture, dispatch flow step 4: the worktree's config carries the hooks path.
      Task channel bullets: the channel holds the brief and the settings, not hooks;
      the environment gets `DUX_STATUS_LOG` and `DUX_REPORT` back and no `GIT_CONFIG_`
      name. File map: drop `hooks/` from `channels/<id>.<run>/`.
- [ ] `bin/workers/codex.sh` header comment: the `ignore_default_excludes` flag was
      there so `GIT_CONFIG_KEY_0` reached git; say the variable is gone and the flag is
      kept only until the adapter is next touched. The flag itself is not changed here.
- [ ] `make check-branch` green, `bin/dux-doctor` passing, the plan's boxes ticked and
      the header current.

## Milestone acceptance

The constitution's quality gates. Two of its own: the ship PR body states that the
session that ran the gate was a plain session and why; and it records the count from
the first worker dispatched after merge once the operator has it, as a follow-up
comment on the merged PR, not as a gate.

## Risks

- A git older than 2.20 on the operator's machine: create refuses with the cannot-scope
  finding. `dux-doctor` does not check the version; a line in the PR, not work.
- A project with `core.worktree` set, or a bare-plus-worktrees layout: refused until the
  operator moves the two keys as git's documentation says. No registered project has
  either today.
- The extension flag stays in registered repositories after Dux is uninstalled. Git
  older than 2.20 refuses to open a repository carrying it; none is in play.
- A hand push to `main` from a Dux worktree between create and teardown is now refused
  where before the run it was allowed. Intended.
- The two new refusals fire inside `install_hooks`, after the project's mechanism has
  built the worktree, which for `make worktree` can take minutes. The shared config of a
  clone cannot be read before the clone exists, so this is where the check belongs; a
  retry reaches the reuse path and the same finding, and `discard` clears it.
- `bin/workers/codex.sh` keeps a flag whose reason is gone. Harmless; noted, not fixed.

## Open questions for the operator

None.

## Design review

Reviewed by a fresh session on 2026-09-10. Findings, and what was done with each:

1. Important, accepted in part. The plan claimed every bypass matched an existing deny
   rule. False: `git config --worktree --remove-section core`, or deleting the
   worktree's config file, names neither denied string and lifts the guard, which no
   file edit could do while the environment carried it. The claim is corrected in the
   plan and the spec. The proposed new deny rule, `Bash(git config*--worktree*)`, is
   not added: a worker has to set out to do this, and a worker that sets out to bypass
   the guard is outside the protection claim (spec 2.1), the same class as unsetting
   the environment was before. A note, not a risk.
2. Minor, accepted. The bare-repository refusal test needs a bare clone of the fixture
   origin, not the origin itself, because `create` fetches `origin/<base>` before
   `install_hooks` runs. Task 1 says so.
3. Minor, accepted. `--git-common-dir` prints a relative `.git` from a primary checkout
   or a clone; Task 1 says to resolve it as the hooks source already is, and to read
   `core.bare` with `--bool`.
4. Minor, accepted. The read of the project's hooks source stays on `git_repo`; through
   the worktree, on reuse, it would answer with the task hooks directory and render
   `__UPSTREAM__` as the hook itself. Task 1 says so.
5. Minor, accepted. The refusals fire after the worktree mechanism has run; recorded
   under Risks with why the check cannot move earlier.
6. Minor, accepted. The plain checkout must be pulled to the merged `main` before the
   next spawn; "How this ships" says so.

Confirmed sound by the reviewer, on git 2.52 in a temp repository: the worktree file
outranks the shared one, is visible from a subdirectory and through `git -C`, and goes
with `git worktree remove`; `core.worktree` and `core.bare` shared with the extension on
break the linked worktree, so both refusals are earned; `dux-result`'s own reads pass
`-c core.hooksPath=/dev/null` and are unaffected; teardown, retire and the wrapper's
`no hooks dir` refusal need nothing new; the plain-session route is the smallest honest
one.
