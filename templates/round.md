{{feedback}}## Round {{N}} for task {{ID}}: feedback on pull request {{PR}}
{{answer}}## Round {{N}} for task {{ID}}: an answer from the operator
{{approval}}## Round {{N}} for task {{ID}}: approval of {{PLAN}}, tasks {{TASKS}}, at {{COMMIT}}

{{feedback}}The operator has read pull request {{PR}} and sends the feedback below. This is the same task, under the same brief, on the same branch, {{BRANCH}}. Never work on {{BASE}}.
{{answer}}The operator answers what your last terminal line asked or was blocked on. This is the same task, under the same brief, on the same branch, {{BRANCH}}. Never work on {{BASE}}.
{{approval}}The operator approves tasks {{TASKS}} of {{PLAN}} exactly as committed at {{COMMIT}}. This is the same task, under the same brief, on the same branch, {{BRANCH}}. Never work on {{BASE}}.

- Run `git fetch origin` and `git status` before anything else, and start from what {{BRANCH}} holds now.
{{BEHIND}}- `origin/{{BASE}}` has moved past {{BRANCH}}. Merge it in first with an ordinary merge, `git merge origin/{{BASE}}`: this is the one merge this round asks of you. If a conflict needs a choice the operator should make, append `needs-decision: <the choice>` and stop.
{{feedback}}- Make the change as new commits on top. Never rebase, amend a pushed commit, squash or force-push: the operator has read what is there.
{{feedback}}- Run `/ship` again. It updates pull request {{PR}}; never open another.
{{feedback}}- Then append `done: PR {{PR}}` to the file named by `$DUX_STATUS_LOG` and wait at the prompt. This round gets one terminal line, and every other rule in the brief still holds.
{{answer}}- Carry on with the task from where it stopped, using the answer below. An answer approves no plan: work that waits for approval still waits for it.
{{answer}}- End with the terminal line the brief asks for, and wait at the prompt. This round gets one terminal line, and every other rule in the brief still holds.
{{approval}}- Implement tasks {{TASKS}} of {{PLAN}} in order, ticking each box as it lands.
{{approval}}- In {{PLAN}}, only box ticks and the three lines under **Where this stands** may differ from {{COMMIT}}. Any other change to the plan needs `needs-decision:` and a renewed approval.
{{approval}}- Run `/ship`, then append `done: PR <url>` to the file named by `$DUX_STATUS_LOG` and wait at the prompt. This round gets one terminal line, and every other rule in the brief still holds.

{{feedback}}## Feedback (the operator's words)
{{answer}}## Answer (the operator's words)
{{approval}}## Approval (the operator's words)
{{WORDS}}
