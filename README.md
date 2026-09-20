<div align="center">

<img src="docs/assets/dux-logo.png" alt="Dux" width="480" />

# Dux

**Run coding agents across your repos without babysitting them.**

[![check](https://github.com/mr-rob0to/dux/actions/workflows/check.yml/badge.svg)](https://github.com/mr-rob0to/dux/actions/workflows/check.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#requirements)
[![bash](https://img.shields.io/badge/bash-3.2%2B-green.svg)](#contributing)

</div>

---

*Dux* is Latin for leader. A dux commanded a force; the work was done by the
people in it. That division is the design: you talk to one agent, and it
dispatches the rest.

<!-- DEMO: record a terminal GIF of a dispatch-to-PR run and drop it here.
     asciinema + agg works well. Keep it under 30 seconds.
<img src="docs/assets/demo.gif" alt="Dispatching a task and getting a PR back" />
-->

```
you   Have a look at how auth works in my-project and report back.
dux   Scout task started. Read-only. I'll have it when you're back.

      ... you close the laptop ...

dux   my-project scout is done. Auth is split across two middlewares and
      one of them is dead code. Report is in the task folder.

you   Plan the fix.
dux   Plan task started. You'll get a docs-only PR to approve.
```

---

## Features

- **One conversation, many agents.** Say what you want. Dux writes the brief,
  opens an isolated worktree, starts the worker, and reports back in plain words.
- **Supervision that costs no tokens.** A background watcher checks on workers
  and turns state changes into one line each. Your session never tails their
  output, so your context stays yours.
- **Interrupted on purpose.** One phone notification for a finished PR, a
  blocking question, a failure, or a base branch that goes red. Nothing else.
- **No shared checkout, ever.** Every task gets its own git worktree and branch
  cut from a freshly fetched base. Agents cannot corrupt each other.
- **Nothing merges on a claim.** Dux checks the branch, the PR and CI before it
  agrees a task is finished, never because a worker said so.
- **A pre-merge gate that ships with it.** `/ship` runs your project's checks, the
  reviews the branch owes, and CI — then opens the PR and stops. It works in any
  repo, with or without Dux.
- **GitHub issues as a queue.** Label an issue; it becomes a queued task, and the
  PR carries `Closes #n`.

---

## Quick start

**1. Clone and install.**

```bash
git clone https://github.com/mr-rob0to/dux.git ~/dux
cd ~/dux && bin/dux-install
```

**2. Sign in to GitHub.**

```bash
gh auth login
```

**3. Register a repo.**

```bash
bin/dux-project add ~/code/my-project --pr-template skip
```

`--pr-template` says what to do about a pull request template, and a repo that
has none will not register until you answer: `skip` leaves the repo untouched,
`install` writes `.github/PULL_REQUEST_TEMPLATE.md` for you to commit. Drop the
flag entirely if the repo already has a template.

**4. Check the install.**

```bash
bin/dux-doctor
```

```
ok claude      ok gh        ok git        ok registry
ok codex       ok jq        ok gh auth    backend: tmux
watcher: no session
```

`watcher: no session` is expected here — the watcher starts with your first
session, in the next step. Everything else should read `ok`.

**5. Run it.**

```bash
cd ~/dux && claude
```

That is the whole thing. Claude Code starts in the Dux repo, takes the session
lock, starts the watcher, and shows you the fleet digest. Then just talk to it.

### Requirements

| Tool | Why |
|---|---|
| [Claude Code](https://claude.com/claude-code) | Runs Dux and runs the workers |
| `git` 2.20+ | Worktrees, and the per-worktree configuration the push guard lives in |
| [`gh`](https://cli.github.com) | PRs, issues, CI status. Must be signed in |
| `jq` | Reads GitHub's JSON |
| `tmux` or [Herdr](https://herdr.dev) | Gives each worker its own pane or tab |
| [`codex`](https://developers.openai.com/codex/cli) | The gate's preferred code reviewer |

macOS or Linux.

**`codex` is required in practice.** The gate falls back to Claude Code without
it, so nothing is broken — but `bin/dux-doctor` reports it missing, and Dux's own
instructions say to fix every doctor failure before dispatching. Treat it as
required unless you also mean to ignore that. It is there so the code review
comes from a second vendor, which is the point of the step.

---

## What you can ask for

Three shapes, from safest to most involved.

**Scout — reads, changes nothing.**

> *"Have a look at how auth works in my-project and report back."*

**Plan — produces a design and plan as a docs-only PR for you to approve.**

> *"Plan the notifications feature in my-project."*

**Ship — implements one milestone, runs the gate, opens a PR.**

> *"Build milestone 2 of that plan."*

From `policy-stage` `m3`, a ship task can plan first: the worker commits a plan,
asks you to approve the tasks it names, and builds exactly those once you do.

And any time, in any repo, with no Dux involved:

> *"Ship it."*

---

## How a task runs

1. You say what you want. Dux writes the intent and acceptance criteria and reads
   them back in two lines.
2. It cuts a worktree on a new branch from a freshly fetched base and starts a
   worker in its own pane.
3. The worker works. Dux sees state changes, not output.
4. It finishes, gets stuck, or asks a question. You get one line. Your answer, or
   your approval of a plan it asked you to approve, goes to the same worker,
   still waiting in its tab. This needs `policy-stage` at `m3`; before that, or
   once that session is gone, the answer is a fresh task.
5. Dux checks the branch, the PR and CI before agreeing it is done.
6. You review, then merge or send feedback. Feedback goes to the same worker,
   still waiting in its tab, and comes back as new commits on the same PR, checked
   again before it counts. This needs `policy-stage` at `m2`; before that, feedback
   is a fresh task.
7. After you merge, Dux tears the worktree down and ends the waiting session,
   refusing if anything there is uncommitted or unpushed.
8. Work in a second repository, such as a client for an API change, is a task
   of its own. From `m3`, Dux starts it only once the first pull request has
   merged and any deployment or contract check named for it has passed.

<details>
<summary><strong>Why this shape — the four problems it is built around</strong></summary>

**Watching an agent burns the context you need to think.** A session that tails a
worker's output fills up with its output. Dux supervises from a background
process that costs no tokens.

**Agents in one checkout corrupt each other.** Two sessions sharing a working
tree share `HEAD` and `git stash`, and quietly undo each other. Every task gets
its own worktree.

**"Done" is not evidence.** An agent that says it finished is making a claim. Dux
checks the branch, the PR and CI before calling anything done.

**Nothing should merge because an agent was confident.** Delivery goes through a
gate that runs the checks, the reviews and CI, opens the PR, and stops there.

</details>

---

## The `/ship` gate

Installing Dux puts the gate in your skills directory, so it works in any
repository whether or not Dux dispatched the work.

1. Resolve the base branch from the repo, never assumed, then fetch it and
   confirm the branch is based on it.
2. Run the project's own checks — whatever CI runs.
3. Self-audit what a diff reviewer cannot see: backwards compatibility, docs the
   repo keeps in sync, tests for the failure modes.
4. **The reviews the branch owes**, run by a reviewer that did not write the
   change and is not told what it is for. A branch that touches authentication,
   permissions, secrets, migrations, data integrity, concurrency or cross-system
   ordering gets a separate security pass as well as the code review; every other
   branch gets one combined review whose prompt covers both. Anything the gate
   cannot establish counts as needing both. The PR says which one ran and why.
5. A fix pass clears the phases, and every fix commit gets a review that covers
   the changed code.
6. Open the PR, body filled from your repo's own template.
7. Watch CI to green.

Each phase records the commit it saw, so a review cannot be outrun by later
commits. Three fix passes per gate; the fourth is refused, because by then the
design is the problem. **The gate never merges.**

---

## What Dux will not do

Refusals in code, not guidelines.

- **Never writes to your repos.** Workers change code inside worktrees. The one
  exception is installing a PR template, when you ask for it.
- **Never merges.** No PR merges without you saying so.
- **Never reads raw worker text into the conversation.** Worker output is
  untrusted until it passes through the one command that caps and fences it.
- **Never tears down work.** A worktree with uncommitted or unpushed changes is a
  refusal, not an obstacle to route around.
- **Never runs two orchestrators at once.** A second session is read-only.

---

<details>
<summary><strong>Configuration</strong></summary>

Everything lives in `config/`, seeded on install and ignored by git. Each file
explains itself in comments. An explicit value always wins over the bundled
default and is never probed.

| File | What it sets |
|---|---|
| `reviewer` | Code reviewer for the gate. `auto` picks from your machine |
| `security-reviewer` | Security reviewer, for the branches that owe a separate pass. `auto` picks from your machine |
| `policy-stage` | Which rollout stage this install may act on. `bin/dux-doctor` prints what it leaves unavailable |
| `models` | Model and effort per task shape |
| `worker-harness` | Which agent runs workers |
| `backend` | `tmux` or `herdr`. Empty means detect |

`bin/dux-project add` also takes `--name`, `--base`, `--issues label:<name>`,
`--worktree make|script|git`, and `--pr-template install|skip`. `--pr-template` is
required when the repo has no pull request template: registration stops with a
finding until you say install or skip, so nobody is silently not asked. It is not
needed when the repo already has one, because there is nothing to decide.

</details>

<details>
<summary><strong>Honest limits</strong></summary>

- **Claude Code only, today.** Dux runs under Claude Code, and workers are Claude
  Code. Codex is used as the gate's code reviewer, which is a different job.
- **One machine, one fleet.** No server, no remote state.

</details>

<details>
<summary><strong>Upgrading</strong></summary>

Dux keeps its state on disk, so pulling and restarting the session is the whole
upgrade.

```bash
cd ~/dux && git pull && bin/dux-install
```

`bin/dux-install` picks up new or renamed skills. It never overwrites a config
file you have edited, so your settings survive. Finish any running task first —
a worker started under the old version keeps running under it.

</details>

---

## Documentation

| Document | What is in it |
|---|---|
| [`docs/specs/`](docs/specs/) | The design, and every decision behind it |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | What each script owns |
| [`docs/constitution.md`](docs/constitution.md) | Engineering standards |
| [`docs/plans/`](docs/plans/) | Roadmap and milestone plans |
| [`tests/harness/ship.md`](tests/harness/ship.md) | A full gate run, from a fresh clone |

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first. In short:

```bash
brew install bats-core shellcheck
make check         # after a change, about two minutes
make check-branch  # before /ship, adds the bash 3.2 pass
```

Scripts are bash 3.2 and shellcheck clean, because macOS still ships bash 3.2.
Findings go to stderr with exit 2. Every guard is broken once and seen to fail
before it counts.

## License

MIT. See [`LICENSE`](LICENSE).
