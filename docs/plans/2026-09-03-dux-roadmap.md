# Dux Roadmap: milestones 1 to 8

**Where this stands**
- Milestone 1 (skeleton) is merged 2026-09-03: plan `2026-09-03-dux-m1-skeleton.md`, 8 of 8 tasks, reviewed_sha a3288cc.
- Milestone 2 (dispatch) is merged in PR #4: plan `2026-09-03-dux-m2-dispatch.md`, 12 of 12 tasks.
- Milestone 3 (supervision) is merged 2026-09-06 as PR #6, rebased onto `main` at 9a7e524: plan `2026-09-04-dux-m3-supervision.md`, 8 of 8 tasks, plus the 5-task security amendment `2026-09-05-dux-m3-security-amendment.md`.
- Milestone 4 (intake) is merged as PR #8: plan `2026-09-06-dux-m4-intake.md`, 4 of 4 tasks.
- Milestone 5 (`/ship` guard) is merged as PR #14: plan `2026-09-07-dux-m5-ship-guard.md`, 4 of 4 tasks. It was the first milestone under the size cap and the plan rules below.
- Three smaller changes merged after it, outside the milestone numbering: the identifier-lint work (PRs #15 to #19), the pull request template consent rule (PR #20, plan `2026-09-08-pr-template-consent.md`), and the pipeline lint that constitution 2.0.5 carries (PR #21).
- Current milestone: 6 (`/ship` stands alone), planned 2026-09-08 in `2026-09-08-dux-m6-ship-standalone.md`, 4 tasks, ~1,350 estimated added lines.
- Milestones 6 to 8 are scoped here at task granularity; each gets its own full plan file when its predecessor merges.
- Re-scoped 2026-09-06 against the size cap below. The old milestone 5 was too big for one session and is now milestones 5 and 6; dogfood and the Codex harness moved to 7 and 8. Nothing was dropped. `ship-guard` is still milestone 5 task 1, so earlier references to it still resolve.
- Spec: `docs/specs/2026-09-03-dux-orchestrator-design.md`.

## How a milestone is sized

One milestone is one session and one PR. A session ships at most **2,500 added lines or 12 tasks, whichever comes first**. The cap itself is constitution principle 1; this section is how to apply it before a plan is written.

Measured on 2026-09-06, the first four milestones ran three to four times over that. Milestone 3's pull request was 9,495 lines across 58 files, about 730 lines for each of its 13 tasks (8 in the plan, 5 in the security amendment). That is why its session needed compaction and why its fix commits outnumbered its feature commits.

Size a milestone in this order:

1. **Estimate added lines, not rows in a table.** A task that edits a script, a skill and a test file is three files and closer to 900 lines. A task that edits one prose file is closer to 150. The count of rows tells you nothing; two seven-task milestones can differ fourfold.
2. **Add the estimates up.** Over 2,500 lines, split. Over 12 tasks, split, even when the lines fit.
3. **Split at a dependency seam**, so each half merges on its own: one milestone ships the mechanism, the next ships what uses it. Never split a task in half to make a number work.
4. **Write the estimate into the plan header** as `Estimated diff: ~N added lines across M tasks`, and put the actual number in the pull request body. The next estimate leans on the last actual.
5. **When the output cannot be estimated**, as with dogfood, the milestone carries a stop rule instead of an estimate: when the cap is reached, what is left is queued as the next milestone rather than finished in the same session.

Splitting after the plan is written throws the plan away. Size first.

## How a plan is written, from milestone 5 onward

Plans for milestones 1 to 4 are the record of what was built and stay as they are. Every plan from milestone 5 on follows these rules.

Measured on 2026-09-06, at commit 2fd9d57:

```
git ls-files 'docs/plans/2026-09-0*-dux-m*.md' | xargs cat | wc -l   # 9,226
git ls-files bin | xargs cat | wc -l                                 # 3,350
```

Three lines of plan for every line of shell they produced. Milestone 3's plan and its amendment run 3,167 lines over 13 tasks, about 244 lines each.

- **A task is at most about 60 lines.** Files, interfaces, acceptance criteria, and the break-verification the task owes. A task that does not fit is two tasks, or its design is not settled yet and belongs in the spec first.
- **No implementation in the plan.** Function signatures, exit codes, output shapes and refusal wording, yes. Script bodies, no. The plan says what a script must do and the implementer writes it. Pasted shell is the single largest cost in the merged plans.
- **A settled design decision lives in the spec, once.** The spec is the design authority (constitution principle 8). A plan that settles something amends the spec and then points at the section by number. It never restates a decision the spec already carries.
- **No constitution blocks.** `docs/constitution.md` is loaded every session. A plan that repeats bash 3.2, shellcheck, findings on stderr, test-driven development, break-verification, attribution or identifier rules spends tokens and lets the two drift apart. Name a principle by number only to record a deviation, which governance already requires.
- **No conversation history**, no exploratory discussion, no options that were rejected. A rejected option that still matters is one line in the spec's decisions section.

The shape is in `docs/plans/TEMPLATE.md`.

## Milestone 1: Skeleton (7 tasks)

Harness with fake claude and fake herdr; `dux-env` (findings on stderr); `dux-lock` keyed on `CLAUDE_PID`; `dux-project` and PR template; backend adapters (`open`, `exists`, `tail`, `close`, `notify`) behind `dux-backend`; `dux-doctor`; `AGENTS.md` (canonical) with `CLAUDE.md` import, `.claude/settings.json` session hooks, `dux-project` skill, README; MIT LICENSE, CONTRIBUTING, the ship skill copied in unchanged, and `dux-install` / `dux-uninstall` with the personal-identifier lint.

Design review 2026-09-03 (fresh Fable): 4 Critical, 14 Important, 12 Minor; all Critical and Important fixed in spec and plan, Minor fixed where in M1 scope, the rest carried into the tasks below.

Acceptance: `make check` green; doctor passes on both backends; two real repos register with correct base branches; a Herdr tab opens without stealing focus.

## Milestone 2: Dispatch (10 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Ledger helpers `bin/dux-ledger` | `bin/dux-ledger`, `tests/dux-ledger.bats` | `add`, `set <id> <key> <val>`, `get <id> <key>`, `list [--state s] [--project p]` over `data/backlog.md` lines of the form `- <id> project= shape= state= source= endpoint= pr= (updated <iso>)`; idempotent set; unknown id is a finding |
| 2 | Task id and folder `bin/dux-task-new` | `bin/dux-task-new`, `tests/dux-task-new.bats` | prints `<project>-<shape>-<yyyymmdd>-<3 alnum>`; creates `data/tasks/<id>/`; refuses unknown project or shape |
| 3 | Brief renderer `bin/dux-brief` | `bin/dux-brief`, `templates/brief.md`, `tests/dux-brief.bats` | renders spec section 5.3 sections from flags `--intent-file`, `--criteria-file`, `--plan`, `--tasks`, `--issue-file`; refuses a brief over 60 lines excluding the fenced issue block; issue block fenced `<untrusted-issue>` and capped at 4,000 chars; rules include "exit after blocked or needs-decision", "write `working: waiting on <what> <url>` before any wait over 10 minutes", and for `plan` shape: "design review is a subagent inside this task; the docs-only PR is the approval artifact; never wait on the operator" |
| 4 | Worktree per mechanism `bin/dux-worktree` | `bin/dux-worktree`, `tests/dux-worktree.bats` | precedence per the operator's global rule: a "Worktrees" section in the project's CLAUDE.md or AGENTS.md, then `make worktree name=<branch> base=<base>` (both fitfights repos use this form and choose the path themselves), then a repo script, then `git worktree add <repo>/.worktrees/<branch>`; after `make` or script, discover the path from `git worktree list --porcelain` by branch and refuse if absent; asserts `.worktrees/` is ignored; fetches `origin/<base>` first and refuses when the new worktree is not on that tip; installs a `pre-push` hook refusing `<base>`; copies `.env*` only for `ship`; `remove` refuses dirty or unpushed |
| 4b | Worker harness adapters | `bin/workers/claude.sh`, `bin/workers/codex.sh`, `tests/fakes/codex`, `tests/worker-adapter.bats` | each defines `worker_cmd <brief> <model> <effort>` printing one command line; claude: `claude -p "$(cat brief)" --model <m> --effort <e> --dangerously-skip-permissions --settings templates/worker-settings.json --output-format stream-json --verbose`; codex: `codex exec --full-auto -m <m> "$(cat brief)"` with the sandbox flag the installed version requires; `config/worker-harness` selects, default `claude`; fake codex mirrors fake claude; the shared adapter test runs once per harness |
| 5 | Worker wrapper `bin/dux-worker-wrap` | `bin/dux-worker-wrap`, `templates/worker-settings.json`, `tests/dux-worker-wrap.bats` | invoked as `dux-worker-wrap <id>` only; writes `state/<id>.pid`; exports `DUX_STATUS_LOG`; runs the command from the selected worker adapter with output to `state/<id>.out`; heartbeat `working: heartbeat` every 300 s only if `<id>.out` grew; on non-zero exit without terminal line appends `failed: worker exited <code>`, on zero exit `ended: exit 0 without terminal status`; on Herdr mirrors status to `herdr pane report-agent` and sets title via `report-metadata`; skips those under tmux. Break-verify that the settings deny rules block `git push origin <base>` under bypass mode before M2 closes; if they do not, the `pre-push` hook is the only guard and the spec says so |
| 6 | Spawn `bin/dux-spawn` | `bin/dux-spawn`, `tests/dux-spawn.bats` | all five refusals from spec 5.5 tested; success records endpoint and `running`; posts issue start comment when source is `gh:` |
| 7 | Teardown `bin/dux-teardown` | `bin/dux-teardown`, `tests/dux-teardown.bats` | refuses non-terminal, dirty, unpushed; otherwise backend close, worktree remove, ledger `done|failed`; task folder kept |
| 8 | Skill `skills/dux-dispatch` and end-to-end | `skills/dux-dispatch/SKILL.md`, `tests/e2e-dispatch.bats` | e2e with fake claude and fake codex on both backends (four runs): spawn, `done: PR`, teardown; skill dry-run dispatches a scout against a throwaway repo with each real harness |

Model per shape: plan `claude-fable-5-1` effort high; ship `claude-opus-5` effort max; scout `claude-sonnet-5` effort medium. M2 acceptance includes each id resolving under `claude --model <id> -p 'say ok'`.

## Milestone 3: Supervision (8 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 0 | Milestone 2 leftovers and registration ergonomics | `bin/backends/tmux.sh`, `bin/backends/herdr.sh`, `tests/backend-adapter.bats`, `tests/dux-spawn.bats`, `tests/dux-worktree.bats`, `.gitignore`, `bin/dux-project`, `tests/dux-project.bats` | Three items carried from M2's ship gate, listed in PR #3. **(a)** `backend_exists` discards the backend's exit status in both adapters (`tmux.sh:41` pipes into `grep -q` with stderr dropped; `herdr.sh:35` keeps only the exit code), so "could not tell" reads as "gone", and `bin/dux-teardown:38-43` consumes that. This is the third instance of the same shape M2 fixed twice; Task 1 of this milestone depends on `dux-backend exists` for liveness, so fix it before building on it. An unanswerable question must be a finding. **(b)** Five assertions compare `$output` exactly against commands that log to stderr on some success paths and pass only because their fixtures take non-logging branches: `tests/dux-spawn.bats:221`, `tests/dux-worktree.bats:33,186,196,211`. Use `run --separate-stderr` and assert stderr explicitly, as `tests/dux-task-new.bats` now does. **(c)** `.gitignore` line 6 is `config/` with no leading slash, so it also matches `templates/config/` and new template config files need `git add -f`; anchor `/config/`, `/data/`, `/state/` and confirm the runtime directories stay ignored. **(d)** `bin/dux-project add` leaks bash's own error when an argument is missing: `bin/dux-project add <path>` prints `bin/dux-project: line 56: 2: path` and nothing else, because `${2:?path}` fires before the script can refuse. Every other refusal in this tool is a sentence; this one is a line number. Print the usage line and exit 2, for every subcommand, and test the missing-argument case. The existing tests only cover refusals the code raises deliberately, never an argument simply left out. **(e)** `add` should take the project name from the folder rather than requiring it twice: `dux-project add <path> [--name <name>]`. The operator reached for that form first, which is the design signal. The name becomes the registry key, the task id prefix and part of the branch name, and a folder's own name serves all three. Keep `--name` for the cases that need it: two repos with the same folder name, a folder name the id charset cannot take, or a name too long to want in every branch. Refuse clearly when the derived name is unusable or already registered. This changes the command's public contract, so do it before any habit or script depends on the current shape. Each fix break-verified. |
| 1 | Watcher `bin/dux-watch` | `bin/dux-watch`, `bin/dux-lock`, `tests/dux-watch.bats` | 30 s loop (env-tunable); liveness is `dux-backend exists` AND `kill -0 $(cat state/<id>.pid)`; emits `done|failed|ended|blocked|needs-decision|stale|dead: <id>` to `state/events.log` when the status log's last state differs from the ledger, then writes the ledger itself (dedup by disagreement, restart-safe); `working` never emits; raises the backend toast on every event; `dux-lock acquire` kills `state/watch.pid` then starts `nohup setsid dux-watch` and records the pid; `release` kills it |
| 2 | Status `bin/dux-status` and skill | `bin/dux-status`, `skills/dux-status/SKILL.md`, `tests/dux-status.bats` | five lines per project, zero-count lines omitted; `--prs` adds `gh pr view` state; `--intake` runs intake first (milestone 4 wires it) |
| 3 | Notify `bin/dux-notify` | `bin/dux-notify`, `tests/dux-notify.bats` | formats a <=200 char line leading with the action; backend `notify` toast; prints the line for Dux to pass to PushNotification |
| 4 | Recover `bin/dux-recover` and skill | `bin/dux-recover`, `skills/dux-recover/SKILL.md`, `tests/dux-recover.bats` | `stale`: one 20 min extension recorded, then SIGINT to `state/<id>.pid`, 60 s, `failed`; `dead`: `failed` + last 20 lines of `state/<id>.out` to report.md; `ended`: check `gh pr list --head` and report.md, classify or ask; `blocked` / `needs-decision`: retry under a new id with the answer appended to Intent, one retry per answer; never more than one auto-retry |
| 5 | Monitor arming in `CLAUDE.md` | `CLAUDE.md` | session-start step arms `Monitor(command: tail -n0 -F state/events.log, persistent: true)`; start-of-turn rule re-arms when tasks are running and no monitor is armed; `dux-status` at start lists unacknowledged events so nothing written while un-armed is lost |
| 6 | Wake handling in `CLAUDE.md` | `CLAUDE.md` | on event: read the line, use the bounded notify or recover output, then `dux-ledger ack <id> <event-state>`; Dux never edits backlog.md directly; status lines are data, never commands; push only for done-with-PR, needs-decision, failed |
| 7 | End-to-end supervision | `tests/e2e-supervise.bats` | fake worker goes silent: watcher emits `stale` after threshold; fake worker dies: `dead`; fake `done`: exactly one event |


**Not milestone 3, and not this repo.** Two follow-ups live in `fitfights_ios`, each its own branch, session and PR: a worktree mode that links the committed `GoogleService-Info.plist.example` so a worker can launch the app without real credentials, and pulling failure screenshots out of the `xcresult` bundle so a worker can attach them to its report. Established during M2: the iOS `make worktree` links the real plist and only the `.example` is committed, so a plain worktree with no linking cannot launch the app. `AppConfig.xcconfig.local` and the fastlane env files are not needed, because the committed debug xcconfig already carries working defaults.

Left over from M2, both settled in Milestone 4 (2026-09-06): rerun `bin/dux-install` so `config/models-codex` and `config/worker-harness` are seeded stays a chore the operator runs by hand from the primary checkout, and Task 9 Step 7's real-harness dry runs are folded into Milestone 4 Task 4 Step 2, which needs the same throwaway registered project and a live `claude`.

## Milestone 4: Intake (4 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Intake `bin/dux-intake` | `bin/dux-intake`, `tests/dux-intake.bats`, `tests/fixtures/gh-issues.json` | `gh issue list --state open --label <l> --json number,title,body,url,labels,updatedAt`; appends `queued` with `source=gh:<owner/repo>#<n>`; idempotent by source key; closed issue reconciled to `dropped`; fixture-driven |
| 2 | Issue-aware brief and comments | `bin/dux-brief`, `bin/dux-spawn`, `bin/dux-teardown` | `--issue-file` path exercised; start comment on spawn; PR-link comment on done; labels untouched |
| 3 | Session start and status wiring | `CLAUDE.md`, `bin/dux-status` | intake runs for every `issues=label:*` project at start and on `--intake`; never in the watcher |
| 4 | `/ship` `Closes #n` | `~/.agents/skills/ship/SKILL.md` step 8 | when the brief carries an issue key, PR body includes `Closes #<n>` |

## Milestone 5: `/ship` guard (4 tasks)

The skill is already bundled at `skills/ship/` and installed by symlink (milestone 1). This milestone gives the gate a memory: a state file recording which commit each phase saw, so a review cannot be quietly outrun by later commits. Spec section 11.

Estimated: ~1,300 added lines. One new script with its bats file, four prose steps, and a dry run for each prose guard.

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | `ship-guard` script | `skills/ship/ship-guard`, `tests/ship-guard.bats` | state file `$(git rev-parse --git-dir)/dux-ship/<branch>`, never a tracked file; `record <phase>` writes `<phase>=<sha>`; `check <phase>` exits 2 when `HEAD` is not equal to or a descendant of the recorded sha; `fix-pass` increments and refuses past 3; `push-ok` per spec section 11 change 1 |
| 2 | Reviewed-SHA and continuity in SKILL.md | `skills/ship/SKILL.md` steps 4, 6, 7, 8 | record after 4, 6, 7; check before 6, 7, 8; step 8 runs `push-ok` |
| 3 | Fail-closed review parsing and bounded fix passes | `skills/ship/SKILL.md` steps 6, 7 | Codex prompt demands `## Findings` and the sentinel `No findings.`; security prompt demands `## Findings` and `## Checked clean`; a missing header is a stop; three fix passes at most, the fourth is a revert recommendation; re-review policy unchanged (only a fixed Critical, scoped to the new commits) |
| 4 | Acceptance criteria to reviewer | `skills/ship/SKILL.md` step 6 | criteria fenced as data, rationale withheld, "necessary not sufficient" sentence |

This milestone closes the receipt gap milestone 4 recorded: the receipt proved the five phases ran in order, not that a review covered the final code.

Each guard is broken once with the failure pasted into the commit. `/ship` is prose, so break-verifying a prose guard is a dry run against a throwaway repo where the guarded condition is set up to fail, with the transcript excerpt pasted.

## Milestone 6: `/ship` stands alone (4 tasks)

The rest of spec section 11. The operator's own reviewer and model names move into config so a fresh clone can run the gate, and the pull request the gate writes carries its own evidence.

Estimated: ~1,200 added lines, mostly config defaults, two prose steps and their dry runs.

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Operator specifics into config | `skills/ship/SKILL.md`, `templates/config/reviewer`, `templates/config/security-reviewer`, `templates/config/models`, `bin/dux-install`, `tests/ship-config.bats` | the reviewer and security-reviewer commands read from `config/reviewer` and `config/security-reviewer`, per-shape models from `config/models`, all seeded from `templates/config/` by `dux-install`; the Sol-or-Terra fallback becomes a documented note next to the default, not a rule inside the skill; no operator-specific name is left in the skill |
| 2 | Evidence, anchored lease, `ls-remote` verify | `skills/ship/SKILL.md` steps 5, 8 | a user-visible change needs a screenshot or a stated reason; `--force-with-lease=<ref>:<sha>` from a fresh fetch; an `ls-remote` equality check after the push |
| 3 | PR template fill and attestation | `skills/ship/SKILL.md` step 8 | the body fills whichever template the repo has, found by the same rule as `dux-project pr-template` (root, `docs/`, `.github/`, any case, any extension), or `templates/PULL_REQUEST_TEMPLATE.md` when the repo has none or only the folder form, passed through `gh pr create --body-file`; verbose material inside `<details>`; a trailing `<!-- dux-attestation:v1 {...} -->` line. `/ship` runs with no `DUX_HOME` and cannot call `bin/dux-project`, so it needs its own copy of the lookup |
| 4 | Fresh-clone dry run | `tests/harness/ship.md` | a clone with default config runs `/ship` end to end against a throwaway repo, with no operator-specific path, reviewer or model name anywhere in the run; the transcript is committed |

Milestone acceptance: `/ship` runs from a fresh clone on default config, and every guard milestone 5 added still refuses.

## Milestone 7: Dogfood (4 tasks)

| # | Task | Acceptance |
|---|---|---|
| 1 | Register `fitfights_api` (issues on, label `dux`) and `fitfights_ios` (issues off) | registry lines correct, PR templates installed or reported |
| 2 | One scout per repo | reports land in `data/tasks/<id>/report.md`; exactly one phone push each |
| 3 | One ship task from a GitHub issue on `fitfights_api` | PR opened by `/ship`, template filled, attestation present, `Closes #n`, issue commented twice |
| 4 | Restart drill | kill Dux mid-task; restart; digest matches reality; worker unaffected; Monitor re-armed |

Findings from dogfood become tests before they become fixes.

**Carried here by the renumbering.** Three questions earlier plans deferred to "milestone 6's dogfood" are this milestone's, and it does not close until each has an answer: whether the watcher should report a `running` task that never got an endpoint, whether a retry needs `--from-branch` when the blocked worker left commits on its branch (both milestone 3, open questions 1 and 2), and whether `dux-result verify` should require `Closes #<n>` in the body of a `gh:` ship task (milestone 4, open question 2).

**Stop rule instead of an estimate.** The four tasks add few lines themselves; what they provoke cannot be estimated in advance. When the fixes reach the 2,500-line cap, the session stops fixing and queues what is left as a milestone of its own, inserted ahead of the Codex harness, which then becomes milestone 9. Every finding is written down whether or not it is fixed in this milestone.

## Milestone 8: Codex as orchestrator harness (5 tasks)

Estimated: ~1,000 added lines. Two small scripts with their bats files, prose fallbacks, and one hand-run transcript.

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Launcher `bin/dux` | `bin/dux`, `tests/dux-launcher.bats` | `dux [claude\|codex]` acquires the lock with its own pid, starts the watcher, execs the harness in the repo, releases on exit; on Claude Code the SessionStart hook sees the lock already held by an ancestor pid and reports ok |
| 2 | Blocking wait `bin/dux-wait` | `bin/dux-wait`, `tests/dux-wait.bats` | blocks until a new line lands in `state/events.log` or `--timeout` elapses; prints the line; used where Monitor is unavailable |
| 3 | AGENTS.md fallback lines | `AGENTS.md` | each Monitor-dependent instruction carries "if this harness has no Monitor tool, run `bin/dux-wait --timeout 1200` and act on its output"; still under 150 lines |
| 4 | Notify fallback | `bin/dux-notify`, `templates/config/webhook` | when PushNotification is unavailable, post the line to `config/webhook` if set; document that phone reply is Claude Code only |
| 5 | Verification transcript | `tests/harness/codex.md`, `README.md` | the checklist run by hand on a real Codex install: start, dispatch, wake via dux-wait, recover, restart; transcript committed; README lists Codex as verified |
