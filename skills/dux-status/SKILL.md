---
name: dux-status
description: Show the fleet digest. Use when the operator asks what is running, what is waiting on them, what is ready to merge, or at session start.
---

# dux-status

1. Run `bin/dux-status` (add `--prs` when the operator asks about merge state).
2. Relay the digest in plain words, per project: what is running, what needs the
   operator, what is ready. No task ids unless asked.
3. Every line under `unacknowledged` is a wake that happened while no Monitor
   was armed. Handle each as the wake rule in `AGENTS.md` says, then run
   `bin/dux-ledger ack <id> <state>` using the state that line reported.
4. `watcher: not running` while tasks are running means supervision is off. Say
   so and run `bin/dux-doctor`; do not dispatch until it passes.
5. The digest counts the ledger. A worker that says it is finished changes
   nothing there until its result is proved, so a task still counted as running
   is running.

Never edit `data/backlog.md`. Never read `state/<id>.out`.
