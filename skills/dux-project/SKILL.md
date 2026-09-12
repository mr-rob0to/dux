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
3a. Run `bin/dux-project pr-template <path>`. It lists every pull request template
   the repo already has, in every place GitHub reads one from, or prints `none`.
   - If it printed paths, pass no `--pr-template` flag at all, and tell the
     operator the repo already has a template and where, and that Dux leaves it
     alone and adds no second one. Do not ask; there is nothing to decide.
   - If it printed `none`, ask the operator once whether Dux should install its
     own template at `.github/PULL_REQUEST_TEMPLATE.md`, as one uncommitted file
     for them to commit. Pass `--pr-template install` on a yes and
     `--pr-template skip` on a no. Declining is a normal outcome and the project
     still registers.
   - This step cannot be skipped. On a repo with no template, `add` with no
     `--pr-template` stops with a finding naming both choices and registers
     nothing, so a forgotten ask is a stop rather than a silent default.
4. Run `bin/dux-project add <path> [--name <name>] [--base X] [--issues Y] [--worktree Z]
   [--pr-template install|skip]`. The name defaults to the folder name; pass
   `--name` only when that is taken or unusable. Pass `--pr-template` only when
   step 3a printed `none`.
5. Report the registry line in plain words: base branch, worktree mechanism,
   issue intake, and which of the three the template step did: installed at
   `.github/PULL_REQUEST_TEMPLATE.md` and needing a commit, left alone at the
   path the script named, or not installed because the operator declined. If the
   script warned that the name is too short for the identifier lint to check,
   say so and name `--name` as the way to a longer one.

## Inspect

- `bin/dux-project list` for names.
- `bin/dux-project get <name> <key>` for `path`, `base`, `worktree`, `issues`.

## Never

- Never edit `data/projects.md` by hand. The script owns the format.
- Never guess a base branch. Disagreeing signals go to the operator.
- Never pass `--pr-template install` without the operator's yes in this
  conversation. Writing into a project repo is the one exception to hard rule 1
  and it is theirs to grant.
- Never overwrite or move a template the repo already has, and never add a second
  one beside it. GitHub does not say which of them it would use.
