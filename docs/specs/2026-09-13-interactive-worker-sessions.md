# Dux: a worker the operator can watch and type to

Design authority for running a Dux worker as a live Claude Code session in its own
Herdr tab or tmux window, where the operator can read what it does and type to it,
instead of the headless run Dux starts today. The orchestrator design
(`2026-09-03-dux-orchestrator-design.md`) stays the authority for everything this
document does not change; its sections 5.4, 5.5, 6 and 19 point here.

Plan: `docs/plans/2026-09-13-interactive-worker-sessions.md`.

Drafted 2026-09-13 by a Dux plan worker. One independent design review by a fresh
session the same day; it sent the launch shape back for a re-measure (section 5.2)
and its findings are recorded at the end of the plan.

## 1. What the operator gets

Today a worker's tab shows the wrapper's few log lines: the command that started it,
a title, and one line when it ends. Everything the worker itself prints goes to a log
file the operator is told never to open. With this change the operator can say "watch
this one" when dispatching, and the worker's tab then shows the ordinary Claude Code
screen: the worker's thinking, its tool calls, its questions. The operator can type
into that tab and the worker reads it as instruction from the person whose authority
it already runs with.

What the operator does not get: a change in how Dux decides a task is done. A watched
worker is proved the same way a headless one is, from the repository, GitHub, the
`/ship` receipt and Dux's own run record. Nothing typed into the tab, and nothing the
worker prints there, is evidence.

The default stays headless. Watching is opt-in per task (section 8 says why).

## 2. What runs today

The worker is started by the wrapper, `bin/dux-worker-wrap`, which itself runs inside
the tab: `bin/dux-spawn:84-85` hands `dux-worker-wrap <id>` to the backend, and the
backend types it into a fresh Herdr tab (`bin/backends/herdr.sh:11,25,29`: `tab
create`, wait for a shell prompt, `pane run`) or starts it in a tmux window
(`bin/backends/tmux.sh:46-50`). So the tab already has a terminal, and the wrapper
already owns it. The wrapper hides the worker from it:

- `bin/workers/claude.sh:11-14` builds the command: `claude -p "<brief>" --model
  --effort --dangerously-skip-permissions --settings <file> --output-format
  stream-json --verbose`. `-p` is print mode: one turn, then exit.
- `bin/dux-worker-wrap:346-349` starts it as a background job in a process group of
  its own (`set -m`), with stdin from `/dev/null` and stdout and stderr redirected to
  `state/<id>.out`. Nothing reaches the tab.
- `bin/dux-worker-wrap:223-233` scrubs the worker's environment: every `DUX_*`,
  `CLAUDE*`, `HERDR_*`, `TMUX*` and `GIT_CONFIG_*` variable is unset, and the worker
  gets back `DUX_STATUS_LOG` and `DUX_REPORT`, both files inside a task channel the
  wrapper made for this run, plus `DUX_SHIP_RECORD` for a ship task (`:232`).

### 2.1 What the stream-json output is used for

`state/<id>.out` is read in four places, and none of them is proof:

| Reader | What it takes from the file |
|---|---|
| `bin/dux-worker-wrap:374-376` | its byte count only: if it grew since the last check, append `working: heartbeat` to `status.log` |
| `bin/dux-worker-wrap:455` | its last 20 lines, appended to `report.md` under `## Failure tail` when the run failed |
| `bin/dux-recover:79-82` and `:84-88` | a capped, control-character-stripped tail, fenced as untrusted data, for the operator during recovery |
| tests | `tests/dux-worker-wrap.bats:40` and `tests/e2e-dispatch.bats:80` assert the file holds an assistant event; `tests/dux-recover.bats:43,69,167` write fixtures into it; `tests/worker-adapter.bats:28` asserts the `--output-format stream-json` flag |

No script runs `jq` on it, and `bin/dux-result` never opens it: `grep -n '\.out'
bin/dux-result` finds nothing. Three skills forbid Dux from reading it
(`skills/dux-status/SKILL.md:23`, `skills/dux-dispatch/SKILL.md:71`,
`skills/dux-recover/SKILL.md:38`). The stream-json format is a formatting choice for a
file only a human ever looks at.

If the file goes away, what breaks is the heartbeat (section 5.4), the failure tail
(section 7), and the tests named above.

## 3. How a task is proved, and why watching leaves it alone

The worker's only sanctioned channel to Dux is the status outbox,
`$DUX_STATUS_LOG` (`bin/dux-worker-wrap:231`). The wrapper polls it
(`import_proposals`, `bin/dux-worker-wrap:261-335`): `working:` lines go to
`status.log`, one terminal line (`done`, `failed`, `blocked`, `needs-decision`) is
held back, and anything else, or anything after the terminal line, fails the run.

When the harness exits (`bin/dux-worker-wrap:384`) and the whole process group is gone
(`:388-390`), the terminal line is judged (`:444-453`). A `done` proposal is a request:
`prove_done` (`:420-442`) runs `bin/dux-result verify <id> <run>` (`:424`), adding
`--report <outbox>` only when the worker wrote a report (`:422-423`). `dux-result`
(`bin/dux-result:373-405`) reads:

- Dux's own run record and result context, written before the worker started and
  hashed so a change is a finding (`load_run`, `bin/dux-result:30-52`;
  `bin/dux-worker-wrap:158-174`);
- the worktree: on the branch, no uncommitted changes, the changed-file set against
  the base (`:127-132`, `read_changes` at `:148`);
- GitHub: exactly one open, non-draft PR from this branch in this repository to this
  base whose head is the local tip, with green checks (`find_pr` at `:68-107`,
  `require_green_checks` at `:109-122`);
- the plan file's task boxes for a `ship` task (`check_plan_tasks`, `:206-289`) and
  the `/ship` receipt, five phases in order with the `ci` phase at the branch tip
  (`check_receipt`, `:306-319`);
- for a `scout`, the report outbox: a regular file, under 1 MiB, with text in it.

Not one of these inputs is the worker's stdin or stdout. The terminal line is the
only worker-authored text in the path, and it is a 200-byte request whose every claim
is re-derived. Exit 1 from `dux-result` becomes `ended: the result was not proved`
(`bin/dux-worker-wrap:436-439`); Dux never guesses done.

**Verdict:** a watched worker preserves this proof unchanged. The outbox, the run
record, the repository and GitHub are exactly where they were. The one input that
changes shape is the harness exit, which an interactive session does not produce on
its own; section 5.3 says how the wrapper produces it.

## 4. What "interactive" means, and where the boundary sits

The tab's terminal becomes the worker's stdin and stdout. The operator types into
the tab. The text goes to the `claude` process and nowhere else.

**Typed text never enters Dux's context.** Dux, the orchestrator session, reads worker
material through exactly two doors: `status.log`, fed only by `import_proposals`
with its grammar and 200-byte cap, and the capped, cleaned, fenced text
`bin/dux-recover` prints. Neither reads a terminal. In the headless run the worker's
output is at least on disk under `state/`, where a careless script could reach it; in
the interactive run it is not written under `DUX_HOME` at all. The Claude Code
transcript lives where the harness keeps it, outside Dux's state, and no Dux script
names that path today (the milestone 7 plan proposes to test its existence for
resume, never to read it).

**Enforced, not asserted, by:**

- the launch: the harness gets the terminal and the outbox and nothing else. No
  `.out` file exists for an interactive run, so `bin/dux-recover`'s tail has nothing
  to read and says so (section 7).
- the environment scrub (`bin/dux-worker-wrap:227`): the worker still has no
  `HERDR_*` or `TMUX` variable, so it cannot address Dux's own pane, and no `DUX_*`
  variable, so it cannot find the ledger or the handoffs.
- a contract test. `dux-backend tail`, the one Dux verb that reads a pane, has no
  caller in `bin/` or `skills/` today; only tests call the adapter function. The plan
  adds a test in `tests/contract.bats` that no file in `bin/` outside `dux-backend`
  and `backends/`, and no file in `skills/`, names `dux-backend tail`,
  `backend_tail`, `pane read` or `capture-pane`. A grep at one point in time is an
  observation; the test makes it a rule the suite enforces on every branch. The rule
  in the three skills that forbid reading `state/<id>.out` is extended to the
  worker's tab.

**Typed text never becomes part of the brief.** The brief the worker runs from is a
read-only copy in the task channel (`bin/dux-worker-wrap:133`), and the facts
`dux-result` proves against (`plan=`, `tasks=`, branch, base, repo) are hashed into
the run record before the harness starts (`:158-174`). What the operator types can
steer *how* the worker works. It cannot change *what counts as done*: a worker told
in the tab to do something else ends unproved, or delivers a PR the operator reviews
as usual. To change the goal, the operator goes through Dux, as today.

**Trust.** The worker runs with the operator's authority (design spec section 2.1),
so the operator typing to it changes nothing about what it can do. Dux's own threat
boundary is unchanged: worker output stays untrusted application data; it is simply
displayed to a human instead of logged, and the human is the one person who already
has every right the worker has. What weakens is not the boundary but the *record*:
an interactive run leaves no output log for later forensics. Section 7 accepts that.

## 5. Mechanics

### 5.1 Choosing the mode

`bin/dux-brief <id> ... --interactive` writes `tasks/<id>/mode` holding
`interactive`, next to the `harness` file `dux-spawn` writes today. Absent file means
headless. The brief is where the flag lives because one rule in the brief changes
(section 5.5), and the brief is rendered before spawn. `dux-spawn` and the wrapper
read the file; neither takes a flag. The wrapper records `mode=` in the run record
and the result context so recovery can tell which kind of run it is looking at. A
retry (`bin/dux-recover:331` renders the retry brief) passes `--interactive` again
when the file says so, so a retried task keeps its mode.

An interactive run is Claude only. `dux-spawn` refuses the mode with a finding for any
other harness, as it refuses `codex` today (`harness_refusal`, `bin/dux-env:111`).

### 5.2 Handing the worker the terminal

The command loses `-p`, `--output-format` and `--verbose`, and gains the brief as
its opening prompt: `claude --model <m> --effort <e> --dangerously-skip-permissions
--settings <file> "<brief>"`, with whatever shared flags the adapter carries by then
(pull request #40 adds a `claude_flags` array both entry points use).
`bin/workers/claude.sh` gains `worker_cmd_interactive` and `worker_run_interactive`
with the same four arguments as their headless pair. The codex adapter gains nothing:
`dux-spawn` refuses before the adapter is reached.

The wrapper today runs the harness as a background job in its own process group
(`set -m`, `bin/dux-worker-wrap:346-349`). A process in a background group that
reads the terminal is stopped by the kernel, so that shape cannot be kept. Three
shapes were measured on 2026-09-13 with bash 3.2.57 on macOS, driving the wrapper
through a pseudo-terminal and typing one line:

| Shape | Result |
|---|---|
| `set -m`, job in its own group, then `fg` to hand it the terminal | the job never received the line; `fg` did not return |
| harness in the foreground; the poll loop as a background subshell | line received, exit status returned, but the wrapper is blocked in the harness and the loop's state cannot reach it (the review's finding 1 and 5) |
| job control off; the harness a background child in the wrapper's own group, stdin the terminal (`<&0 &`); the wrapper's loop and `wait` unchanged | line received; `kill -0` loop ran; `wait` returned the exit status |

The third shape is the design. Without job control a `&` child stays in the wrapper's
process group, which is the terminal's foreground group, so it may read the terminal;
bash gives such a child `/dev/null` as stdin unless told otherwise, hence `<&0`. The
wrapper keeps everything it has today: one process, the same poll loop
(`bin/dux-worker-wrap:365-380`), `wait "$wpid"` and `$rc`, `import_proposals` with its
state in the same variables, the trap. Only the launch line changes, and the
own-process-group refusal (`:352-356`) is skipped in this mode.

What this costs: the harness shares the wrapper's process group, so "the group is
gone" (`group_alive`, `:190`) would ask about the wrapper itself, and the trap's
`kill -TERM -- "-$pgid"` (`:71`) would kill the wrapper. In interactive mode both
work on the harness's *process tree* instead:

- while the harness runs, each pass of the poll loop records its descendants, found
  by walking `ps -axo pid=,ppid=` (present on macOS and Ubuntu) from the harness pid,
  and keeps the union as a snapshot;
- to stop, the wrapper sends TERM to the harness pid and every pid in the snapshot,
  waits, sends KILL to what answers `kill -0`, and refuses the run if anything still
  answers. The trap does the same on INT or TERM, which is what `bin/dux-recover:161`
  sends to a stuck wrapper.

This is weaker than today's group claim, and the design says so: a process the
harness starts and orphans between two polls is re-parented to pid 1 and is not in
the snapshot. Measured on 2026-09-13: a grandchild whose parent had exited showed
`ppid 1` at once. Today's claim already excludes a child that starts a session of its
own (`:186-189`); this mode also excludes one that outlives its parent unseen. The
existing survivor test (`tests/dux-worker-wrap.bats`, the `stubborn` fake) is kept
for the interactive path by having the fake stay alive as the parent, which is what
a real harness does.

`state/<id>.pgid` is still written and holds the shared group. `dux-teardown` reads
it only after it has proved the wrapper pid gone (`bin/dux-teardown:85-102`), so its
meaning there is unchanged: with the wrapper gone, anything left in the group is a
survivor. The tab closing sends `SIGHUP` to the group, which kills the wrapper and
lets the watcher read the task as dead; that is what happens today too.

### 5.3 How an interactive run ends

A print-mode harness exits when its turn ends, and the wrapper judges the terminal
line after `wait` (`bin/dux-worker-wrap:384`). An interactive harness never exits on
its own: it finishes its turn and waits at the prompt. Three ways it ends:

1. **The worker writes its terminal line.** The poll loop sees it within one poll
   (5 s). In interactive mode the loop also exits on a held terminal line, not only on
   a violation (`:365-380`), and the wrapper stops the tree before `wait`, the way it
   already stops the group after a violation (`:383`). It then proves and publishes
   exactly as today. The tab keeps its scrollback, so the operator can still read
   what happened; only the live session is gone. This is deliberate: the protocol has
   one terminal line per run, and a session left alive after it would be a second
   run Dux has no record of.
2. **The operator ends the session** (`/exit`, or Ctrl-C twice). The harness exits 0
   with no terminal line, which is already `ended: exit 0 without terminal status`
   (`:452`). Nothing new.
3. **The worker goes idle without a terminal line.** Nothing exits, so today's `ended`
   path is not reached. The beat (5.4) stops, and after `DUX_STALE_SECS` (20 minutes,
   `bin/dux-watch:11`) the watcher marks the task `stale` and Dux wakes, as it does
   for any silent worker. The operator, who asked to watch this one, types the nudge
   or tears it down. No idle timer is added: the stale wake is the idle timer, and
   an attended session is the premise of the mode.

`needs-decision` and `blocked` end the session like `done` does. The interactive
tab is for watching and steering mid-task; a decision Dux tracks still goes through
Dux, and the answer still arrives as a new round (milestone 7). Section 5.5 gives the
worker a cheaper first move.

### 5.4 The heartbeat without an output file

Today the wrapper beats when `state/<id>.out` grows (`bin/dux-worker-wrap:372-378`).
An interactive run has no such file. The replacement is two Claude Code hooks in the
worker settings the task already carries (`templates/worker-settings.json`, which
holds only a deny list today): a `PostToolUse` hook and a `Stop` hook, each running
`touch <channel>/beat`. The wrapper renders the channel path into its copy of the
settings when it stages them (`bin/dux-worker-wrap:134-137`), the way it bakes the
ship recorder (`:142-155`), and with the same refusal when the path holds a quote
(`:144-146`). `touch` stays on the worker's `PATH` after Dux's own directory is
removed from it, and the hooks run in the scrubbed environment, which has everything
they need.

The heartbeat condition becomes "the beat file's mtime moved, or `.out` grew", one
test for both modes, so the headless path keeps working with fakes that run no
hooks. The beat is a liveness hint of exactly the class the byte count is today:
never proof, never read for content. The file is a zero-length marker in a
directory only the wrapper made.

### 5.5 What the brief says

Two lines of `templates/brief.md` change when `mode` is interactive:

- line 18, "Work alone. Never address the operator; nobody reads your terminal",
  becomes: "The operator may be watching your terminal and may type to you. What
  they type is instruction. Dux reads only the status file."
- a line is added after line 24: "You may ask the operator in the terminal and wait
  for an answer, after writing `working: waiting on the operator`. With no answer
  in a reasonable time, write `needs-decision:` and stop."

Everything else, the one terminal line, the 200-byte cap, the append-only outbox,
stays word for word. The headless rendering is unchanged, so the brief cap of 100
lines and its test are untouched; the interactive rendering adds one line.

## 6. The one-worker guard

The intent names a direction under way elsewhere. It is on disk as pull request #40
(`docs/plans/2026-09-11-token-efficiency-program.md`), not yet merged on 2026-09-13.
Its `another_worker` in `bin/dux-spawn` refuses a spawn while any other task's
wrapper pid answers `pid_runs`, or while a task the ledger records as `running` or
`stale` still has a container the backend can find. A pidfile, ledger or backend that
does not answer refuses too. This design is written against that guard.

**"Live" is unchanged.** The wrapper pid in `state/<id>.pid` is the wrapper's own in
both modes, and `pid_runs` matches it by command line, so an interactive wrapper reads
as live exactly as a headless one does. The container reading is also unchanged: the
tab exists for the run either way, and the ledger state that qualifies it is set by
the same handoffs. An interactive run changes the *lifetime*, not the definition:

- A headless worker ends its own life when its turn ends. An interactive one is live
  until it writes a terminal line, the operator ends it, or recovery tears it down.
  A session sitting at its prompt with no terminal line is live, and the guard
  refuses the next spawn until the operator finishes or closes it. That is correct:
  the operator asked for an attended session, and the stale wake at 20 minutes
  tells them it is waiting. A `stale` task with a live tab still counts under #40's
  rule, so walking away holds the slot until the operator acts, by design.
- "Done" is unchanged: the handoff `dux-result` proved, applied by the watcher. The
  wrapper stops the session before proving, so by the time the ledger says `done`
  the pid is gone and the ledger state no longer qualifies the tab as evidence.

Nothing in this design touches `another_worker`.

## 7. Backwards compatibility

- **Shapes.** `plan`, `ship` and `scout` all run interactively or not; the mode is
  orthogonal to the shape and `dux-result` never reads it.
- **Recovery.** `stale`, `dead`, `blocked`, `needs-decision`, `ended` and `failed` are
  reached by the same paths (5.3). `bin/dux-recover --stop` sends INT to the wrapper
  (`:161`); the interactive trap turns that into a tree stop, so a stuck interactive
  task stops the same way. `bin/dux-recover`'s output tail prints "no output
  captured: interactive run" for a run whose record says `mode=interactive`, and its
  failure tail does the same. A retry keeps the mode (5.1). Everything else in
  recovery reads `status.log`, `report.md`, the pidfile and the backend, none of
  which change.
- **The failure tail is lost for interactive runs.** `report.md` gets the line above
  instead of 20 lines of output. The operator was watching, and the tab's scrollback
  is still there. Accepted.
- **Herdr's own agent detection.** A real Claude Code session in the pane is something
  Herdr detects by itself. The wrapper's `mirror` (`bin/dux-worker-wrap:236-243`)
  reports a state for the same pane under `--source dux`. Two sources for one pane
  is a conflict Herdr's precedence rules decide; the wrapper does not mirror in
  interactive mode and lets Herdr show the real state. `report-metadata --title` is
  kept.
- **Closing the tab.** `dux-backend close` refuses a focused pane
  (`bin/backends/herdr.sh:71-79`). An operator who is watching has it focused.
  Teardown says so and the operator switches away, as today.
- **Milestone 7 (resume) and pull request #40.** Both touch `bin/workers/claude.sh`
  and `bin/dux-worker-wrap`. The M7 plan changes the adapter signature to add a
  session id and a first-or-resume flag; #40 adds the shared flags array and routes
  ship tasks by risk. The interactive functions take the same arguments as their
  headless pair and grow with it. Whichever lands second rebases; the plan's tasks
  assume #40 is in.
- **Tests.** The wrapper's tests drive a fake harness with no terminal. Interactive
  tests need the pseudo-terminal helper measured in
  `2026-09-11-terminal-prompt-tests.md`, which was not landed because nothing on
  `main` needed it. This is the caller it was waiting for; landing it is the first
  task of the plan. The fake harness gains one directive that reads a line from its
  stdin, so a test can type to it, and one that touches a file, so a test can beat.

## 8. Recommendation, and what was rejected

**Hybrid: headless by default, `--interactive` on the brief.** The tradeoff in plain
terms: watching costs the output log and the harness's own exit as an end signal,
and in exchange the operator sees the work and can steer it. That is a good trade
for the task the operator wants to watch and a bad one for the task nobody is
looking at. Tasks arrive from GitHub intake with no operator present; a session
waiting at a prompt in a tab nobody reads is worse than a log file, and it holds the
one-worker guard until someone notices. The default protects those; the flag serves
the operator who is present.

Rejected:

- **A full switch.** Loses the failure tail and the exit signal for every run,
  including unattended ones, and every existing wrapper test would need a terminal.
- **Capture the terminal with `script(1)` to keep an output file.** Gives back the
  heartbeat and a tail, but the tail of a full-screen session is escape codes, and
  the two `script` families diverge in ways the 2026-09-11 spec measured (exit
  status, hangs under bats on Linux). The hook beat is smaller and portable.
- **`herdr agent start` / `herdr agent prompt`.** Would make the launch Herdr-only and
  put a Herdr command, not the wrapper, in charge of the harness. The wrapper must
  own the process it proves, on both backends.
- **Keep print mode and feed the operator's messages through `--input-format
  stream-json`.** Two-way, but the operator reads a JSON log and types through a Dux
  command, which puts their words in Dux's context. The opposite of the boundary
  in section 4.
- **An idle timer that ends an idle session.** More states for a case the stale wake
  already reaches, and it would end a session the operator was about to type into.
- **The harness in the foreground with the poll loop in a background subshell.**
  Measured to work for the terminal, but it leaves the wrapper blocked and moves
  the import state out of the process that judges it (review findings 1, 2 and 5).

## 9. What changes where

| Where | Change |
|---|---|
| `bin/dux-brief`, `templates/brief.md` | `--interactive` writes `tasks/<id>/mode`; two rule lines vary by mode |
| `bin/dux-spawn` | refuses interactive mode for a non-Claude harness |
| `bin/workers/claude.sh` | `worker_cmd_interactive`, `worker_run_interactive` |
| `bin/dux-worker-wrap` | mode in run record and context; same-group launch with the terminal on stdin; descendant snapshot; tree stop and trap; loop exits on a terminal line; hook beat; no mirror; settings render |
| `templates/worker-settings.json` | `PostToolUse` and `Stop` hooks touching `__CHANNEL__/beat` |
| `bin/dux-recover` | "no output captured" for interactive runs; retry passes `--interactive` |
| `tests/helpers/setup.bash`, `tests/pty.bats` | the terminal helper from the 2026-09-11 spec |
| `tests/contract.bats` | no pane reader outside the backend layer |
| `tests/fakes/claude`, `tests/dux-worker-wrap.bats`, `tests/dux-brief.bats`, `tests/dux-spawn.bats`, `tests/dux-recover.bats`, `tests/worker-adapter.bats` | the new cases |
| `skills/dux-dispatch/SKILL.md`, `skills/dux-recover/SKILL.md`, `docs/ARCHITECTURE.md` | the flag, the tab rule, the new state file and hooks, the adapter list (`:62`) and the launch description (`:208-213`) |

Nothing in `bin/dux-result`, `bin/dux-watch`, `bin/dux-ledger`, `bin/dux-teardown`,
`bin/workers/codex.sh` or the backends changes.

## 10. Open questions, each with a recommendation

- **Should the beat hooks be installed for headless runs too?** Recommend yes: one
  settings template, one heartbeat condition. The cost is two `touch` calls per tool
  use, which is nothing.
- **Should the interactive tab be focused on spawn?** Recommend no: keep `--no-focus`
  and have the dispatch skill name the tab. Stealing focus mid-sentence is worse
  than one click.
- **Should Linux be measured before Task 3 is written?** Recommend yes, in Docker, as
  the first step of that task: the same-group shape relies on documented bash
  behaviour, but the 2026-09-11 spec is the record of how often that assumption
  fails.

## 11. Decisions this records

1. Headless stays the default; `--interactive` on `dux-brief` opts a task in, and a
   retry keeps it.
2. The proof pipeline is untouched; the wrapper stops the session on the terminal
   line so the existing judgement runs.
3. Typed text reaches the harness only; Dux adds no reader of any terminal, a
   contract test keeps it that way, and the skills' rule against reading
   `state/<id>.out` now covers the worker's tab.
4. The harness runs as a same-group background child with the terminal on stdin;
   the wrapper's loop, `wait` and import state are unchanged; stopping is by
   descendant snapshot in this mode, and the design names what that misses.
5. Liveness comes from a hook-touched beat file, read for its mtime only.
6. No idle timer; the stale wake is the idle signal.
7. Interactive runs do not mirror agent state to Herdr.
8. The terminal test helper from the 2026-09-11 spec lands as this plan's first task.
