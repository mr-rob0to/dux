# Dux: telling the operator when a base branch goes red

Date: 2026-09-18. Status: proposed, for approval with its plan,
`docs/plans/2026-09-18-base-branch-check.md`. Amends the living spec,
`2026-09-03-dux-orchestrator-design.md`, sections 3, 6.2, 6.3, 8 and 14, which the plan's Task 1
points here.

## 1. The problem

Between 2026-09-15 and 2026-09-18 the Dux `main` branch failed its checks five times after a
change landed (#50, #51, #55, a32fe04, #61). Each pull request was green on its own branch. Dux
said nothing, because a task ends at "pull request delivered" and teardown, and nothing looks at
the run GitHub starts on the base branch afterwards.

One of the five, a32fe04, was a commit pushed straight to `main`. It had no pull request and no
Dux task. A check that only follows merges Dux knows about would have missed it.

## 2. The decision

A new script, `bin/dux-base`, asks GitHub one question per registered repository: what happened
to the newest push run on the registered base branch. The watcher starts it in the background
every five minutes and never waits for it. It keeps one small record per project under
`state/base/`. When a base goes red it appends one line to `state/events.log`, which wakes Dux
the way a task event does.

- **Who checks:** `bin/dux-base check`, started by `bin/dux-watch`.
- **When:** in the watcher's loop, whenever the last start was more than
  `DUX_BASE_INTERVAL_SECS` ago (default 300) and the check it started before has exited. After
  a night with no session that is the first loop. `0` turns it off. A value that is not a whole
  number is logged once and treated as off; it never stops the watcher. Also by hand at any time.
- **How:** one `gh run list` call per project, for push runs on the registered base branch. It
  follows the branch, not a list of merges, so it sees direct pushes and merges made outside Dux,
  and it works the same for a base named `main` or `staging`.

The watcher runs only while a Dux session is open, so a base that goes red overnight is reported
when the next session starts. That is accepted: the phone notification is sent by the Dux
session, so with no session there is nobody to send it.

## 3. What red means

The call is `gh run list --repo <slug> --branch <base> --event push --limit 20`. It returns one
row per run, already at that run's latest attempt. The commit judged is the head commit of the
run with the highest run id, which is the newest. Every row with that head commit counts.

| Answer | Rule |
|---|---|
| `red` | A run on that commit has `status` `completed` and `conclusion` `failure`, `timed_out` or `startup_failure`. Red wins even while other runs on the commit are still going |
| `pending` | Not red, and a run on that commit has any `status` other than `completed` |
| `green` | Not red, nothing pending, and at least one run has `conclusion` `success` |
| `none` | Anything else: no push runs at all, or only other conclusions such as `cancelled`, `skipped` or `neutral` |
| no answer | `gh` exited non-zero, ran past the time limit, printed something `jq` cannot read, or sent a field out of shape (section 6) |

Only `red` and `green` change the record. `pending`, `none` and no answer leave it exactly as it
was. So a base last seen red stays red until a green run says otherwise: a GitHub error, a hang,
a cancelled run or a newer commit still running never clears it, and none of them marks a base
red.

A repository whose checks do not run on GitHub Actions has no push runs and stays `none`. The
check says so when run by hand, and the project skill runs it once at registration so the
operator hears it then.

Judging the newest run's commit, and not the branch tip, is deliberate. A later commit that
started no run (a skipped workflow) does not make a broken base look fixed.

**The time limit.** `gh` is started in the background with its output going to a file in a
`mktemp -d` folder under `state/`. The script looks once a second, and after `DUX_BASE_GH_SECS`
(default 60) it stops `gh` and counts the call as no answer. A trap removes the folder and stops
`gh` when the script exits or is told to stop. Bash only; macOS has no `timeout` command.

## 4. Reporting once, and clearing

The report key is `<sha>:<run id>:<attempt>`. The record keeps the last key reported.

On a red answer:

- If the reported key names the judged commit, and that run is still red at that attempt, it is
  the same failure: nothing is written to the event log. This holds across any number of checks,
  watcher restarts and Dux sessions, because the key is on disk. It also holds when a second
  workflow on the same commit fails later.
- Otherwise the new key is the red run with the lowest run id on the judged commit. The event
  is appended, then the key is saved.

So a re-run that fails (a new attempt) and a newer commit that is also red are each reported
once. A re-run that passes makes the answer `green`: the record turns green and the digest stops
showing the base as red. Clearing is silent: no event, no notification. The operator who pressed
re-run and walked away hears only if it failed again; no news is good news.

The event is appended before the key is saved, so a crash or a failed save between the two
repeats the line rather than losing it. A repeated line is caught at the wake: Dux compares
`reported` with `acked` and stops when they match, as it does for a task.

## 5. Formats

Record, `state/base/<project>/record`, written whole through a temporary file and a rename, and
only by `check`:

    verdict=red
    sha=<40 hex>
    run=<digits>
    attempt=<digits>
    reported=<sha>:<run>:<attempt>
    checked=2026-09-18T00:41:07Z

`verdict` is `red` or `green`. `sha`, `run` and `attempt` are those of the run that set it.
Acknowledgement, `state/base/<project>/acked`, one line holding a key, written only by `ack`.
The two writers share no file, so neither can overwrite the other and no lock is needed.

Event line: `<time> base-red: <project>`. It names a project, not a task.

The watcher keeps `state/base.started` (touched at each start) and `state/base.pid` (the check
it started). On its own stop it stops that check.

## 6. What Dux reads and what it says

Five fields are asked for, and no others: `databaseId`, `headSha`, `status`, `conclusion`,
`attempt`. Shapes: `databaseId` and `attempt` are 1 to 20 digits; `headSha` is 40 hex;
`status` and `conclusion` are 0 to 32 characters of `a-z` and `_`. One field out of shape makes
the whole answer "no answer". A word in shape but not named in section 3 is never an error: an
unknown `status` means not finished, an unknown `conclusion` means neither red nor green. A new
word from GitHub therefore cannot silence the check.

Workflow names, commit titles and author names are repository content. They are never
requested, so they are never stored or shown.

The url is built by Dux: `https://github.com/<slug>/actions/runs/<run id>`, where the slug comes
from the registered path through `github_slug`. No url from GitHub's answer is used.

`bin/dux-notify --base <project>` prints the one fixed line, passed through `cap_line`:

    Look, then fix or re-run: <url> (<project> <base> is red)

The url comes first so the 200-character cut can never shorten it. The line is pushed to the
phone. The rule for a `base-red` wake lives in `skills/dux-status`; `AGENTS.md` points at it and
names `base-red` in its push list, without growing past its 150-line cap.

## 7. What the operator does, and what Dux never does

On a red base Dux tells the operator in plain words which project's base failed and gives the
run url. The operator looks at the run, then fixes it, asks Dux for a fix task in the usual way,
or re-runs it on GitHub. Dux never re-runs a workflow, reverts a commit, opens a pull request or
dispatches a fix on its own. `bin/dux-base` makes `gh run list` calls and no other.

## 8. Restarts and several workers

The check reads projects, never tasks, and never touches the ledger, a worktree or a task's
state files. How many workers are running changes nothing. Its only shared file is
`state/events.log`, to which it appends one short line, as the watcher does.

After a restart everything is read from `state/base/`. An event that landed while no Monitor was
armed is listed by `bin/dux-status` under `unacknowledged` until `bin/dux-base ack` records it.
That is the usual path after a night: the first check finishes before the Monitor is armed.

Two checks at once (the timer's and one by hand) can each append the same event line. The cost
is one repeated line, dropped at the wake as a duplicate.

## 9. Options not taken

- The watcher polling the run of each merge commit it knows of: Dux learns of a merge only at
  teardown or at an `--after` start, it would miss a32fe04, and a network call inside the
  watcher's loop can stall supervision of every worker.
- A step in teardown: teardown runs seconds after the merge, when the base run has barely
  started, so it would either block the Dux session for minutes or see `pending` nearly always.
  It also never sees a re-run, a direct push, or a merge whose task is torn down days later.
- A scheduler outside Dux (launchd or cron): a second thing to install, check and remove, and it
  still cannot send the notification without a Dux session.
- A lock around the records: with the acknowledgement in its own file, the only race left costs
  one repeated line.

## 10. Not covered

- Checks that do not run on GitHub Actions.
- A run started by another workflow finishing, such as a deploy that follows the checks. It is
  not a push run, so its failure is not seen.
- A red base does not stop a dispatch or a merge. A worker that branches from a red base may see
  the same failure on its own pull request.
- A flaky failure that a newer green commit replaces before the next check is never reported.
- Nothing is reported while no Dux session is open; it is reported when one opens.
