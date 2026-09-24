# Contributing

Bug reports, questions and patches are all welcome. This file is the whole
process.

## 1. Open an issue first

**Search the existing issues before you write a new one.**

```bash
gh issue list --search "your keywords"
```

Or use the [issues page](https://github.com/mr-rob0to/dux/issues) and search
there, including closed issues — the answer may already be written down.

If nothing matches, open one:

```bash
gh issue create
```

Say what you expected, what happened, and how to reproduce it. Include your OS,
your `bash --version`, and the output of `bin/dux-doctor` with anything private
removed.

For anything larger than a bug fix, wait for a reply on the issue before you
start building. It is a short wait, and it is cheaper than a rewrite.

## 2. Set up

**Fork it**, then clone your fork:

```bash
gh repo fork mr-rob0to/dux --clone
cd dux
```

**Install the dependencies.** On macOS:

```bash
brew install bats-core shellcheck tmux jq
```

On Debian or Ubuntu:

```bash
sudo apt-get install -y bats shellcheck tmux jq
```

You also need `git` 2.5 or newer and [`gh`](https://cli.github.com), signed in
with `gh auth login`.

**Run the suite** to confirm a clean starting point:

```bash
make check
```

It takes about two minutes and should exit 0 before you change anything.

## 3. Make the change

```bash
git checkout -b fix/short-description
```

Four rules, and the tests enforce all of them:

- **Write the test first, then break it.** Every guard is broken once, seen to
  fail, and the failure pasted into the commit message. A test you have not seen
  fail is not a guard.
- **bash 3.2 and shellcheck clean.** macOS still ships bash 3.2, so no `declare
  -A`, no `${var^^}`, no `readarray`. `make check-branch` runs the suite again
  under 3.2.
- **Findings, not guesses.** A script that meets a surprise prints
  `finding: <what is wrong and what to change>` to stderr and exits 2.
- **No personal paths, usernames or project names** in tracked files. Yours live
  in `data/`, `state/` and `config/`, which are ignored.

Every script has a matching file in `tests/`. Design changes go through
`docs/specs/` before the code.

### Waiting in a test

A busy machine makes every step slower, so a test waits for the thing it cares
about, not for a clock: `wait_until <seconds> <command>` polls until the command
succeeds.

- **A process has ended:** ask `gone <pid>` or `group_gone <pgid>`, never bare
  `kill -0`, which still answers for a process that ended but was not collected.
- **Time has passed:** move the clock with `age_task <id> <seconds>` instead of
  sleeping past a small limit, which a slow start can reach first.
- **Nothing more happened:** only here is a fixed `sleep` fine, before counting
  events that must not have grown. A slow machine makes it weaker, never red.

## 4. Check it

```bash
make check         # the full suite, about two minutes
make check-branch  # the same again under bash 3.2, before you open the PR
```

Running one file on its own, or putting the output back in a readable order:

```bash
bats tests/dux-watch.bats
make test JOBS=1
```

Measuring a test that fails only some of the time: `tests/repeat <make-job>
<runs> [burners]` runs one job that many times with that many busy loops beside
it, and prints how many runs failed and which tests failed in them. Linux is
measured in a container. The repository is copied in, not mounted. Keep
`--init`: without it nothing collects a finished wrapper, and spawn reads it as
still running.

```bash
docker run -d --init --cpus 4 --name dux-load ubuntu:24.04 sleep infinity
docker exec dux-load sh -c 'apt-get update -q && apt-get install -y -q bats shellcheck tmux jq git make perl procps && useradd -m dev'
git archive HEAD | docker exec -i -u dev dux-load sh -c 'mkdir ~/dux && tar -x -C ~/dux'
docker exec -u dev -e TERM=xterm -w /home/dev/dux dux-load tests/repeat job-m/backend-tmux 25 12
docker rm -f dux-load
```

## 5. Open the pull request

```bash
git push -u origin fix/short-description
gh pr create --base main
```

Fill in the template that appears. It asks for what changed, how to review it,
and how you verified it — including which guard you broke and the failure it
printed.

Write the commit message about the diff, not the intent: someone reading it a
year from now should be able to check every claim against the code.

CI runs the suite on Ubuntu and again on macOS under bash 3.2. Both have to be
green.

## What happens next

A maintainer reviews it. Changes to behaviour also go through the ship gate
(`/qed:ship`, from the `qed@mr-rob0to` plugin), which runs the reviews the branch
owes: one combined review, or a code review and a separate security pass when the
diff touches a sensitive area such as authentication or data integrity.
Findings come back on the PR; fix what matters and say plainly which ones you are
not acting on and why.

## License

By contributing, you agree your work is released under the MIT License in
[`LICENSE`](LICENSE).
