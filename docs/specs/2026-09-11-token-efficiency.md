# Dux focused token efficiency

Status: rewritten after one independent design review and an operator-requested scope review;
awaiting operator approval. This document changes no running system.

## 1. Outcome and boundary

Finish more work within the existing Claude subscription without weakening delivery. The measured
problem was several long Fable and Opus workers consuming the same allowance while repeatedly
processing growing contexts. Dux therefore makes fewer planning calls, sends bounded work to
Sonnet, and permits only one Dux-managed Claude worker at a time.

Builds, tests, failure-state exercises, independent Codex correctness review, a separate security
pass, `/ship`, CI and operator-only merge remain. Dux still treats local workers as trusted with
the operator's authority and validates everything they report. It does not observe Claude sessions
started outside Dux or on other devices.

The implementation is one milestone under 2,500 added lines. The prior TE1 through TE9 program is
replaced, not postponed as nine future milestones.

## 2. Decide whether work needs a plan

Dux makes this decision in `AGENTS.md` and applies it through `skills/dux-dispatch/SKILL.md`;
no script parses intent prose and no classifier model is called.

An explicit operator request for a plan always wins. Otherwise a plan is required when any of
these is true:

- a public interface or contract changes;
- stored data needs a schema change, migration or backfill;
- a security or trust boundary changes;
- concurrency or cross-system ordering changes;
- a design choice remains unresolved; or
- implementation needs more than three commit-sized steps.

When none applies, Dux may create a bounded `ship` task with no plan and no design review. This is
the intended route for a PR 37-style asset replacement plus a short README edit. It is still a
code-bearing change because the asset is not human-readable prose, so `/ship` and CI still run.
The existing docs-only exception remains limited to changes where every touched file is prose
that only a human reads.

## 3. Store risk and prove plan-free shipping

No new task shape is added. `dux-brief` accepts `--risk bounded|complex` only for `ship`; omission
means `complex`. It validates before writing and atomically publishes
`data/tasks/<id>/risk` with mode 600.

`plan` and `tasks` form a pair. Both present means planned shipping. Both absent means plan-free
shipping and is accepted only with `risk=bounded`. Either field present alone is a finding.
`templates/brief.md` renders risk and omits the two plan lines for the empty pair.

For `ship`, `dux-worker-wrap` reads the risk file and selects the matching configured entry:

- `bounded=claude-sonnet-5:medium`
- `complex=claude-opus-5:max`

`plan=claude-fable-5-1:high` and `scout=claude-sonnet-5:medium` stay unchanged. A legacy ship task
without a risk file is complex. `dux-install` adds missing bounded and complex entries to an
existing model file without changing any existing entry. Invalid or missing required values are
findings, never silent fallbacks.

`dux-result` treats the empty pair as authorization to skip only plan-path and checkbox proof.
The same branch, implementation-file, five-phase `/ship` receipt, reviewed-commit and green-CI
proof applies. A planned task follows the current box proof unchanged.

The current new-task retry copies risk. Creation belongs to `dux-brief`; teardown removes risk
with the task directory. No other lifecycle operation maintains it.

## 4. Permit one Dux-managed worker

Before creating a worktree or changing task state, `dux-spawn` examines every other registered
task using the pid and backend liveness evidence Dux already maintains. A live worker blocks the
new start. Unreadable, invalid or contradictory evidence also blocks because Dux cannot prove the
slot is free. An old run record alone is not liveness evidence.

The refusal names both tasks, exits 2 and leaves the requested task queued with no worktree. After
the active worker stops or is recovered, the operator reruns the same `dux-spawn` command.

There is no scheduler, capacity queue, reservation, allowance threshold, timer, automatic retry,
foreign-process scan or account-wide capacity claim.

## 5. Use Sonnet for the operator

Implement the already reviewed
`docs/plans/2026-09-11-orchestrator-session-defaults-to-sonnet.md` inside the focused milestone.
The committed `.claude/settings.json` sets `model` to `claude-sonnet-5` for a Dux operator session.
An ignored `.claude/settings.local.json` or an explicit command-line model remains the operator's
override. Workers keep their explicit Task 1 model selection.

## 6. Remove unused worker surfaces

The Claude adapter keeps current settings, project instructions, installed skills, hooks,
permissions and `/ship`. It adds only these installed-CLI controls:

- tools exactly `Bash,Read,Glob,Grep,Write,Edit`;
- `--strict-mcp-config` with a tracked empty MCP configuration; and
- `--no-chrome`.

It does not use safe mode or settings-source isolation. Those would remove inputs Dux still needs
and would require a larger profile-building system.

Before editing the adapter, the implementer qualifies the exact flags against the installed
Claude CLI in a throwaway project. Subscription authentication, project instructions, hooks and
`/ship` must still work. A failure blocks this task and the milestone; it does not cause a silent
fallback or a broader profile subsystem.

## 7. Move automatic security review to Codex

The current correctness review already uses fresh, read-only Codex `gpt-5.6-sol`. Before changing
automatic security selection, the implementer adds a small non-executed vulnerable fixture with
reachable shell injection and path traversal, a clean counterpart, and an expected report. One
fresh Sol run must find every planted Important or Critical issue with file, line, attacker,
input and gain, and must invent no Important or Critical issue in the clean fixture.

If Sol returns HTTP 400, run the same qualification once with `gpt-5.6-terra` and record that the
fallback ran. Another error, a miss or a false Important/Critical finding stops for operator
direction. Qualification evidence lives in the task's commit body; Dux gains no qualification
command, expiry record, token accounting or per-ship probe.

After qualification, explicit `config/security-reviewer` remains authoritative. Automatic
selection requires Codex and returns the existing fresh, read-only Sol command. A host without
Codex stops with a finding. `/ship` retries a Sol HTTP 400 once with Terra and tells the operator
which reviewer ran. It never falls back automatically to Claude. No other `/ship` step changes.

## 8. Deferred work and evidence threshold

Do not implement token or cost capture, usage records, accounting, reports, benchmarks,
allowance-aware admission, automatic queueing, rate-limit pause/resume, operator accounting,
checkpoint pipelines, plan-page rendering, safe-mode profiles, mechanical `/ship` helpers or
automated security requalification.

After five to ten representative tasks, inspect the existing Claude stream JSON manually. If the
focused changes still exhaust allowance, plan the smallest cause that remains. Reconsider the
ship rewrite only if `/ship` dominates those observed runs. A hypothetical edge case or an
unmeasured saving does not reopen the deferred program.

## 9. Supersession

The pending M7 through M9 and TE1 through TE9 execution plans are not additional work. Their
same-session resume, checkpoint, plan-page, usage, scheduler and benchmark systems remain
unimplemented and unscheduled. The small plan-free rule is owned by this design. The Sonnet
operator decision is retained and absorbed as Task 3 of the focused milestone.

The original orchestrator design remains authoritative for security, evidence, lifecycle and
delivery behavior not changed above.
