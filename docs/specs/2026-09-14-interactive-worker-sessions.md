# Dux: every worker runs in a tab the operator can watch and type to

Design authority for running a Dux worker as a live Claude Code session in its own
Herdr tab or tmux window, where the operator can read what it does and type to it. The
orchestrator design (`2026-09-03-dux-orchestrator-design.md`) stays the authority for
everything this document does not change; its sections 5.4, 5.5, 6, 9, 17 and 19 point
here.

Plan: `docs/plans/2026-09-14-interactive-worker-sessions.md`.

**This document supersedes pull request #41** (`2026-09-13-interactive-worker-sessions`)
and should be reviewed in its place. #41 is not merged and the operator will close it.
Two things changed on the operator's word: the live session is the default for every
worker, not an opt-in flag; and the harness runs as the tab's own process, found by pid
through the multiplexer, rather than as a child the wrapper forks with the terminal on
its stdin. Everything else #41 established stands and is restated here so that this
document reads on its own.

Drafted 2026-09-14 by a Dux plan worker. One independent design review by a fresh
session the same day; its findings are recorded at the end of the plan.

## 1. What the operator gets

Today a worker's tab shows the wrapper's few log lines: the command that started it, a
title, and one line when it ends. Everything the worker itself prints goes to a log file
the operator is told never to open. After this change the worker's tab shows the ordinary
Claude Code screen: the worker's thinking, its tool calls, its questions. The operator can
type into that tab and the worker reads it as instruction from the person whose authority
it already runs with. Herdr sees a real Claude session in the pane and shows its own
agent state for it.

**This is the default for every worker, of every shape, on both backends.** There is no
flag to turn it on and none to turn it off. A task nobody is watching runs exactly the
same way: it ends when the worker writes its terminal line (section 5.3), so an attended
operator is not a premise of the mode. Section 8 says why the headless run is not kept.

What the operator does not get: a change in how Dux decides a task is done. The worker is
proved the same way it is today, from the repository, GitHub, the `/ship` receipt and
Dux's own run record. Nothing typed into the tab, and nothing the worker prints there, is
evidence.

## 2. What runs today

`bin/dux-spawn:157-158` composes `dux-worker-wrap <id>` as shell words and hands it to
`dux-backend open`. The Herdr adapter creates a tab, waits for a shell prompt, and types
the command into it (`bin/backends/herdr.sh:8-34`); the tmux adapter opens a window with
`remain-on-exit` and runs the command in its pane (`bin/backends/tmux.sh:41-53`). So the
wrapper is the tab's process, and the wrapper hides the worker from it:

- `bin/workers/claude.sh:33-36` runs `claude -p "<brief>" ... --output-format stream-json
  --verbose`. `-p` is print mode: one turn, then exit.
- `bin/dux-worker-wrap:362-364` starts it as a background job in a process group of its
  own (`set -m`), stdin from `/dev/null`, stdout and stderr to `state/<id>.out`.
- `bin/dux-worker-wrap:239-249` scrubs the worker's environment (every `DUX_*`,
  `CLAUDE*`, `HERDR_*`, `TMUX*` and `GIT_CONFIG_*` variable) and hands back
  `DUX_STATUS_LOG`, `DUX_REPORT` and, for a ship task, `DUX_SHIP_RECORD`, all inside a
  task channel the wrapper made for this run.
- The wrapper then loops on `kill -0 $wpid` (`:381`), reading proposals every 5 s,
  heartbeating when `state/<id>.out` grows (`:389-395`), and after `wait` (`:400`) stops
  the group (`:404-406`) and judges the terminal line (`:460-469`).

### 2.1 What the stream-json output is used for

`state/<id>.out` is read in four places, and none of them is proof:

| Reader | What it takes from the file |
|---|---|
| `bin/dux-worker-wrap:390-393` | its byte count only: if it grew, append `working: heartbeat` |
| `bin/dux-worker-wrap:470-472` | its last 20 lines under `## Failure tail` when the run failed |
| `bin/dux-recover:79-93` | a capped, cleaned tail, fenced as untrusted data, during recovery |
| tests | `tests/dux-worker-wrap.bats:40`, `tests/e2e-dispatch.bats:80` assert an assistant event; `tests/dux-recover.bats` writes fixtures into it; `tests/worker-adapter.bats` asserts the flag |

No script runs `jq` on it, and `bin/dux-result` never opens it: `grep -n '\.out'
bin/dux-result` finds nothing. Three skills forbid Dux from reading it
(`skills/dux-status/SKILL.md:23`, `skills/dux-dispatch/SKILL.md:88`,
`skills/dux-recover/SKILL.md:38`). The file goes away with this design, and what breaks
is the heartbeat (section 5.5), the failure tail (section 7) and those tests.

## 3. How a task is proved, and why the live session leaves it alone

The worker's only sanctioned channel to Dux is the status outbox, `$DUX_STATUS_LOG`
(`bin/dux-worker-wrap:247`). The wrapper polls it (`import_proposals`, `:277-351`):
`working:` lines go to `status.log`, one terminal line (`done`, `failed`, `blocked`,
`needs-decision`) is held back, and anything else, or anything after the terminal line,
fails the run.

When the run is over and the whole process group is gone (`:404-406`), the terminal line
is judged (`:460-469`). A `done` proposal is a request: `prove_done` (`:436-458`) runs
`bin/dux-result verify <id> <run>`, which reads Dux's own run record and result context
(`load_run`, `bin/dux-result:30`), the worktree and its changed-file set (`read_changes`,
`:148`), GitHub for exactly one open, non-draft PR at the branch tip with green checks
(`find_pr` `:68`, `require_green_checks` `:109`), the plan's task boxes for a `ship`
(`check_plan_tasks` `:206`), the `/ship` receipt (`check_receipt` `:306`), and for a
`scout` the report outbox. Not one of these inputs is the worker's stdin or stdout. Exit 1
becomes `ended: the result was not proved` (`:452-455`); Dux never guesses done.

**Verdict:** the live session preserves this proof unchanged. The outbox, the run record,
the repository and GitHub are exactly where they were. Two inputs change shape and
section 5 handles both: the harness's exit is no longer something the wrapper can `wait`
for (5.2), and an interactive session does not exit on its own when its turn ends (5.3).

## 4. What "interactive" means, and where the boundary sits

The tab's terminal is the worker's stdin and stdout. The operator types into the tab. The
text goes to the `claude` process and nowhere else.

**Typed text never enters Dux's context.** Dux, the orchestrator session, reads worker
material through exactly two doors: `status.log`, fed only by `import_proposals` with its
grammar and 200-byte cap, and the capped, cleaned, fenced text `bin/dux-recover` prints.
Neither reads a terminal. Today the worker's output is at least on disk under `state/`,
where a careless script could reach it; after this change it is not written under
`DUX_HOME` at all. The Claude Code transcript lives where the harness keeps it, outside
Dux's state, and no Dux script names that path (the milestone 7 plan tests its existence
for resume, never reads it).

**Enforced, not asserted, by:**

- the launch: the harness gets the terminal, the outbox variables and the staged brief
  and settings, nothing else (5.2). No `state/<id>.out` exists, so `bin/dux-recover`'s
  tail has nothing to read and prints a fixed line instead (section 7).
- the environment scrub, now done by the launcher the wrapper writes into the channel
  (5.2): the same patterns as `bin/dux-worker-wrap:243`, so the worker has no `DUX_*`
  variable to find the ledger or the handoffs with. It does keep its own pane's
  `HERDR_*` and `TMUX` variables, because the pane's shell starts it and those are that
  shell's own; the launcher unsets them all the same, as the wrapper does today.
- the one new backend verb, `dux-backend pid <endpoint> <name>` (5.2), reads process
  metadata from the multiplexer: a pid, a process group, a command name and a working
  directory. It never reads pane output. Herdr's `process-info` also returns the full
  command line, which carries the brief; the adapter takes the four fields it needs
  through `jq` and prints nothing else.
- one verb fewer, and a contract test. `dux-backend tail` is the one Dux verb that reads
  a pane, and it has no caller in `bin/` or `skills/`; only its own tests call the adapter
  function. Task 1 removes the verb and both `backend_tail` functions rather than guard
  something nothing uses. The plan adds a test in `tests/contract.bats` that no file in
  `bin/` and no file in `skills/` names `pane read` or `capture-pane`, the two multiplexer
  commands that read a pane. A grep at one point in time is an observation; the test
  makes it a rule the suite enforces on every branch. The rule in the three skills that
  forbid reading `state/<id>.out` becomes a rule against reading the worker's tab.

**Typed text never becomes part of the brief.** The brief the worker runs from is a
read-only copy in the task channel (`bin/dux-worker-wrap:149`), and the facts
`dux-result` proves against (`plan=`, `tasks=`, branch, base, repo) are hashed into the
run record before the harness starts (`:174-191`). What the operator types can steer
*how* the worker works. It cannot change *what counts as done*: a worker told in the tab
to do something else ends unproved, or delivers a PR the operator reviews as usual. To
change the goal, the operator goes through Dux, as today.

**Trust.** The worker runs with the operator's authority (design spec section 2.1), so the
operator typing to it changes nothing about what it can do. Dux's own threat boundary is
unchanged: worker output stays untrusted application data; it is simply displayed to a
human instead of logged, and the human is the one person who already has every right the
worker has. What weakens is not the boundary but the *record*: a run leaves no output log
for later forensics. Section 7 accepts that.

## 5. Mechanics

### 5.1 Who runs where

Today one process, the wrapper, is both the tab's process and the harness's parent. This
design separates the two:

- **The tab holds the harness.** `dux-spawn` opens the tab as a shell at its prompt and
  records the endpoint, as it does today minus the command. The wrapper then starts the
  harness there through the backend (5.2).
- **The wrapper is a supervisor outside the tab.** `dux-spawn` starts it the way
  `dux-lock` starts the watcher (`bin/dux-lock:43`): `nohup`, its own process group under
  `set -m`, stdin from `/dev/null`, stdout and stderr appended to `state/<id>.wrap.log`,
  working directory the task worktree (the wrapper's own check at
  `bin/dux-worker-wrap:42-43` still holds). That log holds Dux's own lines only; nothing
  the worker prints reaches it. The subshell prints `$!`, so spawn knows the wrapper's
  pid; the `dux-lock` shape drops it, and a wrapper spawn cannot name is one it cannot
  stop. Spawn then waits, up to `DUX_SPAWN_START_SECS` (default 10), for the first of
  three things:
  - `state/<id>.pid` names a live `dux-worker-wrap <id>`: mark the task `running` with
    the same `set-if` as today (`:168`).
  - the wrapper's pid is gone: it refused before the harness started. A refusal after
    the run record exists (`handoff_ready`, `bin/dux-worker-wrap:194`) has left a
    `failed` handoff, which the watcher applies to a queued task (`watched_ids`,
    `bin/dux-watch:232-241`); spawn then touches nothing and prints the finding `the
    wrapper for <id> refused before the harness started; see state/<id>.wrap.log`. With
    no handoff (a refusal before the run record, `:76-79`), spawn undoes as a failed
    `open` is undone today (`undo`, `:143-150`), extended to close the pane it opened
    and clear the endpoint file and ledger field, and prints `the wrapper for <id> did
    not start; see state/<id>.wrap.log`. Either way the task is not `running`.
  - the window ends with the wrapper alive and no pidfile: spawn sends it `TERM`, waits
    for it to go, and takes one of the two branches above by whether a handoff exists.
  A fast refusal is already why `set-if` compares from `queued` (`:162-167`); the wait
  keeps that reasoning and adds the pid.

The wrapper inherits the orchestrator's environment, not a pane's. Two consequences, both
handled: it has the `DUX_*` variables it needs, and it has the orchestrator's own
`HERDR_PANE_ID`, so nothing in it may address "its own pane". `backend_report` and
`_own_pane` (`bin/backends/herdr.sh:87-96`) and the wrapper's `mirror` (`:251-259`) are
removed; `dux-backend title` takes the endpoint it should title (5.4).

### 5.2 How the harness starts, and how the wrapper finds it

**The launcher.** The wrapper writes `<channel>/launch`, mode 500, next to the ship
recorder it already writes the same way (`bin/dux-worker-wrap:158-171`). The launcher
carries this run's paths baked in, so no environment has to reach the pane's shell:

1. the scrub loop from `bin/dux-worker-wrap:239-249`, same `case` patterns, moved here
   because the pane's shell, not the wrapper, is now the harness's parent;
2. `PATH` with Dux's own `bin` directory removed, the directory baked in as a literal
   (the wrapper cannot know the pane shell's `PATH`, and `strip_dux_bin` needs
   `dux-env`, which the launcher must not source);
3. `export DUX_STATUS_LOG=<outbox> DUX_REPORT=<outbox>`, and `DUX_SHIP_RECORD` for a
   ship task;
4. `exec claude --model <m> --effort <e> --dangerously-skip-permissions --settings
   <staged settings> <claude_flags> "$(cat <staged brief>)"`. No `-p`, no
   `--output-format`, no `--verbose`: the brief is the opening prompt of an ordinary
   session. `bin/workers/claude.sh` gains `worker_launcher`, which writes this file, and
   keeps `worker_cmd` as the printed form of the `exec` line for the adapter test.
   A quote in any baked path refuses, as the ship recorder does (`:160-162`).

**The start.** `dux-backend run <endpoint> <cwd> <launcher>`: Herdr types the path into
the pane's shell (`herdr pane run`, `bin/backends/herdr.sh:29`, moved out of `open`);
tmux replaces the pane's shell with it (`respawn-pane -k -c <cwd>`,
`bin/backends/tmux.sh:50`, likewise moved). `open` keeps everything else it does today:
the tab, its label, the wait for a prompt, the fail-closed close.

**The trust dialog.** An interactive `claude` in a directory it has not seen asks whether
to trust the folder before it reads its prompt, and the cursor sits on "No, exit". Print
mode skips the question (`claude --help`, under `-p`); a live session does not. Trust is
recorded per path as `projects.<path>.hasTrustDialogAccepted` in the operator's own
`~/.claude.json` (under `CLAUDE_CONFIG_DIR` when the orchestrator's environment sets it).
Measured 2026-09-15 on Claude Code 2.1.271, in tmux panes, five directories: a plain
directory under a trusted path starts without the dialog, at one level down and at two; a
git repository under that same trusted path shows it; a directory inside an untrusted
repository shows it; and a linked worktree of a trusted repository starts without it even
when the worktree sits outside the repository's own directory, in `/tmp`. So the unit
Claude Code trusts is the repository, not the directory and not the ancestor: a directory
in a repository is trusted as that repository, a worktree resolves to the repository it
was made from, and an ancestor counts only where there is no repository between. A worker
sitting at that dialog would pass discovery (a `claude` pid in the right directory),
never move the beat, and hold the slot until the stale wake, on every unattended run.
So `dux-spawn` checks before it opens the tab: the project's own path, the one the
registry holds, must be trusted in that file, read through `jq` and never written. Not
the worktree, which is new on every task and has never been seen; not an ancestor, which
would pass a repository whose worker then sits at the dialog. Otherwise the finding is
`<repo> is not trusted by Claude Code; open a session in it once and answer "Yes, I
trust this folder"`, and the task stays `queued`. A file that is missing or does not
parse is the same finding. Rejected: writing the trust entry from Dux, because Claude
Code rewrites that file from every live session and a Dux write races the operator's
own; and typing the answer into the pane, because a blind `Down`, `Enter` lands in the
prompt when the dialog is not there, and it answers a safety question on the operator's
behalf without them seeing it.

**The discovery.** `dux-backend pid <endpoint> <name>` prints `<pid> <pgid> <cwd>` for the
pane's foreground process when its command name is `<name>`, prints nothing and exits 1
when there is no such process yet, and is a finding when the multiplexer did not answer.
`<name>` comes from the worker adapter, `worker_process_name` in `bin/workers/claude.sh`,
which prints `claude`: the operator's install is the native binary, and one function is
where an install that shows another name would change. Measured 2026-09-14:

- Herdr: `herdr pane process-info --pane <p>` returns
  `foreground_process_group_id`, `shell_pid`, and `foreground_processes[]` each with
  `pid`, `argv0`, `cwd`. The harness is a foreground job of the pane's shell, in a
  process group of its own, and `argv0` is `claude`.
- tmux 3.6a: `list-panes -t <window> -F '#{pane_pid} #{pane_current_command}
  #{pane_current_path}'` gives the command's own pid; tmux starts a pane command in a
  session of its own, so `ps -o pgid= -p <pid>` equals the pid. Through `sh -c` and the
  launcher's `exec`, the pid is stable and the command name becomes `claude`. A dead pane
  under `remain-on-exit` keeps a stale `pane_pid` that the system can recycle, so the
  adapter reads `#{pane_dead}` first and exits 1 on it outright.

The wrapper polls `pid` every second for up to `DUX_WRAP_START_SECS` (default 120) until it
answers with the adapter's name and the worktree as `cwd`; anything else at the end of that window
is a refusal, `the harness for <id> did not appear in its pane`, published as `failed`
like every wrapper refusal. It then writes the group to `state/<id>.pgid`, the file that
already holds the harness's group today (`:374`) and that teardown
(`bin/dux-teardown:97-104`) and recovery (`bin/dux-recover:193-210`) already read.

**Liveness and stop need no parent.** This is the correction to #41's shape, and the
reason no supervision is rebuilt:

- Liveness in Dux is `pid_runs` (`bin/dux-env:44-60`): `kill -0 <pid>` plus a `ps`
  command-line match at a word boundary. It has no parent-child requirement. The wrapper's
  poll loop replaces `kill -0 "$wpid"` (`bin/dux-worker-wrap:381,387`) with
  `pid_runs "$hpid" "$(worker_process_name)"`. The command-line match is what makes a non-child safe to
  poll: a child's pid cannot be reused before `wait`, a non-child's can, and a recycled
  pid that is not running `claude` reads as gone within one poll.
- Stopping a worker is `kill -TERM -- -<pgid>`, then `KILL` (`stop_group`, `:208-229`)
  and the trap (`:87-88`). A signal to a process group reaches any group the calling user
  may signal, not only the caller's children. `stop_group` and `group_alive` (`:206`) are
  unchanged; only where `pgid` comes from changes.
- The one loss is `wait`. The wrapper cannot collect an exit status from a process it did
  not fork, and it learns of an exit at the next poll rather than the instant it happens.
  Polling every 5 s is already how the wrapper reads proposals, and polling every 30 s is
  how the watcher detects staleness (`bin/dux-watch:10`), so this is not a new gap. A
  harness gone with no terminal line is `ended: the session ended without a terminal
  status` on both backends; `ended` already routes through recovery's own proof
  (`bin/dux-recover`, `ended()`), which is the right place for a crash and for a clean
  `/exit` alike. `failed: worker exited <rc>` goes away with the status it reported.

Herdr's own agent lifecycle API (`pane report-agent`, `report-agent-session`, `agent
wait`) is not used for supervision. It reports a state Herdr detected, it is Herdr only,
and tmux has nothing like it; a pid and a group answer the same question on both
backends with commands Dux already runs. `herdr agent start` is not used to launch either:
it runs the bare `claude` executable, so the scrub and the outbox variables could not
reach the harness; Herdr detects the session the launcher started just the same.

### 5.3 How a run ends

A print-mode harness exits when its turn ends. An interactive one finishes its turn and
waits at the prompt. Three ways a run ends:

1. **The worker writes its terminal line.** The poll loop sees it within one poll. The
   loop now also exits on a held terminal line, not only on a violation (`:386`), and the
   wrapper stops the group before judging, the way it already does after a violation
   (`:399`). It then proves and publishes exactly as today. The tab keeps its scrollback;
   only the live session is gone. This is deliberate: the protocol has one terminal line
   per run, and a session left alive after it would be a second run Dux has no record of.
2. **The operator ends the session** (`/exit`, or Ctrl-C twice). The harness is gone at
   the next poll with no terminal line: `ended: the session ended without a terminal
   status`. Recovery's `ended()` then looks for a result the same way it does today.
3. **The worker goes idle without a terminal line.** Nothing exits. The beat (5.5) stops,
   and after `DUX_STALE_SECS` (20 minutes) the watcher marks the task `stale` and Dux
   wakes, as it does for any silent worker. The operator types the nudge or stops it. No
   idle timer is added: the stale wake is the idle timer.

`needs-decision` and `blocked` end the session like `done` does; a decision Dux tracks
still goes through Dux, and the answer still arrives as a new round (milestone 7).

### 5.4 The tab after the run

On Herdr the pane's shell is back at its prompt with the session's scrollback above it;
on tmux the pane is dead under `remain-on-exit`. Both are what a finished tab looks like
today, and `dux-teardown` closes it by endpoint as today, refusing a focused pane
(`bin/backends/herdr.sh:71-81`). The wrapper sets the tab's title once at the start,
`dux-backend title <endpoint> "<project>: <intent line>"`, by endpoint now that it has no
pane of its own; tmux keeps its no-op, because `backend_find` matches the window name.

### 5.5 The heartbeat without an output file

Today the wrapper beats when `state/<id>.out` grows. The replacement is two Claude Code
hooks in the worker settings the task already carries (`templates/worker-settings.json`,
a deny list only today): a `PostToolUse` hook and a `Stop` hook, each running
`touch '<channel>/beat'`, the path single-quoted as the ship recorder's paths are
(`bin/dux-worker-wrap:167`) so a `DUX_HOME` holding a space still works. The wrapper
substitutes the channel path when it stages the settings (`bin/dux-worker-wrap:150-153`),
the way it bakes the ship recorder, with the same refusal for a path holding a quote.
Whether Claude Code runs these hooks from a `--settings` file in an interactive session
is measured once, against a real `claude`, as the first step of the task that adds them;
nothing in the suite can stand in for that. `touch` is on the worker's `PATH` after Dux's
directory is removed, and the hooks run in the scrubbed environment, which has all they
need. The heartbeat condition becomes "the beat file's mtime moved". The beat is a
liveness hint of exactly the class the byte count is today: never proof, never read for
content. It is a zero-length file in a directory only the wrapper made.

### 5.6 What the brief says

One line of `templates/brief.md` changes. Line 19, "Work alone. Never address the
operator; nobody reads your terminal", becomes: "The operator may be watching your
terminal and may type to you. What they type is instruction. Dux reads only the status
file." Everything else, the one terminal line, the 200-byte cap, the append-only outbox,
`needs-decision` for a question, stays word for word. The worker is not told it may wait
in the terminal for an answer: this is the default for unattended runs too, and a worker
waiting on a person who is not there costs a 20-minute stale wake where `needs-decision`
costs nothing. The brief cap of 100 lines and its test are untouched.

## 6. The one-worker guard

`another_worker` in `bin/dux-spawn:85-123` refuses a spawn while any other task's
`state/<other>.pid` names a pid running `dux-worker-wrap <other>`, or while a task the
ledger records as `running` or `stale` still has a container the backend can find. A
pidfile, ledger or backend that does not answer refuses too.

**"Live" is unchanged.** `state/<id>.pid` still holds the wrapper's own pid
(`bin/dux-worker-wrap:81`), and
`pid_runs` still matches it against `dux-worker-wrap <id>`, in the guard, in the watcher
(`bin/dux-watch:53`) and in recovery (`bin/dux-recover:121`). The discovered harness pid
does not go in that file, because every reader of it signals or matches the *wrapper*:
`dux-recover --stop` sends it `INT` (`:161`) and expects the trap to stop the group. The
harness's group goes in `state/<id>.pgid`, whose readers already treat it as "the
worker's own processes" and refuse to tear down or release while it answers `kill -0`.
The container reading is unchanged too: the tab exists for the run either way.

What changes is the *lifetime*, and in one direction the guard gets stricter:

- A print-mode worker ends its own life when its turn ends. A live one is live until it
  writes a terminal line, the operator ends it, or recovery stops it. A session sitting
  at its prompt with no terminal line holds the slot until the stale wake at 20 minutes
  tells the operator, who finishes or stops it. That is correct: the slot is held by a
  worker that has not said it is done.
- The wrapper is no longer in the tab, so closing the tab kills the harness and not the
  wrapper. The wrapper reads the pid gone at its next poll, publishes `ended`, and exits;
  the pid in `state/<id>.pid` is gone and the ledger no longer says `running`, so the
  slot frees itself. Today the same close kills the wrapper and leaves the task `dead`
  for recovery to clear.
- "Done" is unchanged: the handoff `dux-result` proved, applied by the watcher. The
  wrapper stops the session before proving, so by the time the ledger says `done` the
  group is gone and the pid is gone.
- The wrapper can die while the harness lives: a crash, or a `kill -9`. The watcher reads
  the pidfile as gone and marks the task `dead` (`bin/dux-watch:53,65`); recovery's
  `dead()` marks it `failed` and leaves `state/<id>.pgid` in place while the group
  answers (`bin/dux-recover:193-210`, `:212-221`). `another_worker` reads the pidfile,
  and for `running` or `stale` the container, and never the pgid file, so today a second
  worker could start while the first harness sits in its tab. Print mode bounded that
  hole by ending the turn; a live session does not. So `another_worker` gains one check,
  between the pidfile and the ledger: a `state/<other>.pgid` whose group answers
  `kill -0 -- -<pgid>` is `live <other>`, and a pgid file that does not hold a number is
  `pidfile <other>`, the same fail-closed reading the pidfile gets. The task's `dead()`
  message already tells the operator to end the session in that task's tab.

That one check is the only change to `another_worker`.

## 7. Backwards compatibility

- **Shapes.** `plan`, `ship` and `scout` all run this way; `dux-result` never asks how the
  harness ran.
- **Recovery.** `stale`, `dead`, `blocked`, `needs-decision`, `ended` and `failed` are
  reached by the same paths (5.3). `--stop` sends `INT` to the wrapper (`:161`), whose
  trap sends `TERM` to the harness's group, as today. `dead()` (`:212-221`) still refuses
  to release the channel while `state/<id>.pgid` answers, and now says where that process
  is: the recover skill tells the operator to end the session in the task's tab. The
  output tail (`:79-82`) and the failure tail (`:84-89`) print one fixed line, `no output
  captured: the worker ran in its own tab`, and no fence. Everything else in recovery
  reads `status.log`, `report.md`, the pidfile and the backend, none of which change.
- **The failure tail is lost.** `report.md` gets the line above instead of 20 lines of
  output. The tab's scrollback is still there for a human. Accepted.
- **A crash is `ended`, and `ended` is not pushed.** Today a harness that dies is
  `failed: worker exited <rc>`, which reaches the operator's phone; after this change it
  is `ended`, which wakes Dux and goes through recovery but is never pushed (AGENTS.md
  pushes `done` with a PR, `needs-decision` and `failed` only). The operator hears of a
  crashed worker from Dux in the session, not from a notification. Accepted: recovery is
  where a crash belongs, and the tab shows what happened.
- **`state/<id>.wrap.log`** is the one new file under `state/`. `dux-teardown` removes it
  with the run's other references (`bin/dux-teardown:125-133`); nothing else reads it.
- **Unattended runs.** A task from GitHub intake with no operator present runs and ends
  the same way, because the terminal line ends the session (5.3). Nobody has to be
  watching for a run to complete.
- **Herdr's own agent detection.** A real Claude Code session in the pane is something
  Herdr detects by itself (measured: `process-info` on the orchestrator's own pane names
  its `claude`). Dux no longer mirrors a state under `--source dux`, so there is one
  source per pane.
- **Closing the tab.** `dux-backend close` refuses a focused pane. An operator who is
  watching has it focused. Teardown says so and the operator switches away, as today.
- **Milestone 7 (resume).** It changes the adapter signature to add a session id and a
  first-or-resume flag. `worker_launcher` takes the same arguments and grows with it;
  whichever lands second rebases.
- **Tests.** The wrapper's tests run the fake harness inside a real tmux window under the
  suite's isolated socket directory (`tests/helpers/setup.bash:7-55`), which is what the
  wrapper now expects. The fake reads its script from a file, so the terminal it gets is
  incidental; the fake's own variables reach it through `tmux set-environment` on the
  test session (measured: a respawned pane sees them). The Herdr fake gains a `pane run`
  that starts the command in a group of its own and a `process-info` that reports it. No
  pseudo-terminal helper is needed, because no Dux code touches the terminal; the
  2026-09-11 helper stays where that spec left it. The operator typing to a session is
  covered by the plan's manual acceptance run, not by a test of the multiplexer.

## 8. Recommendation, and what was rejected

**One shape, the live session, for every worker.** The trade in plain terms: Dux loses
the output log and the harness's own exit status, and gains a tab the operator can read
and steer, Herdr's own view of the session, and a launch the wrapper no longer has to
hide from a terminal. The loss is small: the log was read for its byte count and a
failure tail, and the exit status is replaced by `ended`, which recovery already proves.

Rejected:

- **Keeping the headless run as an opt-out.** Two launch shapes in the wrapper, two
  heartbeat sources, two ends, and no user for the second: tests do not need it (section
  7), unattended runs do not need it (5.3), and the backend is required to spawn at all.
- **Pull request #41's launch: the harness as a same-group background child of the
  wrapper with the terminal on stdin.** Measured to work, but it needs the wrapper to be
  the tab's process, a process-tree stop weaker than today's group stop, a descendant
  snapshot, and a pseudo-terminal test helper. Once the harness is the tab's own
  process, the group stop and the existing pgid file do the job unchanged.
- **Rebuilding supervision on Herdr's agent lifecycle API.** Herdr only; it reports a
  detected state, not a pid Dux can signal; and the pid it would replace is one command
  away on both backends (5.2).
- **Capturing the terminal with `script(1)` to keep an output file.** Gives back a tail
  of escape codes, and the two `script` families diverge in ways the 2026-09-11 spec
  measured. The hook beat is smaller and portable.
- **Keeping print mode and feeding the operator's messages through `--input-format
  stream-json`.** Puts the operator's words through a Dux command, which is the opposite
  of section 4.
- **An idle timer that ends an idle session.** More states for a case the stale wake
  already reaches, and it would end a session the operator was about to type into.
- **Letting the worker wait in the terminal for an answer.** In #41's opt-in mode the
  operator was present by premise. As a default it is a 20-minute silence where
  `needs-decision` is immediate (5.6).
- **The harness pid in `state/<id>.pid`.** Every reader of that file matches or signals
  the wrapper (section 6); the harness's group already has a file of its own.
- **Answering the trust dialog for the operator, or writing the trust entry.** Section
  5.2 says why; spawn refuses an untrusted repository instead.
- **Guarding `dux-backend tail` with a test instead of removing it.** Nothing calls it;
  less is less (section 4).

## 9. What changes where

| Where | Change |
|---|---|
| `bin/dux-backend`, `bin/backends/herdr.sh`, `bin/backends/tmux.sh` | `open` without a command; new `run` and `pid`; `title` by endpoint; `report`, `tail` and `_own_pane` removed |
| `bin/workers/claude.sh` | `worker_launcher` writes the launcher; `worker_cmd` prints its `exec` line; `worker_process_name`; `worker_run` removed |
| `templates/brief.md` | line 19 |
| `templates/worker-settings.json` | `PostToolUse` and `Stop` hooks touching `'__CHANNEL__/beat'` |
| `bin/dux-worker-wrap` | no fork, no `set -m`, no `.out`, no `wait`, no mirror; launcher staged; `run`, `pid` discovery, `pgid` written from it; loop on `pid_runs`, exits on a terminal line; beat heartbeat; `ended` wording; settings render; title by endpoint |
| `bin/dux-spawn` | refuses a worktree Claude Code does not trust; `open` without a command; starts the wrapper detached and keeps its pid; waits for the pidfile, the wrapper's exit or the window; undo covers the pane and the endpoint; `another_worker` reads the pgid file |
| `bin/dux-teardown` | removes `state/<id>.wrap.log` |
| `docs/constitution.md`, `AGENTS.md` | principle 7 no longer names `state/<id>.out` or a failure tail; version bumped |
| `bin/dux-recover` | the two fixed tail lines; `dead()` wording |
| `tests/fakes/herdr`, `tests/fakes/claude` | `pane run` and `process-info` that behave; `touch <file>` |
| `tests/contract.bats` | no pane reader anywhere in `bin/` or `skills/` |
| the affected `.bats` files | the new cases; `.out` assertions removed |
| `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `skills/dux-status/SKILL.md`, `docs/ARCHITECTURE.md` | the tab rule; the launcher, the beat, `state/<id>.wrap.log`; the adapter line (`:71`); dispatch steps 5 and 6 (`:226-245`); the process-group paragraph (`:289-292`); the pane line (`:300`) |

Nothing in `bin/dux-result`, `bin/dux-watch`, `bin/dux-ledger`, `bin/dux-env` or
`bin/workers/codex.sh` changes.

## 10. Open questions, each with a recommendation

- **Should tmux's `pane_dead_status` be read for an exit status where it exists?**
  Recommend no: Herdr has no equivalent, `ended` already routes through recovery's proof,
  and measured on 2026-09-14 the field is empty after a signal.
- **Should the tab be focused on spawn?** Recommend no: keep `--no-focus` and have the
  dispatch skill name the tab. Stealing focus mid-sentence is worse than one click.
- **Should Linux be measured before the wrapper task is written?** Recommend yes, in
  Docker, as the first step of that task: `pane_pid`, `set-environment` reaching a
  respawned pane, and a group stop from outside the pane. The 2026-09-11 spec is the
  record of how often a macOS-only measurement fails there.

## 11. Decisions this records

1. Every worker runs as a live Claude Code session in its own tab. No flag; the headless
   run is removed.
2. The proof pipeline is untouched; the wrapper stops the session on the terminal line so
   the existing judgement runs.
3. Typed text reaches the harness only; Dux adds no reader of any terminal, `dux-backend
   tail` is removed, the `pid` verb reads process metadata and never output, a contract
   test keeps it that way, and the skills' rule against reading `state/<id>.out` now
   covers the worker's tab.
4. The harness is the tab's own process, started by the backend from a launcher the
   wrapper writes; the wrapper finds it by pid through the multiplexer and supervises it
   with `pid_runs` and the unchanged group stop. Liveness and stop need no parent.
5. `state/<id>.pid` keeps the wrapper's pid; `state/<id>.pgid` keeps the harness's group.
6. The wrapper is a detached supervisor started by spawn, with Dux's own lines in
   `state/<id>.wrap.log`; it never addresses a pane as its own.
7. A harness gone without a terminal line is `ended`, never `failed: worker exited`.
8. Liveness comes from a hook-touched beat file, read for its mtime only.
9. No idle timer; the stale wake is the idle signal. The worker does not wait in the
   terminal for an answer.
10. Dux does not mirror agent state to Herdr; Herdr's own detection is the one source.
11. This document supersedes pull request #41.
12. Spawn refuses a worktree Claude Code does not trust, reading the operator's trust
    record and never writing it; Dux does not answer the dialog.
13. `another_worker` also refuses while another task's pgid file names a live group, so a
    harness outliving its wrapper still holds the one slot.
14. Spawn keeps the wrapper's pid and treats its early exit as a refusal, not a timeout.
15. Constitution principle 7 is amended in the implementation PR to stop naming
    `state/<id>.out` and the failure tail.
