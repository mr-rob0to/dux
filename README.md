# Dux

*Dux* is Latin for leader, from *dūcere*, to lead. It is where English gets
*duke*. A dux commanded a force; the work was done by the people in it.

That division is the design.

**Dux is an orchestrator you talk to.** It runs coding agents across your
repositories, supervises them while you do something else, and comes back with
pull request links and decisions.

You talk to one agent. It dispatches the others.

---

## Why you would want this

Coding agents are good at a task and bad at a day. Left alone they drift; watched
closely they cost you the time they were meant to save. Four things go wrong, and
Dux is built around each of them.

**Watching an agent burns the context you need to think.** A session that tails a
worker's output fills up with its output. Dux supervises from a background
process that costs no tokens, and wakes you only when a task actually needs a
decision.

**Agents working in one checkout corrupt each other.** Two sessions sharing a
working tree share `HEAD`, share `git stash`, and quietly undo each other. Every
Dux task gets its own git worktree and its own branch, created from a freshly
fetched base.

**"Done" is not evidence.** An agent that says it finished is making a claim. Dux
checks the branch, the pull request and CI before it calls anything done, never
because a worker said so, and tells you what it actually found.

**Nothing merges because an agent was confident.** Delivery goes through `/ship`,
a pre-merge gate that runs your project's own checks, an independent code review,
a separate security pass, and CI. It opens the pull request. It never merges —
that stays yours.

---

## What you get

- **One conversation.** Say what you want in a repo. Dux writes the brief, opens
  the worktree, starts the worker, and reports back in plain words.
- **Three kinds of task.** `plan` produces a design and plan as a docs-only pull
  request. `ship` implements one milestone of an approved plan and takes it
  through the gate. `scout` reads and reports, changing nothing.
- **Free supervision.** A watcher process turns worker state changes into one
  line each. Dux reacts to those lines. Nothing polls, and nothing pays tokens to
  wait.
- **You are interrupted on purpose, not by volume.** A phone notification for a
  finished pull request, a question that blocks progress, or a failure. Nothing
  else.
- **Worker output is treated as untrusted.** A worker runs with your credentials,
  so what it writes is data, not instruction. Raw worker text never lands in the
  conversation except through one command that caps, cleans and fences it.
- **GitHub issues as a work queue.** Label an issue, and it becomes a queued task
  at the next session start. The issue text travels as data, the pull request
  carries `Closes #n`, and an issue closed before work started is dropped.
- **A gate that works on a fresh clone.** `/ship` picks its reviewers from what
  your machine has, every time it runs. Codex if you have it, Claude Code if you
  do not. Nothing to configure before your first run.
- **Refusals instead of guesses.** Every script stops with a `finding:` line
  naming what is wrong and what to change. Dux relays it and stops rather than
  working around it.
- **`/ship` is useful on its own.** Installing Dux puts the gate in your skills
  directory, so you can run it in any repository whether or not Dux dispatched
  the work.

---

## Requirements

macOS or Linux, and:

| Tool | Why |
|---|---|
| [Claude Code](https://claude.com/claude-code) | Runs Dux itself and runs the workers |
| `git` | Version 2.5 or newer, for worktrees |
| [`gh`](https://cli.github.com) | Pull requests, issues and CI status. Must be signed in |
| `jq` | Reads GitHub's JSON |
| `tmux` **or** [Herdr](https://herdr.dev) | Gives each worker its own pane or tab |
| [`codex`](https://developers.openai.com/codex/cli) | The gate's preferred code reviewer |

`codex` is optional in practice — the gate falls back to Claude Code without it —
but `bin/dux-doctor` reports it as missing, because a review by a second vendor
is the point of the step.

For development you also want `bats-core` and `shellcheck`.

---

## Install

**1. Clone it.** Anywhere you like; the path does not matter.

```bash
git clone https://github.com/mr-rob0to/dux.git ~/dux
cd ~/dux
```

**2. Install the skills.**

```bash
bin/dux-install
```

This symlinks the bundled skills into `~/.claude/skills` and seeds `config/`
from `templates/config/`. It never overwrites a config file you have edited. A
skill directory that is already there and is not ours stops the install and tells
you so; re-run with `--yes` to move it aside as `<name>.bak`.

**3. Sign in to GitHub**, if you have not.

```bash
gh auth login
```

**4. Register your first repository.**

```bash
bin/dux-project add ~/code/my-project
```

The folder name becomes the project name. The base branch is detected from the
repository. Useful flags:

| Flag | What it does |
|---|---|
| `--name <name>` | Use a different project name, for two repos with the same folder name |
| `--base <branch>` | Set the base branch instead of detecting it |
| `--issues label:<name>` | Turn issues with that label into queued tasks |
| `--pr-template install` | Write a pull request template into a repo that has none |
| `--worktree make\|script\|git` | Force how worktrees are created, instead of detecting it |

`--pr-template install` is the only time Dux writes into one of your
repositories, and it only happens when you ask for it and the repo has no
template already. Commit that file before dispatching work.

**5. Check the install.**

```bash
bin/dux-doctor
```

Every line should read `ok`. Fix anything that says `FAIL` before dispatching —
the most common one is `registry`, which just means no project is registered yet.

---

## Run it

```bash
cd ~/dux
claude
```

That is the whole command. Claude Code starts in the Dux repository, picks up the
Dux instructions, takes the session lock, starts the watcher, and shows you the
fleet digest.

Then talk to it:

- *"What's running?"* — the digest: what is working, what is waiting on you, what
  is ready to merge.
- *"Have a look at how auth works in my-project and report back."* — a `scout`
  task. Read-only.
- *"Plan the notifications feature in my-project."* — a `plan` task. You get a
  design and plan as a docs-only pull request to approve.
- *"Build milestone 2 of that plan."* — a `ship` task. It implements, runs the
  gate, and opens a pull request.
- *"Ship it"*, inside any repository — runs the gate on the branch you are on,
  with no Dux involvement at all.

While a task runs you can close the laptop. When something finishes or gets
stuck, your phone gets one line telling you what to do.

**Restart the session daily, or after about 40 wakes.** Agent sessions degrade as
they get long. Dux keeps its state on disk, so a restart loses nothing and
reconciles from the files.

---

## What a task looks like

1. You say what you want. Dux writes the intent and the acceptance criteria and
   reads them back to you in two lines.
2. It creates a worktree on a new branch from a freshly fetched base, and starts a
   worker in its own pane or tab.
3. The worker works. Dux sees state changes, not output.
4. The worker finishes, gets stuck, or asks a question. You get one line.
5. On a finished task, Dux checks the branch, the pull request and CI before
   agreeing it is done, and gives you the link.
6. You review and merge. Then Dux tears the worktree down — refusing if anything
   there is uncommitted or unpushed.

---

## The `/ship` gate

Every delivery goes through it, and you can run it by hand in any repository.

1. Resolve the base branch from the repository, never assumed.
2. Fetch it, and confirm the branch is actually based on it.
3. Check the working tree is clean.
4. Run the project's own checks — the Makefile target, the npm script, whatever
   CI runs.
5. Self-audit for the things a diff reviewer cannot see: backwards compatibility,
   docs the repo requires kept in sync, tests for the failure modes.
6. **One independent code review**, by a reviewer that did not write the change
   and is not told what it is for.
7. **A separate security pass**, on every ship, not only when the diff looks
   security-relevant.
8. Open the pull request, with the body filled from your repository's own
   template and evidence for anything a person can see.
9. Watch CI to green.

Each phase records which commit it saw, so a review cannot be quietly outrun by
commits that land afterwards. Fixing anything re-runs the affected phases. Three
fix passes per gate; the fourth is refused, because by then the design is the
problem rather than the fix.

The gate never merges.

---

## Configuration

Everything lives in `config/`, seeded on install and ignored by git.

| File | What it sets |
|---|---|
| `reviewer` | The code reviewer command for step 6. `auto` picks from your machine |
| `security-reviewer` | The security reviewer for step 7. `auto` picks from your machine |
| `models` | Which model and effort each task shape gets |
| `worker-harness` | Which agent runs workers |
| `backend` | `tmux` or `herdr`. Empty means detect |

Each file explains itself in comments. An explicit value always wins over the
bundled default and is never probed.

---

## What Dux will not do

These are refusals in code, not guidelines.

- **Never writes to your repositories.** Workers change code inside worktrees and
  deliver through pull requests. The one exception is installing a pull request
  template when you ask for it.
- **Never merges.** No pull request merges without you saying so.
- **Never reads raw worker text into the conversation.** Everything a worker
  writes is untrusted until it passes through the one command that fences it.
- **Never tears down work.** A worktree with uncommitted or unpushed changes is a
  refusal, not an obstacle to route around.
- **Never runs two orchestrators at once.** A second Dux session is read-only:
  it can look, not dispatch.

---

## Honest limits

- **Workers are Claude Code only.** Codex is refused as a worker today, because
  the deny rules that stop a worker pushing to your base branch have no Codex
  equivalent. Codex is used as the gate's code reviewer, which is a different
  job.
- **Dux runs under Claude Code.** Running Dux itself under Codex is planned, not
  built.
- **The gate's receipt is a record, not proof.** It says the phases ran in order,
  and the worker's own run writes it. The independent evidence is the branch, the
  pull request and CI, which Dux checks directly.
- **The reviewer runs inside the repository it reviews.** The gate stops that
  repository supplying the reviewer's instructions, but a stronger boundary wants
  a different design, and that is written up as an open problem in the spec.
- **One machine, one fleet.** Dux has no server and no remote state.

---

## Upgrading

Dux keeps its state on disk, so pulling a newer version and restarting the
session is normally the whole upgrade. Re-run `bin/dux-install` afterwards to
pick up new or renamed skills; it will not overwrite a config file you have
edited.

One exception, for installs that predate the rule that a worker's word is a
request rather than evidence. A task that was already running across that change
is retired once:

```bash
bin/dux-recover <id> --retire-legacy
```

That stops its worker and records it failed, and keeps its branch and worktree
for one retry.

## Develop

```bash
brew install bats-core shellcheck
make check         # after a change, about two minutes
make check-branch  # before /ship, adds the bash 3.2 pass
```

Scripts are bash 3.2 and shellcheck clean, because macOS still ships bash 3.2.
Findings go to stderr with exit 2.

- Design: `docs/specs/2026-09-03-dux-orchestrator-design.md`
- Architecture: `docs/ARCHITECTURE.md`
- Engineering standards: `docs/constitution.md`
- Plans and roadmap: `docs/plans/`
- A full `/ship` run from a fresh clone against a real remote:
  `tests/harness/ship.md`

## License

MIT. See `LICENSE`.
