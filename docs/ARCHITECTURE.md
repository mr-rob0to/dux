# Dux architecture

Current component map and the two main flows. The design authority is
`docs/specs/2026-09-03-dux-orchestrator-design.md`; this file tracks
what exists. Update it in the same pull request as any change that adds,
removes, or renames a script, adapter, state file, or step in a flow.

## Components

```
AGENTS.md                  operating contract, always loaded (<=150 lines, tested)
CLAUDE.md                  two-line import of AGENTS.md
.claude/settings.json      SessionStart: dux-lock acquire; SessionEnd: dux-lock release
skills/
  dux-dispatch/SKILL.md    turn a goal into a running task, and tear it down after merge
  dux-project/SKILL.md     register a repo, install the PR template if absent
  dux-status/SKILL.md      show the fleet digest and explain its next actions
  dux-recover/SKILL.md     judge and handle stale, dead, ended, or failed work
  ship/SKILL.md            bundled delivery gate, installed by dux-install (milestone 1, task 8)
bin/
  dux-env                  sourced by every script: paths, log, die, finding, now,
                           task_harness, harness_refusal, require_cmd
  dux-lock                 single live session; starts and stops its watcher
  dux-project              registry add/list/get/resolve-base, PR template install, --worktree
  dux-ledger               add/set/get/list/ack/unack over data/backlog.md; the only writer
  dux-task-new             allocate <project>-<shape>-<yyyymmdd>-<3 alnum>, folder, queued line
  dux-brief                render tasks/<id>/brief.md and tasks/<id>/worker-settings.json
  dux-worktree             create/remove/discard a worktree per the project's mechanism
  dux-spawn                worktree plus backend container for a queued task; five refusals
  dux-worker-wrap          runs inside the container: task channel, scrubbed environment,
                           process group, proposal rules, heartbeat, terminal state
  dux-teardown             remove the worktree, close the container, mark done or failed
  dux-watch                classify task events, record them, and raise local toasts
  dux-status               recompute the fleet digest and missed wakes from files
  dux-notify               format one action-first phone notification line
  dux-recover              inspect or recover stale, dead, ended, and failed tasks
  dux-backend              selects a backend once and dispatches to its adapter
  backends/tmux.sh         window per task, remain-on-exit; endpoint tmux:<session>:<window_id>
  backends/herdr.sh        tab per task in the Dux workspace; endpoint herdr:<pane_id>
  workers/claude.sh        worker harness adapter: worker_cmd, worker_run, worker_effort_ok
  workers/codex.sh         same adapter for Codex; tested, not dispatchable in milestone 2
  dux-doctor               preflight: CLIs, gh auth, backend CLI, registry, lock
  dux-install              symlink bundled skills, seed config, write identifier denylist (task 8)
  dux-uninstall            remove only symlinks that point into this repo (task 8)
templates/
  PULL_REQUEST_TEMPLATE.md the template dux-project installs into projects
  brief.md                 the brief skeleton dux-brief renders
  worker-settings.json     Claude deny rules, __BASE__ rendered per task
  hooks/pre-push           base-branch push guard, __BASE__ and __UPSTREAM__ rendered per task
  config/                  defaults dux-install copies into config/ (models, models-codex,
                           worker-harness, backend, reviewer, security-reviewer)
data/         (gitignored) projects.md registry; backlog.md ledger with acked state;
                           tasks/<id>/{intent.md,criteria.md,brief.md,status.log,report.md,
                           worker-settings.json,harness,hooks/,worktree.log,retry,retried-from}
state/        (gitignored) dux.lock; watch.pid; watch.log; wakes.base;
                           <id>.endpoint; <id>.pid; <id>.pgid; <id>.out; events.log;
                           <id>.run; <id>.portal; <id>.result-context;
                           channels/<id>.<run>/{status.outbox,report.outbox,brief.md,
                           worker-settings.json,hooks/}
config/       (gitignored) backend override, reviewer defaults, models, models-codex,
                           worker-harness
tests/                     bats; fakes/{claude,codex,herdr,tmux,gh}; helpers/setup.bash
```

Planned for later milestones (spec section 16): `dux-intake` (milestone 4) and
the `/ship` port (milestone 5).

Rules that shape every component:

- Scripts own mechanics and refuse loudly: `finding: <line>` on stderr, exit 2.
  Agents own judgment and relay findings verbatim.
- Every script sources `bin/dux-env`. Nothing outside an adapter calls `tmux`
  or `herdr` directly.
- State is files under `data/` and `state/` plus the terminal backend.
  Conversation memory is never authoritative.

## Backend selection

`dux-backend` picks the backend once per invocation: `$DUX_BACKEND`, else
`config/backend`, else `herdr` when `HERDR_ENV=1` and `$TMUX` is unset, else
`tmux`. Adapters implement `backend_open`, `backend_find`, `backend_exists`,
`backend_tail`, `backend_close`, `backend_notify`, `backend_report`, and
`backend_title` with identical arguments; `report` and `title` mirror a worker's
status into the container's own chrome and are no-ops under tmux. Endpoints are
opaque strings recorded from creation responses, never derived from labels. `close`
refuses the operator's focused pane and treats a failed Herdr close as a finding.

`find <id>` is the one operation that reads a container back from the label both
backends already set (`dux-<id>`): it prints that container's endpoint, or nothing
when there is none. tmux filters `list-windows -a` on the window name; Herdr
matches `herdr tab list` on `label` and then resolves the tab to a pane through
`herdr pane list`, because the tab listing carries no pane. It never answers
"nothing" when it could not tell: a listing that fails, a listing without the
array it should have, more than one container for the id, or a labelled tab with
no pane is a finding. Under tmux the socket path
(`${TMUX_TMPDIR:-/tmp}/tmux-<uid>/<-L name or default>`) decides how a failed
listing reads, and tmux's wording only refines that once the path is a socket:
builds disagree about what they say for the same path, and the wrong reading
would answer "nothing is running" to a question tmux never answered. No path at
all is a path no server has ever been reachable at and is no window, which is
every first spawn on a machine. A socket there means tmux looked through it, so
`no server running` is the stale socket an exited server left and is no window
too; every other failure there is a finding, because tmux did not look and a live
server holding the worker reads the same way. Anything else at that path is a
finding. `find` is one of the two ways spawn asks whether a worker may still be
alive; the other is the wrapper's own `state/<id>.pid`, which answers whichever
backend started it and catches a worker in a server whose socket vanished.

## Dispatch flow (exists today)

1. Operator states a goal; Dux writes intent and criteria files and runs
   `dux-task-new <project> <shape>`, which allocates the id and folder and
   appends the `queued` ledger line (`dux-ledger add`).
2. `dux-brief <id> ...` renders `tasks/<id>/brief.md` (<=60 lines outside the
   fenced issue block) and `tasks/<id>/worker-settings.json`.
3. `dux-spawn <id>` refuses with a finding unless: the lock is this session's
   (`dux-lock mine`), the task is `queued`, the project is registered, the
   brief has a `- Worktree: ` line to fill, the chosen worker harness is
   dispatchable, the backend selects, no endpoint is recorded for the id,
   `dux-backend find <id>` reports no container for the task, and
   `state/<id>.pid` is absent or names a pid that is gone. The last two are
   independent signals and either one that cannot say "gone" refuses: `find`
   answers only for the current backend and an unrenamed container, while the
   pidfile is written by the wrapper inside the container on every backend.
   Milestone 2 dispatches `claude` workers only. `codex` is refused by
   `harness_refusal` in `dux-env`, which `dux-spawn` and `dux-worker-wrap` both
   call, so the `--harness` flag, `config/worker-harness` and
   `tasks/<id>/harness` all reach the same answer: a Codex worker has no deny
   list, so `git push --no-verify` skips the `pre-push` hook, its one
   mechanical guard. This does not touch Codex as the ship gate's reviewer.
4. `dux-worktree create <id>`: fetch `origin/<base>`, create the worktree
   (project mechanism for `ship`, `git worktree add` otherwise), discover the
   path, refuse the primary checkout or a stale tip, build
   `tasks/<id>/hooks/` with the base-branch `pre-push` guard, and for `ship`
   under `git` copy the project's committed `.env*.example` and `.env*.sample`
   files, renamed to the name the project expects. A real ignored `.env` is
   never copied. Each copy is staged at `<dest>.dux-part` and renamed over
   `<dest>`; a pre-existing path at either name is refused, and the staging file
   is created with `O_EXCL` so it cannot follow a committed symlink. An
   uncommitted example, or a destination name the project does not ignore, is a
   finding; no example at all is a log line.
5. Spawn calls `dux-backend open <id> <wt> <abs>/bin/dux-worker-wrap <id>`, which
   starts the wrapper in a new container; the command is composed as shell words
   because both backends hand it to a shell. Spawn records the endpoint in
   `state/<id>.endpoint` and the ledger, marks `running`, and comments on a `gh:`
   issue. After a failed `open` the brief's worktree line goes back to its
   placeholder either way, and the worktree is discarded only when `find` shows
   no container; a container that outlived the failed `open` is a finding naming
   it, never a silent cleanup around a live worker.
6. `dux-worker-wrap <id>` writes `state/<id>.pid`, makes the task channel (below),
   runs `worker_run` from `bin/workers/<harness>.sh` in a process group of its own
   with output to `state/<id>.out`, heartbeats while that output grows, mirrors the
   dux state to the pane as fixed text, and appends `failed:` or `ended:` when the
   harness exits without a terminal proposal.
7. `dux-teardown <id>` (terminal, clean, pushed) removes the worktree, closes
   the container, and marks `done` or `failed` with the PR url.

## The task channel

A worker runs with the operator's own authority, so nothing it writes is
canonical and nothing it says is evidence. It writes into a channel of its own
and the wrapper decides what, if anything, reaches `status.log` and `report.md`.

- The channel is `state/channels/<id>.<run>`, mode 700, named with a random
  run id. It holds read-only copies of the brief, the worker settings and the
  task hooks, and two mode-600 files the worker appends to: `status.outbox` and
  `report.outbox`. `state/<id>.portal` names it, `state/<id>.run` records the
  run, and `state/<id>.result-context` records the facts a result is later
  proved against. This run refuses to start if any of those four already exists,
  including as a symlink.
- The worker's environment is scrubbed of `DUX_*`, `CLAUDE_*`, `HERDR_*`,
  `TMUX*` and `GIT_CONFIG_*`, and of Dux's own `PATH` entry. Only
  `DUX_STATUS_LOG`, `DUX_REPORT` and the three `GIT_CONFIG_*` values that point
  git at the channel's hooks are put back. The brief names those two variables;
  no Dux path is handed to a worker.
- The worker runs in its own process group with stdin on `/dev/null`. Before any
  terminal state is written the wrapper stops that whole group, TERM then KILL,
  and proves it gone. A survivor is a cleanup finding and no terminal state, so
  a parent that claims done while its children keep running completes nothing.
- Proposal rules, each one a failed task: what Dux has already read may not be
  rewritten or truncated, every line is `<state>: <text>` with a known state, a
  line is at most 200 bytes, the whole status outbox at most 64 KiB and the
  report at most 1 MiB, and after one terminal line nothing more may be written.
  Control characters are stripped. Only `working:` lines reach `status.log`
  during the run; the terminal line is held until the run is over and the
  references still name this run's channel.
- The pane shows `dux <id>: <state>`, fixed text chosen by the state. Worker
  text never reaches the operator except through `dux-notify` and
  `dux-recover`, capped and fenced as data.

## Wake flow (exists today)

1. The SessionStart hook runs `dux-lock acquire`, which starts one `dux-watch`
   process and records it in `state/watch.pid`.
2. Every 30 seconds, or the configured interval, the watcher reads the last
   status line for each running or stale task and checks its wrapper pid.
3. Liveness has three answers: `alive`, `gone`, or `unknown`. A matching
   `dux-worker-wrap <id>` pid decides alive or gone in both directions. The
   backend container only adds corroborating notes and never reverses that answer.
4. A terminal status change emits `<time> <state>: <id>` to `state/events.log`.
   Silence can emit `stale`; a gone wrapper can emit `dead`; a clean worker exit
   without a terminal line can emit `ended`. The event is appended before the
   ledger is updated, so a write failure repeats rather than loses the wake.
   Every event also raises a local backend toast.
5. Dux holds one persistent Monitor on `tail -n0 -F state/events.log`. Each line
   wakes the session once.
6. On a wake, Dux reads only the ledger state and acknowledgement. A matching
   acknowledgement and event state means the wake is a duplicate. Worker text
   reaches context only through the capped and cleaned `dux-notify` or through
   the capped, cleaned, fenced `dux-recover` output.
7. `dux-notify` formats the phone line for `done` with a PR, `needs-decision`,
   and `failed`. `dux-recover` handles the mechanical side of recovery.
8. Dux runs `dux-ledger ack <id> <event-state>` after handling the wake. The
   command refuses if the task has moved to a newer state. `dux-status` lists
   every unacknowledged state after a session restart.

| State | Recovery |
|---|---|
| `stale` | Inspect a capped, fenced output tail; extend once when progressing, otherwise stop the matching wrapper. |
| `dead` | Mark failed, save the last 20 output lines, and keep the worktree. |
| `ended` | Use a branch PR or a non-failure report to classify done; otherwise ask the operator. |
| `failed` | Show the saved failure and offer one retry or a scout. |
| `blocked`, `needs-decision` | Relay the meaning of fenced status data; append the operator answer to one fresh retry. |

## Session lifecycle (exists today)

SessionStart runs `dux-lock acquire` with the pid from `CLAUDE_PID`; exit 3
means another live session holds the lock and this one is read-only. A successful
acquire replaces any watcher recorded in `state/watch.pid`, starts a fresh one,
and writes diagnostics to `state/watch.log`. `DUX_WATCHER=off` is the explicit
test and maintenance switch. `dux-doctor` then requires the watcher while the
switch is on. Dux arms the Monitor before `dux-status` reconstructs the fleet,
and it runs the digest again after replacing a dead Monitor. The ordering means
the digest catches earlier events while the Monitor catches later ones.
SessionEnd runs `dux-lock release`, which stops this session's watcher and removes
the lock only when it holds this session's pid. Worker containers keep running.
