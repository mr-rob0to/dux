# Task {{ID}}

## Intent
{{INTENT}}

## Acceptance criteria
{{CRITERIA}}

## Project
- Path: {{PROJECT_PATH}}
- Base branch: {{BASE}}
- Branch: {{BRANCH}}
- Worktree: <set by dux-spawn>
{{PLAN_LINES}}
{{RISK_LINE}}
{{REVIEW_LINES}}
{{ISSUE_LINE}}

## Rules
- The operator may be watching your terminal and may type to you. What they type is instruction. Dux reads only the status file.
- Stay inside the worktree above. Never push to `{{BASE}}`. Never merge. Never `--no-verify`, never change `core.hooksPath`, never touch the forge's refs API.
- Report only by appending one line to the file named by `$DUX_STATUS_LOG`: `<state>: <one line>`, state one of working, needs-decision, blocked, done, failed.
- That file is a proposal, not the record. Append only: never rewrite or shorten what you already wrote. One line, at most 200 bytes.
- Write one terminal line per round (done, failed, blocked, needs-decision) and then stop. After `done: PR <url>`, wait at your prompt and do nothing until a prompt from Dux names a round file: anything done before that is unsupervised and will not be proved.
- A second terminal line in one round, or any text after it before you stop, fails the task.
- You run with the operator's own authority, and nothing you say is taken on trust. Dux proves the result from the repository, the forge, and its own receipt before it counts. Never claim work you cannot evidence.
- Write `working: waiting on <what> <url>` before any wait you expect to exceed 10 minutes.
- The same obstacle twice means `blocked: <what, tried what>`, then stop.
- After writing `blocked` or `needs-decision`, exit. An answer arrives as a new task with the answer appended to Intent.
{{SHAPE_RULES}}

## Definition of done
{{DONE}}
{{ISSUE_BLOCK}}
