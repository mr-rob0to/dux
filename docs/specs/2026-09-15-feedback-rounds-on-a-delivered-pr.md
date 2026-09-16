# Dux: a delivered pull request takes feedback in the same session

Status: drafted 2026-09-15 by a Dux plan worker, after the operator redirected the task
mid-flight (section 1). One independent design review the same day, fourteen findings, all
taken; the record is at the end of the plan. **Re-cut the same day**, after the operator
asked why the design was this large: the wrapper now stays alive across a park instead of
exiting and being started again per round, which removed a second wrapper process and the
whole family of checks that reattaching needed. Section 12 records that decision and what
it replaced. Nothing here changes a running system until the plan's milestone merges.

## 1. What the operator gets

A worker that has opened its pull request no longer ends. It waits at its prompt, in its
own tab, with its worktree and branch intact. The operator reviews the pull request and
does one of two things in the Dux session:

- **Merge it.** The operator merges on GitHub, tells Dux, and teardown ends the parked
  session and closes the tab, as it closes a finished tab today.
- **Ask for a change.** The operator says what to change, in their own words. Dux writes
  those words to a file and runs one command. The command types one fixed line into the
  worker's tab, naming a round file that holds the feedback. The same session, with its
  context, makes the change, runs `/ship` again, which updates the open pull request, and
  reports `done: PR <url>` again. Dux proves it again, and the operator gets the same
  "review" notification with the same link.

Nothing new is created: no task, no branch, no worktree, no pull request. The cost of a
correction is the tokens the worker spends on the correction.

**Why this shape.** The task as briefed asked for a *new* task that continues an old
task's branch and pull request. While the plan was being written the operator typed into
the worker's terminal: the intent is for the existing worker to wait for feedback and
final approval before closing, with the feedback sent through the main Dux session into
the active worker. That is this document. The measured cost it removes: pull request #44
(one commit, 17 lines) needed a one-line correction after the operator read it, and the
only path was a second task, a second brief, a second worktree, a full second `/ship`
gate with both reviews and CI, and pull request #45 to supersede #44.

**What this does not cover.** A worker that stops at `needs-decision`, `blocked` or
`failed` still ends its session, and the answer still arrives as a new task through
`dux-recover --retry`, exactly as today. The mechanism below would carry those too, and
the one-session spec (`2026-09-10-one-session-planning.md`, section 2) says they should
resume rather than respawn. That is the next milestone, not this one: this one is scoped
to the case that has cost real money, and a delivered pull request is the only state in
which the worker's session is known to be idle and its work is known to be proved.

## 2. Vocabulary

- **Parked.** A task whose ledger state is `done` with a pull request url, whose worker
  session is alive at its prompt in the task's tab, and whose wrapper is alive and
  waiting for the next round. The
  ledger does not get a new state: `done` already means "proved, awaiting the operator",
  and `dux-status` already lists it under `ready`. What is new is that the session behind
  it is alive.
- **Round.** One operator feedback and the run it starts. Round files are
  `data/tasks/<id>/round-<n>.md`, `n` from 1, at most 8. The first run of a task is not
  a round; it is the run the brief started.
- **Run.** One stretch of the session from a start to a terminal line, with its own run
  id, run record, result context and handoff. A task has one run per round plus the
  first. What changes is that one wrapper process now covers all of them: it does not
  exit between runs, so a run is a stretch of that process's life rather than the whole
  of it.

## 3. The session parks after `done: PR <url>`

`bin/dux-worker-wrap` today stops the harness's process group as soon as it sees the
terminal line, then proves and publishes (`2026-09-14-interactive-worker-sessions.md`,
section 5.3, point 1). The order changes and the stop becomes conditional:

1. **Wait for the turn to end.** The wrapper waits, at most `DUX_WRAP_IDLE_SECS`
   (default 60) seconds, for `<channel>/stopped` to appear. That file is touched by a
   third hook in the worker's settings, on `Stop` alone. It is not the `beat` file:
   `templates/worker-settings.json` touches `beat` from `PostToolUse` as well as `Stop`,
   so a moved `beat` means the worker ran a tool, which is the opposite of what this
   wait is asking. The wait running out is a log line, not a refusal: the proof runs
   either way, and the worker was told to stop after its terminal line.
2. **Prove and publish**, exactly as today.
3. **Park, for `done: PR <url>` only.** The wrapper does not exit. It leaves the group
   running and the channel, `state/<id>.pgid` and `state/<id>.portal` in place, renames
   `state/<id>.ship-receipt` to `state/<id>.ship-receipt.delivered` so the receipt that
   proved this delivery is kept and a round starts with no receipt of its own
   (section 5), logs `worker for <id> parked in its tab; feedback goes through dux-round`
   once, and then waits: every second it looks for `data/tasks/<id>/round-<n>.md`, where
   `n` is one more than the number of rounds it has already run. When that file appears
   it runs the round in place (section 5) and, at the end of it, parks again. The wait is
   unbounded, silent and cheap: it logs nothing per pass, because a task can sit parked
   for days and `state/<id>.wrap.log` is never rotated. Every other ending, `done: report`
   included, stops the group, clears the channel and exits as today.

**The final import does not judge a parked session.** Today the group is stopped before
`import_proposals final` runs, so "the worker kept writing after its terminal status" and
"left a status line unfinished" are statements about a dead process. A parked session is
alive and the operator may be typing to it, so on the parking path both rules are off:
bytes after the terminal line belong to no run, and the next round resumes reading from
wherever the outboxes have reached by the time it starts (section 5), not from where this
run stopped reading. Every other ending keeps both rules exactly as they are.

`state/<id>.pid` keeps naming this wrapper, which is still running, so it stays true for
the whole life of the task and there is no window in which it names a process that has
gone. That is the point of not exiting: the earlier design exited here and started a
second wrapper per round, which left the file naming a dead process between the two and
forced the ledger, the watcher and the round to be ordered around that gap (section 12).
`dux-round` now reads the file as positive evidence that something is listening
(section 4, step 5).

The proof of a parked task is the proof of the moment: branch tip, pull request head and
receipt agree at that commit. A session that keeps working after its terminal line
would move the tip. The brief tells it not to, the `stopped` wait gives its turn time to
end, and a later round re-proves from that tip (section 6). Nothing here claims to stop a
worker that ignores its brief; hard rules 2 and 4 cover that, as they cover a worker
that lies.

## 4. `dux-round <id> --file <path>`

One command, run by Dux in the orchestrator session. Every check below is a finding
(exit 2) and nothing is written before all of them pass.

1. `dux-lock mine`; a valid task id; ledger state `done`; ledger `pr` not `-`; shape
   `plan` or `ship`. A scout is refused: `a scout has no pull request to change;
   dispatch a new scout`.
2. `--file` is required, is a regular non-empty file, and carries no `<untrusted-`
   fence. It is the operator's own words, trusted exactly as the intent file is.
3. No handoff is waiting: `next_handoff <id>` must print nothing, or
   `<id> has an unapplied result at sequence <n>; let the watcher finish before sending
   feedback`. A handoff still pending when the round overwrote `state/<id>.run` could
   never be read again, and the gap would hide every later handoff for the task.
4. `n` is one more than the number of `data/tasks/<id>/round-*.md` files. A ninth is
   refused: `eight rounds already on <id>; the pull request is not converging: tear it
   down and dispatch a sharper task`.
5. Something is there to receive it: `state/<id>.pid` names a live process, which is
   the parked wrapper waiting for exactly this file; `state/<id>.pgid` holds a process
   group `kill -0` reaches; `state/<id>.portal` names a directory that exists;
   `state/<id>.endpoint` is recorded and `dux-backend exists` says present. Any miss:
   `the session for <id> is no longer in its tab (<which check>); tear the task down and
   dispatch a fresh task`. The live wrapper is the check that matters most and the one
   the earlier design could not make: a parked wrapper is the thing that reads the round
   file, so its absence means the round would be written and never picked up. The
   wrapper's own group check (section 5) is the backstop for a session ended between
   this moment and the round starting.
6. No other worker may be alive: the same fleet check `dux-spawn` runs, moved into
   `dux-env` as `fleet_busy <id>` so both call one function, with the same refusal
   wording. A parked session does not count (section 8).
7. Git, after `git fetch origin <base>`: `origin/<base>` must be an ancestor of
   `refs/heads/dux/<id>`. Otherwise: `dux/<id> is behind <base>; /ship would stop: merge
   or rebase it by hand, push, then send the round again`. The round would only end at
   `/ship`'s base check, so it is refused before a worker spends anything. The worktree
   must still be registered on the branch (`dux-worktree path`).
8. GitHub: `gh pr view <url> --json state,headRefName,baseRefName` on the ledger's url.
   `MERGED`: `pull request <url> is already merged; tear <id> down`. `CLOSED`: `pull
   request <url> is closed; reopen it or tear <id> down`. A head or base that is not
   the task's branch and base, or `gh` not answering, is a finding too.
9. Render `data/tasks/<id>/round-<n>.md` from `templates/round.md`. The file is under
   40 lines or the round is refused: `round <n> is <k> lines; the limit is 40: shorten
   the feedback`. The 40 is the one-session spec's cap, kept.
10. Move the ledger, then arm the round. `dux-ledger set-if <id> state done running`,
    then `dux-ledger unack <id>`, so the next `done` wakes Dux instead of reading as a
    duplicate of the last one. Then `mv` the rendered file from
    `data/tasks/<id>/.round-<n>.tmp` onto `data/tasks/<id>/round-<n>.md`. That rename is
    the trigger and the last thing that happens: the parked wrapper is waiting for
    exactly that path and picks it up within a second. The rename is atomic within the
    directory, so the wrapper never reads a half-written file. It is ordered after the
    ledger so the task is already `running` before a round exists to be proved, and a
    rename that fails puts the ledger back to `done` and is a finding. No wrapper is
    started and no pidfile is waited on, because the wrapper this round needs has been
    running since the task was dispatched.
11. Print `round <n> sent to <id>`.

### The round file

`templates/round.md`, fixed text with six tokens: `{{N}}`, `{{ID}}`, `{{PR}}`,
`{{BRANCH}}`, `{{BASE}}`, `{{FEEDBACK}}`. Its first line is
`## Round {{N}} for task {{ID}}: feedback on pull request {{PR}}`. Its fixed part tells
the worker: same task, same brief, same branch, never the base; run `git fetch origin`
and `git status` before anything, and start from what the branch holds now; make the
change as commits on top, and never rebase, amend a pushed commit, squash or force-push,
because the operator has read what is there; run `/ship` again, which updates the open
pull request; then append `done: PR {{PR}}` and wait at the prompt, one terminal line
per round. The operator's words follow under `## Feedback (the operator's words)`,
verbatim. No conversation history, no diff summary, no earlier rounds: the worker's
session already holds those.

The line typed into the tab is Dux's own text and never the operator's:
`Read <channel>/round-<n>.md and follow it.` It names the copy the wrapper staged in the
task channel, mode 400, beside the brief. If the pane had somehow returned to a shell, a
shell reads that line as `Read: command not found`, and the wrapper's group check refuses
before typing it anyway (section 5): a session that fell back to a shell is a session
whose harness group has gone.

## 5. The wrapper runs a round in place

The wrapper that parked is the wrapper that runs the round. It never released the
channel, the outbox pins, the process group or its own pidfile, so a round needs none of
the reattachment a second process would need: no flag, no rediscovery of the pane, no
revalidation of the pins, no run id negotiated against what is on disk. What changes
between one run and the next, in order:

- **It sees the file.** The wait in section 3 ends when `data/tasks/<id>/round-<n>.md`
  appears. `n` is the wrapper's own count of rounds run, plus one, so it waits for one
  exact path and no older round file can be mistaken for it. `dux-round` renames the
  file into place (section 4, step 10), so what the wrapper opens is always whole.
- **The group must still be there.** Before anything else, `kill -0` on the group it has
  been holding all along. If it has gone, the operator ended the session in the tab: the
  wrapper publishes `failed: the session for <id> was ended in its tab before round <n>
  could run`, cleans up and exits. That is one signal on a value the wrapper already
  holds, not a rediscovery.
- **The run id is new.** `<channel nonce>r<n>`, alphanumeric, so every existing equality
  test on `run=` holds unchanged. A new run record and result context are written over
  `state/<id>.run` and `state/<id>.result-context`, whose contents belong to the run
  that parked and whose result the watcher has already applied. There is no receipt to
  remove: parking renamed it to `state/<id>.ship-receipt.delivered` (section 3), which
  `dux-result` never reads and `dux-teardown` removes with the rest.
- **The ship recorder is rewritten** with the new run id, at the path the worker's
  `DUX_SHIP_RECORD` already names. That file is mode 500, so the rewrite is `chmod 600`,
  write, `chmod 500`; a plain redirect onto it fails.
- **The outboxes are seeked forward.** `accepted` becomes the status outbox's current
  size and the report copy offset its current size, so the parked run's terminal line is
  not read as a second terminal line and its report is not appended twice. Anything the
  worker wrote while parked, outside any run, is skipped rather than judged: the round
  the operator sent is the run. No checksum of the prefix is needed, because the wrapper
  has held the pins since it made them. Both size caps are measured over the region past
  `accepted`, not over the whole file, or eight rounds would share one 64 KiB status
  budget and one 1 MiB report budget.
- **The context carries two more keys.** `round=<n>` and `since=<sha>`, the tip of
  `refs/heads/dux/<id>` read before the prompt is typed. `dux-result` reads both
  (section 6). A first run writes `round=0` and its own `since`, so the file has one
  shape.
- **The file is staged and the line is typed.** The round file is copied into the task
  channel at mode 400, beside the brief, and `dux-backend prompt <endpoint> <text>` types
  `Read <channel>/round-<n>.md and follow it.` into the pane. `dux-round` never writes to
  the channel and never types into a tab: it renders under `data/tasks/<id>/` and the
  wrapper carries it the last step, so the channel keeps its one writer.
- **Then it supervises as it always has.** The same import loop, the same caps, the same
  terminal-line rules. `done: PR <url>` parks again and the count of rounds run goes up
  by one; anything else stops the group, clears the channel and exits, as a first run
  does.

`dux-backend prompt <endpoint> <text>` is the one new adapter verb: send `<text>` and
Enter to the pane's foreground process, nothing else. The text is one line, Dux's own,
under 200 characters, so neither backend needs quoting rules.

**tmux, measured 2026-09-15 on tmux 3.6a, macOS.** `send-keys -t <target> -l -- "<text>"`
followed by `send-keys -t <target> Enter` delivers the line to the pane's foreground
process, not to a shell: a pane running `cat > file` received `-x $y Enter C-c plain`
byte for byte. The same call without `-l` delivered the identical bytes, because the
whole line is one argument and tmux sends an argument it cannot resolve as a key name
literally. `-l` is kept because a line that happened to be exactly a key name would not
survive without it, but it is not what makes the delivery literal, and a test that
breaks `-l` will not fail. `respawn-pane`, which `backend_run` uses on tmux, replaces
the pane's process and is the wrong verb here.

**Herdr, not measured.** `herdr pane run <pane> <text>` sends text and Enter in one call
and is what `backend_run` already uses, but only ever against a shell prompt:
`backend_open` waits for one before it hands the endpoint out. Whether it reaches a
Claude Code session's prompt, which holds the terminal in raw mode, is the first thing
Task 1 measures, before any code is written. The plan header says what the milestone
becomes if it does not.

## 6. Proof of a round

`dux-result verify` is unchanged for a first run. When the result context says
`round=<n>` with `n` above 0, one more rejection applies, leaving the run `ended` for
recovery like any other unproved result: `since` must be an ancestor of the branch tip,
or `the round rewrote history the operator already reviewed on <branch>`. The operator
read the commits that were there; a round may add to them, not replace them. `since`
itself must be forty hex characters, which is a finding rather than a rejection: it is
Dux's own file.

A round that adds no commit is **not** rejected. Feedback the worker answers without a
change ("you are right, nothing to do here") re-proves the same tip and parks again,
which is the right outcome; rejecting it would end the session and take the task off
`done` over an answer that was correct.

Everything else stays: the pull request found by branch is the same one, exactly one
and open; its head is the local tip; for a `ship` round the receipt is this run's, five
phases in order, `ci` recorded against the tip; the whole branch is still the diff read
against the base, so a ship result still needs an implementation file and a plan result
still changes only documents.

For a `ship` round the receipt requirement is what forces `/ship` to run again: there is
no other way to file five phases against the new tip. A `plan` round has no such force,
because `dux-result` asks a plan result only for a clean worktree, one open pull request
at the tip and a documents-only diff. That is exactly how a plan task's first run is
proved today, so a plan round is no weaker than what it continues, but section 9's cost
argument applies to ship rounds only.

## 7. Teardown and recovery of a parked task

`dux-teardown <id>` on a `done` task finds two live processes: the wrapper named by
`state/<id>.pid`, waiting for a round, and the harness group in `state/<id>.pgid`. Today
a live group here is a refusal. Now, for `done` only, teardown ends both, in that order.
The wrapper goes first, with `TERM`. It is sitting in a one-second wait with nothing in
flight, because a task mid-round is `running` and not `done`; ending it first also means
it cannot pick up a round file that arrives while teardown is running. Then the group,
`TERM` then `KILL` with the wrapper's own grace, through `stop_pgid <pgid>` moved into
`dux-env` from the wrapper's `stop_group`. A wrapper or a group that survives is the
same finding as today. Then the worktree, the pane, the channel and the references go as
today,
`state/<id>.ship-receipt.delivered` with them. For `failed` the refusal stands: a failed
task's group should be gone, and one that is not is something the operator ends in the
tab.

`dux-recover` does not change. A round that goes stale is stopped like any stale run,
and the stop ends the session. A round whose wrapper dies is `dead`, marked `failed`,
with the session possibly still in the tab, exactly as today.

**What a round that does not end `done` leaves.** The task's ledger state is whatever
the round ended in, `failed` or `ended`, and the session is gone, because every ending
but `done: PR` stops the group. Nothing has happened to the pull request: it is still
open on GitHub, still at whatever commit the round pushed or did not push, and the url
is still in the ledger's `pr` field, which nothing clears. The operator's moves are the
ones they already have: merge it on GitHub and tear the task down, or tear it down and
let the pull request go. What they cannot do is send another round, because `dux-round`
takes `done` only. That is an accepted limit, not a defect: a task whose session has
died has nothing left to continue, and a fresh task with the correction in its intent is
the fallback that exists today. The delivered receipt is kept beside the task until
teardown so that nothing about the proved delivery is silently destroyed.

## 8. The one-worker guard

`dux-spawn` refuses to start while any other task's worker might be alive, and reads
`state/<other>.pgid` as one of its signals. A parked session's group is alive and idle:
a session at its prompt spends no tokens, which is what the guard is for. So the guard
skips the pgid signal for a task whose ledger state is `done`. Every other signal, and
every unreadable file, refuses as today. `dux-round` runs the same guard, so a round
cannot start beside a running task either: one worker works at a time; any number may
wait. The one cost is the tab each parked session holds until its pull request merges.

The exemption assumes a parked session is idle, and the brief invites the operator to
type into a worker's tab, so an operator driving a parked session by hand is exempt from
the guard that keeps two agents off one subscription. That is the operator's own choice,
made in front of the tab, and it is a note rather than a defect. The `stopped` file from
section 3 would let a later milestone check idleness rather than assume it.

## 9. `/ship` updates a pull request it finds

Confirmed against `gh` 2.100.0's source, `pkg/cmd/pr/create/create.go`: `gh pr create`
on a branch that already has an open pull request into the same base returns
`a pull request for branch "x" into branch "main" already exists` and exits non-zero.
Step 8 of `skills/ship/SKILL.md` calls it unconditionally, so a round's gate would stop
there. The change, in "Opening it" and in the docs-only paragraph alike: look up the
open pull request for the current branch into the resolved base first; edit its body
when there is one, keeping its title, otherwise create it. Every later push in the
skill already rebuilds the body and edits, so the rest of the gate is unchanged.

The review scope is unchanged too: the reviewer reads the branch's whole diff against
the base, the parked commits included. The gate attests the commit going out, and a
pull request merges as a whole; a review of only the new commits would attest less than
it records. For a ship round that is one full review and one security pass per round,
which is the cost the second task paid and more. A plan round runs no gate, as a plan
task's first run runs none (section 6).

`ship-guard`'s state file lives in the worktree's git directory under the branch name.
Step 0 opens it afresh on every invocation, truncating the file, so a round starts with
no recorded phases and a fix count of zero. Nothing to change.

## 10. What the operator sees

- `dux-notify` for `done` with a pull request says
  `Review, then merge or send feedback: <url> (<project> <shape>)`. The words are
  fixed and come from the ledger, as every notification's do.
- `AGENTS.md` and `skills/dux-dispatch` say what to do with feedback: write the
  operator's words to `data/tasks/<id>/feedback.md`, run `bin/dux-round <id> --file
  data/tasks/<id>/feedback.md`, and tell the operator the worker is on it in its tab.
  Dux never types into the tab itself and never reads it; the one line that reaches the
  tab is typed by the wrapper through the adapter. "Never edit `brief.md` after spawn"
  stands: a round is a new file, and the brief is untouched.
- The lifecycle line gains one arrow: `done -> running` on a round. `dux-status` is
  unchanged: a parked task is `ready`, a round is `running`.
- The brief's rule "one terminal line, then stop" becomes "one terminal line per
  round, then stop and wait at your prompt": after `done: PR <url>` the worker does
  nothing until a prompt from Dux names a round file, and anything it does before that
  is unsupervised and will not be proved.

## 11. What changes where

- `bin/backends/herdr.sh`, `bin/backends/tmux.sh`, `bin/dux-backend`: `prompt`.
- `bin/dux-env`: `fleet_busy` and `stop_pgid`, moved from `dux-spawn` and
  `dux-worker-wrap`, not rewritten. There is no `start_wrapper`: `dux-spawn` remains the
  only thing that ever starts one.
- `bin/dux-worker-wrap`: the idle wait, the conditional park, the round loop.
- `bin/dux-round`, `templates/round.md`: new.
- `templates/worker-settings.json`: the `Stop`-only `stopped` hook.
- `bin/dux-result`: `round` and `since`.
- `bin/dux-spawn`, `bin/dux-teardown`: the parked exemption; the stop before teardown.
- `bin/dux-notify`, `templates/brief.md`, `AGENTS.md`, `skills/dux-dispatch/SKILL.md`,
  `skills/dux-recover/SKILL.md`, `skills/ship/SKILL.md`, `docs/ARCHITECTURE.md`,
  `docs/constitution.md` (principle 6, one clause: the one line Dux writes into the
  tab; a PATCH, 2.0.9).
- Pointers in `2026-09-03-dux-orchestrator-design.md` (5.4, 5.5, 5.6, 6.3, 9, 11, 17),
  in `2026-09-14-interactive-worker-sessions.md` (5.3, the milestone 7 note), and a
  status line in `2026-09-10-one-session-planning.md`.

## 12. Decisions, each with the alternative it beat

- **A round is a prompt typed into the live pane, not a resumed headless session.** The
  one-session spec designed rounds around `claude --resume <session id>` for headless
  workers. Workers are live sessions now, so the session is the one already at its
  prompt, the round is one typed line, and no session id is stored or read. This
  supersedes the "milestone 7 changes the adapter signature to add a session id"
  note in the interactive-sessions spec.
- **`done` parks; nothing else does.** Parking `needs-decision` and `blocked` too would
  retire `--retry`'s respawn, which the operator wants. It is the next milestone, on
  this mechanism, because those states leave a session mid-work and unproved, and
  this one is scoped to the case that cost money.
- **The wrapper stays alive across a park instead of exiting and being started again.**
  This is the re-cut, and it replaces the first draft's answer to review finding 1. That
  draft had the wrapper exit at the park and `dux-round` start a second one with
  `--round <n>`. The second process had to find the channel again, revalidate both
  outbox pins, rediscover the harness in the pane and prove its group matched the pgid
  file, and between the two processes `state/<id>.pid` named something dead, which
  forced the ledger write to be ordered last so the watcher could not read that gap as a
  dead worker. Keeping the one process alive removes all of it: nothing was released, so
  nothing is reacquired, and the pidfile is never untrue, so the ordering problem cannot
  arise rather than being ordered around. It is about 275 fewer lines and it deletes
  that critical finding by construction instead of answering it. What it costs: one
  shell per parked task sitting in a one-second wait, and teardown must end that process
  as well as the harness group (section 7).
- **A parked session does not hold the one-worker slot.** It spends nothing. The
  alternative, one task at a time including the wait for a merge, would make every
  review block the fleet.
- **Feedback goes through Dux, not the tab.** The operator can type into the tab
  today, and still can. But only a round has a run record, so only a round's `done:`
  is proved and wakes Dux. The skill says so.
- **The whole branch is reviewed again.** Section 9.
- **No ledger field for rounds.** The round files are the record and `dux-round`
  prints the number; a ledger key nobody reads is a contract change for nothing.
- **A round that adds no commit still proves.** Section 6. The first draft rejected it,
  which turned a correct answer into a destroyed session.
- **A failed round is not restored to `done`.** A recovery verb that re-proved the
  delivered receipt and republished `done` was considered and dropped: the pull request
  is untouched and mergeable either way (section 7), so the verb would buy a tidier
  digest line and nothing else.
- **Eight rounds, then stop.** The one-session spec's cap, for the same reason: past
  it the pull request is not converging and the session is too long to be the right
  tool.
- **The round is triggered by a file, not a signal or a socket.** `dux-round` renames a
  file into the task folder and the wrapper polls for that one path once a second. A
  signal would need the wrapper to carry a handler across every wait it already does, and
  a socket or a named pipe would add a thing to create, clean up and reason about when
  one end dies. The file is the state either way, because the wrapper has to read it; the
  poll just removes the second mechanism. One second of latency on a correction a human
  is about to read costs nothing.
- **The new-task-on-an-old-branch design is not built.** It was the brief's framing
  and it answers the same cost with a new task, a new worktree, a checkout of a branch
  another task owns, and proof rules for a continued pull request. The operator's
  redirection removes every one of those. If a parked session is ever lost before its
  feedback arrives, the fallback is the one that exists today: a fresh task with the
  correction in its intent.

## 13. Accepted limits

- A parked task holds a wrapper process as well as a tab and a worktree, until its pull
  request merges or it is torn down. It is a shell in a one-second wait and costs nothing
  measurable, but it is a process, and a machine restart takes it with the session it was
  watching. That leaves the task `done` in the ledger with no session, which `dux-round`
  refuses on its liveness checks exactly as it would have before.
- A parked task holds a tab and a worktree until its pull request merges. The digest
  counts it under `ready`, as today. It is never marked long-running, because
  `dux-status` asks that question only of `running` and `stale` tasks; conversely a
  round on a task briefed two days ago is marked long-running from its first second,
  because the age is read from the brief's modification time. Both are cosmetic and
  neither is changed here.
- A round that does not end `done` leaves the task `failed` or `ended` with its pull
  request open and mergeable, and no further round is possible on it (section 7).
- A base branch that moves while a task is parked refuses the round until the operator
  merges or rebases by hand. `/ship` refuses the same state for every task today; the
  round only says so earlier.
- The idle wait reads a `Stop` hook's touch. A Claude Code release that stops firing it
  costs sixty seconds per delivery and nothing else.
- The proof of a parked task is of the moment it was made (section 3).
- A round typed into a pane whose Claude Code is showing a dialog is lost in that
  dialog. Spawn refuses an untrusted repository for that reason today; no second
  dialog is known on a running session.
- The one-worker exemption assumes a parked session is idle (section 8).
- Herdr's own agent lifecycle (`agent prompt`, `agent wait`) is still not used: it
  needs an agent Herdr registered, tmux has nothing like it, and `pane run` sends the
  same keystrokes.
