# Usage: <task id>

<!--
One summary per accepted deliverable, from rollout stage m4, kept beside the rest of its
evidence at data/tasks/<task id>/usage.md. Copy this file there and fill it in. Every count
starts as unknown and stays unknown until a structured record gives a number for it: a
harness's own numeric usage output, or a record Dux wrote. Never a transcript, the tab's
scrollback, a prompt, or a worker's own report. docs/plans/dux-simplification-rollout.md,
tasks 32 to 34, says which harness exposes which count.
-->

- Pull request: <url>
- Merged: <date>
- Filled in by: <who>, on <date>

## Rules

- Unknown is not zero. A count no record gives stays `unknown`, and so does any total that needs it.
- The four counts never overlap. Input leaves out cache reads and cache writes. A harness that
  counts cached tokens inside its input has them taken out before input is written here.
- A session's totals are cumulative. Rounds that ran in one session get that session's last
  total once, never each round's total added together.
- A reviewer that ran inside the worker's own session is already in that session's total. Its
  row says `in session total` instead of numbers.
- A failed or retried attempt counts toward the deliverable it led to. Give it its own row,
  naming the phase it failed in.
- When phases cannot be told apart, write one `Session total` row for the phases it spans and
  set the phase split below to unavailable.
- A phase that did not happen, such as planning for plan-free work or a security review in a
  combined gate, says `not run`.
- Write a total only when every row is a number or `not run` and no two rows count the same
  tokens. Otherwise the total is `unknown`.
- A cost at list price is what the same tokens would cost at list price. It is not how much of
  a subscription allowance was used.

## Counts

| Phase | Task, run and round | Harness and model | Input | Output | Cache read | Cache write | Record |
|---|---|---|---|---|---|---|---|
| Planning | | | unknown | unknown | unknown | unknown | |
| Planning: design review | | | unknown | unknown | unknown | unknown | |
| Implementation | | | unknown | unknown | unknown | unknown | |
| Correctness or combined review | | | unknown | unknown | unknown | unknown | |
| Security review, separate gate | | | unknown | unknown | unknown | unknown | |
| Retry or failed run: <phase it failed in> | | | unknown | unknown | unknown | unknown | |
| Total | | | unknown | unknown | unknown | unknown | |

- Phase split: available | unavailable, because <why>
- Unknown counts: <which, and why no record gives them>
- List-price cost, only where a harness gave one: unknown
