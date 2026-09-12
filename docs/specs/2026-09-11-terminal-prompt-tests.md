# Dux: testing a command that asks at the terminal

Design authority for the test helper that gives a command a terminal and types an
answer into it. It exists so the helper's shape is settled by measurement, on both
platforms the suite runs on, before any command on `main` needs it. The orchestrator
design (`2026-09-03-dux-orchestrator-design.md`) stays the authority for everything
else; its section 15 points here.

Plan: `docs/plans/2026-09-11-salvage-pty-feed.md`.

## 1. Where this comes from

Nothing on `main` reads an answer from a terminal today. No script under `bin/` tests
whether stdin is a terminal, and every `read` in `bin/` reads a file or a pipe. The
suite has no terminal helper and no test that skips for want of one.

An abandoned worktree, task `dux-ship-20260909-a81`, built a feature that does ask: on
that branch `dux-project add` asks at the terminal whether to install the pull request
template when the repo has none and no `--pr-template` flag was given. That branch was
never pushed and has no pull request. Its plan,
`docs/plans/2026-09-09-pr-template-prompt.md`, exists only there. The feature added five
tests to `tests/dux-project.bats` that run the command through a terminal:

- a yes at the prompt installs the template and registers
- a no at the prompt registers and writes nothing
- an empty answer at the prompt registers and writes nothing
- a repo that already has a template is never prompted
- the prompt goes to the terminal and never into the relayed line

The committed helper on that branch passed those tests on macOS and hung them on Linux.
The worker's fix to the helper was left uncommitted when the task failed. This
document records what that fix got right, what it got wrong, and what was measured
on 2026-09-11 when it was re-run on both platforms.

The same uncommitted diff carries a second change: a loop at the top of
`tests/helpers/setup.bash` that unsets every inherited `GIT_CONFIG_*` variable. That
was a workaround for the push guard reaching every repo a worker touched, which pull
request #29 fixed properly by putting the guard in the task worktree's own git
configuration. A worker's environment carries no `GIT_CONFIG_*` variable now, and the
suite on `main` runs green inside a worker without the loop. The loop is dead and is
not to be revived.

## 2. What the helper must do

Three functions in `tests/helpers/setup.bash`, none of them present on `main` today.

- `require_pty`: skips the test when `script(1)` is not on `PATH`. Both CI images and
  the operator's machine have it; the skip is for a bare shell.
- `run_in_pty <answer> <command...>`: runs the command with a pseudo-terminal on stdin,
  prints the session with the terminal's line endings normalised to plain newlines, and
  returns the command's own exit status. It tells the two `script(1)` families apart by
  asking for `--version`, which only util-linux answers, rather than by platform.
  util-linux takes the command as one `-c` string; BSD takes it as words after the
  typescript file, the file `script` records the session into, which is `/dev/null`
  here because the session is captured from stdout instead.
- `pty_feed <answer>`: the writing side of the terminal. It runs as a process
  substitution, a small helper process whose output is `script`'s stdin. It types the
  answer, keeps the pipe open for one second, then exits so the pipe closes. It takes
  nothing else: section 3 says why it does not watch the command's output.

Two facts the helper has to work around, each measured:

- **The command's exit status is written to a file by the command itself**, not read
  back from `script`. util-linux `script -e` returns 0 instead of the command's status
  when its own stdin is a pipe, which is exactly what the answer arrives on. Measured on
  util-linux 2.39.3: `script -q -e -c 'exit 3' /dev/null < <(sleep 0.2)` exits 0, the
  same line with `</dev/null` exits 3. BSD `script` returns 3 either way. Trusting
  `script` would make every status assertion in a terminal test pass on Linux whatever
  the command did.
- **The pipe must close, and not in the same instant as the answer.** Section 3 says
  why. A feeder that never exits hangs the test under bats on both platforms. A feeder
  that exits on the answer's heels loses the answer on macOS.

## 3. What was measured

Measured 2026-09-11 with a three-test self-check: a command that prints a prompt and
reads at once, one that prints and reads two seconds later, and one that reads without
printing anything and exits 3. Each cell is the whole file under bats.

| Feeder shape | macOS 27, BSD script, bats 1.14 | Ubuntu 24.04, util-linux 2.39.3, bats 1.10 |
|---|---|---|
| answer, exit at once | all three fail: the answer never arrives | passes |
| answer, hold one second, exit | passes | passes |
| wait for output, answer, exit at once | passes | passes |
| wait for output, answer, hold one second, exit | passes | passes |
| wait for output, answer, never exit | hangs | hangs |
| answer, hold until `script` returns (the branch's committed shape) | passes | hangs |

The never-exit row is what the abandoned worktree's uncommitted comment calls the
nine-minute hang. The committed shape, the last row, passed on macOS and hung on Linux
under bats. Outside bats the same shape returns in under a second on Linux, with the
real command and with four stand-ins, so the comment's explanation, that util-linux
`script` keeps running while its stdin is open, does not hold as stated. What makes the
difference under bats was not pinned down. The tests run under bats, so the row above is
the fact that matters.

On macOS, the first row's failure is the one the abandoned comment describes: BSD
`script` turns the end of the pipe into an end-of-file on the terminal that lands ahead
of the answer, and `read` sees the end of input first. The session shows `^D^H^Hy`,
the end-of-file mark echoed before the answer. It happens only when the pipe closes in
the same instant the answer is written. Either a one-second hold or waiting for the
command's output before answering avoids it; the two together avoid it too.

**Decision: the helper holds the pipe open one second after the answer, then exits. It
does not wait for the command's output first.** No measured case needs the wait, so
there is no break that makes it fail, and a guard that cannot be seen to fail is not a
guard. It also costs up to ten seconds on any command that reads before it prints,
because the wait is bounded by a timeout rather than by the prompt. The abandoned fix
had both halves and passed everywhere; this shape has one and passes everywhere. If a
command ever arrives that discards typed-ahead input before it reads, that is the case
the wait would serve, and the test that finds it is where the wait gets added.

## 4. How a landing proves it

The helper has no caller on `main`, so its proof is a self-check, `tests/pty.bats`,
with the three tests section 3 was measured with. Each break is seen on the platform
that shows it; the other platform passes it, and the plan says which is which. Linux is
a Docker run of the Ubuntu release CI runs; macOS is the operator's machine or the macOS
CI job.

- Break the hold: remove the one-second hold. macOS: all three tests fail, the answer
  never arrives. Linux: passes.
- Break the close: make the feeder loop forever after the answer. Both platforms: the
  run never finishes. bats cannot report this one: a per-test `BATS_TEST_TIMEOUT` fires
  and the runner still waits, measured at two minutes on macOS before it was killed,
  because the feeder holds the runner's output open. The break is run under an outside
  time limit of sixty seconds and the kill is what gets recorded.
- Break the status: return `script`'s own status instead of the file's. Linux: the
  exit-3 test fails with status 0. macOS: passes.

## 5. Decisions already made

- Nothing on `main` needs the helper today, and landing it alone means test
  infrastructure with no caller. The plan recommends not landing it until a command
  that reads from a terminal is on its way, and records here everything a landing needs
  so nothing about the helper is lost when the abandoned worktree goes.
- When the terminal-prompt feature is re-dispatched, its plan carries the helper and
  this self-check as its first task, so the hang fix is proved before the feature's own
  tests depend on it.
- The `GIT_CONFIG_*` unset loop is dead (section 1). Nothing revives it.
