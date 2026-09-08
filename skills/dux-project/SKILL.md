---
name: dux-project
description: Register a repository with Dux so tasks can be dispatched to it. Use when the operator names a repo Dux does not know, or asks to add, list, or inspect projects.
---

# dux-project

## Register

1. Confirm the absolute path exists and is a git clone with an `origin` remote.
2. Run `bin/dux-project resolve-base <path>`. If it prints a finding, show the
   operator each signal and ask which branch is correct. Pass the answer as
   `--base`.
2a. If the repo's `CLAUDE.md` or `AGENTS.md` has a `Worktrees` heading, read it
   and pass `--worktree make`, `--worktree script`, or `--worktree git` to match
   what it says; `ship` tasks refuse to spawn otherwise.
3. Ask whether GitHub issues should feed the backlog. If yes, ask for the label
   and pass `--issues label:<name>`; otherwise `--issues off`.
4. Run `bin/dux-project add <path> [--name <name>] [--base X] [--issues Y] [--worktree Z]`.
   The name defaults to the folder name; pass `--name` only when that is taken or unusable.
5. Report the registry line in plain words: base branch, worktree mechanism,
   issue intake, and whether a PR template was installed or left alone. If the
   script warned that the name is too short for the identifier lint to check,
   say so and name `--name` as the way to a longer one.

## Inspect

- `bin/dux-project list` for names.
- `bin/dux-project get <name> <key>` for `path`, `base`, `worktree`, `issues`.

## Never

- Never edit `data/projects.md` by hand. The script owns the format.
- Never guess a base branch. Disagreeing signals go to the operator.
