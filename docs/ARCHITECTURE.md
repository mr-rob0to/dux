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
  dux-project/SKILL.md     register a repo, install the PR template if absent
  ship/SKILL.md            bundled delivery gate, installed by dux-install (milestone 1, task 8)
bin/
  dux-env                  sourced by every script: paths, log, die, finding, now, require_cmd
  dux-lock                 single live session per DUX_HOME (pid file, exit 3 when held)
  dux-project              registry add/list/get/resolve-base, PR template install
  dux-backend              selects a backend once and dispatches to its adapter
  backends/tmux.sh         window per task, remain-on-exit; endpoint tmux:<session>:<window_id>
  backends/herdr.sh        tab per task in the Dux workspace; endpoint herdr:<pane_id>
  dux-doctor               preflight: CLIs, gh auth, backend CLI, registry, lock
  dux-install              symlink bundled skills, seed config, write identifier denylist (task 8)
  dux-uninstall            remove only symlinks that point into this repo (task 8)
templates/
  PULL_REQUEST_TEMPLATE.md the template dux-project installs into projects
  config/                  defaults dux-install copies into config/ (task 8)
data/         (gitignored) projects.md registry; tasks/<id>/{brief.md,status.log,report.md}
state/        (gitignored) dux.lock; <id>.endpoint; <id>.out; events.log
config/       (gitignored) backend override and reviewer defaults
tests/                     bats; fakes/claude and fakes/herdr; helpers/setup.bash
```

Planned for later milestones (spec section 16): `dux-brief`, `dux-worktree`,
`dux-spawn`, `dux-worker-wrap`, `dux-teardown` (milestone 2); `dux-watch`,
`dux-status`, `dux-notify`, `dux-recover` (milestone 3); `dux-intake`
(milestone 4); `/ship` port (milestone 5).

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
`tmux`. Adapters implement `backend_open`, `backend_exists`, `backend_tail`,
`backend_close`, `backend_notify` with identical arguments. Endpoints are opaque
strings recorded from creation responses, never derived from labels. `close`
refuses the operator's focused pane and treats a failed Herdr close as a finding.

## Dispatch flow (milestone 2; scripts marked * exist today)

1. Operator states a goal; Dux writes a brief via `dux-brief` (<=60 lines, no
   conversation history).
2. `dux-spawn <project> <shape> <brief>` refuses with a finding unless: the
   project is registered (`dux-project`*), the lock is held by this session
   (`dux-lock`*), the worktree is fresh from `origin/<base>`, and no endpoint
   exists for the id.
3. `dux-worktree` creates the worktree with the project's own mechanism
   (`make`, `script`, or `git`, as recorded by `dux-project`*).
4. `dux-backend open <id> <cwd> <cmd>`* starts `dux-worker-wrap <id>` in a new
   container and prints the endpoint; spawn records it in `state/<id>.endpoint`
   and marks the ledger line `running`.
5. The wrapper runs `claude -p` (or `codex exec`) with the brief and appends
   `<state>: <line>` to `data/tasks/<id>/status.log`.

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
