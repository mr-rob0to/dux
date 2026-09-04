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

## Rules
- Work alone. Never address the operator; nobody reads your terminal.
- Stay inside the worktree above. Never push to `{{BASE}}`. Never merge. Never `--no-verify`, never change `core.hooksPath`, never touch the forge's refs API.
- Report only by appending one line to `{{STATUS_LOG}}`: `<state>: <one line>`, state one of working, needs-decision, blocked, done, failed.
- Write `working: waiting on <what> <url>` before any wait you expect to exceed 10 minutes.
- The same obstacle twice means `blocked: <what, tried what>`, then stop.
- After writing `blocked` or `needs-decision`, exit. An answer arrives as a new task with the answer appended to Intent.
{{SHAPE_RULES}}

## Definition of done
{{DONE}}
{{ISSUE_BLOCK}}
