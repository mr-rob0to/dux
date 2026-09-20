---
name: dux-status
description: Show the fleet digest. Use when the operator asks what is running, what is waiting on them, what is ready to merge, or at session start.
---

# dux-status

1. Run `bin/dux-status --intake` at session start (it pulls the labelled issues
   first); plain `bin/dux-status` otherwise, and add `--prs` when the operator
   asks about merge state. Relay the `intake` block as what arrived, and a
   `skipped:` line as a finding for that project.
2. Relay the digest in plain words, per project: what is running, what needs the
   operator, what is ready. No task ids unless asked.
3. Every line under `unacknowledged` is a wake that happened while no Monitor
   was armed. Handle each as the wake rule in `AGENTS.md` says, then run
   `bin/dux-ledger ack <id> <state>` using the state that line reported. A
   `base-red: <project>` line is handled as "A red base" below says, and its
   acknowledgement is `bin/dux-base ack <project> <reported>`.
4. `watcher: not running` while tasks are running means supervision is off. Say
   so and run `bin/dux-doctor`; do not dispatch until it passes.
5. The digest counts the ledger. A worker that says it is finished changes
   nothing there until its result is proved, so a task still counted as running
   is running.
6. When the `workers:` line shows fewer running than the limit and a task is
   queued, dispatch it through `skills/dux-dispatch` rather than reporting the
   room and waiting to be asked.

Never edit `data/backlog.md`. Never read the worker's tab, by any means: no
pane capture, no scrollback, no screenshot.

## A red base

A wake `<time> base-red: <project>`, or a `base-red: <project>` line under
`unacknowledged`, names a project, not a task: that project's base branch failed
its checks on GitHub. `bin/dux-base check` wrote it; see
`docs/specs/2026-09-18-base-branch-check.md`.

1. Run `bin/dux-base get <project> reported` and `bin/dux-base get <project> acked`.
   If they are equal the line is a duplicate; stop.
2. Push the one line `bin/dux-notify --base <project>` prints with
   PushNotification.
3. Tell the operator in plain words which project's base failed, with the run url
   from that line. They can look at the run, fix it, ask for a fix task, or re-run
   it on GitHub.
4. Run `bin/dux-base ack <project> <reported>`, with the key step 1 read. If the
   base has been reported again since, it refuses and leaves the newer report
   waiting.

Never re-run a workflow, revert a commit, or dispatch a fix unless the operator
asks for it. A fix they ask for is an ordinary task through `skills/dux-dispatch`.
