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
  CLAUDE.md                 operating contract, <=150 lines, always loaded
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
    dux-worker-wrap         runs inside the worker pane: claude -p + status protocol
    dux-intake              pull labelled GitHub issues into backlog.md as queued
    backends/tmux.sh        backend adapter (section 9)
    backends/herdr.sh       backend adapter (section 9)
  data/                     durable, gitignored
    projects.md             registry: one line per project
    backlog.md              queued / running / awaiting / done, one line per task
    tasks/<id>/brief.md     what the worker was told
    tasks/<id>/status.log   append-only "<state>: <line>" from the worker
    tasks/<id>/report.md    scout output or failure tail
  state/                    runtime, gitignored
    events.log              one line per wake-worthy change; Monitor tails this
    dux.lock                pid of the live Dux session
    <id>.endpoint           backend endpoint: tmux window id or herdr pane id
    <id>.out                worker stream-json output
  tests/                    bats tests, fake claude
  config/backend            optional override: tmux | herdr
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
`dux-project` detects it and the operator confirms. `issues` is `off` or
`label:<name>`; only open issues carrying that label are eligible for intake
(section 10).

## 5. Task lifecycle

### 5.1 Shapes

| Shape | Worker model | Output | Definition of done |
|---|---|---|---|
| plan | Fable, high effort | spec + plan in `docs/superpowers/` of the project, docs-only PR | `done: PR <url>` |
| ship | Opus, effort per the operator's rule | one milestone implemented, `/ship` run | `done: PR <url>` after CI green |
| scout | Sonnet | `tasks/<id>/report.md` | `done: report` |

Dux brainstorms goals with the operator in conversation, then writes a brief.
The plan worker writes the spec and plan; the operator approves the docs PR.
Ship tasks are dispatched one milestone at a time, each with the plan path and
task range in the brief.

### 5.2 Task id

`<project>-<shape>-<yyyymmdd>-<3 random alnum>`, e.g. `fitfights_api-ship-20260903-k7q`.
Branch name follows the project's convention with the id as the slug.

### 5.3 Brief (`dux-brief`)

Under 60 lines. Sections, all required:

1. Intent: the operator's goal in their words, including constraints, exclusions,
   and decisions already made. Never a diff summary.
2. Acceptance criteria: numbered, testable.
3. Project: path, base branch, worktree path, plan path and task range for ship.
4. Rules: work alone, never address the operator, stay inside the worktree,
   never push to base, never merge, same obstacle twice means `blocked` and stop,
   report through the status protocol only, read `tasks/<id>/inbox.md` after
   writing `blocked` or `needs-decision` and before exiting.
5. Definition of done, per shape.

The brief never includes Dux conversation history or other tasks.

### 5.4 Status protocol

The worker appends to `tasks/<id>/status.log`:

```
working: <one line, what it is doing now>
needs-decision: <the question, options, recommendation>
blocked: <what, tried what>
done: <PR url | report>
failed: <one line>
```

`dux-worker-wrap` appends `failed: worker exited <code>` if `claude -p` exits
without a terminal line, and `working: heartbeat` every 5 minutes while the
process lives so stale detection has a signal even during long silent steps.

### 5.5 Spawn (`dux-spawn <project> <shape> <brief-path>`)

Refuses, with a finding, when:

- the project is not registered;
- the resolved worktree path equals the primary checkout;
- the worktree is not based on freshly fetched `origin/<base>`;
- the backend is unavailable or an endpoint for the id already exists;
- the lock is not held by this Dux session.

Otherwise: fetch, create worktree via the project's mechanism, copy the brief in,
call the backend's `open` (section 9) to get an endpoint running
`dux-worker-wrap`, record the endpoint and `running` in `backlog.md`.

The worker command is `claude -p` with the brief as the prompt, the project's
`CLAUDE.md` loading normally, the operator's global `CLAUDE.md` loading normally,
`--output-format stream-json` to `state/<id>.out`, and
`--dangerously-skip-permissions` for every shape, because a headless worker
cannot answer prompts and a denied tool call stalls the task. The blast radius is
the worktree plus `gh` and `codex` with the operator's credentials; `/ship`'s
refusal rules and the brief's never-push-to-base rule are the guards. Model via
`--model` per shape; effort via the CLI flag if this version exposes one,
otherwise a one-line system-prompt instruction in the brief.

### 5.6 Teardown (`dux-teardown <id>`)

Refuses when the worktree has uncommitted changes, unpushed commits, or the task
is not terminal. Otherwise removes the worktree with the project's mechanism,
calls the backend's `close`, marks `done` or `failed` in `backlog.md`. Task folder
is kept.

## 6. Supervision

### 6.1 Watcher (`dux-watch`)

A single bash process started by `dux-lock` acquire and killed on release. Every
30 seconds it reads the last line of every running task's `status.log` and asks
the backend `alive <endpoint>`, and appends to `state/events.log` only when:

- the last state changed to `done`, `failed`, `blocked`, or `needs-decision`;
- no new line for 20 minutes while the endpoint is alive (`stale: <id>`);
- the endpoint is gone without a terminal state (`dead: <id>`).

`working` lines never produce an event. Duplicate events for the same
(id, state) are suppressed.

### 6.2 Wake

Dux arms one persistent Monitor on `tail -F state/events.log`. Each line wakes
Dux once. On wake Dux reads that line and at most the last 5 lines of the task's
`status.log`, updates `backlog.md`, and decides: notify, recover, or record.

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

- `stale`: read the last 40 lines of `<id>.out`. If progressing, extend 20
  minutes once. Otherwise send `SIGINT`, wait 60 seconds, mark `failed`.
- `dead`: mark `failed`, preserve worktree, save the last 20 output lines to
  `report.md`.
- `failed`: report to operator with the tail. Offer retry (new task id, same
  brief plus the failure) or scout. Never auto-retry more than once.
- `blocked`: relay verbatim. Operator answers; Dux writes the answer to
  `tasks/<id>/inbox.md`, which the brief tells the worker to read when blocked;
  if the worker has exited, retry with the answer appended to the brief.

## 7. Session lifecycle

On start, CLAUDE.md instructs Dux to run `dux-lock acquire`, then `dux-intake`
for every project with issues enabled, then `dux-status`, then arm the Monitor. If the lock is held by a live pid, Dux announces it is
read-only and skips spawn, teardown, and recover. On stop, the lock releases and
the watcher dies; workers keep running under the backend and are reconciled
next start.

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
| `alive <endpoint>` | exit 0 if the container exists and its process is running |
| `tail <endpoint> <n>` | print the last n lines of output |
| `close <endpoint>` | close only that container; refuse if it is the operator's focused pane |
| `notify <title> <body>` | local visual notice, no-op if unsupported |

tmux: a window per task in the Dux session, `tmux new-window -d -n dux-<id>`.
`alive` checks the window and its pane pid. `notify` is `tmux display-message`.

Herdr: a tab per task in Dux's own workspace, read live from
`HERDR_WORKSPACE_ID`, via
`herdr tab create --workspace $HERDR_WORKSPACE_ID --cwd <worktree> --label dux-<id> --no-focus`,
then `herdr pane run <root_pane> <cmd>`. The endpoint is the pane id from the
create response, never derived from labels. `alive` is `herdr pane get`.
`tail` is `herdr pane read --source recent-unwrapped --lines n`. `close` is
`herdr pane close` on the exact recorded pane, never `workspace close`. `notify`
is `herdr notification show`.

Headless `claude -p` is not auto-detected by Herdr, so `dux-worker-wrap`
publishes state itself: on each status line it runs
`herdr pane report-agent $HERDR_PANE_ID --source dux --agent dux-<id> --state <s> --message <line>`
with `working` for working, `blocked` for needs-decision and blocked, and `idle`
for done and failed; it also sets the sidebar title with
`herdr pane report-metadata --title "<project>: <short intent>"`. Under tmux
these calls are skipped. The status protocol in section 5.4 remains the single
source of truth; backend state is presentation.

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

1. Reviewed-SHA binding. After step 6 and step 7 complete, record
   `reviewed_sha` in the plan file's "where this stands" block. Step 8 refuses to
   push unless `HEAD` equals or descends from it.
2. Head continuity. `ship-guard record <phase>` after steps 4, 6, 7; `ship-guard
   check` before 6, 7, 8. A backward or divergent `HEAD` stops the gate.
3. Fail-closed review parsing. If the Codex output lacks a findings section, or
   the security reviewer returns nothing parseable, stop. Never treat absence as
   clean.
4. Bounded fix rounds. Maximum three review-fix rounds, counted in the plan
   file. A fourth defect means: recommend reverting to the minimal fix, stop.
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
   12). Verbose material goes inside `<details>`.

Not ported: hook enforcement, CI auto-repair, transient reruns, evidence branch.

## 12. PR template

Installed by `dux-project` when the repo has none; existing templates are left
alone and reported.

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
- Approach A (agent distro) over native-only or a daemon.
- PR template lives in each repo, filled by `/ship`, not in global CLAUDE.md.
