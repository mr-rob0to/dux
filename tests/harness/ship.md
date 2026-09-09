# The /ship gate, run end to end from a fresh clone

This is a recording, not a test the suite runs. It exists because nothing in
`make check` can prove that the gate works when it is installed rather than
read: the skill is prose an agent follows, the two helpers beside it are the
only executable parts, and the thing most likely to break is the seam between
them and a checkout they were never run from.

So the whole gate was run once, by hand, against a real remote and real CI.
This file is what it printed.

## What it was run against

A fresh clone of `feat/m6-ship-standalone` at `cd792f2`, with **no `config/`
directory at all**. That is the point: every reviewer value below came from
`templates/config/`, the bundled defaults, because there was nothing else for
`ship-env` to read. A machine that has never run `bin/dux-install` reads the
same files; what those files resolve to now depends on what that machine has,
which the two reviewer steps below say more about.

The repository under review was a throwaway created for this run and deleted
when it finished. It held a `Makefile` whose `check` target compares
`greeting.txt` with `expected.txt`, a GitHub Actions workflow that runs that
target, and a one-commit branch `fix/greeting` that makes the two files agree.
Small on purpose: the subject of the recording is the gate, not the diff.

Paths are redacted. `<tmp>` is the scratch directory the clones sat in,
`<dux>` the Dux clone the gate ran from, `<account>` the GitHub account and
`<throwaway>` the repository that no longer exists.

## Step 0. Resolve the base branch, then the two helpers

```
$ gh repo view --json defaultBranchRef -q .defaultBranchRef.name
main
$ git symbolic-ref --short refs/remotes/origin/HEAD
origin/main
  Both say main and the repo states no convention of its own. BASE=main.

$ SHIP_ENV="$(dirname "$SHIP_GUARD")/ship-env"; [ -x "$SHIP_GUARD" ] && [ -x "$SHIP_ENV" ]
  Both resolved, from the clone. One override pointed both at one checkout.
$ "$SHIP_ENV" --root
<tmp>/task4/dux-clone
$ "$SHIP_GUARD" open
  No output. The gate is open and the fix count is zero.
```

`--root` printing the clone is the first thing worth seeing. `ship-env` walks
up from its own location; it did not need `DUX_HOME`, an environment file, or
anything sourced.

## Step 1. Sync the base ref

```
$ git fetch origin main
  From https://github.com/<account>/<throwaway>
   * branch            main       -> FETCH_HEAD
```

## Step 2. Base check

```
$ git merge-base --is-ancestor origin/main HEAD && echo OK || echo NOT-BASED-ON-BASE
OK
```

## Step 3. Working tree

```
$ git status --porcelain
  Empty. Nothing stray staged and nothing about to be swept in.
```

## Step 4. Local checks

```
$ make check
ok  greeting.txt matches expected.txt
$ "$SHIP_GUARD" record checks
  Recorded against b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4.
```

## Step 5. Pre-review self-audit

```
  No published interface, so nothing to break for a released client. The repo
  names no document as a source of truth. make check covers the failure mode:
  it exits 1 when the two files differ. One atomic commit, conventional subject.
  Evidence: nothing here is user-visible, so the check command and its result
  above are the evidence, which is what step 8's body requirement asks for.
```

The evidence line is the rule step 5 added in this milestone. There was no
screenshot to take, so the transcript says why there is none. That satisfies it;
a missing screenshot is a body requirement, not a stop.

## Step 6. The one code review

```
$ REVIEWER="$("$SHIP_ENV" reviewer)"
$ echo "$REVIEWER"
codex exec -m gpt-5.6-sol --sandbox read-only
```

No `config/reviewer` existed, so the value came from `templates/config/reviewer`.

Since this run the bundled default is the word `auto`, and `ship-env` chooses
the command when the gate runs: codex when it is on `PATH`, otherwise Claude
Code in plan mode, and a finding naming the config file when there is neither.
The machine that made this recording has codex, so the line above is still what
a fresh clone resolves here. An explicit value in `config/reviewer` is never
probed.

The block was run under `bash -c`. Under `zsh` the unquoted `$REVIEWER` is one
word, and the shell reports the whole line as a command that does not exist.
That is why the skill now says these blocks are bash.

```
$ $REVIEWER "Review the diff of this branch against main for correctness, regressions, security, concurrency, backwards compatibility, and missing tests. Answer in this shape and no other: a literal '## Findings' header, then the findings ordered by severity with precise file:line references, or the single line 'No findings.' under that header when there are none. State explicitly when an area has no findings."
--------
workdir: <tmp>/task4/app
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
--------
[... the reviewer read the diff, the working tree, the Makefile and the
     workflow, and ran make check itself ...]

codex
## Findings
No findings.
```

The literal `## Findings` header arrived, so the answer is readable. Exit 0.

```
$ "$SHIP_GUARD" record review
  Recorded against b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4.
$ "$SHIP_GUARD" check review
  No output. The reviewed commit is still the commit at HEAD.
```

## Step 7. The security pass

```
$ SECURITY_REVIEWER="$("$SHIP_ENV" security-reviewer)"
$ echo "$SECURITY_REVIEWER"
agent:security-reviewer
```

Same lookup, same absent `config/`, so this came from
`templates/config/security-reviewer`. The `agent:` form means dispatch the named
agent rather than run a command, which is what happened.

That default is `auto` now too: the agent when a `security-reviewer` definition
is on the host or in the project, otherwise Claude Code in plan mode, and a
finding naming the config file when there is neither. This machine defines the
agent, so the line above is still what it resolves. An explicit `agent:` value
on a host that cannot dispatch agents still stops the gate.

```
$ dispatch agent security-reviewer with the step 7 prompt
## Findings

No findings.

The diff (b45d4cd on fix/greeting vs main) changes two plain-text data files
from `hello` to `hello, world`. Neither file is executed, interpolated, or
parsed as anything but a string compared by `make check`. [...] No exploit path
exists: there is no attacker input, no principal, and nothing to gain.

## Checked clean

- Authentication and authorization: no auth code, endpoints, or principals
  exist anywhere in the repo; nothing in the diff touches identity.
- Secrets and configuration: no credentials, tokens, .env files, or config in
  the diff or the repo; ci.yml references no secrets.
- Injection and untrusted input: the changed values flow only into the Makefile
  comparison; they are quoted, come from the repo itself, and contain no shell
  metacharacters.
- Data exposure: no PII, internal identifiers, or response models.
- Client-side storage and transport: no client, no cookies, no TLS surface.
- Dependencies and supply chain: no dependency manifests; the only third-party
  reference is actions/checkout@v4, pinned to a major tag rather than a commit
  id. For a throwaway repo with no secrets in CI, an accepted limit.
- CI workflow: runs make check only, on push/pull_request (not
  pull_request_target), default read-only token scope.
- Deploy ordering and compatibility: both files change in the same commit, so
  CI stays green at every point on the branch.
- Cryptography, concurrency, object storage, background jobs, infrastructure as
  code: none present; verified absent by reading every tracked file.
```

Both headers are there, `## Findings` and `## Checked clean`, so the answer is
readable and the pass is real rather than assumed. This is the fail-closed
reading the skill asks for: an answer missing either header would have stopped
the gate.

```
$ "$SHIP_GUARD" record security
  Recorded against b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4.
$ "$SHIP_GUARD" check checks && "$SHIP_GUARD" check review && "$SHIP_GUARD" check security
  No output, three times. All three phases saw the commit that is about to be pushed.
$ "$SHIP_GUARD" push-ok
  No output. The gate agrees the branch may leave the machine.
```

## Step 8. The pull request

The push, the block the skill spells out and both push steps share:

```
$ BRANCH="$(git symbolic-ref --short HEAD)"
fix/greeting
$ git fetch --prune origin
$ REMOTE="$(git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH")"
REMOTE=[]
  Empty: the branch has never been pushed. The ancestor test is skipped, because
  there is no remote commit to be behind, and the lease anchors to the empty
  string, which means "create it or refuse".
$ git push --force-with-lease="refs/heads/$BRANCH:$REMOTE" origin "HEAD:refs/heads/$BRANCH"
To https://github.com/<account>/<throwaway>.git
 * [new branch]      HEAD -> fix/greeting
$ [ "$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)" = "$(git rev-parse HEAD)" ]
b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4 = b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4
```

The empty-expect lease is one shape that covers both cases. Pushed by hand
against a ref that had appeared in between, the same command refuses with
`stale info`.

The template lookup:

```
$ "$SHIP_ENV" pr-template "$(git rev-parse --show-toplevel)"
  Empty, exit 0. This repository carries no pull request template.
$ "$SHIP_ENV" pr-template-fallback
<dux>/templates/PULL_REQUEST_TEMPLATE.md
```

`pr-template` is `bin/dux-project pr-template` under a different name, so the
gate and the registration command look in the same places and agree. Nothing
was found, so the bundled template stood in and the body says so.

The body was the bundled template's own headings, filled: **Why**, **What
changed**, **How to review**, **Verification** (checks, evidence, and why
break-verification does not apply to a branch that adds no guard), **Reviews**
with both reviewers and their counts, the full findings inside a `<details>`
block, and **Risk**.

Then the attestation, appended after the prose:

```
$ "$SHIP_GUARD" attest >> "$BODY"
<!-- dux-attestation:v1 {"head_sha":"b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4","fix_passes":0,"steps":[{"step":"checks","status":"completed","sha":"b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4"},{"step":"review","status":"completed","sha":"b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4"},{"step":"security","status":"completed","sha":"b45d4cdfa1de0dc2f165d132235fbb110c3f0dc4"}]} -->
```

Three phases, each naming the commit it saw, all three equal to the head that
was pushed. It is an HTML comment, so it is invisible in the rendered body and
readable by anything that fetches it.

Opening it:

```
$ TITLE="${SHIP_TITLE:-$(git log --format=%s "origin/$BASE..HEAD" | tail -n 1)}"
fix: greet the world, not just anyone
$ gh pr create --base "$BASE" --title "$TITLE" --body-file "$BODY"
https://github.com/<account>/<throwaway>/pull/1
```

`--title` and `--body-file`, never `--fill`: the body is the filled template
and the attestation, and `--fill` would have thrown both away for the commit
message.

## Step 9. CI

```
$ gh run watch <run> --exit-status
✓ fix/greeting ci <account>/<throwaway>#1 · 34307008518
JOBS
✓ check in 5s
  ✓ Set up job
  ✓ Run actions/checkout@v4
  ✓ Run make check
  ✓ Post Run actions/checkout@v4
  ✓ Complete job
== exit 0

$ gh pr checks 1
check	pass	4s
check	pass	5s
```

Green on the first attempt, so there was no fix pass and step 9 never rebuilt
the body. The repository was deleted after this line.

## What this run does not prove

- **The refusal paths.** Everything above is the happy path. The guard refusing
  a stale phase and `ship-env` refusing a checkout it cannot read are covered by
  `tests/ship-guard.bats` and `tests/ship-env.bats`, each broken and seen to
  fail. The ancestor test rejecting a remote this branch has never seen, and the
  lease losing a race, are **not** covered by any test: they are prose in
  `SKILL.md`, and `tests/contract.bats` only proves the prose still says them.
  The empty-expect lease was exercised by hand at milestone 6 and refused with
  `stale info`; the ancestor test was not. A green transcript says nothing about
  any of them.
- **A fix pass.** CI passed first time, so `fix-pass`, the re-review of new
  commits, and step 9's rebuilt body were not exercised end to end here.
- **A repository that has its own template.** This one had none, so the fallback
  branch is what ran. The lookup itself is `bin/dux-project pr-template`, which
  `tests/dux-project.bats` covers in both shapes.
