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
  ship/SKILL.md            bundled delivery gate, installed by dux-install (milestone 1, task 8)
bin/
  dux-env                  sourced by every script: paths, log, die, finding, now,
                           task_harness, harness_refusal, require_cmd
  dux-lock                 single live session per DUX_HOME (pid file, exit 3 when held)
  dux-project              registry add/list/get/resolve-base, PR template install, --worktree
  dux-ledger               add/set/get/list over data/backlog.md; the only writer
  dux-task-new             allocate <project>-<shape>-<yyyymmdd>-<3 alnum>, folder, queued line
  dux-brief                render tasks/<id>/brief.md and tasks/<id>/worker-settings.json
  dux-worktree             create/remove/discard a worktree per the project's mechanism
  dux-spawn                worktree plus backend container for a queued task; five refusals
  dux-worker-wrap          runs inside the container: pid, status mirroring, heartbeat, exit line
  dux-teardown             remove the worktree, close the container, mark done or failed
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
data/         (gitignored) projects.md registry; backlog.md ledger;
                           tasks/<id>/{brief.md,status.log,report.md,worker-settings.json,
                           harness,hooks/,worktree.log}
state/        (gitignored) dux.lock; <id>.endpoint; <id>.pid;
                           <id>.out; events.log
config/       (gitignored) backend override, reviewer defaults, models, models-codex,
                           worker-harness
tests/                     bats; fakes/{claude,codex,herdr,tmux,gh}; helpers/setup.bash
```

Planned for later milestones (spec section 16): `dux-watch`, `dux-status`,
`dux-notify`, `dux-recover` (milestone 3); `dux-intake` (milestone 4); `/ship`
port (milestone 5).

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
no pane is a finding. `find` is how spawn knows a worker may still be alive.

## Dispatch flow (exists today)

1. Operator states a goal; Dux writes intent and criteria files and runs
   `dux-task-new <project> <shape>`, which allocates the id and folder and
   appends the `queued` ledger line (`dux-ledger add`).
2. `dux-brief <id> ...` renders `tasks/<id>/brief.md` (<=60 lines outside the
   fenced issue block) and `tasks/<id>/worker-settings.json`.
3. `dux-spawn <id>` refuses with a finding unless: the lock is this session's
   (`dux-lock mine`), the task is `queued`, the project is registered, the
   brief has a `- Worktree: ` line to fill, the chosen worker harness is
   dispatchable, the backend selects, no endpoint is recorded for the id, and
   `dux-backend find <id>` reports no container for the task.
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
   never copied. An uncommitted example, or a destination name the project does
   not ignore, is a finding; no example at all is a log line.
5. Spawn calls `dux-backend open <id> <wt> <abs>/bin/dux-worker-wrap <id>`, which
   starts the wrapper in a new container; the command is composed as shell words
   because both backends hand it to a shell. Spawn records the endpoint in
   `state/<id>.endpoint` and the ledger, marks `running`, and comments on a `gh:`
   issue. After a failed `open` the brief's worktree line goes back to its
   placeholder either way, and the worktree is discarded only when `find` shows
   no container; a container that outlived the failed `open` is a finding naming
   it, never a silent cleanup around a live worker.
6. `dux-worker-wrap <id>` writes `state/<id>.pid`, exports `DUX_STATUS_LOG` and
   the hooks-dir git config, runs `worker_run` from `bin/workers/<harness>.sh`
   with output to `state/<id>.out`, mirrors each status line through
   `dux-backend report`, heartbeats while output grows, and appends `failed:` or
   `ended:` when the harness exits without an exit line.
7. `dux-teardown <id>` (terminal, clean, pushed) removes the worktree, closes
   the container, and marks `done` or `failed` with the PR url.

## Wake flow (milestone 3; scripts marked * exist today)

1. `dux-lock acquire`* (SessionStart hook) starts `dux-watch`, one bash process.
2. Every 30 seconds the watcher reads the last status line of each non-terminal
   task and checks liveness (`dux-backend exists`* plus the wrapper pid).
3. It appends one line to `state/events.log` only on a change to `done`,
   `failed`, `blocked`, `needs-decision`, or on `stale` and `dead`. `working`
   never emits. It updates `data/backlog.md` so a restart re-emits nothing.
4. Dux holds one Monitor on `tail -F state/events.log`. Each line wakes it once;
   it reads that line plus at most five status lines and decides: notify,
   recover, or acknowledge.
5. `dux-notify` pushes `done`, `needs-decision`, and `failed`; `dux-recover`
   handles `stale`, `dead`, `blocked`, and `ended`.

## Session lifecycle (exists today)

SessionStart runs `dux-lock acquire` with the pid from `CLAUDE_PID`; exit 3
means another live session holds the lock and this one is read-only.
`dux-doctor` runs next and must be clean before anything is dispatched.
SessionEnd runs `dux-lock release`, which removes the lock only when it holds
this session's pid.
