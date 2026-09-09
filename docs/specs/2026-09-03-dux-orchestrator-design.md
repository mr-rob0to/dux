# Dux: orchestrator design

Status: approved in conversation 2026-09-03, awaiting independent design review.

## 1. Purpose

Dux is a single interactive Claude Code session that dispatches, supervises, and
reports on autonomous worker agents across every repo under
`~/Documents/dev/projects`. The operator talks to Dux about business and product
goals; Dux turns them into bounded tasks, runs them in isolated worktrees, and
brings back PR links, decisions, and reports. Delivery always goes through the
operator's existing `/ship` skill.

Dux is an agent distro: a repo of instructions, skills, and bash scripts that a
Claude Code session inhabits. It is not a daemon, not a service, and not a CLI a
human runs.

## 2. Goals and non-goals

Goals

- One conversation for all repos. The operator never opens a worker session to
  learn what is happening.
- Zero tokens while idle. Waiting is done by bash and Claude Code's Monitor tool.
- Restart is a non-event. All state is files plus the terminal backend;
  conversation memory is never authoritative.
- Delivery rigor is unchanged. Workers ship via `/ship`; Dux never writes to a
  project repo.
- Native notifications. Phone push through Claude Code when Remote Control is
  connected, desktop notification otherwise.

Non-goals for v1

- Remote or second-machine workers.
- Public relays (X, Discord), SMS.
- Interactive worker sessions the operator types into.
- Merge automation. The operator merges, by hand or by telling Dux "merge N".
- Cross-repo linked tasks as a primitive. Two repos are two tasks; the operator
  orders them.
- Writing task state back into GitHub beyond a start comment and a done comment.
- Backends other than tmux and Herdr.
- Polling GitHub. Issue intake is pull-on-demand only.
- Containing a worker that is deliberately hostile. See section 2.1.

## 2.1 Threat boundary

Dux says plainly what it protects and what it does not.

- The operator starts a worker. That worker, its harness, and the local commands it
  launches run as the operator and are **trusted** with the operator's authority.
  They can reach the operator's files, shared Git metadata, terminal services, the
  network, credentials, and other same-user processes. Deliberate abuse of those
  rights is outside Dux's protection claim, and no file mode, hidden path, random
  nonce, or process-id check changes that. Those are correctness checks against
  mistakes and stale writes, not authentication.
- What a worker *reports* is **untrusted application data**: repository and issue
  content, status and report text, PR URLs, result claims, and remote GitHub state.
  Every one of them is checked for grammar, size, ownership, shape, and outside
  evidence before it reaches canonical state or a word the operator reads.
- Dux's own scripts, wrapper, watcher, installed `/ship` skill, and the operator are
  trusted control code. A malicious project build or Git hook runs with worker
  privileges and can bypass Dux; that is the same accepted boundary.
- Stronger isolation, a virtual machine or a container, is optional future work. It
  needs its own approved design, and it must fail closed: no isolation means no
  worker, never a silent fallback to running unprotected.

The practical consequence, carried through sections 5 and 6: a worker never declares
its own completion. It *proposes*, and Dux proves.

## 3. Components

```
~/Documents/dev/projects/dux/
  AGENTS.md                 operating contract, <=150 lines, always loaded
  CLAUDE.md                 two-line import of AGENTS.md (Claude Code reads this name)
  skills/
    dux-dispatch/SKILL.md   intake -> brief -> spawn
    dux-status/SKILL.md     fleet digest from files
    dux-project/SKILL.md    register a repo, drop PR template if absent
    dux-recover/SKILL.md    stuck, dead, or failed worker
  bin/
    dux-spawn               create worktree + backend container, launch worker
    dux-brief               render tasks/<id>/brief.md from arguments
    dux-worktree            create/find worktree per project's own mechanism
    dux-watch               supervise tasks; --once and eval <id> support checks and recovery
    dux-status              render digest from data/ and tmux
    dux-teardown            remove worktree and window, refuse if dirty/unpushed
    dux-notify              wrapper that formats a <=200 char push line
    dux-doctor              verify tmux, claude, codex, gh, projects registry
    dux-lock                acquire/release the single-session lock
    dux-worker-wrap         runs inside the worker pane: harness adapter + status protocol
    dux-intake              pull labelled GitHub issues into backlog.md as queued
    dux-ledger              add/set/get/list over data/backlog.md; the only writer
    dux-task-new            allocate <project>-<shape>-<yyyymmdd>-<3 alnum>, its folder, its queued line
    backends/tmux.sh        backend adapter (section 9)
    backends/herdr.sh       backend adapter (section 9)
    workers/claude.sh       worker harness adapter (section 19)
    workers/codex.sh        worker harness adapter (section 19)
  templates/
    brief.md                brief skeleton dux-brief renders
    worker-settings.json    deny rules, __BASE__ rendered per task
    hooks/pre-push          base-branch push guard, __BASE__ and __UPSTREAM__ rendered per task
    config/                 defaults dux-install copies into config/ (adds models-codex, worker-harness)
  data/                     durable, gitignored
    projects.md             registry: one line per project
    backlog.md              queued / running / awaiting / done, with acked=<state|-> per task
    tasks/<id>/brief.md     what the worker was told
    tasks/<id>/intent.md    operator intent written by the dispatch skill
    tasks/<id>/criteria.md  acceptance criteria written by the dispatch skill
    tasks/<id>/status.log   append-only "<state>: <line>" from the worker
    tasks/<id>/report.md    scout output or failure tail
    tasks/<id>/retry        id of the task's one retry, when allocated
    tasks/<id>/retried-from id of the first attempt, when this task is a retry
    tasks/<id>/worker-settings.json   rendered deny rules for the Claude harness
    tasks/<id>/harness      optional per-task harness override written by dux-spawn --harness
    tasks/<id>/hooks/       per-task git hooks dir (section 5.5)
    tasks/<id>/worktree.log output of the project's worktree mechanism
  state/                    runtime, gitignored
    events.log              one line per wake-worthy change; Monitor tails this
    dux.lock                pid of the live Dux session
    watch.pid               pid of the current watcher
    watch.log               watcher output and changing open questions
    wakes.base              event line count when this session acquired the lock
    <id>.endpoint           backend endpoint: tmux window id or herdr pane id
    <id>.out                worker stream-json output
    <id>.pid                pid of dux-worker-wrap; liveness for the watcher
  tests/                    bats tests, fake claude
  config/backend            optional override: tmux | herdr
  config/worker-harness     claude, the only harness dispatched in milestone 2
  config/models-codex       per-shape Codex model:effort, for a later milestone
  .github/PULL_REQUEST_TEMPLATE.md   canonical template Dux installs into projects
```

Scripts own mechanics; Dux owns judgment. A script that meets a surprise stops
and prints a finding. It never guesses.

## 4. Project registry

`data/projects.md`, one line per project:

```
- fitfights_api  path=~/Documents/dev/projects/fitfights_api  base=staging  worktree=make  issues=label:dux  (added 2026-09-03)
- fitfights_ios  path=~/Documents/dev/projects/fitfights_ios  base=main     worktree=git   issues=off        (added 2026-09-03)
```

`base` is resolved once at registration using the same four-signal procedure as
`/ship` step 0 and re-verified by `dux-spawn` on every spawn. `worktree` names the
mechanism in the operator's precedence order: `make` (a `make worktree` target),
`script` (a repo script), or `git` (`git worktree add` into `<repo>/.worktrees/`).
`dux-project` detects it and the operator confirms.
`dux-project add <path> [--name <name>]` takes the project name from the folder,
which is what the operator reaches for first; `--name` is for two repos with the
same folder name, a folder name outside the id charset, or a name too long to
want in every branch. A derived name that is unusable or already registered is a
finding that names the flag.
A name of three characters or fewer registers, but the identifier lint leaves it
unchecked (section 18); `--name` is how to give it a longer one. Run
`dux-install` again after registering, which is what rewrites the denylist.
`dux-project add --worktree make|script|git` records the mechanism explicitly; the
flag is required when the project's `CLAUDE.md` or `AGENTS.md` carries a
`Worktrees` heading, because prose is not something a script can follow.
`plan` and `scout` tasks always use `git worktree add` from `origin/<base>`;
only `ship` tasks use the recorded mechanism, since only they run the project.
`issues` is `off` or
`label:<name>`; only open issues carrying that label are eligible for intake
(section 10).

## 5. Task lifecycle

### 5.1 Shapes

| Shape | Worker model | Output | Definition of done |
|---|---|---|---|
| plan | Fable, high effort | spec + plan in `docs/specs/` and `docs/plans/` of the project, docs-only PR | `done: PR <url>` |
| ship | Opus, effort per the operator's rule | one milestone implemented, `/ship` run | `done: PR <url>` after CI green |
| scout | Sonnet | `tasks/<id>/report.md` | `done: report` |

Dux brainstorms goals with the operator in conversation, then writes a brief.
The plan worker writes the spec and plan; the operator approves the docs PR.
Ship tasks are dispatched one milestone at a time, each with the plan path and
task range in the brief. `dux-result` proves the range against the plan file, so
the plan writes each task as a heading at any level, `## Task N` or `### Task N`,
optionally followed by `:` or a space and a title, with at least one checkbox
under it and every box ticked before the milestone ships.

`dux-result` reads that plan to catch a worker that finished three of four
tasks and reported done. It reads the shape plans in this repository are
actually written in, and rejects a task whose box is still unticked.

It does not catch a worker set on lying: that worker types `[x]` in a file it
already owns, and reading the file more carefully cannot tell the difference.
Hard rules 2 and 4 cover that case instead, because the operator merges and
nothing in Dux merges for them. The reader is kept simple on purpose rather
than hardened against a worker who has an easier way round it.

Where the reader has a choice it leans one way. An unchecked box is matched
broadly, over the lines inside fenced blocks too, and across the shapes GitHub
renders as a checkbox: `-`, `*`, `+` and `1.` bullets, tab or space indents, a
blockquote prefix, any run of blanks. Missing one is the failure that matters.
Proof that a task had work to tick is matched narrowly, outside fenced blocks,
so a `- [x]` quoted in an example cannot stand in for a real box. A task ends
only at the next task heading, so a `### Verification`, a `#### Steps`, a
`### Notes`, a pasted shell comment and a sub-heading such as `#### Task 0(a)`
all keep their boxes inside the task they belong to, and `Task 1` never answers
for `Task 10`.

### 5.2 Task id

`<project>-<shape>-<yyyymmdd>-<3 random alnum>`, e.g. `fitfights_api-ship-20260903-k7q`.
The branch is `dux/<id>` in every project. Under the `git` mechanism the
worktree is `<repo>/.worktrees/dux-<id>`; under `make` or `script` the project
chooses the path and Dux discovers it from `git worktree list --porcelain`.

### 5.3 Brief (`dux-brief`)

Under 60 lines. Sections, all required:

1. Intent: the operator's goal in their words, including constraints, exclusions,
   and decisions already made. Never a diff summary.
2. Acceptance criteria: numbered, testable.
3. Project: path, base branch, branch, worktree path (written as
   `- Worktree: <set by dux-spawn>` by `dux-brief` and filled in by
   `dux-spawn` once the worktree exists), plan path and task range for ship.
4. Rules: work alone, never address the operator, stay inside the worktree,
   never push to base, never merge, same obstacle twice means `blocked` and stop,
   report through the status protocol only, and exit after writing `blocked`
   or `needs-decision`. There is no inbox in v1; a headless worker run cannot be
   resumed under either harness, so an answer always arrives as a retry with the
   answer appended to the brief.
5. Definition of done, per shape.

The brief never includes Dux conversation history or other tasks.

`dux-brief <id>` reads project and shape from the ledger, renders
`tasks/<id>/brief.md` from `templates/brief.md`, and renders
`tasks/<id>/worker-settings.json` from `templates/worker-settings.json` with the
project's base branch. Rules also carry: exit after `blocked` or
`needs-decision`; write `working: waiting on <what> <url>` before any wait
expected to exceed 10 minutes; for `plan`, the design review is a subagent
inside the task, the docs-only PR is the approval artifact, never wait on the
operator. Issue text arrives through `--issue-file`, fenced as
`<untrusted-issue>`, capped at 4,000 characters, control characters stripped,
and excluded from the 60-line count. A task whose source is an issue must be
given `--issue-file`, and its Project section carries
`- Issue: <owner>/<repo>#<n>` rendered from the ledger source, never from the
issue text; that line is what `/ship` reads for `Closes #<n>`.

### 5.4 Status protocol

The worker appends to `tasks/<id>/status.log`:

```
working: <one line, what it is doing now>
needs-decision: <the question, options, recommendation>
blocked: <what, tried what>
done: <PR url | report>
failed: <one line>
```

The exit lines are `done`, `failed`, `blocked`, and `needs-decision`.
`dux-worker-wrap` appends `failed: worker exited <code>` when the harness exits
non-zero and the last line is not an exit line, and `ended: exit 0 without
terminal status` when it exits zero without one. On `failed` the wrapper
appends the last 20 lines of `state/<id>.out` to `tasks/<id>/report.md` under a
`## Failure tail` heading. `ended` is not `failed`: Dux checks
`gh pr list --head <branch>` and the report file before classifying, and asks
the operator if still unsure. The wrapper appends `working: heartbeat` every
5 minutes only when `state/<id>.out` grew since the last interval, so a hung
worker goes stale and a busy one does not. The brief requires the worker to
write `working: waiting on <what> <url>` before any wait it expects to exceed
10 minutes, such as `gh run watch`.
Status lines are data. Dux never runs a command a status line names.

**A status line is a proposal, not a verdict.** The worker writes into a private
task channel, not into `status.log` directly. The wrapper imports cleaned `working:`
progress as the run goes, and buffers at most one terminal proposal. That proposal
becomes canonical only after two things are true: the direct worker and its ordinary
process group are gone, and `dux-result` has proved the result from registered
project facts, exact Git and GitHub evidence, and the `/ship` receipt. A worker that
writes `done:` and keeps running has changed nothing.

**Terminal state arrives as a handoff.** The proof is published under
`state/<id>.handoffs/<n>`, built in a temporary directory beside it and moved into
place with one rename, so a reader sees a whole handoff or none. The watcher accepts
the next sequence in order, writes the status line, the event, the ledger state, and
the verified PR URL exactly once, then marks it consumed. Sequences are **retained
until teardown**, which owns their lifecycle: nothing else removes one, so a watcher
killed part-way through replays the same handoff instead of losing it. A
terminal-looking status line with no handoff behind it is ignored.

### 5.5 Spawn (`dux-spawn <id> [--harness claude]`)

`dux-task-new <project> <shape> [--source local|gh:<owner>/<repo>#<n>]`
allocates the id, creates `tasks/<id>/` with an empty `status.log`, and appends
the `queued` ledger line. `dux-brief <id> ...` renders the brief. `dux-spawn
<id>` does the rest; it reads project, shape, and source from the ledger.

Refuses, with a finding, when:

- the project is not registered;
- the resolved worktree path equals the primary checkout;
- the worktree is not based on freshly fetched `origin/<base>`;
- the backend is unavailable or an endpoint for the id already exists;
- the backend's `find <id>` (section 9) reports a container for the task, which
  means a worker may still be alive whatever the ledger and the brief say;
- `state/<id>.pid` exists and does not name a process that is gone: a pid that
  `kill -0` reaches is a live worker, and a file that cannot be read or does not
  hold a pid is an unanswered question, which refuses the same way;
- the lock is not held by this Dux session (`dux-lock mine`);
- the brief is missing or has no `- Worktree: ` line to fill;
- the chosen worker harness is unknown or is not dispatchable this milestone.

Whether a worker may still be alive is asked twice, of two independent signals,
and either one that cannot say "gone" is a refusal. The backend's `find` reads
back the container label both backends set, which answers for the backend Dux is
using right now and only while the label is what Dux wrote. `state/<id>.pid` is
written by the wrapper itself, inside the container, on every backend, so it
still answers after Dux restarts under the other backend and after someone
renames or moves the container. Neither replaces the other. Spawn writes no mark
of its own: a spawn killed before anything started would leave one no retry could
clear, and a cleanup after a failed `open` would clear one while a worker ran.
The pidfile is not that mark, because only a wrapper that reached the container
writes it and `dux-teardown` removes it. A recycled pid therefore refuses a spawn
that could have gone ahead, which costs one rescue, against two agents on one
branch in the other direction. Spawn fills whatever `- Worktree: ` line the brief
has, rather than only the placeholder, so a spawn killed after that line was
filled needs no hand edit.

Otherwise: `dux-worktree create <id>` (fetch, mechanism, discovery, tip check,
hooks dir, env-example copy for ship under the `git` mechanism), fill the brief's
worktree line, call the backend's `open` (section 9) with the single command
`<abs path>/bin/dux-worker-wrap <id>`, record the endpoint in
`state/<id>.endpoint` and the ledger, set `running`, and for a `gh:` source post
one issue comment (a failed comment is a warning, not a refusal, because the
worker is already running). If `open` fails, the brief's worktree line is
restored and the new worktree is removed (`dux-worktree discard`), so the task
stays `queued` and a retry is one command. The worktree is kept, and the failure
is a finding naming the endpoint, when `find` still reports a container: a
backend can start the command and fail afterwards, and nothing is cleaned up
around a live worker. The wrapper writes `state/<id>.pid` before starting the
harness.

The worker command comes from the harness adapter `bin/workers/<harness>.sh`
(section 19), never from this section. Milestone 2 dispatches `claude` workers
only. Spawn refuses `codex` with a finding wherever the name comes from (the
`--harness` flag, `config/worker-harness`, or `tasks/<id>/harness`): a Codex
worker has no deny list, so `git push --no-verify` skips the `pre-push` hook,
its one mechanical guard. Codex's separate role as the ship gate's code reviewer
is unchanged. The brief is the prompt, the project's
`CLAUDE.md` and the operator's global `CLAUDE.md` load normally under Claude, and
the harness's output goes to `state/<id>.out`. Every shape runs unattended
(`--dangerously-skip-permissions`) because a headless worker cannot answer
prompts and a denied tool call stalls the task. The blast radius is the worktree
plus `gh` and `codex` with the operator's credentials. It does not include the
project's live secrets: only committed env examples are copied, so no real
`.env` reaches a worker. Prompt rules are not the guard. Every Claude worker gets `--settings tasks/<id>/worker-settings.json`, rendered
from `templates/worker-settings.json` with deny rules `Bash(git push* <base>*)`,
`Bash(git push*:<base>*)`, `Bash(git push*--no-verify*)`,
`Bash(git*core.hooksPath*)`, `Bash(*GIT_CONFIG_COUNT*)`, `Bash(gh pr merge*)`,
`Bash(gh api*git/refs*)`, `Bash(gh repo delete*)`, `Bash(gh auth token*)`,
`Bash(gh secret*)`, and `Bash(gh api -X DELETE*)`. Claude Code documents that deny rules block in every
mode including bypass; milestone 2 break-verifies that against a real `claude`
before the milestone closes. The `pre-push` guard is a per-task hooks directory
`tasks/<id>/hooks/`: a symlink to every hook the project already has plus a
`pre-push` that refuses `refs/heads/<base>` and then runs the project's own
`pre-push` with the same input. `dux-worker-wrap` points every git the worker
runs at it through `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0=core.hooksPath` in the
worker's environment. Nothing is written into the project's `.git/config` or
`.git/hooks`. The Codex adapter ships and stays tested at the adapter level for a
later milestone: its sandbox is `danger-full-access` (a linked worktree's git dir
lives under the primary checkout, outside any workspace-write root) with
`shell_environment_policy.ignore_default_excludes` set so `GIT_CONFIG_KEY_0`
reaches git. The hook alone would be its only mechanical guard, which is why
dispatch refuses it.
These guards stop a mistaken push, not a worker that sets out to bypass them:
`--no-verify`, `git -c core.hooksPath=`, unsetting the environment, or the
forge API all get past them, which is why they are denied by rule and by the
brief, and why the worker's credentials are the operator's to bound.
Env files are copied only for `ship` tasks, never for `plan` or `scout`, and only
the project's committed `.env*.example` and `.env*.sample` files, renamed to the
name the project expects (`.env.example` to `.env`, `.env.local.example` to
`.env.local`). A real ignored `.env` is never copied, under any condition; the
two real projects run their tests off built-in defaults. An example the project
has not committed, or a destination name it does not ignore (which would leave
the worktree dirty and block teardown), is a finding and nothing is copied. The
copy is staged at `<dest>.dux-part` and renamed over `<dest>`, so a symlink at
either name is refused rather than written through: the worktree is checked out
at `origin/<base>`, which can carry a committed symlink at either one, and the
staging file is created with `O_EXCL` so the create cannot follow a link. A
project with no example gets no env file and one log line. Model via
`--model` per shape; effort via the CLI flag if this version exposes one,
otherwise a one-line system-prompt instruction in the brief.

### 5.6 Teardown (`dux-teardown <id>`)

Refuses when the lock is not held by this session, the ledger does not say
`done` or `failed` (a status line saying so is the worker talking about itself
and settles nothing), or the
worktree has uncommitted changes or unpushed commits. It reads `state/<id>.pid`
exactly as `dux-spawn` does, so the two agree about the same worker: absent is
the only reading that means no worker, while a file that cannot be read, one that
does not hold a pid, and one whose pid `kill -0` reaches all refuse. Otherwise
removes the worktree (`git worktree remove`, branch kept), closes the container
when it still exists, deletes `state/<id>.endpoint` and `state/<id>.pid`, clears
the run's retained references (`state/<id>.handoffs`, `state/<id>.run`,
`state/<id>.result-context`, `state/<id>.ship-receipt`), and marks `done` or
`failed` in `backlog.md` with the url the ledger already holds.
It then sets the ledger's `endpoint` to `-`, which is how the digest tells a
torn-down task from one awaiting merge. A worktree or container that is already gone is logged, not refused, so an
interrupted teardown completes on rerun. The task folder is kept.
For a `done` task with a PR from a `gh:` source, teardown posts one comment,
"Dux delivered PR <url>.", when the URL is in the source's repository; a
failed comment is a warning.

## 6. Supervision

### 6.1 Watcher (`dux-watch`)

A single bash process. `dux-lock acquire` stops the watcher named in
`state/watch.pid` only when that pid runs `dux-watch`; a stranger's pid is
reported and left alone. It starts `dux-watch` in its own process group through
bash job control (`set -m`, because macOS has no `setsid`) with output in
`state/watch.log`. The watcher writes its own pid to `state/watch.pid` and exits
before a pass when that file names another pid. `release` stops it the same way.
Acquire and release run from Claude Code `SessionStart` and `SessionEnd` hooks in
the repo's `.claude/settings.json`, not from a CLAUDE.md instruction, so an
orphaned watcher from a crashed session is replaced on the next start.

Every 30 seconds the watcher reads the last line of every running or stale
task's `status.log`, checks liveness, and appends `<iso8601Z> <state>: <id>` to
`state/events.log` only when:

- the last state changed to `done`, `failed`, `blocked`, or `needs-decision`;
- no new line for 20 minutes while the endpoint is alive (`stale: <id>`);
- the endpoint is gone without a terminal state (`dead: <id>`).

`working` lines never produce an event. Deduplication is "the status log's last
state differs from the ledger's state": the watcher itself updates `backlog.md`
when it emits, so a restart re-emits nothing already recorded and an event
written before a crash is still pending because the ledger still disagrees.
The watcher also raises the backend's local toast on every event, so local
visibility does not depend on a live Monitor.

The task-specific wrapper pid decides liveness in both directions, and the
container is supporting evidence. A pid that runs as `dux-worker-wrap <id>` is
alive even when the backend lost its window; a numeric pid that does not run as
that wrapper is gone even when a container remains. A backend that did not
answer, a missing container beside a live wrapper, and a missing endpoint beside
a live wrapper are logged as notes without changing the verdict. An unreadable
or nonnumeric pidfile is skipped as unknown. With no pidfile, the task is
starting during a short grace period and gone after it; with neither pidfile nor
endpoint it is skipped as unknown. The watcher logs the whole changed set of
notes and skipped questions once, then logs when every task answers again.
Process matching accepts the Dux command name only at the start of the command
line or after a path separator, and only when followed by a space or the end.
An unrelated command with a prefixed name is never trusted or signalled.

A `working` line after `stale` sets the ledger back to `running` without an
event and clears its acknowledgement. The silence clock uses the newest of the
status log's and pidfile's modification times, so a later silence produces a new
`stale` wake.

Truth order: `status.log` last line plus liveness is the truth; `backlog.md` is
derived and written only by scripts, never by Dux directly. `dux-status`
recomputes from the status logs when the two disagree and says so.

### 6.2 Wake

Dux arms one persistent Monitor on `tail -n0 -F state/events.log` before it reads
the startup digest. Each line wakes Dux once. Starting the Monitor first closes
the gap: the later digest finds events already written, and the Monitor catches
events written after it starts. After replacing a dead Monitor, Dux runs the
digest again for the same reason. On wake Dux reads the event state and id, then
uses `dux-notify` or `dux-recover` for worker-controlled text; those scripts cap,
strip, and fence what enters context. Events written while no Monitor was armed
are therefore not lost. Each ledger line carries `acked=<state|->`; Dux runs
`dux-ledger ack <id> <event-state>` after handling a wake. The command refuses
when the ledger has since moved to another state, leaving that newer event
unacknowledged. The watcher and `dux-recover --extend` clear the acknowledgement
when they return a stale task to `running`, so the same state can wake again
after new progress. `dux-status` lists every event-state task whose
acknowledgement differs.

Dux never reads `state/<id>.out` except inside `dux-recover`, and then only the
last 40 lines.

### 6.3 Notifications (`dux-notify`)

`dux-notify <id>` formats one line of at most 200 characters that leads with
what the operator would do (`Review and merge:`, `Decide:`, `Unblock:`, `Retry
or drop:`, `Check:`, `Classify:`) and prints it for Dux to pass to
PushNotification. Every word of it comes from the ledger: the state, the
project, the shape, the task id, and the PR url the ledger holds. A push has no
way to mark where a worker's words start and end, so it carries none of them;
the operator reads the worker's own account through `dux-recover`. Dux pushes for `done` with a PR link, `needs-decision`, and
`failed`. `blocked`, `stale`, and `dead` go to the digest, and push only if they
persist past one recovery attempt. The watcher raises the backend's local toast
when it emits; `dux-notify --toast` raises it again only where a push is
unavailable. Remote Control on the Dux session is how the operator replies from
a phone.

### 6.4 Recovery (`dux-recover`)

`dux-recover <id>` does the mechanical half; Dux keeps the judgment. Every call
first looks for a handoff the watcher has not consumed: a result that arrived
while the wake was in flight is reported and left exactly where it is, because
applying one is the watcher's job alone.

- `stale`: inspect prints whether the one extension was used, the last 5 status
  lines, and the last 40 lines of `state/<id>.out`. Worker-controlled lines have
  control characters stripped, are cut at 200 characters, and are fenced as
  data before they enter Dux's context. Dux judges progress. `--extend` appends
  `working: extended once by dux-recover`, then scans again for a terminal line
  that raced the extension. A terminal line wins even when the extension line
  was appended after it. Otherwise the extension restarts the silence clock and
  is the record that forbids a second extension.
  `--stop` checks the pid runs `dux-worker-wrap <id>` (a recycled pid is a
  finding, never a signal), sends SIGINT, and waits 60 seconds. A wrapper that
  published its result on the way out has spoken for the run and that stands;
  one that published nothing is marked `failed` with the last 20 output lines in
  `report.md`. A wrapper still alive after the wait is a finding and nothing is
  marked.
- `dead`: marks `failed`, saves the last 20 output lines to `report.md`, and
  keeps the worktree. A wrapper pid found alive is a finding: the task is not
  dead.
- `ended`: recovery runs the same `dux-result verify <id> <run>` the wrapper
  would have run, offering `report.md` as scout evidence only when it holds
  something other than a failure tail. What that proves is published into the
  next handoff sequence for the watcher to apply; recovery never writes the
  ledger or a url itself. An unproved result publishes nothing and says why,
  fenced as data. `--classify` takes `failed` and nothing else: `done` comes
  from the proof or not at all.
- `failed`, `blocked`, `needs-decision`: inspect prints capped, stripped, fenced
  status and failure text for Dux to relay.
  `--retry [--answer-file <f>]` allocates a new id, appends the answer (or the
  failure) to a copy of the Intent, renders the brief, records
  `tasks/<old>/retry` and `tasks/<new>/retried-from`, appends `failed:
  superseded by <new>` to a blocked or needs-decision task so teardown accepts
  it, and spawns. One retry per task; a failed task that is itself a retry is
  never retried automatically. The answer is required after `blocked` or
  `needs-decision`.

## 7. Session lifecycle

A `SessionStart` hook runs `dux-lock acquire` (pid from `CLAUDE_PID`) and prints
the result, including whether the watcher started, into context. AGENTS.md then
has Dux run `dux-doctor`, arm the Monitor, and run `dux-status --intake`, which
runs `dux-intake` for every project with issues enabled and then prints the
digest.
If the lock is held by a live pid, Dux announces it is read-only and skips spawn,
teardown, and recover. A `SessionEnd` hook releases the lock and kills the
watcher; workers keep running under the backend and are reconciled next start.

Dux is a long-lived session, which the operator's global "one session, one task"
rule does not allow by default. The written opt-out: Dux's task is supervision,
its state is entirely on disk, and it is restarted at least daily or after 40
wakes, whichever comes first. The digest at start makes the restart a non-event.

## 8. Fleet digest (`dux-status`)

Files and the backend only; no network unless `--prs` or `--intake` is given.
First a watcher line and the wake count since session start. Per project, six lines, with zero-count lines omitted:
queued; running, with stale and long-running counts in a suffix; awaiting you
(needs-decision, blocked); needs recovery (dead, ended); ready (done with a PR
or a report, not yet torn down); failed (not yet torn down). Long-running means
the task's `brief.md` is older than `DUX_LONG_RUNNING_SECS`, which defaults to
four hours. Every count comes from the ledger; a status log that reads finished
is a worker talking about itself and moves nothing until a proved handoff does.
Then an
`unacknowledged` block prints one `<state>: <id> (<project>)` line per task Dux
has not acknowledged. `--prs` adds `gh pr view` state per ready PR; a failed
`gh` is a warning, not a finding. `--intake` prints an `intake` block first:
each labelled project's intake output, or one `skipped:` line carrying the
finding when that project's intake failed, so one bad project never hides the
digest (section 14).

## 9. Runtime backends

One adapter interface, two implementations, selected once per Dux session.

Selection: `config/backend` if present; else `herdr` when `HERDR_ENV=1` and
`$TMUX` is unset; else `tmux`. The innermost multiplexer wins. `dux-doctor`
prints the resolved backend.

Interface, each a function in `bin/backends/<name>.sh`:

| Function | Contract |
|---|---|
| `open <id> <cwd> <cmd>` | start `<cmd>` in a new visible container labelled `dux-<id>`, print an opaque endpoint, never steal focus |
| `find <id>` | print the endpoint of the container labelled `dux-<id>`, or nothing when there is none; a backend that cannot tell raises a finding |
| `exists <endpoint>` | exit 0 if the container is present, 1 if the backend says it is gone, a finding when the backend did not answer; process liveness is the wrapper pid's job |
| `tail <endpoint> <n>` | print the last n lines of output |
| `close <endpoint>` | close only that container; refuse if it is the operator's focused pane |
| `notify <title> <body>` | local visual notice, no-op if unsupported |
| `report <id> <state> <message>` | mirror one status line to the container's UI; presentation only; tmux no-op |
| `title <title>` | set the container's sidebar title; tmux no-op |

tmux: a window per task in the Dux session, `tmux new-window -d -n dux-<id>`
with `remain-on-exit on`, so the window and its scrollback survive the worker's
exit until teardown. `exists` checks the window is present. `find` filters
`tmux list-windows -a` on the window name and never touches `_session`, which
would start a server to answer a question about it. A failed listing is read from
what the socket path is, never from tmux's error text alone: tmux says different
things on different platforms for the same path, and reading the wrong one as
"nothing is running" would let a second worker start on a branch that already has
one. A plain file at the socket path is `error connecting to <path> (Socket
operation on non-socket)` under tmux 3.6a on macOS and `no server running on
<path>` under tmux 3.4 on Linux. The socket path is
`${TMUX_TMPDIR:-/tmp}/tmux-<effective uid>/<name>`, where the name is the `-L`
value or `default`, and the three readings are:

- **No path.** No server has ever been reachable there, which is what every first
  spawn on a machine sees: no window.
- **A socket.** tmux looked through it, so `no server running` is the stale socket
  an exited server left behind, a normal state a spawn must not wedge on: no
  window. Every other failure there is a finding, because tmux did not look and a
  live server holding the worker reads the same way once its socket stops
  accepting.
- **Anything else.** A finding: something is wrong at the path and guessing is
  not allowed.

The worker in a server whose socket was removed outright reads as no window here
and is caught by `dux-spawn`'s `state/<id>.pid` check, which does not depend on
the backend.
`notify` is `tmux display-message`.

Herdr: a tab per task in Dux's own workspace, read live from
`HERDR_WORKSPACE_ID`, via
`herdr tab create --workspace $HERDR_WORKSPACE_ID --cwd <worktree> --label dux-<id> --no-focus`,
then `herdr pane run <root_pane> <cmd>`, where `<cmd>` is always one absolute
path plus the task id, so shell quoting and the operator's rc files cannot alter
it. `pane run` types into a live shell, so `open` waits for the pane's shell
prompt with `herdr pane wait-output` before running. The endpoint is the pane id
from the create response, never derived from labels. The one place a label is
read back is `find`, which asks `herdr tab list` for the tab whose `label` is
`dux-<id>` and then `herdr pane list` for that tab's pane, because the tab
listing carries no pane. It is not scoped to `HERDR_WORKSPACE_ID`: a tab moved to
another workspace still holds a live worker. A listing that fails, a listing
without the array it should have, more than one tab with the label, or a tab with
no pane is a finding, so "I could not tell" is never returned as "nothing is
running". `exists` is `herdr pane get`;
a pane outlives its process, which is why liveness comes from the pid file.
`tail` is `herdr pane read --source recent-unwrapped --lines n`. `close` is
`herdr pane close` on the exact recorded pane, never `workspace close`; a close
that fails is a finding, so teardown never records `done` with a leaked tab.
An `open` that gets past `tab create` and then fails closes what it made before
its finding: the pane it was given, or, when the create returned no pane id,
that create's own `tab_id` through `herdr tab close`. Nothing else is closed.
`notify` is `herdr notification show`.

Headless workers are not auto-detected by Herdr, so `dux-worker-wrap` mirrors
every new status line through `dux-backend report`, which on Herdr runs
`herdr pane report-agent $HERDR_PANE_ID --source dux --agent dux-<id> --state <s> --message <line>`
with `working` for working, `blocked` for needs-decision and blocked, and `idle`
for done and failed; it sets the title once through `dux-backend title`, which
on Herdr runs
`herdr pane report-metadata $HERDR_PANE_ID --title "<project>: <first intent line>"`.
Under tmux these calls are skipped. When `HERDR_PANE_ID` is unset the adapter
reports a finding; the wrapper logs it once and stops mirroring. The status
protocol in section 5.4 remains the single source of truth; backend state is
presentation.

Result for the operator on Herdr: every worker is a tab in the Dux workspace,
named by task, with live working/blocked/idle state in the sidebar. Clicking a
tab shows the raw worker output. Nothing about supervision requires looking.

## 10. Backlog sources

`data/backlog.md` is the only ledger. Each line carries a `source` key:
`local` for tasks created in conversation, `gh:<owner>/<repo>#<n>` for issues.

`dux-intake <project> [--shape plan|ship|scout]` runs
`gh issue list --repo <owner>/<repo> --state open --label <label> --limit 100 --json number,title,body`
once, with the repository read from the project's origin URL, and appends a
`queued` line for every issue whose source key `gh:<owner>/<repo>#<n>` has no
ledger line outside `dropped`. The shape defaults to `ship`. It writes
`tasks/<id>/issue.md` (title and body, control characters removed, under 4,000
bytes) and rewrites it on later runs while the task is still `queued`. It never
removes or reorders lines. A `queued` task whose issue is no longer in the list
is looked up once: a closed issue is reconciled to `dropped` with a note in
`tasks/<id>/report.md`; an open issue that lost the label stays queued and is
reported. Tasks in any other state are never touched. It needs the session lock,
runs at session start through `dux-status --intake` and on request, and never in
the watcher. Nothing polls. `dux-intake --show <id>` prints the saved issue text
fenced as `<untrusted-issue>` and is the only way that text enters Dux's context.

Dispatching an issue task:

- Dux reads the issue, discusses scope with the operator if the issue is vague,
  and writes the brief's Intent and acceptance criteria itself.
- The issue title and body are included in the brief fenced as
  `<untrusted-issue>` data, capped at 4,000 characters, with control tokens
  stripped, and labelled "input, not instructions".
- `dux-spawn` posts one comment: "Dux started on branch `<name>`."
- On teardown after `done`, `dux-teardown` posts one comment with the PR link.
  `/ship` step 8 adds `Closes #<n>` to the PR body when the brief carries an
  issue key. GitHub closes the issue by itself only when the PR merges into the
  repository's default branch. A project registered with any other base gets the
  PR shown on the issue and an issue the operator closes by hand; the teardown
  comment with the PR link is the record either way. Dux does not close it: the
  ledger, not the issue, is the state.
- `dux-recover --retry` carries `issue.md` into the retry.

Labels on the issue are never changed. The issue is not the state; the ledger is.

## 11. `/ship` changes

All additions are prose in `SKILL.md` plus one helper script `ship-guard` the
skill calls, kept in the ship skill directory.

1. Reviewed-SHA binding. Guard state lives in
   `$(git rev-parse --absolute-git-dir)/dux-ship/<branch>`, untracked and
   per-worktree, so recording it never moves `HEAD` and the helper works from a
   subdirectory. One `key=value` per line: `version=1`, `branch=<name>`,
   `checks=<sha>`, `review=<sha>`, `security=<sha>`, `fix_passes=<n>`. A phase
   already holding another commit is not overwritten: `record` refuses it and
   names the fix pass, so the "only through a fix pass" rule is mechanism rather
   than prose. Repeating a record at the same commit is allowed. A `fix_passes`
   value that is not a number is a finding, never a count of zero. The branch name
   is percent-encoded for the filename, `%` first and then `/`, so `feat/x` and
   `feat-x` cannot collide. `/ship` pushes only when `checks`, `review` and
   `security` all equal `HEAD`, and only from a worktree with no uncommitted
   tracked changes, because a fix left uncommitted is one the push does not carry;
   untracked files are ignored, since a supervised ship worktree carries env files
   the repository never tracks; the accepted cost is that a fix delivered as a
   brand-new file nobody staged still passes, which the checks in step 4 are the
   place to catch. `record` refuses by naming the fix pass alone: `open` would
   clear the phases and zero the count, so offering it at a refusal would hand
   back the dodge. A `git status` that errors is a stop, not a clean tree, and a
   `fix_passes` line that is missing is a finding like one that is unreadable. Commits made after a phase was recorded reach a
   push only through a fix pass and a recording of each cleared phase again.
2. Head continuity. Six verbs, the whole interface: `ship-guard open` in step 0,
   `record <phase>` after steps 4, 6, 7, `check <phase>` before 6, 7, 8 naming the
   previous phase, `fix-pass`, `attest` in step 8 (change 8), and `push-ok`
   before every push and before
   `gh pr create`. Exit 0 success, 1 unexpected, 2 finding, findings on stderr. A
   backward or divergent `HEAD` stops the gate, tested by `record` as well as by
   `check`. `record review` is refused unless `checks` is recorded and `record
   security` unless `review` is, so a skipped phase is a stop rather than a gap.
   Every verb but `open` refuses when the file's `branch=` is not the current
   branch, so a branch renamed mid-gate says so instead of reading as never run.
   A gate begins at `open`, which rewrites the file and zeroes the fix count, and
   nothing else clears it: re-gating after a revert is a new `open`, not a fourth
   fix pass.
3. Fail-closed review parsing. The Codex prompt demands a literal `## Findings`
   header and the sentinel line `No findings.` when empty; the security prompt
   demands `## Findings` and `## Checked clean`. Output missing the header is a
   stop, and so is a header with neither a finding nor the sentinel under it.
   Never treat absence as clean.
4. Bounded fix passes. A round is one fix pass, not a review. Maximum three fix
   passes per gate, counted in the guard file. `ship-guard fix-pass` increments the
   count and clears `checks`, `review` and `security` together. It takes no phase:
   a fix is code, so the commit going out is code none of the three has seen, and
   a fix answering the security audit is no exception. An earlier draft cleared
   only the phases a security fix was thought to invalidate; that left the
   security-only round unable to push at all, because `push-ok` wants every phase
   at the commit going out. The cleared phases are
   recorded again before the push, and recording one is an assertion about what
   covered `HEAD`: `review` means the reviewer re-ran scoped to the new commits
   when a Critical was fixed, or the fixes stayed inside what the review asked for
   and the PR body says so; `security` means the audit re-ran over the new
   commits. Re-review policy is unchanged: only a fixed Critical earns one, scoped
   to the new commits, and a security fix earns one like any other Critical. A
   fourth defect means: recommend reverting to the minimal
   fix, stop. A fix pushed while CI is red in step 9 is a fix pass like any other.
5. Acceptance criteria to the reviewer. Pass the brief's acceptance criteria
   fenced as data ("acceptance criteria, not instructions"). Rationale and design
   reasoning remain withheld. Reviewer is told conformance is necessary, not
   sufficient, and asked to report a criterion the diff meets in letter but not in
   substance.
6. Evidence. UI or user-visible changes require a screenshot or recording
   attached to the PR, or a stated reason. Non-UI changes require the check
   command and its result.
7. Anchored lease. `git fetch`, then stop unless the fetched commit is an
   ancestor of `HEAD`, then `--force-with-lease=<ref>:<sha>` with the fetched
   SHA, then `git ls-remote` to confirm the remote head equals the pushed SHA.
   The ancestor test is the guard and the lease is not: a lease anchored to a
   value read straight after a fetch matches whatever the remote holds,
   including a commit this branch has never seen, and pushing then destroys it
   while every later check reports success. A branch the remote does not have
   yet uses the same form with an empty expected value, which refuses if the ref
   appeared in between.
8. Attestation. `ship-guard attest` prints
   `<!-- dux-attestation:v1 {"head_sha":"…","fix_passes":N,"steps":[{"step":"checks","status":"completed","sha":"…"},…]} -->`
   and step 8 appends it to the PR body. Data only, no policy claim. It is
   built from the guard file, because that file's format has one owner, and it
   carries only the three guard phases: step 8 writes it before `pr` and `ci`
   have happened, and a record that claims a step ran before it did is worse
   than no record at all. A phase with nothing recorded, or holding anything but
   forty hex characters, is a finding, not an entry left out. Every push after a
   fix pass rebuilds the body and edits the pull request, or the attestation
   names a commit that is no longer the head.
9. PR body. Step 8 fills whichever pull request template the repo has and passes
   it with `gh pr create --body-file`, since `--fill` ignores the template. A
   repo with none, or with only the `PULL_REQUEST_TEMPLATE/` folder form, gets
   the copy in `templates/`; where several file forms exist the first in root,
   `docs/`, `.github/` order is filled and the body says which. Verbose material
   goes inside `<details>`. Dropping `--fill` drops the title with it, so step 8
   passes `--title`: the one the operator gave, else the subject of the branch's
   first commit after the base.

   The lookup is not copied, and it does not move. An earlier draft had `/ship`
   carry its own copy, on the grounds that it cannot call `bin/dux-project`. It
   can: `skills/ship/ship-env` resolves the Dux checkout before it answers
   anything, so `<root>/bin/dux-project pr-template <repo>` is reachable, and
   `ship-env pr-template` delegates to it. `find_templates` therefore stays
   where section 12 put it, with one implementation, no move of reviewed code,
   and no dependency from `bin/` into `skills/`. A non-zero exit from the
   delegate is a finding in `ship-env`, never empty output: empty means the repo
   has no template, and a lookup that failed must not be read as one.

The ship skill is bundled in this repo at `skills/ship/` from milestone 1 and
installed by `dux-install` (section 18), so this is an ordinary PR with a diff
Codex can review and commits that can carry break-verification.

`ship-guard` sits beside `SKILL.md` rather than under `bin/`, because
`dux-install` symlinks the skill directory and the helper travels with it, and
because `/ship` runs inside a project worktree that knows nothing about
`DUX_HOME`. It sources nothing and defines its own `finding`. Step 0 resolves it
once into `$SHIP_GUARD`: an already set `SHIP_GUARD`, else
`~/.claude/skills/ship/ship-guard`, else `~/.agents/skills/ship/ship-guard`. When
none is executable the gate stops; it never runs unguarded, and a `SHIP_GUARD`
that is set but not executable stops it too rather than falling through to the
next candidate, so a typo cannot silently run a different guard. Unlike
`DUX_SHIP_RECORD`, which is set only under Dux, the guard runs on every `/ship`.
`bin/dux-result` does not read the guard file and `verify` is unchanged: it
proves the five phases ran in order and that `ci` was recorded at the head, not
that a review covered that head. The review-covers-head proof lives in the guard
file only. A worker that skips the helper altogether is the trust boundary in
section 6, not something a local file can settle. Teaching the receipt to carry
the guard's verdict is a change to section 5.6 for a later milestone.

`skills/ship/ship-env` sits beside it for the same reasons and answers the
questions the gate has about the Dux checkout it was installed from: the step 6
reviewer, the step 7 reviewer, and the pull request template lookup and its
fallback. It finds that checkout by resolving its own directory through
`dux-install`'s symlink and taking the two levels above it; a checkout is one
whose `templates/config` is a directory, and anything else stops the gate. So a
skill copied rather than installed stops it, unlike `ship-guard`, which needs
nothing but the repository it is run in and keeps working when copied. Step 0
derives `SHIP_ENV` from `SHIP_GUARD`'s directory, so one override points both
helpers at one checkout. A value comes from `config/<key>` and falls back to
`templates/config/<key>`, which is what lets a fresh clone run the gate before
anyone has run the installer; there is no environment override, since
`dux-worker-wrap` scrubs every `DUX_*` variable but three from a worker. The
`security-reviewer` value is either `agent:<name>`, meaning dispatch that agent
on this host, or a command line the audit prompt is appended to. A host that
cannot dispatch agents stops on an `agent:` value and names the config file:
falling back to some other reviewer would be the silent degradation the rest of
this section exists to remove.

Both reviewer defaults are the word `auto`, and `auto` means `ship-env` chooses
the command when the gate runs, from what the host has. For the code review that
is codex when `codex` is on `PATH`, otherwise Claude Code with Fable in plan
mode, which reads the tree and the diff and can change neither. For the security
pass it is `agent:security-reviewer` when a definition for that agent is in the
user's own Claude agents directory, otherwise the same Claude command line. That
directory is the only one read. The project the gate runs in is the repository
whose diff is being audited, and Claude Code would prefer a definition committed
there, so a branch carrying `.claude/agents/security-reviewer.md` would be
appointing and writing its own auditor. Workers are untrusted by construction,
which is exactly who would write that file. With neither available `ship-env` stops the gate and names the
config file, which is a better failure than a command that is not there.

The choice is made again on every run and never written to disk. Deciding it
once, when `bin/dux-install` runs, would freeze it: the installer never
overwrites an existing `config/` file, so a machine that installs codex a week
later would keep the wrong default forever, which is the shape of the
install-time denylist defect this repository has already fixed once. It also
cannot be decided reliably at install time, since `codex` may reach `PATH` only
through a shell the installer was not run from.

This does not reopen the silent degradation the paragraph above closes, on three
counts. The probe never overrules a stated value: an explicit `agent:` on a host
that cannot dispatch agents still stops the gate, exactly as before. It runs only
where nobody has stated anything, where the alternative is not a better reviewer
but a command that does not exist. And it is inspectable in both directions:
`ship-env reviewer` prints the choice before the gate runs, and step 6 requires
the pull request to name the reviewer that actually ran. A degradation the
operator can read on the pull request is not a silent one. The cost is a probe
that can be wrong in one direction: an agent supplied by a plugin is invisible to
a shell, and one a project defines for itself is deliberately not looked at, so
either host gets the command line instead. The cure for both is one line in
`config/security-reviewer`, which belongs to the operator and is never probed.

The two recorders have different rules and the skill keeps their calls apart.
`$DUX_SHIP_RECORD <phase>` runs once per phase per gate and is never repeated:
`record-ship` refuses a repeated or out-of-order phase, so a second call stops a
supervised gate. `ship-guard record <phase>` is the one that repeats after a fix
pass, and only after one: it refuses a phase that already names a different
commit.

The nine changes are too much for one session under the size cap (constitution
principle 1), so they ship as two milestones. Milestone 5 takes 1 to 5, the guard
and what it bounds. Milestone 6 takes 6 to 9, plus the move of the reviewer
commands and per-shape models into `config/` with defaults in `templates/config/`,
so the skill works for anyone who installs Dux.

Not ported: hook enforcement, CI auto-repair, transient reruns, evidence branch.

## 12. PR template

Installed by `dux-project` only when the operator says so and only when the repo
has none. `dux-project pr-template <path>` lists what a repo already has: GitHub
reads a template from the repository root, from `docs/` and from `.github/`, in
any letter case, with any extension, and as a `PULL_REQUEST_TEMPLATE/` folder of
several. `/ship` asks the same question through `skills/ship/ship-env`, which
delegates to this subcommand rather than reimplementing it, so the two cannot
disagree about what a repo has (section 11 change 9). An existing template is left alone and its path reported, and Dux never
adds a second one beside it.

That last rule is a decision, taken 2026-09-08 and recorded in
`docs/plans/2026-09-08-pr-template-consent.md`. GitHub's documentation does not
say which template wins when a repo has more than one, so a second template is a
guess about which one a person opening a pull request in the browser would see.
The operator who wants this template in a repo that already has one copies it
across by hand.

The installed file is untracked in the primary checkout and invisible to
worktrees cut from `origin/<base>`, so `dux-project` says so and the operator
commits it, or Dux dispatches a docs-only task to land it. `/ship` falls back to
the copy in `templates/` when a repo has none.

```markdown
## Why
One or two sentences. Problem and link to the plan or issue.

## What changed
- User-visible first, then internal. Flag anything surprising.

## How to review
Suggested file order. What needs thought, what is mechanical.

## Verification
- Checks: command and result
- Evidence: screenshot or recording for UI, or why none
- Break-verification: which guard was broken, the failure it printed

## Reviews
- Codex (model): N findings, fixed / logged
- Security: areas clean, findings
<details><summary>Full findings</summary></details>

## Risk
Low | Medium | High, one-line rationale. Backwards compatibility, deploy
ordering, deferred follow-ups.
```

## 13. Token budget

| Consumer | Rule |
|---|---|
| Dux always-loaded | CLAUDE.md <= 150 lines; skills on demand; digest 4 lines per project |
| Dux per wake | one event line + <= 5 status lines; target < 2k tokens |
| Dux idle | zero; Monitor and bash wait |
| Dux lifetime | restart daily or after 40 wakes; each wake re-reads the whole context at cache rates |
| Brief | <= 60 lines; no conversation history |
| Worker | owns its cost; one task per session; model per shape |
| Reviews | unchanged: one Codex review, one security pass, inside `/ship` |

Blocked anti-patterns: Dux reading worker output outside `dux-recover`; workers
receiving anything beyond the brief file and their project's own instructions.

## 14. Error handling summary

| Condition | Behavior |
|---|---|
| Worker fails | preserve worktree and branch; tail to report.md; offer retry or scout |
| Worker stale | one extension, then SIGINT, then failed |
| Same obstacle twice | worker writes blocked and stops (brief rule) |
| Spawn precondition unmet | refuse with finding |
| Teardown on dirty or unpushed | refuse with finding; never bypass |
| Dux restarted mid-task | reconcile from files and backend; workers unaffected |
| Backend unreachable | spawn and teardown refuse; watcher uses the wrapper verdict and logs the changed open-question set once |
| Issue intake fails | skip with one warning; backlog unchanged |
| Issue intake finds a closed issue that was already dispatched | nothing; the PR closes or references it |
| Second Dux session | read-only, announced |
| Monitor dies | AGENTS.md start-of-turn rule: if no monitor is armed and tasks are running, re-arm |

## 15. Testing

- One bats file per script. A fake `claude` on `PATH` that replays a scripted
  status sequence and exit code. A fake `herdr` and a real tmux server in a
  named test session, so both adapters run the same adapter test file.
- End-to-end: spawn against a throwaway repo, fake worker emits working, done;
  watcher emits one event; teardown succeeds. Second run: fake emits nothing,
  watcher emits stale after the threshold (threshold configurable via env for
  tests).
- Every refusal path in `dux-spawn` and `dux-teardown` has a test that reaches it.
- Each test is break-verified once: the guarded condition is broken, the failure
  is pasted into the commit, then restored.
- Skills are dry-run against the throwaway repo before the milestone closes.
- Intake: a fixture of `gh issue list` JSON drives it; idempotence runs intake
  twice; reconciliation runs it with an issue removed and the fake `gh`
  answering CLOSED, then OPEN.
- `/ship` additions: each new guard broken once with the failure pasted into the
  commit.

## 16. Milestones

1. Skeleton: repo, CLAUDE.md, registry, `dux-doctor`, `dux-lock`, `dux-project`,
   PR template, backend adapters with the shared adapter test, tests harness
   with fake claude and fake herdr.
2. Dispatch: `dux-brief`, `dux-worktree`, `dux-spawn`, `dux-worker-wrap`,
   `dux-teardown`, `dux-dispatch` skill, end-to-end happy path on both backends.
3. Supervision: `dux-watch`, Monitor arming, `dux-status`, `dux-notify`,
   `dux-recover`, stale and dead paths.
4. Intake: `dux-intake`, registry `issues` field, issue fencing in briefs, start
   and done comments.
5. `/ship` guard: section 11 changes 1 to 5, break-verified. Reviewed-SHA
   binding, head continuity, fail-closed review parsing, bounded fix passes,
   acceptance criteria to the reviewer.
6. `/ship` stands alone: section 11 changes 6 to 9, plus the reviewer commands
   and per-shape models into `config/`. Evidence, anchored lease, attestation,
   PR body, and a fresh-clone dry run.
7. Dogfood: register fitfights_api and fitfights_ios, run one scout and one ship
   task each, one from a GitHub issue, fix what breaks.
8. Codex as orchestrator harness: `bin/dux` launcher, `bin/dux-wait`, the
   `AGENTS.md` fallback lines, the notify fallback, and a hand-run verification
   transcript (section 19).

Each milestone is its own session and PR, per the operator's one-session rule,
and is sized against the cap before its plan is written (constitution principle
1). Task granularity and the sizing procedure are in
`docs/plans/2026-09-03-dux-roadmap.md`.

## 17. Decisions already made

- Name: Dux (Latin, leader; root of conductor).
- Workers headless, Dux interactive.
- Backlog ledger is local markdown. GitHub Issues are an intake source per
  project, pulled on demand, never the ledger.
- Herdr and tmux are both supported through one adapter interface; auto-detected,
  overridable.
- Worktrees use the project's mechanism, not `herdr worktree create`, so worktree
  lifecycle does not depend on the terminal backend.
- No worker inbox in v1. Blocked and needs-decision always resolve by retry with
  the answer in the brief. A bidirectional worker (`--input-format stream-json`)
  is a later milestone if retries prove costly.
- The ship skill is bundled in this repo and installed by symlink.
- Dux is open source under the MIT license. The operator's personal rules stay in
  their global CLAUDE.md; the repo encodes them only as configurable defaults.
- `finding` writes to stderr so command substitution can never swallow it.
- Approach A (agent distro) over native-only or a daemon.
- PR template lives in each repo, filled by `/ship`, not in global CLAUDE.md.

## 18. Distribution

Dux is an open-source agent distro under the MIT license. The repo is the
product; there is no build or package.

- **Bundled**: every skill under `skills/` (`ship`, `dux-project`,
  `dux-dispatch`, `dux-status`, `dux-recover`), every script under `bin/`, and
  every default under `templates/`.
- **Personal, gitignored**: `data/`, `state/`, `config/`. `templates/config/`
  holds the defaults `dux-install` copies into `config/` on first run:
  `reviewer` and `security-reviewer` (both default to `auto`, which `ship-env`
  resolves against the host at gate time: codex or Claude Code for the code
  review, the `security-reviewer` agent or Claude Code for the security pass,
  and a finding naming the file when there is neither), `models` (per shape),
  `backend` (empty means auto-detect). `/ship` reads the two reviewer files
  through `skills/ship/ship-env`, which falls back to `templates/config/` so the
  gate runs before the installer has. An explicit value in either file is never
  probed. `models` is read by `bin/dux-worker-wrap` for
  workers; the gate does not use it.
- **Install**: `bin/dux-install` symlinks each bundled skill into
  `~/.claude/skills/<name>`. An existing real directory there is refused until
  the operator confirms, then moved to `<name>.bak`. `bin/dux-uninstall` removes
  only symlinks that point into this repo. Updating the repo updates the skills.
- **No personal identifiers in tracked files**: no operator paths, usernames,
  project names, or accounts. `make lint` greps for two gitignored denylists
  that `dux-install` writes: `tests/personal-identifiers.txt`, the operator's
  home path and registered project names, matched as substrings; and
  `tests/personal-names.txt`, the account name and home directory name, matched
  as whole words. Two kinds of registered name are left out, and the installer
  says so each time: the project whose repository is the checkout being
  installed into, and any name shorter than four characters, which would match
  nearly every file. The first is left out on the identity of the repository, not
  on the name: for Dux's own name there is nothing to leak, since it is the
  repository's name in the README and in every script, and for an alias the
  operator chose for this checkout the install says on every run that it is not
  being checked. Registering this checkout under a name that must not appear in
  its tracked files is therefore not protected against. A short name gets no lint
  coverage until it is registered under a longer one with
  `dux-project add --name`.
- **The operator's global rules stay global.** `/ship` must stand alone for a
  stranger: every rule it depends on is either in its own text or a config
  default. The operator's global CLAUDE.md may be stricter, never required.

## 19. Harness support

Dux separates the harness that runs the orchestrator from the harness that runs
workers. They are supported at different levels.

**Workers** are a command in a container plus a brief plus a status file, so
any harness that can run bash works. `bin/workers/<harness>.sh` provides
`worker_cmd <brief> <model> <effort> <settings>`, which prints the command line
for logs and tests, `worker_run` with the same arguments, which execs it (no
`eval` anywhere), and `worker_effort_ok <effort>`. Claude Code: `claude -p
"<brief>" --model <m> --effort <e> --dangerously-skip-permissions --settings
<settings> --output-format stream-json --verbose`. Codex: `codex exec -m <m>
--sandbox danger-full-access -c
shell_environment_policy.ignore_default_excludes=true -c
model_reasoning_effort="<e>" "<brief>"`. Models and efforts come from
`config/models` (Claude) or `config/models-codex` (Codex), one `shape=model:effort`
token per shape. The
default worker harness is `claude`; `config/worker-harness` overrides it and
`dux-spawn --harness` overrides per task. Both harnesses read the brief's rules, and the project's
`AGENTS.md` (Codex) or `CLAUDE.md` (Claude Code) load as usual. Milestone 2 ships
both adapters but dispatches `claude` workers only: the deny list is a Claude
Code feature, so a Codex worker's one mechanical guard would be the `pre-push`
hook and `git push --no-verify` skips it. `dux-spawn` and `dux-worker-wrap`
refuse `codex` with a finding; the Codex adapter stays correct and tested at the
adapter level for a later milestone, and Codex's role as the ship gate's code
reviewer is unaffected. The end-to-end test runs on each backend with a `claude`
worker, plus one case that asserts the refusal.

**The orchestrator** depends on five harness features. The layout is
harness-neutral from milestone 1 (`AGENTS.md` canonical, `CLAUDE.md` an import,
skills with frontmatter both harnesses read). Behavior parity is not:

| Feature | Claude Code (verified, v1) | Codex (milestone 8) |
|---|---|---|
| Wake on event | Monitor tool; zero tokens idle | `bin/dux-wait` blocks until the next event, then returns; Codex calls it in a bounded loop |
| Phone push and reply | PushNotification and Remote Control | local toast plus optional webhook; no reply path |
| Session hooks | SessionStart / SessionEnd | `bin/dux` launcher wrapper acquires the lock, runs the harness, releases on exit |
| Session pid | `CLAUDE_PID` | the launcher's own pid |
| Instructions and skills | `CLAUDE.md` import, `/skill` | `AGENTS.md`, `$skill` |

The README lists verified orchestrator harnesses. A harness is verified only
when `tests/harness/<name>.md` has been run through by hand on a real
installation and the transcript is committed. Unverified harnesses are not
refused, but `dux-doctor` says "orchestrator harness not verified" and the
Monitor-dependent steps in `AGENTS.md` carry a fallback line.
