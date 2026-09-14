# Every worker runs in a tab the operator can watch and type to

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, never at the ship
> gate. Do not run a code review of your own work: `/ship` owns the branch's one review
> and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-14 by a Dux plan worker. One independent design review by a fresh
  session the same day: fourteen findings, all taken, recorded at the bottom. Awaiting
  the operator.
- **Supersedes pull request #41**, which is not merged and should be closed, not
  reviewed. The operator's two changes: the live session is the default for every
  worker, and the harness is the tab's own process found by pid, not a child the wrapper
  forks. Nothing is implemented.
- Merges as one ship PR of five tasks.

**Estimated diff:** ~1,400 added lines across 5 tasks. Under the cap of 2,500 lines or 12
tasks (constitution principle 1). Task 3 is the large one, ~400, most of it the wrapper's
test file moving from a forked fake to a fake in a tmux window; Task 4 grew to ~300 with
the trust check, the three-way wait and the guard's pgid read.

**Deviations:** constitution principle 7 says worker output goes to `state/<id>.out` and
every failure leaves a tail in `report.md`. This design removes both. Task 5 amends the
principle and bumps the version in `AGENTS.md`, in the implementation PR, so the
constitution describes the code it ships with.

**Goal:** Every worker's tab shows the ordinary Claude Code screen and the operator can
type into it. Dux proves the task the same way it does today and reads nothing from that
tab. Nobody has to be watching for a task to finish.

**Spec:** `docs/specs/2026-09-14-interactive-worker-sessions.md`, new in this pull
request. Sections 3 and 4 carry the two claims this plan rests on: the proof pipeline is
untouched, and typed text never enters Dux's context. Section 5.2 carries the correction
to #41: liveness and stop need no parent, so the harness is found by pid through the
multiplexer and nothing about supervision is rebuilt; it also carries the trust dialog
and why spawn refuses rather than answers it. Section 6 is the one-worker guard,
section 8 the recommendation.

## Design

Only what the spec does not carry.

- **Order.** The backend verbs land first because the wrapper task cannot be tested
  without `run` and `pid`. The launcher lands second because the wrapper stages it. Spawn
  lands after the wrapper because until then the wrapper is still started by `open`, and
  the end-to-end tests change with spawn. Recovery and the docs close.
- **Between Tasks 3 and 4** the branch is not dispatchable end to end: the wrapper expects
  an endpoint and a shell pane that spawn does not yet give it. Each task's own tests pass;
  the milestone ships as one PR.
- **`dux-backend pid` output** is one line, three words: `<pid> <pgid> <cwd>`. Exit 0 with
  the line, exit 1 with nothing when no foreground process named `<name>` is there yet or
  the tmux pane is dead, exit 2 with a finding when the multiplexer did not answer.
- **The trust check** reads `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` with `jq` and
  walks from the worktree path to `/`, looking for
  `.projects[<path>].hasTrustDialogAccepted == true`. Tests point `HOME` at a fixture.
  Missing file, bad JSON and no match are the one finding in spec section 5.2.
- **Spawn's wait** ends on the first of: the pidfile names a live wrapper; the wrapper's
  pid is gone; `DUX_SPAWN_START_SECS` elapses. The two refusal wordings are in spec
  section 5.1; a handoff directory for the id is what tells them apart.
- **The wrapper's start window.** `pid` is polled once a second for `DUX_WRAP_START_SECS`
  (default 30). The refusal wording: `the harness for <id> did not appear in its pane
  within 30s`. Spawn's own window, `DUX_SPAWN_START_SECS` (default 10), is for the wrapper
  pid, not the harness.
- **Task 4's tests need a trusted `HOME`.** Every spawn test that expects a start points
  `HOME` at a fixture whose `.claude.json` trusts the suite's temporary root; the
  refusal test uses one that trusts nothing.
- **Tests that drive the wrapper directly** open a real tmux window under the suite's
  socket directory, write `state/<id>.endpoint`, and set the fake's variables with
  `tmux set-environment` on that session; the wrapper is then run from the worktree as
  today. Herdr-backend tests use the fake `herdr`, whose `pane run` starts the command
  detached in a group of its own and whose `process-info` reports it.

## Task 1: the backend verbs

**Files:** `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh`,
`tests/fakes/herdr`, `tests/backend-adapter.bats`, `tests/dux-backend-select.bats`,
`tests/contract.bats`.

**Interface:** `open <id> <cwd>` opens the tab as a shell at its prompt and prints the
endpoint; Herdr keeps the prompt wait and the fail-closed close, tmux keeps
`remain-on-exit`. `run <endpoint> <cwd> <cmd>` starts `<cmd>` in the pane: Herdr `pane
run`, tmux `respawn-pane -k -c <cwd>`. `pid <endpoint> <name>` as the Design says: Herdr
from `pane process-info` (`foreground_processes[0].pid`, `.argv0`, `.cwd`,
`foreground_process_group_id`), tmux from `list-panes -F '#{pane_pid}
#{pane_current_command} #{pane_current_path}'` and `ps -o pgid=`, after `#{pane_dead}`
says the pane is alive. `title <endpoint> <text>` titles that pane on Herdr, no-op on
tmux. `report`, `tail`, both `backend_tail` functions and `_own_pane` are removed. The
usage line names the verbs.

**Acceptance:** on real tmux, `open` then `run` with `sh -c 'exec sleep 300'` makes `pid`
print the sleep's pid, its own pid as group, and `<cwd>`; `pid` with the name `nothing`
exits 1 and prints nothing; `kill -TERM -- -<pgid>` from the test ends it and `pid` then
exits 1 with the pane dead. On the fake Herdr the same four hold. `report` and `tail`
are unknown to `dux-backend`, and no file in `bin/` or `skills/` names `pane read` or
`capture-pane`.

**Steps**

- [ ] `bin/backends/tmux.sh`: split `open`; add `backend_run`, `backend_pid`; `title`
      stays a no-op with the endpoint argument.
- [ ] `bin/backends/herdr.sh`: split `open`; add `backend_run`, `backend_pid` reading the
      four fields through `jq`; `backend_title` by endpoint; remove `backend_report`,
      `_own_pane`.
- [ ] `bin/dux-backend`: the verbs, their argument counts, the usage line.
- [ ] `tests/fakes/herdr`: `pane run` starts the command in its own process group and
      records the pid; `pane process-info` answers in the real shape, with `argv0` and
      `cwd` read from `ps` and `lsof` for the recorded pid, never from a constant.
- [ ] `tests/contract.bats`: the pane-reader rule, and the `tail` tests removed from
      `tests/backend-adapter.bats`.
- [ ] `tests/backend-adapter.bats`: the acceptance cases for both adapters.
- [ ] Break-verify: make `backend_pid` skip the name comparison. Expected: the `nothing`
      case fails on both adapters, a pid is printed. Restore. Paste both.
- [ ] Break-verify: add a `capture-pane` call to a skill file. Expected: the contract
      test fails naming the file. Restore. Paste.
- [ ] `make check` green.

## Task 2: the launcher, the beat hooks, the brief line

**Files:** `bin/workers/claude.sh`, `templates/worker-settings.json`, `templates/brief.md`,
`tests/worker-adapter.bats`, `tests/dux-brief.bats`, `tests/fakes/claude`.

**Interface:** `worker_launcher <path> <brief> <model> <effort> <settings> <dux_bin>
[<ship_record>]` writes the launcher spec section 5.2 gives, mode 500, refusing a quote in
any argument with the ship recorder's wording; `worker_cmd` prints its `exec` line;
`worker_run` is gone; `worker_process_name` prints `claude`. The settings template gains
`PostToolUse` and `Stop` hooks running `touch '__CHANNEL__/beat'`, the path quoted;
`dux-brief` renders `__BASE__` as today and leaves `__CHANNEL__` literal. Brief line 19 becomes the sentence in spec section 5.6. The fake
harness gains `touch <file>`.

**Acceptance:** a launcher run with a fake `claude` that dumps its environment, from a
shell that exports `DUX_HOME`, `HERDR_PANE_ID`, `TMUX` and `GIT_CONFIG_COUNT`, shows none
of them, shows the three outbox variables, and shows a `PATH` without `<dux_bin>`;
`worker_cmd` prints no `-p`, no `--output-format`, and the shared flags. The rendered task
settings hold the two hooks with `__CHANNEL__` literal. A rendered brief holds "may be
watching your terminal" and not "nobody reads your terminal", under 100 lines.

**Steps**

- [ ] Measure once against a real `claude`, interactive, in a tmux pane: a session
      started with `--settings` holding the two hooks touches the beat file after one
      tool call and again at `Stop`. Record the result in the commit body. If it does
      not, stop and report; do not pick a fallback.
- [ ] `bin/workers/claude.sh`: `worker_launcher`; `worker_cmd`; `worker_process_name`;
      drop `worker_run`.
- [ ] `templates/worker-settings.json`: the hooks. `templates/brief.md`: line 19.
- [ ] `tests/fakes/claude`: `touch`.
- [ ] `tests/worker-adapter.bats`: the launcher cases. `tests/dux-brief.bats`: the hooks
      and the brief line.
- [ ] Break-verify: drop the scrub loop from the launcher. Expected: the environment case
      fails, `DUX_HOME` is present. Restore. Paste.
- [ ] Break-verify: drop the `PATH` strip. Expected: the `PATH` case fails. Restore. Paste.
- [ ] `make check` green.

## Task 3: the wrapper supervises a process it did not fork

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`, `tests/fakes/claude`.

**Interface:** the wrapper reads `state/<id>.endpoint`, stages the launcher and the
settings with the channel path substituted, calls `dux-backend run`, polls `dux-backend
pid` for the window in the Design, writes the group to `state/<id>.pgid`, and loops on
`pid_runs "$hpid" "$(worker_process_name)"`. No fork, no `set -m`, no own-group
refusal, no `state/<id>.out`, no `wait`, no mirror; `title` by endpoint. The loop exits on a held terminal line and the
wrapper stops the group before judging. The heartbeat condition is the beat file's mtime.
A harness gone with no terminal line is `ended: the session ended without a terminal
status`; the failure tail is the fixed line from spec section 7.

**Acceptance:** the existing happy path, proof, violation and survivor cases pass with the
fake in a tmux window. A fake whose script is `status done: report` then `sleep 600` is
stopped within `2 * DUX_WRAP_POLL_SECS` and the handoff is `done: report`. A fake that
`exit 0`s with no line yields the `ended` handoff with the new wording, and so does one
that `exit 1`s. A fake that touches the beat file and writes nothing produces `working:
heartbeat` within `DUX_HEARTBEAT_SECS`; one that does neither produces none. A `stubborn`
child still yields the survivor finding. `state/<id>.out` is never created. A pane whose
foreground process is `sh -c 'sleep 60'` and never `claude` yields the "did not appear"
refusal with `DUX_WRAP_START_SECS=2`.

**Steps**

- [ ] Re-measure on Linux first (`ubuntu:24.04`, `bats git tmux jq`): `pane_pid`,
      `set-environment` reaching a respawned pane, a group stop from outside. Record the
      result in the commit body. If any differs, stop and report; do not pick a fallback.
- [ ] `bin/dux-worker-wrap`: the launch section (`:353-378`) and the loop (`:380-406`)
      rewritten as the interface says; the settings substitution; the judgement wording.
- [ ] `tests/dux-worker-wrap.bats`: `prepare` opens the window and writes the endpoint;
      the fake's variables through `set-environment`; the cases above.
- [ ] Break-verify the end: remove the exit-on-terminal condition. Expected: the `sleep
      600` case exceeds its bound. Restore. Paste.
- [ ] Break-verify the beat: read the wrong mtime. Expected: the touch case fails, no
      heartbeat. Restore. Paste.
- [ ] Break-verify the discovery: accept any foreground process. Expected: the `sh -c`
      case fails, no refusal. Restore. Paste.
- [ ] `make check` green.

## Task 4: spawn starts the wrapper outside the tab

**Files:** `bin/dux-spawn`, `tests/dux-spawn.bats`, `tests/e2e-dispatch.bats`,
`tests/e2e-supervise.bats`, `skills/dux-dispatch/SKILL.md`.

**Interface:** before `open`, the trust check in the Design; its finding is the one in
spec section 5.2 and leaves the task `queued`. Then spawn calls `open <id> <wt>`, records
the endpoint as today, starts `dux-worker-wrap <id>` as spec section 5.1 says (the
`dux-lock:43` shape with `$!` printed, from the worktree, output to
`state/<id>.wrap.log`), and runs the three-way wait in the Design. Pidfile live: `set-if`
running. Wrapper gone or window over (after `TERM` and a wait for it): with a handoff
directory, touch nothing and print `the wrapper for <id> refused before the harness
started; see state/<id>.wrap.log`; without one, `undo` as today plus closing the pane
it opened and clearing the endpoint file and ledger field, then `the wrapper for <id>
did not start; see state/<id>.wrap.log`. `another_worker` reads `state/<other>.pgid`
between the pidfile and the ledger, as spec section 6 says. The dispatch skill names the
tab and says never to read it.

**Acceptance:** `dux-spawn` on a fixture task leaves a live wrapper pid whose parent is
not the spawn process, a tab, and `running`; the end-to-end scout run reaches `done:
report` with no `state/<id>.out`. A fake wrapper that exits at once with no handoff:
the "did not start" finding, `queued`, no endpoint, no container. The real wrapper with
the task's settings file removed: the "refused" finding, the watcher then applies
`failed`, the worktree and endpoint are kept. A `HOME` whose `.claude.json` trusts
nothing: the trust finding, `queued`, no tab opened. Another task whose `.pgid` names
the test's own live process group: refusal `live <other>`; a `.pgid` holding `x`:
refusal `pidfile <other>`.

**Steps**

- [ ] `bin/dux-spawn`: the trust check; the open; the start with its pid; the wait; the
      two endings; the pgid read in `another_worker`.
- [ ] `tests/dux-spawn.bats`: the six cases. `tests/e2e-dispatch.bats`,
      `tests/e2e-supervise.bats`: `.out` assertions replaced by the handoff; `HOME`
      trusting the suite root.
- [ ] Break-verify: make the wait accept a pidfile naming a dead pid. Expected: the
      fake-wrapper case fails, the task is `running`. Restore. Paste.
- [ ] Break-verify: make the wait undo whether or not a handoff exists. Expected: the
      real-wrapper case fails, the worktree is gone. Restore. Paste.
- [ ] Break-verify: make the trust check return 0 on a missing key. Expected: the
      untrusted case fails, a tab opens. Restore. Paste.
- [ ] Break-verify: skip the pgid read in `another_worker`. Expected: the `live <other>`
      case fails, spawn proceeds. Restore. Paste.
- [ ] `skills/dux-dispatch/SKILL.md`: the tab, and the tab in the "never read" rule.
- [ ] `make check` green.

## Task 5: recovery, teardown, the constitution, the component map

**Files:** `bin/dux-recover`, `bin/dux-teardown`, `tests/dux-recover.bats`,
`tests/dux-teardown.bats`, `skills/dux-recover/SKILL.md`, `skills/dux-status/SKILL.md`,
`docs/ARCHITECTURE.md`, `docs/constitution.md`, `AGENTS.md`.

**Interface:** `print_tail` and `failure_tail_to_report` print `no output captured: the
worker ran in its own tab` and no fence; `out=` is gone. `dead()` says to end the session
in the task's tab when the group still answers. `dux-teardown` removes
`state/<id>.wrap.log` with the run's other references. The two skills' "never read
`state/<id>.out`" rule becomes "never read the worker's tab". `ARCHITECTURE.md`: the
adapter line, dispatch steps 5 and 6, the process-group paragraph, the pane line,
`state/<id>.wrap.log`, the launcher, the beat and the trust check. Constitution
principle 7: the `state/<id>.out` and failure-tail sentence replaced by "the worker's
output stays in its own tab; status goes to `status.log`; events go to
`state/events.log`", with a version-history entry and the version bumped in `AGENTS.md`.

**Acceptance:** `dux-recover` on a stale task prints the fixed line and no
`<untrusted-output>` fence; a stopped task's `report.md` holds the fixed line under
`## Failure tail`; teardown of a finished task leaves no `state/<id>.wrap.log`; the
constitution names no `.out` file and `AGENTS.md` names the new version.

**Steps**

- [ ] `bin/dux-recover`: the two tails; the `dead()` wording.
- [ ] `tests/dux-recover.bats`: the fixtures that wrote `.out` removed; the two cases.
- [ ] Break-verify: make `print_tail` read `state/<id>.out` again with a fixture present.
      Expected: the stale case fails, a fence appears. Restore. Paste.
- [ ] `bin/dux-teardown`: the log in the removal list. `tests/dux-teardown.bats`: the
      case.
- [ ] Break-verify: drop the log from the removal list. Expected: the teardown case
      fails, the file remains. Restore. Paste.
- [ ] The two skills, `docs/ARCHITECTURE.md`, `docs/constitution.md` and `AGENTS.md` as
      the interface says.
- [ ] `make check` green, `bin/dux-doctor` passing, then `/ship`.

## Milestone acceptance

- Every task's acceptance holds and every break was seen to fail, with the failures in
  the commit bodies.
- A real `scout` run in a Herdr tab, driven by hand: the tab shows the Claude Code
  screen with no trust dialog, Herdr lists the agent, a typed line is acted on, the beat
  file's mtime moves during the run, the terminal line ends the session, the handoff is
  proved, and `data/backlog.md` says `done`. The same on tmux.
  Then `dux-recover --stop` on a second stale run stops it, and closing the tab of a
  third run yields `ended` within one poll and frees the one-worker guard.
- The constitution's gates: shellcheck and bash 3.2 clean, identifier lint clean,
  `ARCHITECTURE.md` in the same PR, `/ship` the only gate.

## Risks

- Herdr's `process-info` fields were measured once, on the orchestrator's own pane. Task
  1's fake copies that shape; a Herdr release that renames a field makes `pid` a finding,
  never a wrong pid.
- The harness appears in a Herdr pane only after the shell runs the typed command; a slow
  shell start eats into the 30 s window. The window is a knob.
- A Claude Code release that ignores `SIGTERM` at the prompt leaves the stop to `SIGKILL`;
  `stop_group` catches survivors as today.
- The detached wrapper inherits the orchestrator's environment. Nothing in it addresses
  a pane as its own after Task 1; a new backend call that does would title or report on
  the orchestrator's pane. The contract test does not catch this; review does.
- A pid recycled onto another `claude` between two polls reads as alive one poll longer.
  Harmless and improbable; not guarded.
- Milestone 7 touches `bin/workers/claude.sh` and `bin/dux-worker-wrap`; whichever
  merges second rebases.
- tmux and `set-environment` were measured on macOS; Task 3 measures Linux first.
- Trust inheritance from a parent path was measured once, on Claude Code 2.1.270. A
  release that stops inheriting shows the dialog in the tab and the run goes stale at 20
  minutes; the check reads as trusted, so nothing refuses. The tab shows why.
- A project whose `CLAUDE.md` imports a file outside the worktree raises a second
  dialog, "Allow external CLAUDE.md file imports?", measured 2026-09-14 from a
  subdirectory. A worktree root imports its own files, so registered projects are not
  expected to hit it. Not guarded; same symptom as above.
- `worker_process_name` prints `claude` for the native binary. An npm install shows
  `node` to both multiplexers and to `ps`, so discovery would never answer and the run
  would refuse at 30 s. The operator's install is native; a second name is one function
  away when needed.

## Open questions for the operator

None. Spec section 10 records three with recommendations; the plan takes them.

## Design review

One independent review on 2026-09-14 by a fresh session (Claude Code in print mode,
model `claude-fable-5-1`, read-only tools) that had not seen the design, against the spec,
the plan, the constitution and the scripts they cite. Fourteen findings; every code
citation was checked against the file, and the trust dialog was measured in a tmux pane
before it was acted on. All fourteen were taken.

| # | Finding | Outcome |
|---|---|---|
| 1 | Critical: an interactive `claude` in a fresh worktree shows the workspace trust dialog with the cursor on "No, exit"; discovery would pass, no beat would move, and every unattended run would stall until the stale wake. | Accepted, measured: a fresh directory shows it, a directory under a trusted path does not. Spawn refuses an untrusted repository, reading the operator's trust record and never writing it (spec 5.2, Task 4). Answering the dialog and writing the entry were both rejected. |
| 2 | Important: when the wrapper dies and the harness lives, `dead()` marks the task `failed` and leaves the pgid file, and `another_worker` never reads it, so a second worker could start. | Accepted. `another_worker` reads `state/<other>.pgid` (spec 6, Task 4). |
| 3 | Important: spawn's wait collided with a fast wrapper refusal: the watcher applies the `failed` handoff while spawn times out and discards the worktree; the `dux-lock` shape also loses `$!`. | Accepted. Spawn keeps the pid and ends the wait on the wrapper's exit; a handoff means touch nothing, none means undo (spec 5.1, Task 4). |
| 4 | Important: constitution principle 7 says output goes to `state/<id>.out`; the plan had no Deviations line. | Accepted. Deviations line added; Task 5 amends the principle and bumps the version. |
| 5 | Important: the spec said the orchestrator design's sections point here, and none did; its decision "workers headless" is reversed. | Accepted. Pointers added to sections 5.4, 5.5, 6, 9, 17 and 19 in this PR. |
| 6 | Important: nothing verifies Claude Code runs `PostToolUse` and `Stop` hooks from `--settings` in an interactive session. | Accepted. Task 2 measures it first; milestone acceptance checks the beat moved. |
| 7 | Minor: `state/<id>.wrap.log` was never removed. | Accepted. Teardown removes it (Task 5). |
| 8 | Minor: the hook's path was unquoted. | Accepted. Quoted like the ship recorder's. |
| 9 | Minor: three wrong citations (`pid_runs` range, the watcher's interval line, an unnamed `:81`). | Accepted, fixed. |
| 10 | Minor: a fake `process-info` printing a constant `argv0` would let the Herdr test assert the fixture. | Accepted. The fake reads `ps` for the recorded pid. |
| 11 | Minor: a dead tmux pane keeps a stale `pane_pid`. | Accepted. `pid` reads `#{pane_dead}` first. |
| 12 | Minor: a crash becomes `ended`, which is never pushed. | Accepted, recorded in spec section 7. |
| 13 | Minor: the name `claude` was hardcoded; an npm install shows `node`. | Accepted. `worker_process_name`, and a Risks line. |
| 14 | Minor: guarding `dux-backend tail` with a test is more than deleting it. | Accepted. The verb is removed; the contract test guards `pane read` and `capture-pane`. |

Claims the reviewer confirmed against the code: the proof pipeline never reads worker
output; no pane reader exists outside the backend layer; `pid_runs` and the group stop
need no parent; the headless path is gone with no flag. The one-worker guard needed the
change in finding 2.
