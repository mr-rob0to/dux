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

Verified orchestrator harness: Claude Code. Worker harnesses: Claude Code and Codex, selected by `config/worker-harness` or `dux-spawn --harness`. Codex as orchestrator: milestone 7.

## Run

    cd ~/Documents/dev/projects/dux && claude

## Develop

    brew install bats-core shellcheck
    make check
