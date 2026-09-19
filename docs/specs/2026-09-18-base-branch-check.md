# Dux: telling the operator when a base branch goes red

Date: 2026-09-18. Status: proposed, for approval with its plan,
`docs/plans/2026-09-18-base-branch-check.md`. Amends the living spec,
`2026-09-03-dux-orchestrator-design.md`, sections 6.2, 6.3, 8 and 14, which the plan's Task 1
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
- **When:** on the watcher's first loop after it starts, then every `DUX_BASE_INTERVAL_SECS`
  (default 300; `0` turns it off). Also by hand at any time.
- **How:** one `gh run list` call per project, for push runs on the registered base branch. It
  follows the branch, not a list of merges, so it sees direct pushes and merges made outside Dux,
  and it works the same for a base named `main` or `staging`.

The watcher runs only while a Dux session is open, so a base that goes red overnight is reported
when the next session starts. That is accepted: the phone notification is sent by the Dux
session, so with no session there is nobody to send it.

## 3. What red means

The commit judged is the head commit of the newest push run on the base branch. Every push run
in the answer with that head commit counts, each at its latest attempt.

| Verdict | Rule |
|---|---|
| `red` | A run on that commit has finished with `failure`, `timed_out` or `startup_failure`. Red wins even while other runs on the commit are still going |
| `pending` | Not red, and a run on that commit has not finished |
| `green` | Not red, nothing pending, and at least one run finished with `success` |
| `none` | Anything else: no push runs at all, or only cancelled, skipped or neutral ones |
| no answer | GitHub did not answer, the call ran past `DUX_BASE_GH_SECS` (default 60), or a field was not in the expected shape. The record is left exactly as it was: never red, never cleared |

A cancelled run is not red: the operator, or a newer push, stopped it. A repository whose checks
do not run on GitHub Actions has no push runs and stays `none`; the check says so when run by
hand, and the project skill runs it once at registration so the operator hears it then.

Judging the newest run's commit, and not the branch tip, is deliberate. A later commit that
started no run (a skipped workflow) does not make a broken base look fixed.

## 4. Reporting once, and clearing

The report key is `<sha>:<run id>:<attempt>` of the red run with the lowest run id on the judged
commit. The record keeps the last key reported.

- Red with a key that differs from the last one reported: append the event, then save the key.
- Red with the same key: nothing. The same failure is never reported twice, across any number of
  checks, watcher restarts and Dux sessions, because the key is on disk.
- A re-run that passes: the run's newest attempt is `success`, the verdict becomes `green`, and
  the digest stops showing the base as red. Clearing is silent: no event, no notification.
- A re-run that fails is a new attempt, so a new key, and is reported once. The operator who
  pressed re-run and walked away hears only if it failed again; no news is good news.
- A newer commit that is also red is a new key and is reported once.

The event is appended before the key is saved, so a crash between the two repeats the line
rather than losing it. A repeated line is caught at the wake: Dux compares `reported` with
`acked` and stops when they match, as it does for a task.

## 5. Formats

Record, `state/base/<project>`, written whole through a temporary file and a rename:

    version=1
    base=main
    sha=<40 hex>
    verdict=red
    run=<digits>
    attempt=<digits>
    reported=<sha>:<run>:<attempt>
    acked=-
    checked=2026-09-18T00:41:07Z

A record whose `base` differs from the registry's is thrown away and rebuilt. Event line:
`<time> base-red: <project>`. It names a project, not a task.

Every read-decide-write of a record, the event append, and `ack` happen under one short mutex,
`state/base.lock`, with the rules the ledger's mutex has. The GitHub call happens before the
mutex is taken and before the record is read, so an acknowledgement that lands during a slow
call is never overwritten with an older value.

## 6. What Dux reads and what it says

Only six fields are asked for: `databaseId`, `headSha`, `status`, `conclusion`, `attempt`, and
`createdAt` for order. Each is checked against its shape (digits, 40 hex, a fixed list of words)
before use, and one bad field makes the whole answer "no answer". Workflow names, commit titles
and author names are repository content; they are never requested, stored or shown.

The url is built by Dux: `https://github.com/<slug>/actions/runs/<run id>`, where the slug comes
from the registered path through `github_slug`. No url from GitHub's answer is used.

`bin/dux-notify --base <project>` prints the one fixed line:

    Look, then fix or re-run: <url> (<project> <base> is red)

It is pushed to the phone. `AGENTS.md` gains `base-red` in its push list and its wake rule.

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

## 9. Options not taken

- The watcher polling the run of each merge commit it knows of: Dux learns of a merge only at
  teardown or at an `--after` start, it would miss a32fe04, and a network call inside the
  watcher's loop can stall supervision of every worker.
- A step in teardown: teardown runs seconds after the merge, when the base run has barely
  started, so it would either block the Dux session for minutes or see `pending` nearly always.
  It also never sees a re-run, a direct push, or a merge whose task is torn down days later.
- A scheduler outside Dux (launchd or cron): a second thing to install, check and remove, and it
  still cannot send the notification without a Dux session.

## 10. Not covered

- Checks that do not run on GitHub Actions.
- A red base does not stop a dispatch or a merge. A worker that branches from a red base may see
  the same failure on its own pull request.
- A flaky failure that a newer green commit replaces before the next check is never reported.
- Nothing is reported while no Dux session is open; it is reported when one opens.
