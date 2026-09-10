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
  dux-project/SKILL.md     register a repo; ask before installing the PR template
  dux-status/SKILL.md      show the fleet digest and explain its next actions
  dux-recover/SKILL.md     judge and handle stale, dead, ended, or failed work
  ship/SKILL.md            bundled delivery gate, installed by dux-install (milestone 1, task 8)
  ship/ship-guard          open/record/check/fix-pass/attest/push-ok: binds each gate phase
                           to the commit it saw, refuses a push the review never covered
                           (milestone 5), and builds the pull request attestation from the
                           guard file (milestone 6). Sources nothing: it runs in a project
                           worktree with no DUX_HOME
  ship/ship-env            reviewer/security-reviewer/pr-template/pr-template-fallback/--root:
                           what the gate reads out of the Dux checkout it was installed
                           from. Values come from config/ and fall back to templates/config/;
                           both reviewers default to auto, which picks the command from what
                           the host has, on every run and never written down, and stops the
                           gate when the host has nothing to run; a stated value is never
                           probed. pr-template delegates to bin/dux-project so the lookup has
                           one owner (milestone 6). Sources nothing either, and stops when it
                           is not inside a checkout
bin/
  dux-env                  sourced by every script: paths, log, die, finding, now,
                           task_harness, harness_refusal, require_cmd, take_bytes,
                           take_line
  dux-lock                 single live session; starts and stops its watcher
  dux-project              registry add/list/get/resolve-base/pr-template, --worktree,
                           --pr-template install|skip
  dux-ledger               add/set/set-if/get/list/ack/unack over data/backlog.md; the only writer
  dux-task-new             allocate <project>-<shape>-<yyyymmdd>-<3 alnum>, folder, queued line
  dux-intake               queue labelled GitHub issues as tasks; --show fences one issue's text
  dux-brief                render tasks/<id>/brief.md and tasks/<id>/worker-settings.json
  dux-worktree             create/remove/discard a worktree per the project's mechanism
  dux-spawn                worktree plus backend container for a queued task; five refusals
  dux-worker-wrap          runs inside the container: task channel, scrubbed environment,
                           process group, proposal rules, heartbeat, terminal state
  dux-result               record-ship files the five /ship phases in order; verify proves a
                           plan, ship, or scout result from the registry, Git, and GitHub
  dux-teardown             remove the worktree, close the container, mark done or failed;
                           --abandon lets go of a task that never started
  dux-watch                classify task events, record them, and raise local toasts
  dux-status               recompute the fleet digest and missed wakes from files
  dux-notify               format one action-first phone notification line
  dux-recover              inspect or recover stale, dead, ended, and failed tasks;
                           retire one from before the security-boundary upgrade
  dux-backend              selects a backend once and dispatches to its adapter
  backends/tmux.sh         window per task, remain-on-exit; endpoint tmux:<session>:<window_id>
  backends/herdr.sh        tab per task in the Dux workspace; endpoint herdr:<pane_id>
  workers/claude.sh        worker harness adapter: worker_cmd, worker_run, worker_effort_ok
  workers/codex.sh         same adapter for Codex; tested, not dispatchable in milestone 2
  dux-doctor               preflight: CLIs, gh auth, backend CLI, registry, lock
  dux-install              symlink bundled skills, seed config, write identifier denylist (task 8)
  dux-uninstall            remove only symlinks that point into this repo (task 8)
templates/
  PULL_REQUEST_TEMPLATE.md the template dux-project installs, with consent, into a
                           project that has none
  brief.md                 the brief skeleton dux-brief renders
  worker-settings.json     Claude deny rules, __BASE__ rendered per task
  hooks/pre-push           base-branch push guard, __BASE__ and __UPSTREAM__ rendered per task
  config/                  defaults dux-install copies into config/ (models, models-codex,
                           worker-harness, backend, reviewer, security-reviewer)
data/         (gitignored) projects.md registry; backlog.md ledger with acked state;
                           tasks/<id>/{intent.md,criteria.md,brief.md,issue.md,status.log,
                           report.md,worker-settings.json,harness,hooks/,worktree.log,
                           retry,retried-from}
state/        (gitignored) dux.lock; watch.pid; watch.log; wakes.base;
                           <id>.endpoint; <id>.pid; <id>.pgid; <id>.out; events.log;
                           <id>.run; <id>.portal; <id>.result-context;
                           channels/<id>.<run>/{status.outbox,report.outbox,brief.md,
                           worker-settings.json,hooks/}
config/       (gitignored) backend override, reviewer defaults, models, models-codex,
                           worker-harness
tests/                     bats; fakes/{claude,codex,herdr,tmux,gh}; helpers/setup.bash;
                           harness/ship.md, the /ship gate recorded from a fresh clone
```

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

## Intake flow (exists today)

1. `dux-status --intake` at session start runs `dux-intake <project>` for every
   project whose registry line has `issues=label:<name>`. One project's finding
   is one `skipped:` line; the rest of the fleet still reports.
2. `dux-intake` reads the forge once, `gh issue list --state open --label <name>
   --limit 100`, and validates the answer is a list of issues before using it.
3. For each issue it builds the source key `gh:<owner>/<repo>#<n>` from the
   repository's own origin url and asks the ledger, `dux-ledger list --source`,
   whether a task already carries it. A task that exists and is not `dropped`
   means nothing new is queued: the key is the idempotence rule, so a second run
   queues nothing twice.
4. A new issue becomes a task through `dux-task-new <project> ship --source
   <key>`, and its title and body are cleaned, capped, and written to
   `tasks/<id>/issue.md`. That file is the only copy Dux keeps, and
   `dux-intake --show <id>` is the only way its text reaches Dux's context,
   fenced as data the way `dux-recover` fences worker text.
5. A `queued` task whose issue has left the list is reconciled: closed means the
   task is dropped with a line in its report, and an open issue that lost the
   label is reported and left queued. Only `queued` tasks; a worker is never
   stopped because someone closed an issue.

## Dispatch flow (exists today)

1. Operator states a goal; Dux writes intent and criteria files and runs
   `dux-task-new <project> <shape>`, which allocates the id and folder and
   appends the `queued` ledger line (`dux-ledger add`).
2. `dux-brief <id> ...` renders `tasks/<id>/brief.md` (<=60 lines outside the
   fenced issue block) and `tasks/<id>/worker-settings.json`. A task with a
   `gh:` source needs `--issue-file`, and its brief carries one
   `- Issue: <owner>/<repo>#<n>` line taken from the ledger, never from the
   issue text; that line is what `/ship` turns into `Closes #<n>`.
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
   issue. The `running` write is `dux-ledger set-if <id> state queued running`:
   the open has already started the worker, a worker that refuses at once leaves
   a proved terminal handoff the watcher can apply before that line runs, and an
   unconditional write would put a finished task back to `running` for good.
   `set-if` compares and writes under the ledger's own lock, so nothing can move
   between the two, and a refusal is a finding naming the state that won. After
   a failed `open` the brief's worktree line goes back to its placeholder either
   way, and the worktree is discarded only when `find` shows no container; a
   container that outlived the failed `open` is a finding naming it, never a
   silent cleanup around a live worker.
6. `dux-worker-wrap <id>` writes `state/<id>.pid`, makes the task channel (below),
   runs `worker_run` from `bin/workers/<harness>.sh` in a process group of its own
   with output to `state/<id>.out`, heartbeats while that output grows, mirrors the
   dux state to the pane as fixed text, and publishes the run's result as a
   handoff (below). A `done` proposal goes through `dux-result verify` first; a
   harness that exits without a terminal proposal gets `failed:` or `ended:`.
7. `dux-teardown <id>` (the ledger says terminal, worktree clean, branch pushed)
   removes the worktree, closes the container, clears the run's retained
   references, and reports the ledger's own state and PR url. For a `done` task
   from an issue whose PR is in that issue's repository, it posts one comment,
   `Dux delivered PR <url>.`, on the first teardown that completes; a failed
   comment is a warning, not a refusal.
8. `dux-teardown --abandon <id>` is the other verb: letting go of a task that
   never started, which plain teardown cannot do because it would walk the
   worktree, container and receipt path against a task that has none of them. It
   takes `queued` and `dropped` only. Never having run is proved from the
   filesystem rather than the ledger, because a spawn killed between the worktree
   and the state write leaves a live task still reading `queued`: a run record, a
   pid file, a pgid file, a portal or a worktree is a refusal naming the one it
   found. On success the ledger reads `dropped` and `data/tasks/<id>` is gone; no
   project repo, branch or pull request is touched.

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
- Each outbox is pinned: a second hard link, `.status.pin` and `.report.pin`,
  kept for the whole run. An outbox is "still the same file" when it and its pin
  are the same inode. The pin is what makes that true, because Linux frees an
  inode as soon as a file is removed and hands the same number to the file
  written in its place, so the number alone would read a replacement as the
  original. Removing the pin is a replacement too: the question then has nothing
  to answer with. Both readings fail the task.
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
  Control characters are stripped. Only `working:` lines reach `status.log` from
  the wrapper; the terminal state is held until the run is over and leaves as a
  handoff, never as a line the wrapper appends.
- The pane shows `dux <id>: <state>`, fixed text chosen by the state. Every
  notification, toast and digest line is likewise fixed by state, with the url
  the ledger holds; `dux-recover` is the only place worker text reaches the
  operator, capped, cleaned and fenced as data.

## The terminal handoff

A run's ending is a directory, not a line. `dux-worker-wrap` builds
`state/<id>.handoffs/.tmp.<run>.<n>.<pid>` holding `run`, `status` and `event`,
then renames it to `state/<id>.handoffs/<n>` in one move, so a reader sees a
whole handoff or none of it.

- `done` is never the worker's to declare. The wrapper runs
  `bin/dux-result verify <id> <run>`, and the line it publishes is the one that
  came back: exit 0 publishes the canonical result, exit 1 publishes
  `ended: the result was not proved: <reason>`, exit 2 is a finding. A worker's
  own url, report claim and shape are not inputs. Any other terminal word is the
  worker reporting on itself, which only ever moves a task away from `done`, so
  its own line stands.
- The watcher takes the lowest sequence with no `consumed` marker and stops at
  the first gap, so sequences apply in order. It refuses a handoff that names
  another run, is not exactly three one-line regular files, does not parse as a
  status line, does not match the shape the run recorded, carries a url outside
  the registered repository, or is a ship result with no five-phase receipt
  behind it.
- Applying one writes `status.log`, then `events.log`, then the ledger state,
  then the ledger url, then `consumed`; the first two are guarded by their own
  markers, so a watcher killed part-way through replays without duplicating
  anything. A ledger write that fails leaves the sequence pending and the
  watcher retries it on the next pass.
- A terminal-looking status line with no handoff behind it proves nothing and is
  ignored by the watcher, the digest and teardown alike.
- Sequences are retained for the whole run. `dux-teardown` is their lifecycle
  owner, and clears them with `state/<id>.run`, `state/<id>.result-context`,
  `state/<id>.ship-receipt`, `state/<id>.portal`, `state/<id>.pgid` and the task
  channel the portal names. A wrapper that died without cleaning up leaves those
  last three behind; recovery clears them only once the worker's own process
  group is proved gone, and teardown asks the same question before it removes
  anything: a live group in `state/<id>.pgid`, or a file it cannot read as one,
  is a finding, because the folder those processes are working in is the
  worktree teardown is about to take away. Both go through the same step, which
  requires the portal's stored path to name this task's own channel, directly
  under `state/channels/`, and to be exactly what it resolves to. A prefix check
  on its own is text, and text walks back out or points elsewhere:
  `state/channels/../../<anything>` starts with the directory without being in
  it, and a path that is a link to another task's channel, or simply that
  task's own path written down, is that task's live channel. The wrapper makes
  the channel as `state/channels/<id>.XXXXXXXX`, whose suffix holds no dot, and
  records the path the kernel agrees on, so a task named `a` cannot read task
  `a.b`'s channel as its own either. Anything that fails the rule is a broken
  reference, left alone and logged rather than turned into a recursive delete of
  something else. What those messages quote from a file goes through the same
  one-line cleaning as a worker's own text: a finding is relayed to the operator
  as it stands, so nothing a file holds may add a line to one.

## Retiring a task from before the upgrade

A task that was running before this milestone landed has no run record, so no
handoff can ever be published for it and no result can ever be proved. It would
sit in the fleet forever. `dux-recover <id> --retire-legacy` is the one-time
migration that ends it, and it proves the task really is one of those before it
writes anything.

- It refuses unless the ledger says `running`, `stale`, `dead` or `ended`.
- It refuses if `state/<id>.run` exists at all, including as a symlink: a task
  with a run record is an ordinary task, recovered the ordinary way. A run
  record it wrote itself carries `retired=`, so a second retirement is refused
  by name rather than repeated.
- It refuses if a handoff is already waiting, because a task from before the
  upgrade cannot have published one.
- Only then does it signal the wrapper, INT and then a bounded wait, and refuse
  if the wrapper is still there afterwards. Nothing of the old run is left
  running before anything is written.
- What it writes is a retirement run record and one handoff,
  `failed: stopped for security-boundary upgrade; worktree kept`. The watcher
  applies that like any other handoff, which is what puts the task in `failed`
  and raises the wake.

The branch and the worktree are kept. From `failed` the ordinary paths apply and
each applies once: one `--retry`, which is a new task with its own worktree and
its own run, or `dux-teardown`, with its usual clean, pushed and stopped checks.
A second retirement and a second retry are both findings.

## What this boundary does not claim

The worker runs as the operator, so the boundary is about mistakes and about
text, not about a hostile program.

- It contains the ordinary process group. A child that deliberately starts a
  session of its own escapes it, and a survivor of TERM and KILL is a finding
  with no result, never a quiet success.
- It caps what a worker can say: 200 bytes a status line, 64 KiB of status
  proposals, 1 MiB of report. It does not cap what a worker can do inside its
  own worktree with the operator's own rights.
- Every operator surface, pane, toast, notification and digest line, carries
  fixed text chosen by state and the url the ledger holds. `dux-recover` is the
  only place worker text reaches the operator, capped, cleaned and fenced as
  data.
- A stronger boundary, a separate user account or a sandbox, is possible later
  and is not required by anything here. If one is added it fails closed: no
  isolation, no dispatch.

## Wake flow (exists today)

1. The SessionStart hook runs `dux-lock acquire`, which starts one `dux-watch`
   process and records it in `state/watch.pid`.
2. Every 30 seconds, or the configured interval, the watcher reads the last
   status line for each running or stale task and checks its wrapper pid.
3. Liveness has three answers: `alive`, `gone`, or `unknown`. A matching
   `dux-worker-wrap <id>` pid decides alive or gone in both directions. The
   backend container only adds corroborating notes and never reverses that answer.
4. A consumed handoff emits `<time> <state>: <id>` to `state/events.log`.
   Silence can emit `stale`; a gone wrapper can emit `dead`; a clean worker exit
   without a terminal proposal reaches the watcher as an `ended` handoff. The
   event is appended before the ledger is updated, so a write failure repeats
   rather than loses the wake. Every event also raises a local backend toast.
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
| `ended` | Run the same proof the wrapper would have run and publish what it proves into the next sequence; otherwise ask the operator, whose only classification is `failed`. |
| `failed` | Show the saved failure and offer one retry or a scout. |
| from before the upgrade | `--retire-legacy` stops the old wrapper and publishes one retirement handoff; the branch and worktree are kept for one retry or a teardown. |
| `blocked`, `needs-decision` | Relay the meaning of fenced status data; append the operator answer to one fresh retry. |

## Session lifecycle (exists today)

SessionStart runs `dux-lock acquire` with the pid from `CLAUDE_PID`; exit 3
means another live session holds the lock and this one is read-only. A successful
acquire replaces any watcher recorded in `state/watch.pid`, starts a fresh one,
and writes diagnostics to `state/watch.log`. `DUX_WATCHER=off` is the explicit
test and maintenance switch. `dux-doctor` then requires the watcher while the
switch is on. Dux arms the Monitor before `dux-status --intake` pulls the labelled issues and
reconstructs the fleet, and it runs the plain digest again after replacing a dead
Monitor. The ordering means
the digest catches earlier events while the Monitor catches later ones.
SessionEnd runs `dux-lock release`, which stops this session's watcher and removes
the lock only when it holds this session's pid. Worker containers keep running.
