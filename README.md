# Dux

An orchestrator you talk to. Dux runs worker agents across your repos in isolated
worktrees, supervises them without spending tokens, and brings back PR links and
decisions. Delivery goes through `/ship`.

Dux watches every running worker, wakes only when work needs attention, and
shows missed events in the next session's fleet digest. Register a repository
with `bin/dux-project add <path>`; its folder name becomes the project name unless
you pass `--name <name>`.

Design: `docs/specs/2026-09-03-dux-orchestrator-design.md`.
Plans: `docs/plans/`.

Verified orchestrator harness: Claude Code. Worker harnesses: Claude Code and Codex, selected by `config/worker-harness` or `dux-spawn --harness`. Codex as orchestrator: milestone 7.

## Run

    cd ~/Documents/dev/projects/dux && claude

## Develop

    brew install bats-core shellcheck
    make check
