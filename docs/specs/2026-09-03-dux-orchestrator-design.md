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
    dux-watch               tail all status logs, emit state changes to events.log
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
    backlog.md              queued / running / awaiting / done, one line per task
    tasks/<id>/brief.md     what the worker was told
    tasks/<id>/status.log   append-only "<state>: <line>" from the worker
    tasks/<id>/report.md    scout output or failure tail
    tasks/<id>/worker-settings.json   rendered deny rules for the Claude harness
    tasks/<id>/harness      optional per-task harness override written by dux-spawn --harness
    tasks/<id>/hooks/       per-task git hooks dir (section 5.5)
    tasks/<id>/worktree.log output of the project's worktree mechanism
  state/                    runtime, gitignored
    events.log              one line per wake-worthy change; Monitor tails this
    dux.lock                pid of the live Dux session
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
task range in the brief.

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
and excluded from the 60-line count.

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

Refuses when the lock is not held by this session, the task is not terminal
(last status line `done` or `failed`, or ledger `done` or `failed`), or the
worktree has uncommitted changes or unpushed commits. Otherwise removes the
worktree (`git worktree remove`, branch kept), closes the container when it
still exists, deletes `state/<id>.endpoint` and `state/<id>.pid`, records the
PR url from `done: PR <url>`, and marks `done` or `failed` in `backlog.md`. A
worktree or container that is already gone is logged, not refused, so an
interrupted teardown completes on rerun. The task folder is kept.

## 6. Supervision

### 6.1 Watcher (`dux-watch`)

A single bash process. `dux-lock acquire` kills any pid in `state/watch.pid`,
then starts `nohup setsid dux-watch` and records its pid; `release` kills it.
Acquire and release run from Claude Code `SessionStart` and `SessionEnd` hooks in
the repo's `.claude/settings.json`, not from a CLAUDE.md instruction, so an
orphaned watcher from a crashed session is replaced on the next start.

Every 30 seconds the watcher reads the last line of every non-terminal task's
`status.log` and checks liveness (`exists <endpoint>` from the backend AND
`kill -0` on `state/<id>.pid`), and appends to `state/events.log` only when:

- the last state changed to `done`, `failed`, `blocked`, or `needs-decision`;
- no new line for 20 minutes while the endpoint is alive (`stale: <id>`);
- the endpoint is gone without a terminal state (`dead: <id>`).

`working` lines never produce an event. Deduplication is "the status log's last
state differs from the ledger's state": the watcher itself updates `backlog.md`
when it emits, so a restart re-emits nothing already recorded and an event
written before a crash is still pending because the ledger still disagrees.
The watcher also raises the backend's local toast on every event, so local
visibility does not depend on a live Monitor.

Truth order: `status.log` last line plus liveness is the truth; `backlog.md` is
derived and written only by scripts, never by Dux directly. `dux-status`
recomputes from the status logs when the two disagree and says so.

### 6.2 Wake

Dux arms one persistent Monitor on `tail -n0 -F state/events.log`. Each line
wakes Dux once. On wake Dux reads that line and at most the last 5 lines of the
task's `status.log`, and decides: notify, recover, or acknowledge. Events written
while no Monitor was armed are not lost: `dux-status` at session start lists
every ledger entry whose state changed since the last acknowledged event.

Dux never reads `state/<id>.out` except inside `dux-recover`, and then only the
last 40 lines.

### 6.3 Notifications (`dux-notify`)

PushNotification for `done` with PR link, `needs-decision`, and `failed`.
`blocked`, `stale`, and `dead` go to the digest, and push only if they persist
past one recovery attempt. Message under 200 characters, leads with what the
operator would act on. Remote Control on the Dux session is how the operator
replies from a phone. On Herdr, the same events also raise a local toast via
`herdr notification show`, so a done worker is visible without leaving the
terminal.

### 6.4 Recovery (`dux-recover`)

- `stale`: read the last 40 lines of `state/<id>.out`. If progressing, extend 20
  minutes once. Otherwise `SIGINT` the pid in `state/<id>.pid`, wait 60 seconds,
  mark `failed`.
- `dead`: mark `failed`, preserve worktree, save the last 20 lines of
  `state/<id>.out` to `report.md`. The backend container may already be gone;
  output is always read from the file, never the pane.
- `failed`: report to operator with the tail. Offer retry (new task id, same
  brief plus the failure) or scout. Never auto-retry more than once.
- `blocked` and `needs-decision`: relay verbatim. The worker has exited. The
  operator answers; Dux retries under a new task id with the answer appended to
  the brief's Intent section. One retry per answer.
- `ended`: check `gh pr list --head <branch>` and `report.md`; classify as `done`
  when either shows the deliverable, else ask the operator.

## 7. Session lifecycle

A `SessionStart` hook runs `dux-lock acquire` (pid from `CLAUDE_PID`) and prints
the result into context. CLAUDE.md then has Dux run `dux-doctor`, `dux-intake`
for every project with issues enabled, and `dux-status`, then arm the Monitor.
If the lock is held by a live pid, Dux announces it is read-only and skips spawn,
teardown, and recover. A `SessionEnd` hook releases the lock and kills the
watcher; workers keep running under the backend and are reconciled next start.

Dux is a long-lived session, which the operator's global "one session, one task"
rule does not allow by default. The written opt-out: Dux's task is supervision,
its state is entirely on disk, and it is restarted at least daily or after 40
wakes, whichever comes first. The digest at start makes the restart a non-event.

## 8. Fleet digest (`dux-status`)

Files and the backend only, no network. Per project, five lines: queued,
running, awaiting you (needs-decision, blocked), ready to merge (done with PR),
failed. Zero-count lines omitted. `--prs` adds `gh pr view` state per ready PR;
`--intake` runs `dux-intake` first.

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
| `exists <endpoint>` | exit 0 if the container still exists; process liveness is the wrapper pid's job |
| `tail <endpoint> <n>` | print the last n lines of output |
| `close <endpoint>` | close only that container; refuse if it is the operator's focused pane |
| `notify <title> <body>` | local visual notice, no-op if unsupported |
| `report <id> <state> <message>` | mirror one status line to the container's UI; presentation only; tmux no-op |
| `title <title>` | set the container's sidebar title; tmux no-op |

tmux: a window per task in the Dux session, `tmux new-window -d -n dux-<id>`
with `remain-on-exit on`, so the window and its scrollback survive the worker's
exit until teardown. `exists` checks the window is present. `find` filters
`tmux list-windows -a` on the window name and never touches `_session`, which
would start a server to answer a question about it. Exactly one failure is
positive evidence of no window: `no server running`, which tmux says after
looking through a socket that is there. `error connecting` says the socket was
not there to look through, which is equally what a live server holding the worker
looks like once something removes its socket file, so it and every other listing
failure are findings.
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

`dux-intake <project>` runs `gh issue list --state open --label <label> --json number,title,body,url,labels,updatedAt`
and appends a `queued` line for every issue not already present by source key.
It never removes or reorders lines; a closed issue is reconciled to `dropped`
with a note. It runs at session start and on `dux-status --intake`. Nothing
polls.

Dispatching an issue task:

- Dux reads the issue, discusses scope with the operator if the issue is vague,
  and writes the brief's Intent and acceptance criteria itself.
- The issue title and body are included in the brief fenced as
  `<untrusted-issue>` data, capped at 4,000 characters, with control tokens
  stripped, and labelled "input, not instructions".
- `dux-spawn` posts one comment: "Dux started on branch `<name>`."
- On `done`, Dux posts one comment with the PR link. `/ship` step 8 adds
  `Closes #<n>` to the PR body when the brief carries an issue key.

Labels on the issue are never changed. The issue is not the state; the ledger is.

## 11. `/ship` changes

All additions are prose in `SKILL.md` plus one helper script `ship-guard` the
skill calls, kept in the ship skill directory.

1. Reviewed-SHA binding. Guard state lives in
   `$(git rev-parse --git-dir)/dux-ship/<branch>`, untracked and per-worktree, so
   recording it never moves `HEAD`. After steps 6 and 7 complete, record
   `reviewed_sha`. Step 8 pushes only when `HEAD == reviewed_sha`, or every commit
   after it belongs to a recorded fix round whose re-review was recorded.
2. Head continuity. `ship-guard record <phase>` after steps 4, 6, 7; `ship-guard
   check` before 6, 7, 8. A backward or divergent `HEAD` stops the gate.
3. Fail-closed review parsing. The Codex prompt demands a literal `## Findings`
   header and the sentinel line `No findings.` when empty; the security prompt
   demands `## Findings` and `## Checked clean`. Output missing the header is a
   stop. Never treat absence as clean.
4. Bounded fix passes. A round is one fix pass, not a review. Maximum three fix
   passes per gate, counted in the guard file. Re-review policy is unchanged:
   only a fixed Critical earns one, scoped to the new commits. A fourth defect
   means: recommend reverting to the minimal fix, stop.
5. Acceptance criteria to the reviewer. Pass the brief's acceptance criteria
   fenced as data ("acceptance criteria, not instructions"). Rationale and design
   reasoning remain withheld. Reviewer is told conformance is necessary, not
   sufficient.
6. Evidence. UI or user-visible changes require a screenshot or recording
   attached to the PR, or a stated reason. Non-UI changes require the check
   command and its result.
7. Anchored lease. `git fetch`, then `--force-with-lease=<ref>:<sha>` with the
   fetched SHA, then `git ls-remote` to confirm the remote head equals the
   pushed SHA.
8. Attestation. Step 8 appends
   `<!-- dux-attestation:v1 {"head_sha":"…","steps":[{"step":"checks","status":"completed"},…]} -->`
   to the PR body. Data only, no policy claim.
9. PR body. Step 8 fills the repo's `.github/PULL_REQUEST_TEMPLATE.md` (section
   12) and passes it with `gh pr create --body-file`, since `--fill` ignores the
   template. Verbose material goes inside `<details>`.

The ship skill is bundled in this repo at `skills/ship/` from milestone 1 and
installed by `dux-install` (section 18), so milestone 5 is an ordinary PR with a
diff Codex can review and commits that can carry break-verification. Milestone 5
also moves the reviewer commands and per-shape models into `config/` with the
defaults in `templates/config/`, so the skill works for anyone who installs Dux.

Not ported: hook enforcement, CI auto-repair, transient reruns, evidence branch.

## 12. PR template

Installed by `dux-project` when the repo has none; existing templates are left
alone and reported. The installed file is untracked in the primary checkout and
invisible to worktrees cut from `origin/<base>`, so `dux-project` says so and the
operator commits it, or Dux dispatches a docs-only task to land it. `/ship`
falls back to the copy in `templates/` when a repo has none.

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
| Backend unreachable | spawn and teardown refuse; watcher marks nothing, logs `backend-down` once |
| Issue intake fails | skip with one warning; backlog unchanged |
| Second Dux session | read-only, announced |
| Monitor dies | CLAUDE.md start-of-turn rule: if no monitor is armed and tasks are running, re-arm |

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
- Intake: a fixture of `gh issue list` JSON; idempotence test runs intake twice.
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
5. `/ship` port: the nine changes in section 11, break-verified.
6. Dogfood: register fitfights_api and fitfights_ios, run one scout and one ship
   task each, one from a GitHub issue, fix what breaks.

Each milestone is its own session and PR, per the operator's one-session rule.

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
  `reviewer` (default `codex exec -m gpt-5.6-sol --sandbox read-only`),
  `security-reviewer` (default: the Claude `security-reviewer` agent, Codex
  variant documented), `models` (per shape), `backend` (empty means
  auto-detect).
- **Install**: `bin/dux-install` symlinks each bundled skill into
  `~/.claude/skills/<name>`. An existing real directory there is refused until
  the operator confirms, then moved to `<name>.bak`. `bin/dux-uninstall` removes
  only symlinks that point into this repo. Updating the repo updates the skills.
- **No personal identifiers in tracked files**: no operator paths, usernames,
  project names, or accounts. `make lint` greps for a denylist kept in
  `tests/personal-identifiers.txt`, which is itself gitignored and seeded by
  `dux-install` from the operator's home directory name and registry.
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

| Feature | Claude Code (verified, v1) | Codex (milestone 7) |
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
