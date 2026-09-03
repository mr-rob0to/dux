# Dux Roadmap: milestones 1 to 6

**Where this stands**
- Current milestone: 1 (skeleton), plan `2026-09-03-dux-m1-skeleton.md`, not started.
- Milestones 2 to 6 are scoped here at task granularity; each gets its own full plan file when its predecessor merges.
- Spec: `docs/superpowers/specs/2026-09-03-dux-orchestrator-design.md`.

One milestone is one session and one PR. After a milestone's PR merges, the next session starts from its plan file.

## Milestone 1: Skeleton (7 tasks)

Harness with fake claude and fake herdr; `dux-env`; `dux-lock`; `dux-project` and PR template; backend adapters behind `dux-backend`; `dux-doctor`; `CLAUDE.md`, `dux-project` skill, README.

Acceptance: `make check` green; doctor passes on both backends; two real repos register with correct base branches; a Herdr tab opens without stealing focus.

## Milestone 2: Dispatch (8 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Ledger helpers `bin/dux-ledger` | `bin/dux-ledger`, `tests/dux-ledger.bats` | `add`, `set <id> <key> <val>`, `get <id> <key>`, `list [--state s] [--project p]` over `data/backlog.md` lines of the form `- <id> project= shape= state= source= endpoint= pr= (updated <iso>)`; idempotent set; unknown id is a finding |
| 2 | Task id and folder `bin/dux-task-new` | `bin/dux-task-new`, `tests/dux-task-new.bats` | prints `<project>-<shape>-<yyyymmdd>-<3 alnum>`; creates `data/tasks/<id>/`; refuses unknown project or shape |
| 3 | Brief renderer `bin/dux-brief` | `bin/dux-brief`, `templates/brief.md`, `tests/dux-brief.bats` | renders spec section 5.3 sections from flags `--intent-file`, `--criteria-file`, `--plan`, `--tasks`, `--issue-file`; refuses a brief over 60 lines excluding the fenced issue block; issue block fenced `<untrusted-issue>` and capped at 4,000 chars with `<\|`, `\|>`, `<system>`, `[INST]` stripped |
| 4 | Worktree per mechanism `bin/dux-worktree` | `bin/dux-worktree`, `tests/dux-worktree.bats` | `create <project> <branch>` uses `make worktree`, a repo script, or `git worktree add <repo>/.worktrees/<branch>`; asserts `.worktrees/` is ignored; fetches `origin/<base>` first and refuses when the new worktree is not on that tip; `remove` refuses dirty or unpushed |
| 5 | Worker wrapper `bin/dux-worker-wrap` | `bin/dux-worker-wrap`, `tests/dux-worker-wrap.bats` | exports `DUX_STATUS_LOG`; runs `claude -p "$(cat brief.md)" --model <m> --effort <e> --dangerously-skip-permissions --output-format stream-json --verbose > state/<id>.out`; heartbeat `working: heartbeat` every 300 s; on exit without terminal line appends `failed: worker exited <code>`; on Herdr, mirrors each status line to `herdr pane report-agent` and sets title via `report-metadata`; skips those under tmux |
| 6 | Spawn `bin/dux-spawn` | `bin/dux-spawn`, `tests/dux-spawn.bats` | all five refusals from spec 5.5 tested; success records endpoint and `running`; posts issue start comment when source is `gh:` |
| 7 | Teardown `bin/dux-teardown` | `bin/dux-teardown`, `tests/dux-teardown.bats` | refuses non-terminal, dirty, unpushed; otherwise backend close, worktree remove, ledger `done|failed`; task folder kept |
| 8 | Skill `skills/dux-dispatch` and end-to-end | `skills/dux-dispatch/SKILL.md`, `tests/e2e-dispatch.bats` | e2e with fake claude on both backends: spawn, `done: PR`, teardown; skill dry-run dispatches a scout against a throwaway repo |

Model per shape: plan `claude-fable-5-1` effort high; ship `claude-opus-5` effort max; scout `claude-sonnet-5` effort medium.

## Milestone 3: Supervision (7 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Watcher `bin/dux-watch` | `bin/dux-watch`, `tests/dux-watch.bats` | 30 s loop (env-tunable); emits `done|failed|blocked|needs-decision|stale|dead: <id>` once per (id,state) to `state/events.log`; `working` never emits; started by `dux-lock acquire`, killed on release |
| 2 | Status `bin/dux-status` and skill | `bin/dux-status`, `skills/dux-status/SKILL.md`, `tests/dux-status.bats` | five lines per project, zero-count lines omitted; `--prs` adds `gh pr view` state; `--intake` runs intake first (milestone 4 wires it) |
| 3 | Notify `bin/dux-notify` | `bin/dux-notify`, `tests/dux-notify.bats` | formats a <=200 char line leading with the action; backend `notify` toast; prints the line for Dux to pass to PushNotification |
| 4 | Recover `bin/dux-recover` and skill | `bin/dux-recover`, `skills/dux-recover/SKILL.md`, `tests/dux-recover.bats` | `stale`: one 20 min extension recorded, then SIGINT, 60 s, `failed`; `dead`: `failed` + last 20 lines to report.md; `blocked`: writes operator answer to `inbox.md` or retries with answer appended; never more than one auto-retry |
| 5 | Monitor arming in `CLAUDE.md` | `CLAUDE.md` | session-start step arms `Monitor(command: tail -n0 -F state/events.log, persistent: true)`; start-of-turn rule re-arms when tasks are running and no monitor is armed |
| 6 | Wake handling in `CLAUDE.md` | `CLAUDE.md` | on event: read the line, at most 5 status lines, update ledger, notify or recover; push only for done-with-PR, needs-decision, failed |
| 7 | End-to-end supervision | `tests/e2e-supervise.bats` | fake worker goes silent: watcher emits `stale` after threshold; fake worker dies: `dead`; fake `done`: exactly one event |

## Milestone 4: Intake (4 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Intake `bin/dux-intake` | `bin/dux-intake`, `tests/dux-intake.bats`, `tests/fixtures/gh-issues.json` | `gh issue list --state open --label <l> --json number,title,body,url,labels,updatedAt`; appends `queued` with `source=gh:<owner/repo>#<n>`; idempotent by source key; closed issue reconciled to `dropped`; fixture-driven |
| 2 | Issue-aware brief and comments | `bin/dux-brief`, `bin/dux-spawn`, `bin/dux-teardown` | `--issue-file` path exercised; start comment on spawn; PR-link comment on done; labels untouched |
| 3 | Session start and status wiring | `CLAUDE.md`, `bin/dux-status` | intake runs for every `issues=label:*` project at start and on `--intake`; never in the watcher |
| 4 | `/ship` `Closes #n` | `~/.agents/skills/ship/SKILL.md` step 8 | when the brief carries an issue key, PR body includes `Closes #<n>` |

## Milestone 5: `/ship` port (6 tasks)

All in `~/.agents/skills/ship/` (symlinked from `~/.claude/skills/ship`).

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | `ship-guard` script | `ship-guard`, `tests/ship-guard.bats` | `record <phase>` writes `<phase>=<sha>` into the plan file's "where this stands" block; `check <phase>` exits 2 with a finding when `HEAD` is not equal to or a descendant of the recorded sha; `rounds <n>` increments and refuses past 3 |
| 2 | Reviewed-SHA and continuity in SKILL.md | `SKILL.md` steps 4, 6, 7, 8 | record after 4, 6, 7; check before 6, 7, 8; push refuses when `HEAD` does not descend from `reviewed_sha` |
| 3 | Fail-closed review parsing and bounded rounds | `SKILL.md` steps 6, 7 | missing findings section is a stop; three rounds max, fourth is a revert recommendation |
| 4 | Acceptance criteria to reviewer | `SKILL.md` step 6 | criteria fenced as data, rationale withheld, "necessary not sufficient" sentence |
| 5 | Evidence, anchored lease, ls-remote verify | `SKILL.md` steps 5, 8 | UI change needs screenshot or reason; `--force-with-lease=<ref>:<sha>` from fresh fetch; `ls-remote` equality check |
| 6 | PR template fill and attestation | `SKILL.md` step 8 | body fills `.github/PULL_REQUEST_TEMPLATE.md`; verbose content in `<details>`; trailing `<!-- dux-attestation:v1 {...} -->` |

Each guard broken once with the failure pasted into the commit. `/ship` is prose, so break-verification for prose guards is a dry run against a throwaway repo where the guarded condition is set up to fail, with the transcript excerpt pasted.

## Milestone 6: Dogfood (4 tasks)

| # | Task | Acceptance |
|---|---|---|
| 1 | Register `fitfights_api` (issues on, label `dux`) and `fitfights_ios` (issues off) | registry lines correct, PR templates installed or reported |
| 2 | One scout per repo | reports land in `data/tasks/<id>/report.md`; exactly one phone push each |
| 3 | One ship task from a GitHub issue on `fitfights_api` | PR opened by `/ship`, template filled, attestation present, `Closes #n`, issue commented twice |
| 4 | Restart drill | kill Dux mid-task; restart; digest matches reality; worker unaffected; Monitor re-armed |

Findings from dogfood become tests before they become fixes.
