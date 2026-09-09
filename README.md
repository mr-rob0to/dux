# Dux

An orchestrator you talk to. Dux runs worker agents across your repos in isolated
worktrees, supervises them without spending tokens, and brings back PR links and
decisions. Delivery goes through `/ship`.

Dux watches every running worker, wakes only when work needs attention, and
shows missed events in the next session's fleet digest. Register a repository
with `bin/dux-project add <path>`; its folder name becomes the project name unless
you pass `--name <name>`.

Register with `--issues label:<name>` and every open issue carrying that label
becomes a queued task at the next session start; the issue text rides in the
brief as data, the PR body carries `Closes #<n>`, and a closed issue that was
never started is dropped. GitHub closes the issue by itself only when the PR
merges into the repository's default branch; on any other base branch the PR is
shown on the issue and you close it yourself.

A worker is trusted to act with your account, so what it writes is treated as
untrusted text rather than as evidence: a task is done when Dux has proved it
against the repository, GitHub and the `/ship` receipt, never because a worker
said so. If a task was already running when this boundary landed, retire it
once with `bin/dux-recover <id> --retire-legacy`; that stops its worker and
records it failed, and keeps its branch and worktree for one retry.

Design: `docs/specs/2026-09-03-dux-orchestrator-design.md`.
Plans: `docs/plans/`.

Verified orchestrator harness: Claude Code. Worker harnesses: Claude Code and Codex, selected by `config/worker-harness` or `dux-spawn --harness`. Codex as orchestrator: milestone 8.

The `/ship` gate runs on the bundled defaults, so a fresh clone needs no setup.
Both defaults are the word `auto`, which means the gate picks its reviewers from
what your machine has, each time it runs. The code review goes to codex when
`codex` is on your `PATH` and to Claude Code otherwise; the security pass goes to
a `security-reviewer` agent when you have one defined in your own agents
directory and to Claude Code otherwise. Only your directory is read, never the
repository being reviewed, so a branch cannot appoint the reviewer that audits
it. If that repository holds an agent definition file of the same name, the gate
stops rather than guess which one it would run. That check reads one path and is
a speed bump rather than a wall: the gate still dispatches its reviewer inside
the repository being reviewed, which wants a different design. With neither the
gate stops and names the file to edit rather than running a command that is not
there. Nothing is written down, so installing
codex later is enough to start using it.

To pin a reviewer instead, put the command line in `config/reviewer` or
`config/security-reviewer`. Those win over the bundled files and are never
probed. Two limits on "win", both deliberate. The gate still refuses an `agent:`
value, stated here as much as picked, when the repository being reviewed holds an
agent definition file of that name: it stops rather than run one of two
definitions it cannot choose between. And a command line you name here runs with
its working directory inside that repository, so how far it is isolated from the
change it is reading is a property of the command, not of this file; the bundled
fallback uses Claude Code's safe mode for that reason. What this file does buy is
that the repository being reviewed cannot change *which* reviewer runs. `bin/dux-install` seeds both on first run and never overwrites one you
have edited, so a machine installed before this change keeps whatever it seeded;
delete those two files to get the picked defaults back. A recording of the whole
gate, run from a fresh clone against a real remote, is in
`tests/harness/ship.md`.

## Run

    cd ~/Documents/dev/projects/dux && claude

## Develop

    brew install bats-core shellcheck
    make check         # after a task, about two minutes
    make check-branch  # once before /ship, adds the bash 3.2 pass
