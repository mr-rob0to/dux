# Dux: one session, from plan to pull request, and back

Design authority for the change that lets the operator talk to the Dux session and
nothing else: a plan comes back to that session, is read as a page, is approved
there, and the worker that wrote it goes on to build it. A worker's question comes
back the same way, and the answer goes back to the worker that asked. The
orchestrator design (`2026-09-03-dux-orchestrator-design.md`) stays the authority for
everything this document does not change; sections 5.1, 5.3, 5.4, 5.5 and 17 of it
point here.

Amended 2026-09-10, superseding the version in pull request #26, with three decisions
the operator made after the first draft: resume, never respawn (section 2); waiting is
a status line, not something Dux infers from elapsed time (section 4); stop the worker
process and resume its session later, rather than keeping it alive (section 4). The
first draft resumed only `plan` tasks; this one resumes every shape, retires the
respawn path, and says what a resume costs and what a pause can lose.

Plans: `docs/plans/2026-09-10-dux-m7-resume-any-worker.md` (milestone 7),
`docs/plans/2026-09-10-dux-m8-plan-ready-and-implement.md` (milestone 8) and
`docs/plans/2026-09-10-dux-m9-plan-page-and-rule.md` (milestone 9). The design
reviews are recorded at the end of the milestone 7 plan.

## 1. What the operator gets

Today a plan task ends with a docs-only pull request the operator has to go and find,
read as a diff, merge, and then dispatch a second task to implement. A worker that
asks the operator anything is thrown away: the answer is appended to its brief and a
new worker starts in a new worktree, with a new session that has to read everything
again. After this change:

- A worker that asks a question, or hits a wall, stops. The operator answers in the
  Dux session and the same worker picks up where it left off, in the same worktree, on
  the same branch, with everything it had read still in its context. This holds for
  every shape: `plan`, `ship` and `scout`.
- A plan task pauses when its plan is written. Dux tells the operator, on the phone
  and in the session, that a plan is waiting.
- The operator reads the plan as a page, rendered by Dux from the plan file, opened
  in their browser. They never read a diff to approve a plan.
- The operator says "approve", or says what to change, in the Dux session. Nothing
  else is touched. A change request goes back to the same worker, which revises and
  pauses again. An approval goes back to the same worker, which implements the plan,
  ticks its boxes, runs `/ship`, and ends with one pull request holding the spec, the
  plan and the code.
- A worker that fails part-way is resumed once, not restarted. What it had done stays.
- Dux and the worker decide whether a change needs a plan at all by a written rule
  (section 10). A change that meets none of its clauses ships without one.

Out of scope: the two branches in flight on `bin/dux-project` and `bin/dux-teardown`.
Neither script is edited. Section 12 lists what teardown therefore leaves behind.

## 2. The rule: resume, never respawn

The operator's rule, which this design applies and does not weigh:

> The existing worker is resumed for anything that continues its own work. That means
> implementation it has already started, and any question it needs the operator to
> answer. A separate fresh worker is right only when the task is purely to write a
> plan.

Applied to Dux:

- **Every question resumes.** A `needs-decision:` or `blocked:` line from any shape
  parks the task. The operator's answer becomes a round (section 7) and the same
  session continues. This replaces `dux-recover --retry --answer-file`, which made a
  new task, a new branch and a new session for every question, and which could not
  retry a brief near its line cap at all because it appended the answer to the intent.
- **Every failure resumes, once.** `failed:` from any shape, a `dead` worker, or a
  `stale` one the operator stopped, is continued by a `retry` round in the same
  session. The worker's uncommitted work is still in its worktree. This replaces the
  automatic retry that copied the brief into a new task.
- **Approval resumes.** A `plan` task that pauses at `plan-ready` is approved or
  changed by a round to the same session; the worker that reasoned the plan out builds
  it.
- **The one fresh worker.** A `plan` task dispatched as **plan only** (section 3) ends
  at a docs-only pull request, as every plan task does today. It is for a document the
  operator wants merged before anything is built on it: a roadmap, a design amendment
  such as this one, a plan that spans more than one milestone. Its implementer, later,
  is a fresh `ship` worker with `--plan` and `--tasks`, reading the merged plan. That
  is the only place a fresh worker is the design; everywhere else it is a defect.
- **A session the harness has lost** is the one case where continuing means a new
  session (`--fresh`, section 7). It is the same task, branch and worktree, and the new
  session is given the brief and every round so far. It is a fallback, recorded as a
  finding when it happens, never the normal path.

`dux-recover --retry` is retired. Its two users, the answer and the automatic retry,
are rounds now. Nothing else made a second task from a first one.

## 3. The shape of a task after this change

```
queued -> running -+-(plan proved)-> plan-ready -(approve)-> running -> done | ended
                   |                    |  ^
                   |                    |  '-(change)-- running <-'
                   |                    '-(drop)-> failed
                   |
                   +-(question)-> needs-decision | blocked -(answer)-> running
                   |
                   +-(stopped or exited)-> failed | dead -(retry, once)-> running
```

The middle and bottom arms are every shape. The top arm is a `plan` task that is not
plan only. `done`, `ended` after a failed proof, and `failed` after a drop or a second
failure are where a task ends.

One task, one branch, one worktree, several runs. A run is what it is today: one
wrapper process, one task channel, one run record, one handoff. What is new is that
a task can have more than one, and that each run has a **kind**:

| Kind | Which run | Worker may propose | Proof that ends it |
|---|---|---|---|
| `plan` | first run of a `plan` task, and every run after a change request or an answer given in a plan round | `plan-ready:`, `needs-decision:`, `blocked:`, `failed:` | section 5 |
| `implement` | the run after approval, an answer given in an implement round, and one retry | `done:`, `needs-decision:`, `blocked:`, `failed:` | section 9 |
| `plan-only` | every run of a `plan` task dispatched plan only | `done:` and the rest, as a plan task today | unchanged: the docs-only proof `dux-result` has today |
| `ship` | every run of a `ship` task | `done:` and the rest, as today | unchanged, plus section 11 |
| `scout` | every run of a `scout` task | `done: report` and the rest | unchanged |

The kind is decided by Dux when the run starts and written into the run's result
context, so `dux-result` proves a run against its kind rather than the task's shape.
A resumed run keeps the shape's model: every run of a `plan` task, resumed or not, is
started with the `plan` entry of `config/models` (Fable, high effort), and the approve
round tells it to delegate each task's code to a subagent on the operator's
implementation model; every run of a `ship` task uses the `ship` entry, and of a
`scout` task the `scout` entry.

**Plan only** is a flag on the brief, `dux-brief <id> --plan-only`, recorded as a
line under the brief's project facts and read by the wrapper into the kind. The
dispatch skill asks for it when the intent is a document the operator wants merged on
its own; the default is plan and build. A plan-only task keeps today's rules text, its
worktree is made the plain `git` way, and it never reaches `plan-ready`.

Why one task and not two: the operator asked for approval and answers to travel back
to the same worker. The worker runs headless as `claude -p`, and that harness can
continue a session by id (`--session-id` on the first run, `--resume <id>` on later
ones; both present in Claude Code 2.1.267). So "the same worker" is literal: the same
session, with the reasoning behind its plan and its rejected alternatives still in
context, picks up the approval, the change request or the answer as its next prompt.
A second task would have a new branch, a fresh session and a brief that restates the
plan; it would also need the plan merged first, which is the pull request the operator
does not want to go and find.

Because a `plan` task's worker will implement, its worktree is made the way a `ship`
worktree is: with the project's own mechanism (`make worktree`, a script, or plain
`git worktree add`), and with the project's committed env examples copied under the
`git` mechanism. A plan spawn on a project with a slow mechanism takes the minutes a
ship spawn takes; the dispatch skill already raises the tool timeout for that.

## 4. The pause: three parked states, one stopped process

A task is **parked** in `plan-ready`, `needs-decision` or `blocked`. In all three the
worker process is gone and the operator is the only thing that can move the task.

`plan-ready` is a new task state, not a reuse of `needs-decision`. The two differ in
every way that matters:

| | `needs-decision`, `blocked` | `plan-ready` |
|---|---|---|
| What arrives | the worker's own words, a question or a wall | a file on the branch, proved from Git |
| What the operator answers | free text | approve, change, or drop |
| What Dux reads | nothing but the ledger; the question only through `dux-recover` | nothing but the ledger and Dux's own page |
| Pushed to the phone | `needs-decision` yes, `blocked` no, as today | yes |
| Worktree | as the worker left it, possibly dirty | clean and pushed, the proof required it |

**The worker's side.** A worker parks by appending one terminal line, `plan-ready:`,
`needs-decision:` or `blocked:`, to its status outbox and exiting. That is the rule the
brief already gives for the last two, and the wrapper enforces it: one terminal line,
then exit, and a second line or any text after it is a violation. In a `plan` round
`done:` is a rule violation and fails the run, so a worker following the old brief
cannot slip a docs-only "done" past the new proof. `plan-ready:` outside a `plan`
round is the same kind of violation. The wrapper holds a `plan-ready:` line back
exactly as it holds `done:`, and asks `dux-result` to prove it (section 5). What
reaches `status.log` is the proof's own line, never the worker's.

**How a parked worker is told apart from a hung one.** By the ledger state, which was
set from a status line the worker wrote, and never by elapsed time. This is the
operator's first decision, and the watcher already works this way:

- A parked task is `plan-ready`, `needs-decision` or `blocked` because the wrapper
  published a handoff carrying that word after the worker exited, and the watcher
  consumed it. The watcher's liveness pass lists only `running` and `stale` tasks
  (`bin/dux-watch`, `watched_ids`), so a parked task is never measured against the
  20-minute silence clock and cannot go `stale` or `dead`, however long the operator
  takes. The watcher touches a parked task only to finish a handoff a crash
  interrupted. `dux-ledger list --unacked` includes all three, so a wake that lands
  while no Monitor is armed is still under `unacknowledged` at the next session start.
- A hung worker is `running` with no status line for 20 minutes. It goes `stale`, the
  operator or `dux-recover --stop` sends it a signal, and it is `dead` or `failed`. A
  worker that has decided to wait for the operator but not written the line is hung by
  definition: the brief says write the line and exit, and Dux does not guess.
- A worker that wrote its terminal line and then kept running is the one ambiguous
  shape. The wrapper buffers the line and waits for the process to exit, so the task
  stays `running` and goes `stale` after 20 minutes. When `--stop` ends the worker, the
  wrapper publishes the buffered line as the result, so the task parks late instead of
  failing. Nothing new is needed for this; it is what the wrapper does today.

**The process is stopped; the session is resumed.** This is the operator's second
decision, and the alternative is recorded so it is not re-argued:

- *Stopped and resumed* (chosen). The worker exits. What it holds is its session
  transcript, which the harness keeps on disk under its own project directory, keyed by
  the session id Dux chose and the worktree it ran in. Nothing of the worker's is in
  memory while it waits. The costs, each met as stated:
  - The first turn after a resume re-reads the whole transcript into the model's
    context, so a resume costs one full-context prompt. The harness's prompt cache
    expires within an hour of the last turn, so a live process waiting longer than
    that, which every wait on the operator is, pays the same. Met by the round cap:
    at most eight rounds, so at most eight such prompts.
  - The container has to be closed and opened again, because the backend runs one
    command per pane. A close the backend refuses (the operator's focused pane) is a
    finding that names the tab to switch away from. Met by the resume step that does
    it, section 7.
  - The transcript is the harness's file, not Dux's. It can be deleted by the harness's
    own retention (`cleanupPeriodDays`, thirty days by default) or by a harness upgrade
    that cannot read it. Met by `--fresh`, section 7, which is why it is in milestone 7.
  - The context is as long on resume as it was at the stop, and grows with every round.
    A task that goes eight rounds is a long session. Met by the round cap, which is also
    the point at which the plan is not converging and the operator should redispatch
    with a sharper intent.
- *Kept alive* (rejected). The harness's headless mode prints one result and exits;
  keeping it waiting would need `--input-format stream-json` and a writer Dux does not
  have. Each parked task would hold a process, its memory and a pane for hours or days,
  and the watcher would need a second signal to separate "waiting" from "hung", which
  is the ambiguity the operator's first decision removes. The prompt cache would have
  expired anyway. Nothing is bought.

**While it waits.** The container stays: a tmux window with remain-on-exit, or a Herdr
tab, showing the wrapper's last log line. That is the one thing a parked task holds,
one pane, and it is reused by the resume. At `plan-ready` the worktree is clean and its
branch is pushed, which the proof required. At `needs-decision` or `blocked` the
worktree is however the worker left it, dirty included, and is not touched: the
uncommitted work is the worker's own to continue. The digest counts all three under
"awaiting you"; for `plan-ready` it adds the GitHub link and, from milestone 9, the
page path. There is no pull request yet for a plan. `dux-spawn` refuses a plain spawn
of a parked task (not `queued`), `dux-teardown` refuses it (not terminal), and the
only ways out are the rounds in section 7 and a drop.

## 5. Proof at `plan-ready`

`dux-result verify <id> <run>` for a run of kind `plan` proves, in this order, and
prints one line or exits 1 with a reason:

1. The run record and result context are this run's, as today.
2. The worktree is on `dux/<id>` and clean.
3. The branch is pushed: `refs/remotes/origin/dux/<id>` exists in the worktree and
   equals the local tip. A push updates that ref, so the check is offline and needs
   no credentials; it catches a worker that forgot to push, which is the mistake it
   is for. The hook-free Git call `dux-result` already uses cannot reach the network
   with the operator's credentials, and does not need to.
4. Every change since the merge base with `origin/<base>` passes the document rule
   the plan shape has today (`plan_entry_ok`: a regular `docs/**/*.md`, or a flat
   `docs/plans/*.html`). The rule is reused unchanged; the brief tells the worker to
   write markdown only, and nothing here reads an HTML file.
5. At least one `docs/specs/*.md` changed (constitution principle 8: the decisions
   the plan needs are in the spec before the plan).
6. Exactly one `docs/plans/*.md` was **added** (raw status `A`). Modified plan files
   (the roadmap, a previous plan's "where this stands") are allowed and ignored. The
   added file's path is the plan. Its name is `[A-Za-z0-9._-]+\.md`, at most 120
   characters, no subdirectory; anything else is not a plan Dux can name, and the
   reason says so without repeating the name.
7. The plan has headings `## Task 1` to `## Task K`, read with the section reader
   `check_plan_tasks` already has, in a new mode that wants at least one box under
   each task, ticked or not (the existing mode wants every box ticked and stays for
   the ship proof). K is contiguous from 1 and at most 12. Over 12 is the
   constitution's cap on a milestone and the reason is `the plan has K tasks; the cap
   is 12`.

The line it prints, and the only thing about the plan that ever enters `status.log`,
the events log or the ledger, is built from Git's answers, never the worker's:

```
plan-ready: docs/plans/2026-09-10-thing.md tasks 1-7 at 4f9c2e1a...
```

The watcher applies it like `done: PR`: status line, event, ledger state
`plan-ready`, and a new state file `state/<id>.plan`, written with a temp file and one
rename:

```
version=1
id=<id>
path=docs/plans/2026-09-10-thing.md
tasks=1-7
sha=<40 hex>
```

That file is Dux's, written by the watcher from a line `dux-result` composed. It is
what the page renderer, the digest, the inspect output and the implement round read.
Nothing reads the worker's `plan-ready:` line for its content; the wrapper discards it
after the proof. The watcher's own cross-check of a `done` handoff (a complete `/ship`
receipt behind it) switches from the context's shape to its kind, so an `implement`
run's `done` is checked there too.

A proof that fails leaves the run `ended: the result was not proved: <reason>`, exactly
as a failed `done` does today. `dux-recover <id>` on an `ended` task re-runs the same
proof and publishes what it proves; it takes the handoff's event from the first word of
the proof's line (`plan-ready` or `done`) rather than assuming `done`, so a plan round
that ended because the push had not landed yet is recovered by one command after the
push. An unproved result still publishes nothing and says why.

## 6. How the plan reaches the operator without breaking hard rule 3

Hard rule 3 says Dux never reads raw worker text. A plan is worker text, and the
operator has to read it. The resolution is the same one `dux-recover` uses: the
worker's words reach the operator through a fixed frame Dux owns, capped and cleaned,
and never reach Dux's own context at all.

**The path.**

1. The worker writes markdown only. The brief's plan rules say so: no HTML, no
   published artifact, no waiting in-session for approval.
2. `dux-result` proves the branch and names the plan's path from Git (section 5).
3. The watcher writes `state/<id>.plan` and raises `plan-ready`.
4. On the wake Dux runs `bin/dux-notify <id>`, which prints a fixed line from the
   ledger (`Approve or change: <project> plan is ready (<id>)`) for the phone, and
   `bin/dux-recover <id>`, which prints the GitHub link to the plan
   (`https://github.com/<repo>/blob/dux/<id>/<path>`, built from the registry and the
   proven path) and one link per other document the plan round changed, read from
   Git's name-only diff between the merge base and the proven commit. From milestone
   9 Dux also runs `bin/dux-plan-page <id> --open`, which renders `state/<id>.plan.html`
   and opens it in the operator's browser. Dux repeats the links and the page path in
   fixed text and says: approve, say what to change, or drop.
5. The operator reads the page. Dux reads nothing: not the markdown, not the page.
   Until milestone 9 lands, the GitHub links are the reading surface; GitHub renders
   the markdown through its own sanitiser.

**What the operator is approving.** Everything the plan round changed: the plan and
every other document on the branch, which check 5 says includes at least one spec
file. The page therefore lists every changed document path, renders the plan first,
and renders each changed `docs/specs/*.md` after it as a folded section. The approval
covers that set, and section 9 freezes it.

**The page (`bin/dux-plan-page <id> [--open]`).** A fixed HTML template that Dux
owns, with the documents' text placed into it as data:

- Source: each document at the proven commit, read with `git show <sha>:<path>` under
  the hook-free, config-free Git call `dux-result` already uses. The working files are
  not read, so what the operator sees is what was pushed.
- Cap: 512 KiB per document. Over that, a finding and no page. A line over 1,000
  characters is cut there with a visible marker. The reader is protected from a page
  that never finishes, not from a long plan.
- Cleaning: control characters stripped (the `dux-recover` filter), Unicode format
  characters stripped (`strip_format_chars`, so a right-to-left override cannot make
  "drop" read as "approve"), and every `<`, `>`, `&`, `"` escaped before any markdown
  is interpreted. Raw HTML in the plan is shown as text.
- What renders: ATX headings, paragraphs, bullet and numbered lists to two levels,
  task boxes as glyphs, fenced code, inline code, bold, italic, pipe tables, rules. A
  block quote renders as a paragraph. A link renders as its text followed by its target
  in brackets, not as an anchor. An image renders as `[image: alt]`. Nothing on the
  page is clickable and nothing on it loads anything.
- Fixed structure: the first heading is the title; a "Where this stands" section is
  a callout at the top; `## Task N` sections fold (`<details>`, open when six or
  fewer); "Risks", "Open questions" and "Design review" sections get a tinted panel;
  each further document is one folded section named by its path. The reader scans
  the shape before the words, which is the reason the page exists for milestone-sized
  plans.
- Locked down: `<meta http-equiv="Content-Security-Policy" content="default-src
  'none'; style-src 'unsafe-inline'">`, no script element, no external resource, no
  form. A `source-sha256` meta of the plan's bytes, as the one hand-written page in
  `docs/plans/` already carries, and a `source-commit` meta, which is new.
- Output: `state/<id>.plan.html`, mode 600, overwritten on every plan round. `--open`
  runs `open` on macOS or `xdg-open` elsewhere when present; otherwise the path is
  printed and that is all.

**What a controller of the plan text can reach.** Assume the plan says whatever an
adversary wants. Then:

- Dux's context: nothing. Dux never reads the file. `dux-result` parses it
  mechanically for headings and boxes and emits a path (validated against a
  character class) and a count (an integer at most 12). `dux-plan-page` reads it and
  writes a file. `dux-notify`, `dux-status`, `dux-recover` and the events log carry
  paths from Git and fixed words.
- The operator's browser: text, in a page that cannot run script, fetch, submit, or
  navigate. A link in the plan is visible as text and has to be typed to be followed.
- The operator's judgement: a plan can be misleading. That is the same exposure as
  today's pull request diff, and the cost of a bad approval is one branch of work the
  operator still has to merge by hand after `/ship`'s gate. Hard rules 2 and 4 hold.
- Dux's state: the plan path is the only worker-influenced value written anywhere, it
  is a repository-relative document path under `docs/plans/`, and every reader joins
  it under the worktree or passes it to `git show`. A path with `..`, a slash inside
  the name, a quote, or a control byte never gets that far. The other document paths
  are read from Git each time and never stored.

What this does not claim: the worker runs as the operator and can write anything to
disk, including `state/<id>.plan.html`. The page is a defence against text, not
against a hostile program, which is the boundary the orchestrator spec already draws.
Two things this leaves as they are: `dux-result` already repeats one worker-chosen
file name into an `ended:` reason (`check_plan_shape`), which reaches the operator
only fenced through `dux-recover`; and the GitHub links are clickable in the Dux
session, as a pull request link is today.

## 7. Approve, change, answer, retry, fresh, drop

Five answers, one mechanism. Every answer is a **round**: a prompt file Dux renders
from fixed text, and a new run of the same task started by `dux-spawn <id> --resume`.
Rounds apply to every shape; only `approve` and `change` are particular to a `plan`
task that is not plan only.

**Round files.** `dux-brief <id> --round approve|change|answer|retry [--answer-file <f>]`
renders `tasks/<id>/round-<n>.md` from `templates/round.md`, `n` counting from 1. The
file is under 40 lines and contains:

- `approve` (from `plan-ready`): the proven plan path, task range and commit (from
  `state/<id>.plan`); the instruction to implement in this worktree on this branch,
  one task at a time in order, ticking each box in the plan file as it lands and
  break-verifying at the task boundary; that the plan's task sections and the spec
  files it changed are approved text and must not change, with divergences recorded
  above the first task heading; to delegate each task's code to a subagent on the
  operator's implementation model (Opus, max effort) and keep this session for
  orchestration and the plan file; to run `/ship` as the only gate; then `done: PR
  <url>`; and that every rule in the brief still applies.
- `change` (from `plan-ready`): the operator's answer file, verbatim (it is the
  operator's text, trusted as the intent is); the instruction to revise the same plan
  file on this branch, push, and append `plan-ready:` again.
- `answer` (from `needs-decision` or `blocked`, any shape): the operator's answer
  file, verbatim; the instruction to continue the run that asked, from the state of
  the worktree as it stands, and to finish with the terminal line that run's kind
  allows. The new run's kind is the kind of the run that asked.
- `retry` (from `failed`, any shape, once; a `dead` task is marked `failed` by
  `dux-recover` first, as today): the last status lines and the
  failure tail of the previous run, cleaned, capped and fenced exactly as
  `dux-recover` fences them today; the instruction to look at `git status` and the
  plan's boxes before anything else, because the last turn may have been cut off
  mid-edit, and then continue to the terminal line the kind allows. For `implement`
  and `ship` that is the plan file's boxes, then `/ship`, then `done:`.

Refusals, each a finding: the state does not fit the kind; `change` or `answer`
without `--answer-file`; an answer file containing an `<untrusted-` fence; a second
`approve`; a second `retry`; a ninth round of any kind; a round file over 40 lines; a
round rendered before the previous one has run. Eight rounds in all is the cap on the
conversation: past it the plan is not converging, and the operator's next move is drop
and redispatch with a sharper intent.

**An implement run that does not prove.** A red check, an unticked box or a missing
receipt leaves the run `ended`, as a ship task's does today. The path is
`dux-recover <id> --classify failed`, then `--round retry` and `--resume retry`, once.

**`dux-spawn <id> --resume <round-kind> [--fresh]`.** In order, each step a finding
when it fails:

1. Lock held; the state fits the kind (`plan-ready` for approve and change;
   `needs-decision` or `blocked` for answer; `failed` for retry); the round
   file for this round exists and is the newest.
2. No live worker: the pidfile and process-group checks a first spawn makes. A
   wrapper that is somehow still running is a finding, never a signal.
3. The worktree recorded in the brief exists and is on `dux/<id>`. For `approve` and
   `change` it is also clean, which the plan proof already required. For `answer` and
   `retry` it is left as it is: a dirty worktree is the worker's own work in progress,
   and the round tells the worker to start from `git status`.
4. For `approve`: write `tasks/<id>/approved`, one line, the time and the plan's
   commit.
5. Archive the previous run's references (`state/<id>.run`, `.portal`, `.pgid`,
   `.result-context`, `.pid`, `.out`, `.ship-receipt`) into
   `state/<id>.runs/<run>/`, one rename each. Handoffs stay where they are, retained
   until teardown; the wrapper's refusal on an existing handoff directory becomes a
   refusal on an **unconsumed** handoff. A crash between two renames leaves a run the
   wrapper refuses to start over; the refusal names the leftover file, and the
   operator's fix is the same rename.
6. Close the finished container and open a fresh one with the same name, through the
   backend's existing `close` and `open`. A close the backend refuses (a focused
   pane) is a finding that names the tab to switch away from. Record the new
   endpoint.
7. Start the wrapper with the round file as the prompt. The result context carries
   the kind (`implement` for approve; `plan` for change; the asking run's kind for
   answer; the failed run's kind for retry), and for `implement` the `plan=` and
   `tasks=` from `state/<id>.plan`. The wrapper sets `DUX_SHIP_RECORD` and the
   ship-only environment for `implement` runs exactly as it does for a `ship` task.
8. Ledger `set-if <state> running`; acknowledgement cleared so the next wake counts.

**Session continuity.** The first spawn chooses a UUID (`uuidgen`, else 32 hex from
`/dev/urandom`), writes it to `tasks/<id>/session` (mode 600), and the worker adapter
passes `--session-id <uuid>`. Every resume passes `--resume <uuid>` with the round
file as the prompt; the session already holds the brief. The adapter's signature
becomes `worker_run <prompt-file> <model> <effort> <settings> <session> <first|resume>`.
The harness keys a session by the directory it started in, so a resume runs from the
worktree, which the wrapper does already.

**`--fresh`, for a session the harness cannot find.** A resume the harness refuses
(its transcript removed by the harness's own retention, or a harness upgrade that
cannot read it) fails the run with the harness's exit code, and `dux-recover <id>`
names the flag in its `next:` line. `dux-spawn <id> --resume retry --fresh` writes a
new session id over `tasks/<id>/session`, keeps the old one in
`tasks/<id>/session.<n>`, and starts the wrapper with a prompt file staged at
`tasks/<id>/round-<n>.fresh.md`: the brief, then every round file so far in order, then
the retry round. The adapter is called with `first`. What the new session has is
everything Dux ever said to the old one and everything the operator answered; what it
does not have is the old session's reasoning, which is the loss section 8 names.
`--fresh` is refused when the previous run did not fail with the harness's exit code
(`--fresh is for a resume the harness refused; the last run ended <state>`), so it
cannot be used to dodge a worker's own failure. It counts as the one retry.

**Drop.** `dux-recover <id> --classify failed` accepts `plan-ready`, `needs-decision`
and `blocked` as well as `ended`. The status line is `failed: dropped by the
operator`, the branch and worktree are kept, and teardown proceeds as for any failed
task.

**The Dux session.** On a `plan-ready` wake: `dux-notify` and push; `dux-recover <id>`
for the links; from milestone 9, `dux-plan-page --open`; tell the operator in fixed
words; acknowledge. On a `needs-decision` or `blocked` wake: as today, the question
through `dux-recover`, fenced. On the operator's answer, all through
`skills/dux-recover`:

- "approve": `bin/dux-brief <id> --round approve`, then `bin/dux-spawn <id> --resume approve`.
- a change, or an answer to a question: write it to `data/tasks/<id>/answer.md`,
  `bin/dux-brief <id> --round change|answer --answer-file ...`, then
  `bin/dux-spawn <id> --resume change|answer`.
- "retry", on a failed task (a dead one is first marked failed by `bin/dux-recover
  <id>`, as today): `bin/dux-brief <id> --round retry`, then
  `bin/dux-spawn <id> --resume retry`, with `--fresh` only when the previous run's
  inspect output named it.
- "drop": `bin/dux-recover <id> --classify failed`, then teardown when the operator
  says so.

The operator can ask Dux nothing about the plan's content. Dux has not read it and
says so; the page is the answer. This is the cost of hard rule 3 and it is stated in
the skill so the operator is not surprised by it.

## 8. A worker that dies mid-pause, and what is recovered

While a task is parked there is no worker process, so "dies" means one of four
things. In every case the operator's answer, the plan and Dux's record are on disk
and survive; only the session can be lost, and it is the harness's file, not Dux's.

| What happens | What is on disk | What Dux does |
|---|---|---|
| The machine or Dux restarts during the pause | everything: the ledger state, the branch (pushed at `plan-ready`), the worktree as the worker left it, `state/<id>.plan`, `tasks/<id>/session`, every round file and answer, `tasks/<id>/approved` if given | nothing is needed; after a restart Dux reconciles from the ledger, the wake is still under `unacknowledged`, and a round resumes the session as if no time had passed |
| The harness's transcript is gone (retention, upgrade, the operator cleaned it) | as above, minus the session | the resume fails with the harness's exit code; `dux-recover` names `--fresh`; the operator's retry starts a new session with the brief and every round so far. Lost: the worker's reasoning, its rejected alternatives and what it had read. Kept: every decision that was written down, which is why approvals, answers and the plan are files |
| The resumed run dies before it finishes (a rate limit, a crash, a kill) | the transcript up to the last completed turn; the worktree with whatever the last turn had half-done; the status log up to the last `working:` line | the wrapper publishes `failed: worker exited <code>` with the failure tail, or the watcher marks it `dead`; one `retry` round resumes the session, and the round's first instruction is to read `git status` and the plan's boxes before continuing. A second death is `failed` for good, and the path is drop |
| The worktree is gone or on the wrong branch | the ledger and the session, but not the work | the resume refuses at step 3 and names the worktree; there is no automatic repair, because rebuilding a worktree around uncommitted work is not something a script should guess at |

What is never recovered from the worker's own words: the ledger state comes from the
handoff, the plan's path and commit from Git, the round count from the files Dux
wrote. The one thing that lives only in the session, the worker's reasoning, is the
one thing this design accepts losing, because the alternative is a worker that never
stops.

## 9. Proof after implementation, and why it stays one task

`dux-result verify` for a run of kind `implement` is the ship proof with two inputs
that come from Dux's state rather than the brief, and one check that is new:

- `plan=` and `tasks=` in the result context were copied from `state/<id>.plan` by the
  wrapper at run start, so the boxes checked are the boxes of the plan at the path Git
  named. A worker that renames the plan after approval fails the proof at "the plan
  the brief names is not a regular file in the worktree".
- **The approved text is frozen.** For every path the plan round changed under
  `docs/specs/`, the blob at the tip equals the blob at the approved commit. For the
  plan file, the text from the first `## Task` heading to the end of the file, with
  every `[ ]` normalised to `[x]`, is identical at the tip and at the approved commit;
  the header above the first task heading may change, which is where "where this
  stands" and any recorded divergence live. The reason is `the plan changed after
  approval outside its boxes and header` or `<spec path> changed after approval`.
  This is what makes "the operator approved this" true of what ships: a worker that
  rewrites a task under the same heading, ticks it, and runs `/ship` fails here.
  Other documents, `ARCHITECTURE.md` included, may change freely; the constitution
  asks for that.
- Everything else is unchanged: the worktree clean and on branch, exactly one open
  non-draft pull request headed by this branch at its tip, at least one change
  outside the plan documents, every task in the range with all boxes ticked, a
  `/ship` receipt for **this run** in the five phases ending at the tip, and green
  checks. The receipt check already compares the run id, so a receipt from the plan
  round can never stand in.

Why this is one task and not "plan task, then ship task":

- The pull request is one: spec, plan and code, on the branch the plan was written
  on. There is no docs-only pull request to find, and the plan is recorded in the
  repository exactly as the constitution asks (the plan file with its boxes ticked,
  in the same pull request as the code).
- The proof does not weaken. Each run is proved against its own kind with its own
  receipt; the task is `done` only when the implement run's proof passes. A task that
  paused and never resumed is `plan-ready` for as long as the operator leaves it, and
  a drop makes it `failed`, never `done`.
- What a second task would add is a second dispatch, a second brief that restates the
  plan, a second worktree, and the plan merge in between. None of that is evidence.

A plan whose implementation is more than one milestone (over 12 tasks or 2,500 lines
by the roadmap's sizing) is written as a spec, a roadmap and the first milestone's
plan. The approve round implements that first milestone. Every later milestone is a
new `plan` task pointed at the merged spec and roadmap, which writes its own plan and
implements it the same way. `ship` tasks with a plan path and task range remain for
the case where a plan was merged earlier and only its implementation is wanted, which
is the plan-only task's second half.

## 10. When a plan is warranted

The rule is applied twice: by Dux, with the operator, when choosing the shape at
dispatch (`plan`, or `ship` without a plan); and by a `ship` worker with no plan, who
writes `blocked: needs a plan: <clause>` and stops when the change turns out to meet a
clause once the code has been read. Nothing steps down: a `plan` worker that finds the
change small still writes the plan, which is short, and pauses.

A change gets a plan when **any one** of these is true. Otherwise it does not.

1. **Interface.** It adds, removes or renames something another script, skill or
   session reads: a task state, a script, a state file, a ledger key, a config file,
   a status-line form, a flag, a command a skill names. The test is mechanical: the
   component list or a numbered flow in `ARCHITECTURE.md` would gain or lose a line.
   Editing the description of an existing line does not count.
2. **Decision.** Building it means choosing between ways that produce different
   things. Count the choices the intent would have to record: two or more, plan. One,
   with a recommendation, is made in the conversation and written into the intent.
3. **Size.** The estimate, made the way the roadmap's "How a milestone is sized"
   says, is over 400 added lines outside tests and documents, or over 3 commit-sized
   steps. File counts are not a signal: a rename across twenty files is one step.
4. **Blast radius.** It changes a format on disk that older data must survive (the
   ledger line, a run record version, a state file), a contract between two
   repositories, or what a guard the threat boundary names accepts or refuses (a new
   word the wrapper takes from a worker, a new input `dux-result` proves from, a deny
   rule, a hook). A fix that makes a guard do what the spec already says, with a test
   written first that fails on the old code, is not a change to what it accepts.
5. **Asked for.** The operator wants one.

Documents-only changes never get a plan. A change that a clause catches gets a plan
even when it is small; a plan for a small change is a short page.

**Worked through against 2026-09-09.**

- Pull request #24, reviewers picked from what the host has at gate time (595 added
  lines: 290 in tests, 87 in the spec, 46 in other documents, the rest in `ship-env`,
  two config templates and the skill). Clause 1: `ship-env` was already a component;
  its line's description changed and no line was added or removed. No. Clause 2: one
  choice, gate time against install time, with a clear recommendation; it was made in
  conversation and is in the pull request body. No. Clause 3: about 170 lines outside
  tests and documents, one step. No. Clause 4: no format, no contract, and `ship-env`
  is not a guard the boundary names (it picks a reviewer and fails closed). No.
  Clause 5: not asked. **No plan.** That is what happened.
- Pull request #25, the README and CONTRIBUTING rewrite (419 added lines, 3 in a
  contract test). Documents only, and clause 3 counts 0 lines outside tests and
  documents. **No plan.** That is what happened.
- Two earlier checks, so the rule is not tuned to one day. Pull request #13, the plan
  reader fix (84 lines in `dux-result`, 368 in its tests, 26 in the spec): a guard,
  but a fix toward what the spec already said, with the failing tests first, so
  clause 4's exemption applies; no other clause fires. **No plan.** That is what
  happened. Pull request #21, the pipeline lint (203 added lines over 21 files, 13
  outside tests): clause 1 fires (a new test file and a new lint every script must
  pass gained a line in the constitution's gates), so the rule says **plan** where a
  small change shipped without one. That is the rule's cost, and the intended one:
  a new gate is an interface.
- As a control, this change: a new state, three new state files, a new script, a new
  run-record field, and the wrapper's proposal rules. Clauses 1 and 4. **Plan**, and
  more than one milestone.

## 11. Ship without a plan

A change the rule clears is dispatched as a `ship` task with no plan. `dux-brief`
accepts a `ship` brief without `--plan` and `--tasks`; its definition of done becomes
"the acceptance criteria met, `/ship` run, CI green; then `done: PR <url>`". The
result context records empty `plan=` and `tasks=`, and `dux-result` skips the box
check when both are empty and keeps every other ship check: a change outside
documents, the receipt, the open pull request, green checks. The dispatch skill
records which clause of the rule cleared it, in the report to the operator.

## 12. What changes where

| Component | Change |
|---|---|
| `bin/dux-ledger` | state `plan-ready`, in `list --unacked` too |
| `bin/dux-worker-wrap` | prompt from a round file; run kind in the context; session id and resume through the adapter; unconsumed-handoff refusal; `plan-ready:` proposal in a `plan` round, `done:` refused there |
| `bin/workers/claude.sh` | `--session-id` on a first run, `--resume` on a resume |
| `bin/dux-result` | `verify` by kind: `plan` (section 5), `implement` (section 9, with the frozen-text check), `plan-only` (today's plan proof), `ship` without a plan (section 11) |
| `bin/dux-watch` | apply `plan-ready` handoffs, write `state/<id>.plan`, leave parked tasks alone, receipt cross-check by kind |
| `bin/dux-brief` | `--round` for the four kinds; `--plan-only`; `ship` without a plan; plan rules text; `templates/round.md` |
| `bin/dux-spawn` | `--resume <kind>` and `--fresh`; session id at first spawn |
| `bin/dux-worktree` | a `plan` worktree that is not plan only is made like a `ship` one |
| `bin/dux-notify`, `bin/dux-status` | the `plan-ready` line; "awaiting you" with the GitHub link and, later, the page path |
| `bin/dux-recover` | `--retry` retired; inspect on a parked or failed task prints the round commands as `next:`; `--classify failed` from any parked state; `ended` re-proof publishes the proof's own event; `--fresh` named when the harness refused |
| `bin/dux-plan-page` | new, section 6 |
| `skills/dux-dispatch`, `skills/dux-recover`, `AGENTS.md` | the rule; the five answers; plan only; the wakes |
| `docs/ARCHITECTURE.md` | components and the wake flow, in the same pull request as each milestone |

Not changed: `bin/dux-teardown` and `bin/dux-project` (out of scope, in flight),
`skills/ship`, the backends' interfaces, `data/backlog.md`'s line format. Because
teardown is not changed, it leaves `state/<id>.plan`, `state/<id>.plan.html`,
`state/<id>.runs/`, `tasks/<id>/session`, `tasks/<id>/session.<n>`,
`tasks/<id>/approved` and the round files behind; that is a chore for the teardown
branch once it lands, recorded here so it is not lost.

## 13. Milestones

Three, in this order. Each merges on its own. The first draft had two; the operator's
rule moved the question and retry rounds from a `plan`-only feature to every shape,
and that piece is worth merging first, on its own, because it fixes the cost the
operator named today (a one-word question costs a whole new session) before any of
the plan machinery exists.

- **Milestone 7, resume any worker** (plan `2026-09-10-dux-m7-resume-any-worker.md`,
  8 tasks, about 1,500 added lines). Sections 2, 4 (the parked states that exist
  today), 7 (answer, retry, fresh) and 8. After it, a `ship`, `scout` or `plan` worker
  that asks a question or fails is resumed in its own session with the operator's
  answer, `dux-recover --retry` is gone, and a lost session has `--fresh`. No
  `plan-ready` yet; a plan task still ends at a docs-only pull request.
- **Milestone 8, a plan pauses and the same worker builds it** (plan
  `2026-09-10-dux-m8-plan-ready-and-implement.md`, 7 tasks, about 1,600 added lines).
  Sections 3, 4 (`plan-ready`), 5, 7 (approve, change, drop) and 9, and plan only.
  After it, a plan task pauses at `plan-ready`, the operator reads the plan through
  the GitHub links and approves, changes or drops it in the Dux session; the same
  session implements and ships. No page yet.
- **Milestone 9, the page and the rule** (plan
  `2026-09-10-dux-m9-plan-page-and-rule.md`, 7 tasks, about 1,500 added lines).
  Sections 6, 10, 11 and the end-to-end test of the whole loop. After it, the plan
  opens as a page in the browser, the rule is in the dispatch skill, and small changes
  ship without a plan.

Together they are about 4,600 lines and 22 tasks, over the cap for one plan twice,
which is why there are three. Milestone 8 depends on milestone 7 for the session id,
the round files and `dux-spawn --resume`. Milestone 9 depends on milestone 8 for
`state/<id>.plan`; its rule and its ship-without-a-plan tasks do not, and could ship
first if milestone 8 slips.

## 14. Open questions, each with a recommendation

Closed by the operator on 2026-09-10, recorded so they are not reopened: resume the
session rather than start fresh (was question 1 of the first draft); `needs-decision`
and `blocked` on `ship` and `scout` resume too, from milestone 7 rather than later
(was question 3).

1. **Should a `retry` round on a `ship` task be allowed more than once?** Today's
   automatic retry is once. A resumed retry is cheaper than a respawn, so two might
   be affordable. Recommendation: once, as today. The second failure in a row is the
   signal the operator's own rules name ("two consecutive rounds of fresh defects
   means the design is wrong"), and the eight-round cap already bounds a task that
   keeps asking.
2. **Should a plan round also open a draft pull request, for the phone?** It would
   give a phone a rendered plan with comments. Recommendation: no. The GitHub blob
   link renders the markdown already, a draft complicates `/ship`'s open-or-update
   step and `dux-result`'s "exactly one open pull request", and the page is the
   reading surface.
3. **Should plan only be the default for a `plan` task, with plan and build opted
   into?** Recommendation: no. The operator's ask is that the same worker builds the
   plan; plan only is the exception the rule names, and the dispatch skill asks when
   the intent reads like a document.
4. **Links on the page: none, or only to the repository?** Recommendation: none.
   A plan that must link somewhere shows the target as text; the operator types it.
5. **Render with an external markdown tool if present?** `cmark` and `pandoc` are
   better renderers. Recommendation: no. A new dependency for one page, and a
   renderer that passes raw HTML through by default in one of them; the awk subset
   is enough and is tested here.
6. **Should Dux ever keep a worker process alive across a pause?** A bidirectional
   worker would save the resume's full-context prompt when the operator answers
   within the cache window. Recommendation: no, and not later. The operator's second
   decision is stop and resume; the saving exists only for answers within the hour,
   and the watcher's clear line between waiting and hung is worth more.

## 15. Decisions this supersedes in the orchestrator spec

- Section 17, "No worker inbox in v1": every shape now takes its answers through a
  resumed run. Nothing resolves by retry into a new task.
- Section 5.1, the `plan` row: output and definition of done are now section 9 here,
  or today's docs-only pull request when dispatched plan only.
- Section 5.3, "an answer arrives as a retry with the answer appended to the brief":
  an answer arrives as a round to the same session, for every shape. "A headless
  worker run cannot be resumed under either harness": Claude Code can, by session id.
  Codex is still not dispatchable, for the reason already given.
- Section 5.4, exit lines: `plan-ready` joins them, in a `plan` round only.
- Section 5.5, "env files are copied only for `ship` tasks" and the `git` mechanism
  for non-ship worktrees: a `plan` task's worktree is made like a `ship` task's unless
  the task is plan only.
- Section 6.1, the watcher: unchanged in behaviour, but now the stated reason a
  parked worker is never `stale` or `dead` is that its state came from a line the
  worker wrote, not from time.
