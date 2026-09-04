# Dux

An orchestrator you talk to. Dux runs worker agents across your repos in isolated
worktrees, supervises them without spending tokens, and brings back PR links and
decisions. Delivery goes through `/ship`.

Design: `docs/specs/2026-09-03-dux-orchestrator-design.md`.
Plans: `docs/plans/`.

Verified orchestrator harness: Claude Code. Worker harnesses: Claude Code and Codex, selected by `config/worker-harness` or `dux-spawn --harness`. Codex as orchestrator: milestone 7.

## Run

    cd ~/Documents/dev/projects/dux && claude

## Develop

    brew install bats-core shellcheck
    make check
