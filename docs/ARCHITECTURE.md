# Dux architecture

Current component map and the two main flows. The design authority is
`docs/specs/2026-09-03-dux-orchestrator-design.md`; this file tracks
what exists. Update it in the same pull request as any change that adds,
removes, or renames a script, adapter, state file, or step in a flow.

## Components

```
AGENTS.md                  operating contract, always loaded (<=150 lines, tested)
CLAUDE.md                  two-line import of AGENTS.md
.claude/settings.json      SessionStart: dux-lock acquire; SessionEnd: dux-lock release;
                           model claude-sonnet-5 for the orchestrator session
skills/
  dux-dispatch/SKILL.md    turn a goal into a running task, and tear it down after merge
  dux-project/SKILL.md     register a repo; ask before installing the PR template
  dux-status/SKILL.md      show the fleet digest and explain its next actions
  dux-recover/SKILL.md     judge and handle stale, dead, ended, or failed work
  ship/SKILL.md            bundled delivery gate, installed by dux-install (milestone 1, task 8);
                           each review run's usage: line, Codex's own counts for that run,
                           unknown, or in session total for an agent, goes in the pull request
                           (rollout milestone 4)
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
                           probed. review-mode is the rule that turns the brief's recorded
                           classification and the gate's own read of the diff into combined
                           or separate: it is not a classifier and never reads the diff,
                           and every pair but a combined claim over a clear diff is
                           separate. auto for the security pass is Codex Sol, read-only, the
                           only reviewer qualified against tests/fixtures/security-review;
                           no agent is chosen automatically and a host without codex stops.
                           pr-template delegates to bin/dux-project so the lookup has one
                           owner (milestone 6). Sources nothing either, and stops when it
                           is not inside a checkout
bin/
  dux-env                  sourced by every script: paths, log, die, finding, now,
                           task_harness, harness_refusal, require_cmd, take_bytes,
                           take_line
  dux-lock                 single live session; starts and stops its watcher
  dux-project              registry add/list/get/resolve-base/pr-template, --worktree,
                           --pr-template install|skip, required when the repo has
                           no pull request template
  dux-ledger               add/set/set-if/get/list/ack/unack over data/backlog.md; the only writer
  dux-task-new             allocate <project>-<shape>-<yyyymmdd>-<3 alnum>, folder, queued line;
                           --after names the one ship task it waits on, in tasks/<id>/after
  dux-intake               queue labelled GitHub issues as tasks; --show fences one issue's text
  dux-brief                render tasks/<id>/brief.md and tasks/<id>/worker-settings.json,
                           and for a ship task write tasks/<id>/risk (mode 600) from
                           --risk bounded|complex, defaulting to complex; --phase planning
                           writes tasks/<id>/phase for work that plans first, and
                           --after-check the check a waited-on merge must pass
  dux-worktree             create/remove/discard a worktree per the project's mechanism
  dux-spawn                worktree, tab and wrapper for a queued task; refusals including a
                           worktree Claude Code does not trust and a live worker on any
                           other task; a task that waits starts only on a proved delivery,
                           merged into the fetched base, recorded in tasks/<id>/prerequisite
  dux-worker-wrap          runs beside the tab, not inside it: task channel, launcher,
                           the harness's own process group, proposal rules, heartbeat,
                           terminal state; parks a proved delivery, a question or a
                           blocker, and runs its rounds
  dux-result               record-ship files the phases the branch's review mode owes, in
                           order, into a versioned receipt that names the mode; verify proves
                           a plan, ship, or scout result from the registry, Git, and GitHub.
                           A combined gate owes checks, review, pr, ci; a separate one owes
                           security as well; a receipt from before review modes keeps all
                           five. A task classified separate cannot record or prove a combined
                           review, and escalation the other way needs no permission.
                           A ship brief naming no plan and no task range skips the checkbox
                           proof and nothing else. Work that plans first proves nothing
                           before its approval, and is then held to the plan, task range and
                           commit that approval names
  dux-round                a round for a session parked in its tab: feedback on a done
                           task's open pull request, an answer to needs-decision or blocked,
                           or approval of a plan committed under --phase planning; writes
                           tasks/<id>/round-<n>.md for the parked wrapper; eight rounds at most
  dux-teardown             remove the worktree, close the container, mark done or failed,
                           keeping a done task's delivery proof in tasks/<id>/delivery/;
                           --abandon lets go of a task that never started
  dux-watch                classify task events, record them, and raise local toasts
  dux-status               recompute the fleet digest and missed wakes from files
  dux-notify               format one action-first phone notification line
  dux-recover              inspect or recover stale, dead, ended, and failed tasks;
                           retire one from before the security-boundary upgrade
  dux-backend              selects a backend once and dispatches to its adapter; prompt
                           types one line into a task's tab, which is how a round starts
  backends/tmux.sh         window per task, remain-on-exit; endpoint tmux:<session>:<window_id>
  backends/herdr.sh        tab per task in the Dux workspace; endpoint herdr:<pane_id>
  workers/claude.sh        worker harness adapter: worker_cmd, worker_run, worker_effort_ok;
                           both entry points share one flag list: --tools limited to
                           Bash,Read,Glob,Grep,Write,Edit,Skill, --strict-mcp-config with the
                           empty templates/worker-mcp.json, and --no-chrome
  workers/codex.sh         same adapter for Codex; tested, not dispatchable in milestone 2.
                           worker_usage reads a codex exec --json event stream: input with
                           cached input taken out, output, cache read, cache write, each
                           thread's last running total once, unknown where Codex gave none
  dux-doctor               preflight: CLIs, gh auth, backend CLI, both reviewers resolved the
                           way the gate resolves them, the rollout stage and what it leaves
                           unavailable, registry, lock
  dux-install              symlink bundled skills, seed config, add model keys an existing
                           config/models* is missing, write identifier denylist (task 8).
                           Says what a real directory holds before proposing to replace it,
                           and reports a second copy of a skill in the shared skills
                           directory without touching it
  dux-uninstall            remove only symlinks that point into this repo (task 8)
templates/
  PULL_REQUEST_TEMPLATE.md the template dux-project installs, with consent, into a
                           project that has none
  brief.md                 the brief skeleton dux-brief renders
  round.md                 the round file dux-round renders
  usage.md                 the usage summary an accepted deliverable gets from stage m4,
                           copied into its task folder and filled from structured records
  worker-settings.json     Claude deny rules, __BASE__ rendered per task
  worker-mcp.json          the empty MCP config every Claude worker is held to
tests/fixtures/
  security-review/         vulnerable.sh, clean.sh and expected.md: the planted defects a
                           security reviewer must find, and must not invent, before auto
                           will choose it. Never executed; implementation evidence only
  hooks/pre-push           base-branch push guard, __BASE__ and __UPSTREAM__ rendered per task
  config/                  defaults dux-install copies into config/ (models, models-codex,
                           worker-harness, backend, reviewer, security-reviewer,
                           policy-stage)
data/         (gitignored) projects.md registry; backlog.md ledger with acked state;
                           tasks/<id>/{intent.md,criteria.md,brief.md,issue.md,status.log,
                           report.md,worker-settings.json,risk,review,harness,hooks/,worktree.log,
                           retry,retried-from,phase,after,after-check,prerequisite,
                           round-<n>.md,round-<n>.approval,delivery/,usage.md}
state/        (gitignored) dux.lock; watch.pid; watch.log; wakes.base;
                           <id>.endpoint; <id>.pid; <id>.pgid; <id>.wrap.log; events.log;
                           <id>.run; <id>.portal; <id>.result-context;
                           channels/<id>.<run>/{status.outbox,report.outbox,brief.md,
                           worker-settings.json}
config/       (gitignored) backend override, reviewer defaults, models, models-codex,
                           worker-harness, policy-stage
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
`tmux`. Adapters implement `backend_open`, `backend_run`, `backend_pid`,
`backend_find`, `backend_exists`, `backend_close`, `backend_notify` and
`backend_title` with identical arguments. `open` makes a container holding a
shell and nothing else, and prints its endpoint; `run` hands that shell one
command line, which a shell reads on both backends, so a path in it is the
caller's to quote, and the tmux adapter prefixes `exec` so that the pane's own
pid is the command's on a machine whose `/bin/sh` forks instead of replacing
itself; `pid` prints `<pid> <pgid> <cwd>` for the process the shell is
running, exit 1 for "nothing there yet" and exit 2 for a multiplexer that could
not answer. `title` names the tab and is a no-op under tmux. No verb reads what
a pane has drawn: the worker's screen belongs to the operator, and a contract
test greps `bin/` and `skills/` for `pane read` and `capture-pane` so no branch
can bring one back. Endpoints are opaque strings recorded from creation
responses, never derived from labels. `close` refuses the operator's focused
pane and treats a failed Herdr close as a finding.

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
alive; the other is the wrapper's own `state/<id>.pid`. Spawn starts the wrapper
itself, outside the container, so that file answers on whichever backend opened
the tab and catches a worker in a server whose socket vanished.

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
   appends the `queued` ledger line (`dux-ledger add`). `--after <task-id>`
   writes `tasks/<id>/after` first, naming the one `ship` task this one waits
   on; sequencing is linear.
2. `dux-brief <id> ...` renders `tasks/<id>/brief.md` (<=100 lines outside the
   fenced issue block) and `tasks/<id>/worker-settings.json`. A task with a
   `gh:` source needs `--issue-file`, and its brief carries one
   `- Issue: <owner>/<repo>#<n>` line taken from the ledger, never from the
   issue text; that line is what `/ship` turns into `Closes #<n>`. A `ship` task
   also gets `tasks/<id>/risk`, `bounded` or `complex`, which is what
   `dux-worker-wrap` looks up in `config/models` instead of the shape. `--plan`
   and `--tasks` are one pair; the empty pair is plan-free shipping and needs
   `--risk bounded`, or is work that plans first under `--phase planning`. That
   brief runs on the complex model and tells the worker to commit a plan, ask
   for its approval at `needs-decision` and build nothing before it, and
   `tasks/<id>/phase` reads `planning` until an approval round moves it on. For a
   task that waits, `--after-check <name>` writes `tasks/<id>/after-check`: a
   check, such as a deployment, that has to have passed on the merge.
3. `dux-spawn <id>` refuses with a finding unless: the lock is this session's
   (`dux-lock mine`), the task is `queued`, the project is registered, the
   brief has a `- Worktree: ` line to fill, the chosen worker harness is
   dispatchable, the backend selects, no endpoint is recorded for the id,
   `dux-backend find <id>` reports no container for the task, and
   `state/<id>.pid` is absent or names a pid that is gone. The last two are
   independent signals and either one that cannot say "gone" refuses: `find`
   answers only for the current backend and an unrenamed container, while the
   pidfile is written by the wrapper, which spawn starts itself on every
   backend.
   One more refusal covers the whole fleet: no other registered task may have a
   worker that might be alive. Its `state/<other>.pid` must be absent or name a
   pid no longer running `dux-worker-wrap <other>`; its `state/<other>.pgid`
   must be absent or name a process group nothing answers for; and where the
   ledger still records that task as `running` or `stale`, `dux-backend find
   <other>` must report no container. The pgid file is the one that matters now
   that a worker is a live session: the session outlives its wrapper, so a
   wrapper killed while the harness sits at its prompt leaves a pidfile reading
   gone and a tab full of agent, and the pidfile alone would let a second worker
   start beside it. The pane outlives the worker on both backends, so a task the
   ledger has settled is not read as busy. Evidence that cannot be read
   refuses. This is a refusal and not a queue: nothing is reserved, nothing is
   started later, and the operator runs the same command again once the active
   task has stopped. It comes before the worktree and the container, so a
   refused task is unchanged and still `queued`.
   A task that waits is refused the same way, ending `remains queued`, until the
   task it waits on is proved delivered and merged. The ledger must say `done`;
   the run record, the `/ship` receipt's `ci` commit and the consumed handoff
   carrying the ledger's pull request must agree, read from `state/` or, once
   that task is torn down, from the copy in `tasks/<after>/delivery/`; GitHub
   must say that pull request merged from `dux/<after>` at that commit into the
   registered base; the merge commit must be on that base once fetched; and a
   check named in `after-check` must have succeeded on it. What was verified is
   written to `tasks/<id>/prerequisite`, and a record already there, from an
   earlier start or carried by a retry, must match or the task stays queued.
   Milestone 2 dispatches `claude` workers only. `codex` is refused by
   `harness_refusal` in `dux-env`, which `dux-spawn` and `dux-worker-wrap` both
   call, so the `--harness` flag, `config/worker-harness` and
   `tasks/<id>/harness` all reach the same answer: a Codex worker has no deny
   list, so `git push --no-verify` skips the `pre-push` hook, its one
   mechanical guard. This does not touch Codex as the ship gate's reviewer.
4. `dux-worktree create <id>`: fetch `origin/<base>`, create the worktree
   (project mechanism for `ship`, `git worktree add` otherwise), discover the
   path, refuse the primary checkout or a stale tip, build
   `tasks/<id>/hooks/` with the base-branch `pre-push` guard and point the
   worktree's own git configuration at it with `git config --worktree
   core.hooksPath`, which needs `extensions.worktreeConfig` in the shared config
   and refuses a repository that shares `core.worktree` or `core.bare` with its
   worktrees. The guard therefore holds for the worktree's whole life and
   reaches no other repository. For `ship`
   under `git` copy the project's committed `.env*.example` and `.env*.sample`
   files, renamed to the name the project expects. A real ignored `.env` is
   never copied. Each copy is staged at `<dest>.dux-part` and renamed over
   `<dest>`; a pre-existing path at either name is refused, and the staging file
   is created with `O_EXCL` so it cannot follow a committed symlink. An
   uncommitted example, or a destination name the project does not ignore, is a
   finding; no example at all is a log line.
5. Spawn opens the tab, then starts the wrapper beside it. First it asks Claude
   Code whether it trusts the project: `hasTrustDialogAccepted` for the project
   path itself in `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`. It is the project
   and not the worktree, and not an ancestor of either: Claude Code trusts a
   directory as the repository it is in, resolves a linked worktree to the
   repository it was made from, and asks again for a repository whose parent is
   trusted. An untrusted project is a finding naming it and how to fix it, and
   nothing is opened, because the harness would otherwise raise its "do you
   trust this folder" dialog in the worker's tab and wait there for a keystroke
   nobody is watching for. Then `dux-backend open <id> <wt>` makes a tab holding
   a shell and nothing else, and its endpoint goes to `state/<id>.endpoint` and
   the ledger. Then spawn starts `bin/dux-worker-wrap <id>` itself, outside that
   tab, under `nohup` with its output appended to `state/<id>.wrap.log`, and
   keeps the pid it forked. It waits up to `DUX_SPAWN_START_SECS` (10 seconds)
   for the wrapper to write its own `state/<id>.pid`, and stops waiting the
   moment that forked pid exits, so a wrapper that refuses at once costs no
   wait. What happens next is decided by whether a handoff appeared while the
   wrapper lived: one that published nothing is undone, tab closed, endpoint
   cleared, worktree discarded and the brief's line put back, and one that
   published its refusal is left exactly as it stands, because the watcher owns
   what follows and the tab holds what the operator would want to see. A wrapper
   that is still there after the signal and ten more seconds is neither: undoing
   under a live wrapper would close the tab it is about to run in and discard
   the worktree it is about to work in, so everything stays where it is and the
   finding names the pid to stop, as `undo` does for a live container. Spawn
   then marks `running` and comments on a `gh:` issue. The `running` write is
   `dux-ledger set-if <id> state queued running`:
   the wrapper is already running by then, a worker that refuses at once leaves
   a proved terminal handoff the watcher can apply before that line runs, and an
   unconditional write would put a finished task back to `running` for good.
   `set-if` compares and writes under the ledger's own lock, so nothing can move
   between the two, and a refusal is a finding naming the state that won. After
   a failed `open` the brief's worktree line goes back to its placeholder either
   way, and the worktree is discarded only when `find` shows no container; a
   container that outlived the failed `open` is a finding naming it, never a
   silent cleanup around a live worker.
6. `dux-worker-wrap <id>` writes `state/<id>.pid`, makes the task channel
   (below), and writes a launcher into it: one `/bin/sh` file, mode 500, built
   by `worker_launcher` in `bin/workers/<harness>.sh`, which scrubs the
   environment, drops Dux's own `bin` from `PATH`, exports the two outbox
   variables and then execs the harness on the brief. That file exists because
   the pane's shell is the harness's parent now, not the wrapper, so everything
   the wrapper used to do to its own environment before forking has to travel
   in it. The wrapper titles the tab, runs the launcher in it with `dux-backend
   run`, and then asks `dux-backend pid` once a second, for up to
   `DUX_WRAP_START_SECS` (300 seconds), what that pane is running. The answer
   counts only when it carries the harness's own process name and the task
   worktree as its directory; a harness that never appears, or a multiplexer
   that cannot say, is a refusal rather than a guess. The process group that
   comes back is written to `state/<id>.pgid`. The heartbeat is the harness's
   own `PostToolUse` and `Stop` hooks, which the task's settings file points at
   `<channel>/beat`: every `DUX_HEARTBEAT_SECS` the wrapper compares that file's
   modification time with the last one it saw, and a beat that moved is one
   `working: heartbeat` line in `status.log`. A session that is thinking and not
   using tools writes nothing, which is what eventually reads as stale. The
   run's result is published as a handoff (below). A `done` proposal goes through `dux-result verify`
   first; a session that ends with no terminal proposal gets
   `ended: the session ended without a terminal status`, because a process the
   wrapper did not fork leaves no exit status to read.

   A `plan` or `ship` run whose `done` is proved parks instead of ending, and so
   does one that ends at `needs-decision` or `blocked`, once the harness's `Stop`
   hook has touched `<channel>/stopped` after the terminal line. The wait for
   that is `DUX_WRAP_IDLE_SECS` (60 seconds), and running out
   proves nothing: the run ends as any other does. A parked wrapper publishes
   the handoff, writes `state/<id>.parked` naming the run, itself and the group,
   and waits with the session idle at its prompt. Spawn and `dux-round` count a
   parked session as idle only while all three still hold. `dux-round <id>
   --file <path>` takes a `done` task whose pull request is open for feedback.
   `--purpose answer` takes a `needs-decision` or `blocked` task, and approves
   nothing. `--purpose approval` takes a `needs-decision` ship task briefed
   `--phase planning`, with `--plan`, `--tasks` and `--commit`: the commit must
   be the branch tip, with the plan committed there holding every task in the
   range. It writes `tasks/<id>/round-<n>.approval`, naming the plan, the range
   and the full commit, and moves the phase to `implementation`. Every purpose
   moves the ledger to `running` and renames `tasks/<id>/round-<n>.md` into
   place. A session no longer in its tab is refused, and its answer goes to a
   fresh task through `dux-recover --retry` instead. The wrapper takes the round
   up only after the watcher has consumed the parked run's handoff. It removes the marker, stages the file in the channel at mode 400,
   and types `Read <channel>/round-<n>.md and follow it.` into the tab through
   `dux-backend prompt`: the one line Dux ever writes there. The round is a new
   run, `<nonce>r<n>`, with its own run record and result context carrying
   `round` and `since`, and it ends as this step describes, parked again or not.
   The watcher counts the newest round file as activity, so a round is not
   stale for the days its task sat parked.
7. `dux-teardown <id>` (the ledger says terminal, worktree clean, branch pushed)
   ends a parked session first, the wrapper with `TERM` and then the harness's
   group, so the tab closes with nothing waiting in it. For a `done` task it
   copies the run record, the `/ship` receipts and the last handoff into
   `tasks/<id>/delivery/` for a task that waits on it, and a copy it cannot make
   is a finding that leaves everything in place. It then removes the worktree,
   closes the container, clears the run's retained references, and reports the ledger's own state and PR url. For a `done` task
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
   found. On success the ledger reads `dropped` and `data/tasks/<id>`, with any
   record of what the task waited on, is gone; no project repo, branch or pull
   request is touched.

## The task channel

A worker runs with the operator's own authority, so nothing it writes is
canonical and nothing it says is evidence. It writes into a channel of its own
and the wrapper decides what, if anything, reaches `status.log` and `report.md`.

- The channel is `state/channels/<id>.<run>`, mode 700, named with a random
  run id. It holds read-only copies of the brief and the worker settings, not
  the hooks, and two mode-600 files the worker appends to: `status.outbox` and
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
- The worker's environment is scrubbed by the launcher, of `DUX_*`, `CLAUDE_*`,
  `HERDR_*`, `TMUX*` and `GIT_CONFIG_*`, and of Dux's own `PATH` entry. Only
  `DUX_STATUS_LOG`, `DUX_REPORT` and, when Dux has one, `CLAUDE_CONFIG_DIR` are
  put back. The config directory travels because spawn read the trust record out
  of it: with the name scrubbed and nothing put back, the worker would answer the
  trust question out of a different file than the one that cleared it. It is the
  value Dux itself was given, baked in where the launcher is written, so a pane
  carrying another session's does not win. No `GIT_CONFIG_` name travels at
  all: an environment setting applies in every repository the worker touches,
  and the push guard belongs to the task worktree alone, which is where
  `dux-worktree` wrote it. The brief names those two variables; no Dux path is
  handed to a worker.
- The harness runs in the pane's own process group, with the operator's keyboard
  on its standard input. The wrapper did not fork it and so cannot wait on it:
  it learns the group from the multiplexer, writes it to `state/<id>.pgid`, and
  polls the pid with a command-line match, which is what makes a recycled pid,
  and a zombie, both read as gone. Before any terminal state is written the
  wrapper stops that whole group, TERM then KILL, and proves it gone. A survivor
  is a cleanup finding and no terminal state, so a parent that claims done while
  its children keep running completes nothing.
- Proposal rules, each one a failed task: what Dux has already read may not be
  rewritten or truncated, every line is `<state>: <text>` with a known state, a
  line is at most 200 bytes, the whole status outbox at most 64 KiB and the
  report at most 1 MiB, and after one terminal line nothing more may be written.
  Control characters are stripped. Only `working:` lines reach `status.log` from
  the wrapper; the terminal state is held until the run is over and leaves as a
  handoff, never as a line the wrapper appends.
- The tab is titled `<project>: <the brief's first line of intent>` once, when
  the run starts, and nothing else is ever written to it. What it draws is the
  worker's own screen: the operator reads it by looking and may type into it,
  and Dux never reads it by any means. Every notification, toast and digest line
  is fixed text chosen by state, with the url the ledger holds; `dux-recover` is
  the only place worker text reaches the operator, capped, cleaned and fenced as
  data.

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
- A parked run's handoff is published before the session is left idle, and its
  receipt stays at `state/<id>.ship-receipt`, where the watcher checks it, until
  that handoff is consumed. Only then does the wrapper keep it as
  `state/<id>.ship-receipt.delivered`, or `.unfinished` after a question or a
  blocker, and only then will it take up a round, because a round writes the
  run records again. Each round is proved on its own:
  its run, its receipt, its final commit, and a branch that still holds the
  commit the round started from. A round that rewrote what the operator
  reviewed is `ended`, never `done`.
- Work that plans first proves nothing before its approval. After it, a `done`
  is proved only when the plan differs from the approved commit in box ticks and
  the three lines under **Where this stands** alone, and every box in the
  approved range is ticked. The ticks are not the proof of delivery; the
  receipt, the pull request and CI still are.
- Sequences are retained for the whole run. `dux-teardown` is their lifecycle
  owner, and clears them with `state/<id>.run`, `state/<id>.result-context`,
  `state/<id>.ship-receipt`, `state/<id>.wrap.log`, `state/<id>.portal`,
  `state/<id>.pgid` and the task channel the portal names. The wrapper's log
  holds Dux's own lines about the run and nothing the worker wrote; spawn's
  start refusals point the operator at it, so it lives exactly as long as the
  task does. A wrapper that died without cleaning up leaves those
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
  with no result, never a quiet success. What counts as a survivor is read from
  `ps`, not from `kill -0`: a process nobody has waited on is still a process
  there, and on Linux `kill -0` answers for it, so a group of nothing but those
  is a group that has gone.
- It caps what a worker can say: 200 bytes a status line, 64 KiB of status
  proposals, 1 MiB of report. It does not cap what a worker can do inside its
  own worktree with the operator's own rights.
- Every operator surface Dux writes to, tab title, toast, notification and
  digest line, carries fixed text chosen by state and the url the ledger holds.
  `dux-recover` is the only place worker text reaches the operator, capped,
  cleaned and fenced as data.
- The worker's tab is not one of those surfaces. It is the harness's own screen,
  the operator reads and types into it directly, and nothing in `bin/` or
  `skills/` may read it back: no pane capture, no scrollback, no screenshot. So
  a worker's output is never summarised anywhere, and a failure tail says only
  that the output stayed in its tab.
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
| `stale` | Inspect a capped, fenced status tail, which is all the worker said; extend once when progressing, otherwise stop the matching wrapper. |
| `dead` | Mark failed and keep the worktree; the session the wrapper was watching may still be running in the task's tab. |
| `ended` | Run the same proof the wrapper would have run and publish what it proves into the next sequence; otherwise ask the operator, whose only classification is `failed`. |
| `failed` | Show the saved failure and offer one retry or a scout. |
| `done` | Nothing to recover. A pull request goes out as `Review, then merge or send feedback: <url>`; feedback is a round through `dux-round`, and a round that ends `failed` or `ended` leaves the pull request open and takes no further round. |
| from before the upgrade | `--retire-legacy` stops the old wrapper and publishes one retirement handoff; the branch and worktree are kept for one retry or a teardown. |
| `blocked`, `needs-decision` | Relay the meaning of fenced status data. A session parked in its tab takes the operator's answer, or approval of the plan it committed, as a round through `dux-round`; otherwise append the answer to one fresh retry. |

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
