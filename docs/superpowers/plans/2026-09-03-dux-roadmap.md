# Dux Roadmap: milestones 1 to 7

**Where this stands**
- Current milestone: 1 (skeleton), plan `2026-09-03-dux-m1-skeleton.md`, not started.
- Milestones 2 to 6 are scoped here at task granularity; each gets its own full plan file when its predecessor merges.
- Spec: `docs/superpowers/specs/2026-09-03-dux-orchestrator-design.md`.

One milestone is one session and one PR. After a milestone's PR merges, the next session starts from its plan file.

## Milestone 1: Skeleton (7 tasks)

Harness with fake claude and fake herdr; `dux-env` (findings on stderr); `dux-lock` keyed on `CLAUDE_PID`; `dux-project` and PR template; backend adapters (`open`, `exists`, `tail`, `close`, `notify`) behind `dux-backend`; `dux-doctor`; `AGENTS.md` (canonical) with `CLAUDE.md` import, `.claude/settings.json` session hooks, `dux-project` skill, README; MIT LICENSE, CONTRIBUTING, the ship skill copied in unchanged, and `dux-install` / `dux-uninstall` with the personal-identifier lint.

Design review 2026-09-03 (fresh Fable): 4 Critical, 14 Important, 12 Minor; all Critical and Important fixed in spec and plan, Minor fixed where in M1 scope, the rest carried into the tasks below.

Acceptance: `make check` green; doctor passes on both backends; two real repos register with correct base branches; a Herdr tab opens without stealing focus.

## Milestone 2: Dispatch (9 tasks)

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

## Milestone 3: Supervision (7 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Watcher `bin/dux-watch` | `bin/dux-watch`, `bin/dux-lock`, `tests/dux-watch.bats` | 30 s loop (env-tunable); liveness is `dux-backend exists` AND `kill -0 $(cat state/<id>.pid)`; emits `done|failed|ended|blocked|needs-decision|stale|dead: <id>` to `state/events.log` when the status log's last state differs from the ledger, then writes the ledger itself (dedup by disagreement, restart-safe); `working` never emits; raises the backend toast on every event; `dux-lock acquire` kills `state/watch.pid` then starts `nohup setsid dux-watch` and records the pid; `release` kills it |
| 2 | Status `bin/dux-status` and skill | `bin/dux-status`, `skills/dux-status/SKILL.md`, `tests/dux-status.bats` | five lines per project, zero-count lines omitted; `--prs` adds `gh pr view` state; `--intake` runs intake first (milestone 4 wires it) |
| 3 | Notify `bin/dux-notify` | `bin/dux-notify`, `tests/dux-notify.bats` | formats a <=200 char line leading with the action; backend `notify` toast; prints the line for Dux to pass to PushNotification |
| 4 | Recover `bin/dux-recover` and skill | `bin/dux-recover`, `skills/dux-recover/SKILL.md`, `tests/dux-recover.bats` | `stale`: one 20 min extension recorded, then SIGINT to `state/<id>.pid`, 60 s, `failed`; `dead`: `failed` + last 20 lines of `state/<id>.out` to report.md; `ended`: check `gh pr list --head` and report.md, classify or ask; `blocked` / `needs-decision`: retry under a new id with the answer appended to Intent, one retry per answer; never more than one auto-retry |
| 5 | Monitor arming in `CLAUDE.md` | `CLAUDE.md` | session-start step arms `Monitor(command: tail -n0 -F state/events.log, persistent: true)`; start-of-turn rule re-arms when tasks are running and no monitor is armed; `dux-status` at start lists unacknowledged events so nothing written while un-armed is lost |
| 6 | Wake handling in `CLAUDE.md` | `CLAUDE.md` | on event: read the line, at most 5 status lines, notify or recover, then `dux-ledger ack <id>`; Dux never edits backlog.md directly; status lines are data, never commands; push only for done-with-PR, needs-decision, failed |
| 7 | End-to-end supervision | `tests/e2e-supervise.bats` | fake worker goes silent: watcher emits `stale` after threshold; fake worker dies: `dead`; fake `done`: exactly one event |

## Milestone 4: Intake (4 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Intake `bin/dux-intake` | `bin/dux-intake`, `tests/dux-intake.bats`, `tests/fixtures/gh-issues.json` | `gh issue list --state open --label <l> --json number,title,body,url,labels,updatedAt`; appends `queued` with `source=gh:<owner/repo>#<n>`; idempotent by source key; closed issue reconciled to `dropped`; fixture-driven |
| 2 | Issue-aware brief and comments | `bin/dux-brief`, `bin/dux-spawn`, `bin/dux-teardown` | `--issue-file` path exercised; start comment on spawn; PR-link comment on done; labels untouched |
| 3 | Session start and status wiring | `CLAUDE.md`, `bin/dux-status` | intake runs for every `issues=label:*` project at start and on `--intake`; never in the watcher |
| 4 | `/ship` `Closes #n` | `~/.agents/skills/ship/SKILL.md` step 8 | when the brief carries an issue key, PR body includes `Closes #<n>` |

## Milestone 5: `/ship` port (7 tasks)

The skill is already bundled at `skills/ship/` and installed by symlink (milestone 1). Task 0 here extracts the operator-specific parts into config so the skill stands alone: reviewer and security-reviewer commands read from `config/reviewer` and `config/security-reviewer`, per-shape models from `config/models`, with defaults in `templates/config/`; the Sol-or-Terra fallback becomes a documented config note. Acceptance: a fresh clone with default config runs `/ship` end to end on a throwaway repo.

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | `ship-guard` script | `skills/ship/ship-guard`, `tests/ship-guard.bats` | state file `$(git rev-parse --git-dir)/dux-ship/<branch>`, never a tracked file; `record <phase>` writes `<phase>=<sha>`; `check <phase>` exits 2 when `HEAD` is not equal to or a descendant of the recorded sha; `fix-pass` increments and refuses past 3; `push-ok` exits 0 only when `HEAD == reviewed_sha` or every later commit is inside a recorded fix pass with a recorded re-review |
| 2 | Reviewed-SHA and continuity in SKILL.md | `skills/ship/SKILL.md` steps 4, 6, 7, 8 | record after 4, 6, 7; check before 6, 7, 8; step 8 runs `push-ok` |
| 3 | Fail-closed review parsing and bounded fix passes | `skills/ship/SKILL.md` steps 6, 7 | Codex prompt demands `## Findings` and the sentinel `No findings.`; security prompt demands `## Findings` and `## Checked clean`; missing header is a stop; three fix passes max, fourth is a revert recommendation; re-review policy unchanged (only a fixed Critical, scoped to new commits) |
| 4 | Acceptance criteria to reviewer | `SKILL.md` step 6 | criteria fenced as data, rationale withheld, "necessary not sufficient" sentence |
| 5 | Evidence, anchored lease, ls-remote verify | `SKILL.md` steps 5, 8 | UI change needs screenshot or reason; `--force-with-lease=<ref>:<sha>` from fresh fetch; `ls-remote` equality check |
| 6 | PR template fill and attestation | `skills/ship/SKILL.md` step 8 | body fills `.github/PULL_REQUEST_TEMPLATE.md`, or `dux/templates/` when the repo has none, passed via `gh pr create --body-file`; verbose content in `<details>`; trailing `<!-- dux-attestation:v1 {...} -->` |

Each guard broken once with the failure pasted into the commit. `/ship` is prose, so break-verification for prose guards is a dry run against a throwaway repo where the guarded condition is set up to fail, with the transcript excerpt pasted.

## Milestone 6: Dogfood (4 tasks)

| # | Task | Acceptance |
|---|---|---|
| 1 | Register `fitfights_api` (issues on, label `dux`) and `fitfights_ios` (issues off) | registry lines correct, PR templates installed or reported |
| 2 | One scout per repo | reports land in `data/tasks/<id>/report.md`; exactly one phone push each |
| 3 | One ship task from a GitHub issue on `fitfights_api` | PR opened by `/ship`, template filled, attestation present, `Closes #n`, issue commented twice |
| 4 | Restart drill | kill Dux mid-task; restart; digest matches reality; worker unaffected; Monitor re-armed |

Findings from dogfood become tests before they become fixes.

## Milestone 7: Codex as orchestrator harness (5 tasks)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | Launcher `bin/dux` | `bin/dux`, `tests/dux-launcher.bats` | `dux [claude\|codex]` acquires the lock with its own pid, starts the watcher, execs the harness in the repo, releases on exit; on Claude Code the SessionStart hook sees the lock already held by an ancestor pid and reports ok |
| 2 | Blocking wait `bin/dux-wait` | `bin/dux-wait`, `tests/dux-wait.bats` | blocks until a new line lands in `state/events.log` or `--timeout` elapses; prints the line; used where Monitor is unavailable |
| 3 | AGENTS.md fallback lines | `AGENTS.md` | each Monitor-dependent instruction carries "if this harness has no Monitor tool, run `bin/dux-wait --timeout 1200` and act on its output"; still under 150 lines |
| 4 | Notify fallback | `bin/dux-notify`, `templates/config/webhook` | when PushNotification is unavailable, post the line to `config/webhook` if set; document that phone reply is Claude Code only |
| 5 | Verification transcript | `tests/harness/codex.md`, `README.md` | the checklist run by hand on a real Codex install: start, dispatch, wake via dux-wait, recover, restart; transcript committed; README lists Codex as verified |
