# Dux: one session, from plan to pull request

Design authority for the change that lets the operator talk to the Dux session and
nothing else: a plan comes back to that session, is read as a page, is approved
there, and the worker that wrote it goes on to build it. The orchestrator design
(`2026-09-03-dux-orchestrator-design.md`) stays the authority for everything this
document does not change; sections 5.1, 5.3, 5.4, 5.5 and 17 of it point here.

Plans: `docs/plans/2026-09-10-dux-m7-plan-ready-and-resume.md` (milestone 7) and
`docs/plans/2026-09-10-dux-m8-plan-page-and-rule.md` (milestone 8). The design
review is recorded at the end of the milestone 7 plan.

## 1. What the operator gets

Today a plan task ends with a docs-only pull request the operator has to go and find,
read as a diff, merge, and then dispatch a second task to implement. After this
change:

- A plan task pauses when its plan is written. Dux tells the operator, on the phone
  and in the session, that a plan is waiting.
- The operator reads the plan as a page, rendered by Dux from the plan file, opened
  in their browser. They never read a diff to approve a plan.
- The operator says "approve", or says what to change, in the Dux session. Nothing
  else is touched. A change request goes back to the same worker, which revises and
  pauses again. An approval goes back to the same worker, which implements the plan,
  ticks its boxes, runs `/ship`, and ends with one pull request holding the spec, the
  plan and the code.
- Dux and the worker decide whether a change needs a plan at all by a written rule
  (section 8). A change that meets none of its clauses ships without one.

Out of scope: the two branches in flight on `bin/dux-project` and `bin/dux-teardown`.
Neither script is edited. Section 10 lists what teardown therefore leaves behind.

## 2. The shape of a task after this change

```
queued -> running -(plan proved)-> plan-ready -(approve)-> running -> done | failed | ended
                                      |  ^                                   |
                                      |  '-(change)-- running <-'            '-(retry once)-> running
                                      '-(drop)-> failed
```

One task, one branch, one worktree, several runs. A run is what it is today: one
wrapper process, one task channel, one run record, one handoff. What is new is that
a task can have more than one, and that each run has a **kind**:

| Kind | Which run | Worker may propose | Proof that ends it |
|---|---|---|---|
| `plan` | first run of a `plan` task, and every run after a change request or an answer given in a plan round | `plan-ready:`, `needs-decision:`, `blocked:`, `failed:` | section 4 |
| `implement` | the run after approval, an answer given in an implement round, and one retry | `done:`, `needs-decision:`, `blocked:`, `failed:` | section 7 |
| `ship` | a `ship` task | `done:` and the rest, as today | unchanged, plus section 9 |
| `scout` | a `scout` task | `done: report` and the rest | unchanged |

The kind is decided by Dux when the run starts and written into the run's result
context, so `dux-result` proves a run against its kind rather than the task's shape.
A `plan` shape task keeps its name and its model: every run of it, resumed or not, is
started with the `plan` entry of `config/models` (Fable, high effort), and the approve
round tells it to delegate each task's code to a subagent on the operator's
implementation model. What changes is that the task no longer ends when the plan is
written.

Why one task and not two: the operator asked for approval to travel back to the same
worker. The worker runs headless as `claude -p`, and that harness can continue a
session by id (`--session-id` on the first run, `--resume <id>` on later ones; both
present in Claude Code 2.1.267). So "the same worker" is literal: the same session,
with the reasoning behind its plan and its rejected alternatives still in context,
picks up the approval or the change request as its next prompt. A second task would
have a new branch, a fresh session and a brief that restates the plan; it would also
need the plan merged first, which is the pull request the operator does not want to
go and find.

Because a `plan` task's worker will implement, its worktree is made the way a `ship`
worktree is: with the project's own mechanism (`make worktree`, a script, or plain
`git worktree add`), and with the project's committed env examples copied under the
`git` mechanism. A plan spawn on a project with a slow mechanism takes the minutes a
ship spawn takes; the dispatch skill already raises the tool timeout for that.

## 3. The pause: `plan-ready`

`plan-ready` is a new task state, not a reuse of `needs-decision`. The two differ in
every way that matters:

| | `needs-decision` | `plan-ready` |
|---|---|---|
| What arrives | the worker's own words, a question | a file on the branch, proved from Git |
| What the operator answers | free text | approve, change, or drop |
| What Dux reads | nothing but the ledger; the question only through `dux-recover` | nothing but the ledger and Dux's own page |
| Pushed to the phone | yes | yes |

A `plan` task's worker may still write `needs-decision:` or `blocked:` in any round,
for a real question or a wall. For a `plan` task those are answered the same way a
change request is: the operator's answer goes into a round file and the same session
resumes (section 6). `dux-recover --retry`, which makes a new task, refuses a `plan`
shape task and names the resume path instead; `ship` and `scout` tasks keep the retry
path unchanged.

**The worker's side.** In a `plan` round `done:` is a rule violation and fails the run,
so a worker following the old brief cannot slip a docs-only "done" past the new proof.
`plan-ready:` outside a `plan` round is the same kind of violation. The worker writes
the plan, pushes its branch, appends one `plan-ready: <one line>` to its status outbox,
and exits. The wrapper holds that line back exactly as it holds `done:`, and asks
`dux-result` to prove it (section 4). What reaches `status.log` is the proof's own
line, never the worker's.

**While it waits.** The wrapper has exited, so no worker process is alive. The
container stays: a tmux window with remain-on-exit, or a Herdr tab, showing the
wrapper's last log line. The worktree is clean and its branch is pushed, which the
proof required. The watcher does not look at `plan-ready` tasks, so the task cannot go
`stale` or `dead` however long the operator takes; it lists them only to finish a
handoff a crash interrupted. `dux-ledger list --unacked` includes `plan-ready`, so a
wake that lands while no Monitor is armed is still under `unacknowledged` at the next
session start. The digest counts it under "awaiting you" with the GitHub link and, from
milestone 8, the page path. There is no pull request yet. `dux-spawn` refuses a plain
spawn of it (not `queued`), `dux-teardown` refuses it (not terminal), and the only
ways out are the answers in section 6.

## 4. Proof at `plan-ready`

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

## 5. How the plan reaches the operator without breaking hard rule 3

Hard rule 3 says Dux never reads raw worker text. A plan is worker text, and the
operator has to read it. The resolution is the same one `dux-recover` uses: the
worker's words reach the operator through a fixed frame Dux owns, capped and cleaned,
and never reach Dux's own context at all.

**The path.**

1. The worker writes markdown only. The brief's plan rules say so: no HTML, no
   published artifact, no waiting in-session for approval.
2. `dux-result` proves the branch and names the plan's path from Git (section 4).
3. The watcher writes `state/<id>.plan` and raises `plan-ready`.
4. On the wake Dux runs `bin/dux-notify <id>`, which prints a fixed line from the
   ledger (`Approve or change: <project> plan is ready (<id>)`) for the phone, and
   `bin/dux-recover <id>`, which prints the GitHub link to the plan
   (`https://github.com/<repo>/blob/dux/<id>/<path>`, built from the registry and the
   proven path) and one link per other document the plan round changed, read from
   Git's name-only diff between the merge base and the proven commit. From milestone
   8 Dux also runs `bin/dux-plan-page <id> --open`, which renders `state/<id>.plan.html`
   and opens it in the operator's browser. Dux repeats the links and the page path in
   fixed text and says: approve, say what to change, or drop.
5. The operator reads the page. Dux reads nothing: not the markdown, not the page.
   Until milestone 8 lands, the GitHub links are the reading surface; GitHub renders
   the markdown through its own sanitiser.

**What the operator is approving.** Everything the plan round changed: the plan and
every other document on the branch, which check 5 says includes at least one spec
file. The page therefore lists every changed document path, renders the plan first,
and renders each changed `docs/specs/*.md` after it as a folded section. The approval
covers that set, and section 7 freezes it.

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

## 6. Approve, change, answer, drop, retry

Four answers, one mechanism. Every answer is a **round**: a prompt file Dux renders
from fixed text, and a new run of the same task started by `dux-spawn <id> --resume`.

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
- `answer` (from `needs-decision` or `blocked`): the operator's answer file, verbatim;
  the instruction to continue the round that asked. The new run's kind is the kind of
  the run that asked.
- `retry` (from `failed`, only after an approval): the last status lines and the
  failure tail of the previous run, cleaned, capped and fenced exactly as
  `dux-recover --retry` does today; the instruction to continue implementing from the
  plan file's boxes, then `/ship`, then `done:`.

Refusals, each a finding: the state does not fit the kind; `change` or `answer`
without `--answer-file`; an answer file containing an `<untrusted-` fence; a second
`approve`; a second `retry`; a ninth round of any kind; a round file over 40 lines; a
round rendered before the previous one has run. Eight rounds in all is the cap on the
conversation: past it the plan is not converging, and the operator's next move is drop
and redispatch with a sharper intent.

**An implement run that does not prove.** A red check, an unticked box or a missing
receipt leaves the run `ended`, as a ship task's does today. The path is
`dux-recover <id> --classify failed`, then `--round retry` and `--resume retry`, once.

**`dux-spawn <id> --resume <round-kind>`.** In order, each step a finding when it
fails:

1. Lock held; the state fits the kind (`plan-ready` for approve and change;
   `needs-decision` or `blocked` for answer; `failed` with `tasks/<id>/approved`
   present for retry); the round file for this round exists and is the newest.
2. No live worker: the pidfile and process-group checks a first spawn makes. A
   wrapper that is somehow still running is a finding, never a signal.
3. The worktree recorded in the brief exists, is on `dux/<id>`, and is clean.
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
   the kind (`implement` for approve and retry; `plan` for change; the asking run's
   kind for answer), and for `implement` the `plan=` and `tasks=` from
   `state/<id>.plan`. The wrapper sets `DUX_SHIP_RECORD` and the ship-only
   environment for `implement` runs exactly as it does for a `ship` task.
8. Ledger `set-if <state> running`; acknowledgement cleared so the next wake counts.

**Session continuity.** The first spawn chooses a UUID (`uuidgen`, else 32 hex from
`/dev/urandom`), writes it to `tasks/<id>/session` (mode 600), and the worker adapter
passes `--session-id <uuid>`. Every resume passes `--resume <uuid>` with the round
file as the prompt; the session already holds the brief. The adapter's signature
becomes `worker_run <prompt-file> <model> <effort> <settings> <session> <first|resume>`.
A resume the harness refuses (its session file removed by the harness's own cleanup,
or a harness upgrade) fails the run with the harness's exit code, and the operator's
options are the retry above, which resumes again, or drop. Milestone 8 adds
`--fresh`: a new session id, with the brief followed by the round file as the prompt,
for the case where the session is gone for good.

**Drop.** `dux-recover <id> --classify failed` accepts `plan-ready` as well as
`ended`. The status line is `failed: plan dropped by the operator`, the branch and
worktree are kept, and teardown proceeds as for any failed task.

**The Dux session.** On a `plan-ready` wake: `dux-notify` and push; `dux-recover <id>`
for the links; from milestone 8, `dux-plan-page --open`; tell the operator in fixed
words; acknowledge. On the operator's answer, all through `skills/dux-recover`:

- "approve": `bin/dux-brief <id> --round approve`, then `bin/dux-spawn <id> --resume approve`.
- a change, or an answer to a question: write it to `data/tasks/<id>/answer.md`,
  `bin/dux-brief <id> --round change|answer --answer-file ...`, then
  `bin/dux-spawn <id> --resume change|answer`.
- "drop": `bin/dux-recover <id> --classify failed`, then teardown when the operator
  says so.

The operator can ask Dux nothing about the plan's content. Dux has not read it and
says so; the page is the answer. This is the cost of hard rule 3 and it is stated in
the skill so the operator is not surprised by it.

## 7. Proof after implementation, and why it stays one task

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
the case where a plan was merged earlier and only its implementation is wanted.

## 8. When a plan is warranted

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

## 9. Ship without a plan

A change the rule clears is dispatched as a `ship` task with no plan. `dux-brief`
accepts a `ship` brief without `--plan` and `--tasks`; its definition of done becomes
"the acceptance criteria met, `/ship` run, CI green; then `done: PR <url>`". The
result context records empty `plan=` and `tasks=`, and `dux-result` skips the box
check when both are empty and keeps every other ship check: a change outside
documents, the receipt, the open pull request, green checks. The dispatch skill
records which clause of the rule cleared it, in the report to the operator.

## 10. What changes where

| Component | Change |
|---|---|
| `bin/dux-ledger` | state `plan-ready`, in `list --unacked` too |
| `bin/dux-worker-wrap` | `plan-ready:` proposal in a `plan` round, `done:` refused there; run kind in the context; session id and resume through the adapter; unconsumed-handoff refusal; prompt from a round file |
| `bin/workers/claude.sh` | `--session-id` on a first run, `--resume` on a resume |
| `bin/dux-result` | `verify` by kind: `plan` (section 4), `implement` (section 7, with the frozen-text check), `ship` without a plan (section 9) |
| `bin/dux-watch` | apply `plan-ready` handoffs, write `state/<id>.plan`, leave `plan-ready` tasks alone, receipt cross-check by kind |
| `bin/dux-brief` | `--round`; `ship` without a plan; plan rules text; `templates/round.md` |
| `bin/dux-spawn` | `--resume <kind>`; session id at first spawn; `--fresh` in milestone 8 |
| `bin/dux-worktree` | a `plan` worktree is made like a `ship` one: the project's mechanism, and env examples under `git` |
| `bin/dux-notify`, `bin/dux-status` | the `plan-ready` line; "awaiting you" with the GitHub link and, later, the page path |
| `bin/dux-recover` | `plan-ready` inspect with the document links; `--classify failed` from `plan-ready`; `ended` re-proof publishes the proof's own event; `--retry` refuses a `plan` shape task |
| `bin/dux-plan-page` | new, section 5 |
| `skills/dux-dispatch`, `skills/dux-recover`, `AGENTS.md` | the rule; the four answers; the wake |
| `docs/ARCHITECTURE.md` | components and the wake flow, in the same pull request as each milestone |

Not changed: `bin/dux-teardown` and `bin/dux-project` (out of scope, in flight),
`skills/ship`, the backends' interfaces, `data/backlog.md`'s line format. Because
teardown is not changed, it leaves `state/<id>.plan`, `state/<id>.plan.html`,
`state/<id>.runs/`, `tasks/<id>/session`, `tasks/<id>/approved` and the round files
behind; that is a chore for the teardown branch once it lands, recorded here so it is
not lost.

## 11. Milestones

Two, in this order. Each merges on its own.

- **Milestone 7, pause and resume** (plan
  `2026-09-10-dux-m7-plan-ready-and-resume.md`, 8 tasks, about 1,900 added lines).
  Sections 2, 3, 4, 6, 7. After it, a plan task pauses at `plan-ready`, the operator
  reads the plan through the GitHub links, and approves, changes, answers or drops it
  in the Dux session; the same session implements and ships. No page yet.
- **Milestone 8, the page and the rule** (plan
  `2026-09-10-dux-m8-plan-page-and-rule.md`, 8 tasks, about 1,650 added lines).
  Sections 5, 8, 9, plus `--fresh` and the end-to-end test of the whole loop. After
  it, the plan opens as a page in the browser, the rule is in the dispatch skill, and
  small changes ship without a plan.

Together they are about 3,550 lines and 16 tasks, over the cap for one plan, which is
why there are two. Milestone 8 depends on milestone 7 for `state/<id>.plan` and the
resume path; its rule and its ship-without-a-plan tasks do not, and could ship first
if milestone 7 slips.

## 12. Open questions, each with a recommendation

1. **Resume the session, or start a fresh one with the plan as its brief?** The
   operator's own "one session, one task" rule argues for fresh; their ask, and the
   plan skill they use themselves, argue for the same session. Recommendation:
   resume, with `--fresh` as the recorded fallback in milestone 8. The plan file
   stays the state either way, so switching later is a one-flag change.
2. **Should a plan round also open a draft pull request, for the phone?** It would
   give a phone a rendered plan with comments. Recommendation: no. The GitHub blob
   link renders the markdown already, a draft complicates `/ship`'s open-or-update
   step and `dux-result`'s "exactly one open pull request", and the page is the
   reading surface.
3. **Should `needs-decision` and `blocked` on `ship` and `scout` tasks adopt the same
   resume path?** For `plan` tasks they do, from milestone 7. Recommendation: for the
   other shapes, later and separately, once resume has run for a few plan tasks.
4. **Links on the page: none, or only to the repository?** Recommendation: none.
   A plan that must link somewhere shows the target as text; the operator types it.
5. **Render with an external markdown tool if present?** `cmark` and `pandoc` are
   better renderers. Recommendation: no. A new dependency for one page, and a
   renderer that passes raw HTML through by default in one of them; the awk subset
   is enough and is tested here.

## 13. Decisions this supersedes in the orchestrator spec

- Section 17, "No worker inbox in v1": a `plan` task now takes its answers through a
  resumed run. `ship` and `scout` tasks still resolve by retry.
- Section 5.1, the `plan` row: output and definition of done are now section 7 here.
- Section 5.3, "a headless worker run cannot be resumed under either harness": Claude
  Code can, by session id. Codex is still not dispatchable, for the reason already
  given.
- Section 5.4, exit lines: `plan-ready` joins them, in a `plan` round only.
- Section 5.5, "env files are copied only for `ship` tasks" and the `git` mechanism
  for non-ship worktrees: a `plan` task's worktree is made like a `ship` task's.
