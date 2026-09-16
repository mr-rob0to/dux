## Round {{N}} for task {{ID}}: feedback on pull request {{PR}}

The operator has read pull request {{PR}} and sends the feedback below. This is the same task, under the same brief, on the same branch, {{BRANCH}}. Never work on {{BASE}}.

- Run `git fetch origin` and `git status` before anything else, and start from what {{BRANCH}} holds now.
{{BEHIND}}- `origin/{{BASE}}` has moved past {{BRANCH}}. Merge it in first with an ordinary merge, `git merge origin/{{BASE}}`: this is the one merge this round asks of you. If a conflict needs a choice the operator should make, append `needs-decision: <the choice>` and stop.
- Make the change as new commits on top. Never rebase, amend a pushed commit, squash or force-push: the operator has read what is there.
- Run `/ship` again. It updates pull request {{PR}}; never open another.
- Then append `done: PR {{PR}}` to the file named by `$DUX_STATUS_LOG` and wait at the prompt. This round gets one terminal line, and every other rule in the brief still holds.

## Feedback (the operator's words)
{{FEEDBACK}}
