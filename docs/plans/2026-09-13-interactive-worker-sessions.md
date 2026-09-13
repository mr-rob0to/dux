# A worker the operator can watch and type to

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the work, not the conversation. Break-verify at the task boundary, never at the ship
> gate. Do not run a code review of your own work: `/ship` owns the branch's one review
> and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-13 by a Dux plan worker. One independent design review by a fresh
  session the same day sent the launch shape back; the re-measured shape is in spec
  section 5.2 and the review's findings are at the bottom. Awaiting the operator.
- Picks up the operator's ask to watch a worker live and type to it. Nothing is
  implemented; the default stays headless.
- Merges as one ship PR of six tasks, after pull request #40.

**Estimated diff:** ~700 added lines across 6 tasks. Under the cap of 2,500 lines or 12
tasks (constitution principle 1). Task 1 is ~110 lines of test helper on its own.

**Goal:** When the operator says "watch this one", the worker's tab shows the ordinary
Claude Code screen and the operator can type into it. Dux proves the task the same way
it does today, reads nothing from that tab, and every other task keeps running headless.

**Spec:** `docs/specs/2026-09-13-interactive-worker-sessions.md`, new in this pull
request. Sections 3 and 4 carry the two claims this plan rests on: the proof pipeline
is untouched, and typed text never enters Dux's context. Section 5 carries the
mechanics, section 6 the one-worker guard, section 8 the recommendation.

## What the spec does not carry

- **Order.** The terminal test helper lands first because Tasks 3 and 4 cannot be
  break-verified without it. The mode flag lands second because the wrapper tasks read
  `tasks/<id>/mode` and need a way to write it in tests.
- **After #40.** The tasks assume pull request #40 is merged: `worker_run_interactive`
  reuses its `claude_flags` array, and `dux-brief` already has a second per-task file
  (`risk`) next to which `mode` goes.
- **The descendant snapshot** is a variable in the wrapper, refreshed on each pass of
  the existing poll loop, holding every pid whose parent chain reaches the harness
  pid. The stop signals the harness pid and the snapshot; the survivor check asks
  `kill -0` of each. Nothing is written to disk for it.
- **The stop after a terminal line** reuses the violation path
  (`bin/dux-worker-wrap:380-383`): in interactive mode the loop's condition also ends
  on a held terminal line, and the stop before `wait` is the tree stop.

## Task 1: the terminal test helper

**Files:** `tests/helpers/setup.bash`, `tests/pty.bats` (new), `docs/ARCHITECTURE.md`
(the `tests/` line).

**Interface:** `require_pty`, `run_in_pty <answer> <command...>`, `pty_feed <answer>`,
exactly as `docs/specs/2026-09-11-terminal-prompt-tests.md` section 2 decides and as
`docs/plans/2026-09-11-salvage-pty-feed.md` Task 1 spells out. No product script
changes.

**Acceptance:** `tests/pty.bats` passes on macOS and in Docker with the three tests
that plan names; the three breaks it names are seen to fail; `make check` green.

**Steps**

- [ ] Land the three functions and `tests/pty.bats` per the salvage plan's Task 1,
      steps one and two, unchanged.
- [ ] Break-verify the hold, the close and the status as that task's three break steps
      say. Paste each failure into the commit body as bats printed it.
- [ ] `docs/ARCHITECTURE.md`: add `pty.bats` to the `tests/` line.
- [ ] `make check` green.

## Task 2: the mode flag

**Files:** `bin/dux-brief`, `templates/brief.md`, `bin/dux-spawn`, `tests/dux-brief.bats`,
`tests/dux-spawn.bats`, `skills/dux-dispatch/SKILL.md`.

**Interface:** `dux-brief <id> ... --interactive` writes `tasks/<id>/mode` holding
`interactive` and renders the brief with the two lines spec section 5.5 gives. Without
the flag, no file and today's lines. `dux-spawn` refuses with a finding when `mode` is
`interactive` and the harness is not `claude`. The dispatch skill names the flag and the
tab, and tells Dux never to read the worker's tab.

**Acceptance:** `dux-brief <id> --interactive` leaves `mode` and a brief holding "may be
watching your terminal" and "waiting on the operator", under 100 lines; without the
flag, no `mode` file and "nobody reads your terminal". `dux-spawn` on a task briefed
with `--interactive` and spawned with `--harness codex` prints `finding: interactive
mode runs Claude workers only` and exits 2.

**Steps**

- [ ] `bin/dux-brief`: parse `--interactive`; write `tasks/<id>/mode`; render the two
      lines by mode. `templates/brief.md`: the two lines become placeholders.
- [ ] `bin/dux-spawn`: read `tasks/<id>/mode`; refuse a non-Claude harness.
- [ ] `tests/dux-brief.bats`: both renderings and the line cap. `tests/dux-spawn.bats`:
      the refusal, with `mode` created through `dux-brief --interactive`, never by
      writing the file, so the break below reaches it.
- [ ] Break-verify: drop the `mode` write. Expected: the `mode` test fails and the spawn
      refusal test fails, both because the file is absent. Restore. Paste both.
- [ ] `skills/dux-dispatch/SKILL.md`: one line for the flag, one for the tab label, and
      the tab added to the "never read" rule.
- [ ] `make check` green.

## Task 3: the harness gets the terminal

**Files:** `bin/workers/claude.sh`, `bin/dux-worker-wrap`, `tests/fakes/claude`,
`tests/worker-adapter.bats`, `tests/dux-worker-wrap.bats`.

**Interface:** `worker_cmd_interactive` and `worker_run_interactive`, four arguments,
the command spec section 5.2 gives with the shared flags. In interactive mode the
wrapper writes `mode=interactive` into the run record and result context, starts the
harness as a same-group background child with the terminal on stdin, skips the
own-group refusal and the mirror, keeps a descendant snapshot, and stops by tree from
both the stop path and the trap. The fake harness gains `ask <file>`: read one line
from stdin and write it to the file.

**Acceptance:** under `run_in_pty`, a wrapper run of an interactive scout whose fake
script is `ask <f>`, `report ok`, `status done: report` ends with a `done: report`
handoff and `<f>` holding the typed line. A headless run of the same task is unchanged.
A fake that starts a `stubborn` child and then sleeps sees the wrapper's survivor
finding after `dux-recover --stop`. `worker_cmd_interactive` prints no `-p` and no
`--output-format`.

**Steps**

- [ ] Re-run the same-group shape from spec section 5.2 in Docker (`ubuntu:24.04`,
      `bats git expect`). Record the result in the commit body. If it fails there,
      stop and report; do not pick a fallback.
- [ ] `bin/workers/claude.sh`: the two functions. `tests/worker-adapter.bats`: the
      printed command has no `-p` and no `--output-format`, and has the shared flags.
- [ ] `bin/dux-worker-wrap`: read `mode`; the two record lines; the launch; skip the
      own-group refusal; the snapshot in the loop; `stop_tree`; the trap variant; no
      mirror. Headless path untouched.
- [ ] `tests/fakes/claude`: `ask`. `tests/dux-worker-wrap.bats`: the acceptance cases,
      each starting with `require_pty`.
- [ ] Break-verify the terminal: launch with stdin from `/dev/null` in interactive
      mode. Expected: the `ask` case fails, `<f>` is empty. Restore. Paste.
- [ ] Break-verify the stop: make the survivor check skip the snapshot and ask only
      the harness pid. Expected: the `stubborn` case fails, no survivor finding.
      Restore. Paste.
- [ ] `make check` green.

## Task 4: the run ends on the terminal line

**Files:** `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats`.

**Interface:** in interactive mode the poll loop ends when it holds a terminal line;
the wrapper stops the tree before `wait` and judges as today. A harness that exits on
its own with no terminal line is `ended: exit 0 without terminal status`, as today.

**Acceptance:** an interactive fake whose script is `status done: report` then `sleep
600` is stopped within `2 * DUX_WRAP_POLL_SECS`, and the handoff is `done: report`. A
fake whose script is `exit 0` yields the `ended` handoff. A fake that writes
`needs-decision: x` then sleeps is stopped and the handoff is that line.

**Steps**

- [ ] `bin/dux-worker-wrap`: the loop's exit condition; the tree stop before `wait`.
- [ ] `tests/dux-worker-wrap.bats`: the three cases, with `DUX_WRAP_POLL_SECS=1` and a
      wall-clock bound.
- [ ] Break-verify: remove the exit-on-terminal condition. Expected: the first and
      third cases exceed the bound and fail. Restore. Paste.
- [ ] `make check` green.

## Task 5: the heartbeat from hooks

**Files:** `templates/worker-settings.json`, `bin/dux-worker-wrap`, `tests/fakes/claude`,
`tests/dux-worker-wrap.bats`, `tests/dux-brief.bats`.

**Interface:** the settings template carries `PostToolUse` and `Stop` hooks running
`touch __CHANNEL__/beat`; the wrapper substitutes the channel path when it stages the
settings, refusing a path with a quote as it does for the ship recorder. The heartbeat
condition is "beat mtime moved or `.out` grew", one test for both modes.

**Acceptance:** the staged settings in the channel name the channel, never
`__CHANNEL__`. A headless fake that touches the beat file and writes nothing to stdout
produces `working: heartbeat` within `DUX_HEARTBEAT_SECS`; one that does neither
produces none. The existing heartbeat test at `tests/dux-worker-wrap.bats:104` still
passes.

**Steps**

- [ ] `templates/worker-settings.json`: the two hooks. `tests/dux-brief.bats`: the
      rendered task settings still hold the literal placeholder.
- [ ] `bin/dux-worker-wrap`: substitute on staging; the two-source condition.
- [ ] `tests/fakes/claude`: `touch <file>`. `tests/dux-worker-wrap.bats`: the two cases
      with `DUX_HEARTBEAT_SECS=2`.
- [ ] Break-verify: drop the mtime half of the condition. Expected: the touch case
      fails, no heartbeat. Restore. Paste.
- [ ] `make check` green.

## Task 6: recovery, the contract test, the component map

**Files:** `bin/dux-recover`, `tests/dux-recover.bats`, `tests/contract.bats`,
`skills/dux-recover/SKILL.md`, `docs/ARCHITECTURE.md`.

**Interface:** `dux-recover`'s output tail and failure tail print `no output captured:
interactive run` when the run record holds `mode=interactive`; its retry passes
`--interactive` to `dux-brief` when `tasks/<id>/mode` says so. `tests/contract.bats`
asserts that no file in `bin/` outside `dux-backend` and `backends/`, and no file in
`skills/`, names `dux-backend tail`, `backend_tail`, `pane read` or `capture-pane`. The
recover skill's "never read `state/<id>.out`" rule names the worker's tab too.
`ARCHITECTURE.md` gains `tasks/<id>/mode`, the beat file, the hooks, the two adapter
functions on its `workers/claude.sh` line, and a rewritten launch step (its step 6 in
the dispatch flow, which today says "process group of its own" and "output to
`state/<id>.out`").

**Acceptance:** `dux-recover` on a stale interactive task prints the line and no
`<untrusted-output>` fence; on a headless task it prints the tail as today. A retried
interactive task has a `mode` file. The contract test passes on the branch.

**Steps**

- [ ] `bin/dux-recover`: read `mode=` from the run record; the two tail branches; the
      retry flag.
- [ ] `tests/dux-recover.bats`: the three cases.
- [ ] Break-verify: make the tail read `mode` from the wrong file. Expected: the
      interactive case fails, a fence appears. Restore. Paste.
- [ ] `tests/contract.bats`: the pane-reader rule.
- [ ] Break-verify: add a `dux-backend tail` call to a skill file. Expected: the
      contract test fails naming the file. Restore. Paste.
- [ ] `skills/dux-recover/SKILL.md` and `docs/ARCHITECTURE.md` as the interface says.
- [ ] `make check` green, `bin/dux-doctor` passing, then `/ship`.

## Milestone acceptance

- Every task's acceptance holds and every break was seen to fail, with the failures in
  the commit bodies.
- A real interactive `scout` run in a Herdr tab, driven by hand: the tab shows the
  Claude Code screen, a typed line is acted on, the terminal line ends the session, the
  handoff is proved, and `data/backlog.md` says `done`. The same on the tmux backend.
  Then `dux-recover --stop` on a second interactive run stops it.
- A headless run of each shape is unchanged: same handoffs, same `state/<id>.out`.
- The constitution's gates: shellcheck and bash 3.2 clean, identifier lint clean,
  `ARCHITECTURE.md` in the same PR, `/ship` the only gate.

## Risks

- The same-group shape was measured on macOS only. Task 3 measures Linux first and
  stops on a different answer.
- The tree stop misses a process the harness orphans between two polls. Spec section
  5.2 says so; it is a narrower claim than today's, accepted for this mode only.
- A Claude Code release that ignores `SIGTERM` at the prompt leaves the stop to
  `SIGKILL`; the snapshot check catches survivors and the operator sees the finding.
- Two agent-state sources for one Herdr pane. The wrapper stops mirroring in this
  mode; if Herdr still shows a stale `dux` state, `herdr agent explain` says why.
- Pull request #40 and the milestone 7 plan touch the same two files. This plan
  assumes #40 is in; whichever of this and M7 merges second rebases.
- An operator who walks away from an interactive session holds the one-worker guard
  until the stale wake. Accepted; it is the mode's premise.

## Open questions for the operator

None. Spec section 10 records three with recommendations; the plan takes them.

## Design review

One review, 2026-09-13, by a fresh session that did not write the design. Every
`file:line` cite in the spec was checked; the reviewer also re-measured the launch
shapes under bash 3.2. Findings and what was done, as plain bullets, not boxes:

- Critical, the background poll loop could not hand its state back, and a final
  re-read from zero would double-log and refuse every `done`. Taken: the loop stays
  in the wrapper; the harness becomes a same-group background child with the
  terminal on stdin, which the reviewer measured and the planner re-measured
  (spec 5.2).
- Critical, teardown sends no signal, `dux-recover --stop` sends INT, and the design
  ignored INT while sharing a group whose TERM would hit the wrapper. Taken: the trap
  and the stop both work by process tree in this mode (spec 5.2, 7).
- Important, the shape that removes the problem was missing from the table. Taken.
- Important, a tree walk from the harness pid misses orphans re-parented to pid 1.
  Taken: a descendant snapshot kept while the harness runs, and the weaker claim
  stated (spec 5.2).
- Important, the wrapper blocked in the foreground could not act on the loop's
  terminal line. Moot with the same-group shape.
- Important, the one-worker guard is on disk in pull request #40 and counts panes for
  `running` and `stale` tasks, so "never panes" was wrong. Taken: section 6 rewritten
  against the real guard.
- Important, "enforced, not asserted" was a grep at one point in time. Taken: a
  contract test forbids pane readers outside the backend layer (Task 6).
- Minor, `DUX_SHIP_RECORD` is a third exported variable; the tab shows log lines, not
  one line; the section 9 table contradicted itself on `dux-recover`;
  `ARCHITECTURE.md:62` and `:208-213` go stale; a retry rendered the brief headless;
  the estimate was low; `worker_cmd_interactive` was needed for the adapter test and
  the codex function was dead; the spawn break only fires through `dux-brief`; a
  quote in the channel path breaks the settings JSON. All taken.
- Disputed: none.

Verdict as given: redesign the launch shape, approve the rest with the fixes. The
launch shape was redesigned and re-measured; the operator's approval is the gate.
