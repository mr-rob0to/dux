# Dux Milestone 9: The plan as a page, and the rule for when a plan is warranted

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Drafted 2026-09-10, design-reviewed (the records are at the end of the milestone 7
  plan; findings 10, 11 and 16 shaped this one), awaiting the operator. This was
  milestone 8 in pull request #26; `--fresh` moved out of it to milestone 7 and it
  moved behind the plan-ready milestone.
- Follows milestone 8 (`2026-09-10-dux-m8-plan-ready-and-implement.md`), which lands
  `plan-ready` and `state/<id>.plan`, and milestone 7, which lands the resume path.
  Tasks 4 to 6 depend on neither.
- When this merges, a ready plan opens as a page in the operator's browser, the
  dispatch skill applies a written rule for when a plan is warranted, a small change
  ships as a `ship` task with no plan, and the whole loop has an end-to-end test.

**Estimated diff:** ~1,500 added lines across 7 tasks. The cap is 2,500 lines or 12 tasks
(constitution principle 1). Sizing procedure: roadmap, "How a milestone is sized".

**Goal:** The operator reads a milestone-sized plan as a page with its shape visible,
not as a diff, and never sees a plan for a change too small to need one.

**Spec:** `docs/specs/2026-09-10-one-session-planning.md` sections 6, 10, 11, 12.

## Design

- **Renderer:** one awk program inside `bin/dux-plan-page`, fed the cleaned, escaped
  markdown one line at a time, emitting HTML. Block state is a small set of flags (in a
  fence, in a list at depth d, in a table, in a quote, in a task section). Inline
  markup (code, bold, italic, links, images) is a second pass over each text line, after
  escaping, and never spans lines. Unknown constructs are paragraphs.
- **Template:** the head (meta, CSP, style) and the frame (title, callout, panels) are
  fixed strings in the script. No template file: the page has one owner and one reader.
- **Order:** Task 1 and 2 are the page; 3 wires it; 4 and 5 are the rule and what it
  dispatches; 6 is the documentation; 7 is the end-to-end test of the loop milestones 7
  and 8 built. Tasks 4 to 6 can land before milestone 8 merges.

## Task 1: The renderer

**Files:** `bin/dux-plan-page`, `tests/dux-plan-page.bats`, `tests/fixtures/plan-page/*.md`.

**Interface:** `dux-plan-page --render <markdown-file>` writes HTML to stdout, for tests
and for the wired command in Task 3. Input over 512 KiB is the finding `the plan is N
bytes; the cap is 512 KiB`. Each line is stripped of control characters, then of Unicode
format characters, then cut at 1,000 characters with ` [cut]`, then HTML-escaped
(`& < > "`), then rendered. Rendered: ATX headings 1 to 6; paragraphs; `-`, `*`, `+`
and `1.` lists to two levels by two-space or tab indent; `- [ ]` and `- [x]` as
`☐` and `☑` glyphs; fenced code (three or more backticks or tildes, closed by the same
marker) as `<pre>`; inline code; `**bold**`; `*italic*`; pipe tables with a header
rule; `---` rules. A `>` quote is a paragraph. `[text](url)` becomes `text [url]` and
`![alt](url)` becomes `[image: alt]`, both as text. Raw HTML stays escaped text.

**Acceptance:** fixtures for each construct with the exact expected HTML; a fixture with
`<script>`, an `<img>`, a `javascript:` link, a right-to-left override and a 1,200
character line, asserting the escaped text, the marker, and that the output contains no
`<script`, `<img`, `<a ` or `href`; an oversize file refuses without reading it into
memory (test with a 600 KiB fixture built in `setup`).

**Steps**

- [ ] Cleaning and escaping pipeline; the cap.
- [ ] Block elements; inline elements; the link and image rewrites.
- [ ] Break-verify: remove the `<` escape, confirm the script fixture test fails; restore.
      Remove the format-character strip, confirm the override fixture test fails; restore.
      Paste both.

## Task 2: The page frame and its lockdown

**Files:** `bin/dux-plan-page`, `tests/dux-plan-page.bats`.

**Interface:** `--render` wraps the body in the frame: `<!doctype html>`, `lang="en"`,
charset, viewport, `<meta http-equiv="Content-Security-Policy" content="default-src
'none'; style-src 'unsafe-inline'">`, `source-sha256` (of the markdown bytes as read)
and `source-commit` (from `--commit <sha>`, or `-` under `--render`), a `<title>` from the
first H1 (escaped) or the file name, and one `<style>` block. A "Where this stands"
section (a heading or a bold line with those words) renders as a callout under the
title. Each `## Task N` section is a `<details>` with the heading as its summary, open
when there are six or fewer tasks. Sections whose heading starts with `Risks`, `Open
questions` or `Design review` render inside a tinted panel. The page uses the system
font stack and the colour variables the hand-written page in `docs/plans/` uses, in
light and dark schemes.

**Acceptance:** a seven-task fixture renders seven closed `<details>`; a six-task
fixture renders them open; the CSP meta and both source metas are present exactly once;
the title is the H1 text; the output has no `<script`, `<link`, `<iframe`, `<form` or
`on[a-z]*=` anywhere, asserted with one regex over the whole output for every fixture.

**Steps**

- [ ] Head and metas; the style block.
- [ ] Callout, task folding, panels.
- [ ] Break-verify: drop the CSP meta, confirm its test fails; restore. Emit the `<details>`
      open on seven tasks, confirm; restore. Paste both.

## Task 3: The page for a task, opened for the operator

**Files:** `bin/dux-plan-page`, `bin/dux-status`, `bin/dux-recover`, `AGENTS.md`,
`skills/dux-recover/SKILL.md`, `tests/dux-plan-page.bats`, `tests/dux-status.bats`,
`tests/contract.bats`.

**Interface:** `dux-plan-page <id> [--open]` reads `state/<id>.plan`, refuses when the
ledger state is not `plan-ready` or the file is missing, lists every path changed
between the merge base and `sha` with Git's name-only diff under the same hook-free
flags `dux-result` uses, reads each with `git -C <worktree> show <sha>:<path>`, renders
the plan first with `--commit <sha>`, then a "Documents this plan changes" list, then
each changed `docs/specs/*.md` as one folded section named by its path, writes
`state/<id>.plan.html` with a temp file, one rename and mode 600, and prints the path.
`--open` runs `open` (Darwin) or `xdg-open` (elsewhere) on the path when the command
exists; it is never a finding when it does not. `dux-status` and `dux-recover` inspect
print the page path on the line after the links when the file exists. `AGENTS.md`'s
`plan-ready` bullet adds `bin/dux-plan-page <id> --open` before the fixed words, and the
`dux-recover` skill's `plan-ready` section says the page is Dux's render, that it shows
every document the plan changed, and that Dux has not read it.

**Acceptance:** with a bare remote fixture, the page is rendered from the committed
blobs, not the working files (the test edits the working plan after commit and asserts
the page holds the committed text); a changed spec file appears as a folded section and
a changed roadmap appears in the list but not as a section; a state other than
`plan-ready` refuses; the file is mode 600; `--open` with `PATH` emptied prints the path
and exits 0.

**Steps**

- [ ] The task command; the changed-paths list; blob reads; atomic write; `--open`.
- [ ] Status and recover lines; AGENTS.md and skill wording; contract test.
- [ ] Break-verify: read the working file instead of the blob, confirm the committed-text
      test fails; restore. Drop the spec sections, confirm the folded-section test fails;
      restore. Paste both.

## Task 4: The rule, where it is applied

**Files:** `skills/dux-dispatch/SKILL.md`, `templates/brief.md`, `bin/dux-brief`,
`tests/dux-brief.bats`, `tests/contract.bats`.

**Interface:** The dispatch skill's step 1 becomes: apply spec section 10's five clauses
in order, name the first that fires, and choose `plan` when one does or `ship` with no
plan when none does; documents-only never gets a plan; nothing steps down; the report to
the operator names the clause. A `ship` brief with no plan carries one extra rules line:
`If the change meets a clause of the plan rule (spec section 10) once you have read the
code, write blocked: needs a plan: <clause> and stop.` The contract test asserts the
skill names all five clauses by their headings.

**Acceptance:** the rendered no-plan ship brief has the line and stays under 100 lines; a
ship brief with a plan does not have it; the contract test passes.

**Steps**

- [ ] Skill text; brief line; tests.
- [ ] Break-verify: drop the line from the template, confirm the brief test fails; restore.
      Paste the failure.

## Task 5: A ship task with no plan

**Files:** `bin/dux-brief`, `bin/dux-worker-wrap`, `bin/dux-result`, `skills/dux-dispatch/SKILL.md`,
`tests/dux-brief.bats`, `tests/dux-worker-wrap.bats`, `tests/dux-result.bats`.

**Interface:** `dux-brief` accepts a `ship` brief with neither `--plan` nor `--tasks`
(one without the other is still a finding); its definition of done reads `Acceptance
criteria met, /ship run, CI green; then append done: PR <url>` and the Project section
has no plan lines. The wrapper writes empty `plan=` and `tasks=` for such a run.
`dux-result verify` for `kind=ship` with both empty skips `check_plan_tasks` and keeps
every other ship check; one empty and one set is a finding. A `retry` round copies
the absence as it copies the presence.

**Acceptance:** the no-plan brief renders and proves with a receipt, a pull request and
green checks from the fakes; the same fixture with a change only under `docs/` is
rejected as a ship result; a context with `plan=` set and `tasks=` empty is a finding.

**Steps**

- [ ] Brief; wrapper context; the retry round's copy.
- [ ] Result proof; tests.
- [ ] Break-verify: skip `check_plan_tasks` whenever `tasks=` is empty regardless of
      `plan=`, confirm the mixed-context test fails; restore. Paste the failure.

## Task 6: Documentation

**Files:** `docs/ARCHITECTURE.md`, `README.md`, `docs/plans/2026-09-03-dux-roadmap.md`.

**Interface:** `ARCHITECTURE.md` gains `dux-plan-page` in the component list, the page in
the wake flow, and the no-plan ship shape. `README.md`'s "what a task looks like" section
describes the pause, the page and the three answers in the operator's words, and says a
small change ships without a plan. The roadmap's "where this stands" records milestones
7 to 9 as merged.

**Acceptance:** `make check-branch` green; the README section reads without a task id, a
path or a flag in it.

**Steps**

- [ ] The three files.
- [ ] Break-verify: not applicable; documents only, and no assertion is added. Say so in
      the commit body.

## Task 7: The whole loop, end to end

**Files:** `tests/e2e-supervise.bats`.

**Interface:** One e2e test with the fake backend, fake claude, fake `gh` and a bare
remote: a plan task's fake worker commits a spec and a plan, pushes, writes `plan-ready:
x`; the watcher lands `plan-ready` and the state file, and `dux-plan-page` renders a page
holding the plan's title; `dux-brief --round change` then `dux-spawn --resume change` runs
a second plan round that lands `plan-ready` again and overwrites the page; `--round
approve` and `--resume approve` run an implement round whose fake worker ticks the boxes,
adds a file, fakes the receipt and reports `done:`; the result is `done: PR <url>`. A
second variant has the implement worker reword one task body before ticking, and the
result is `ended:` with the frozen-text reason.

**Acceptance:** both variants pass under bash 3.2 on both backends' fakes.

**Steps**

- [ ] The happy path.
- [ ] The reworded-task variant.
- [ ] Break-verify: make the fake implement worker leave one box unticked in the happy
      path, confirm the e2e ends `ended:` and the test fails; restore. Paste the failure.

## Milestone acceptance

Constitution gates as for milestones 7 and 8. Specific to this milestone: every fixture's
output passes the one no-active-content regex; the rule's worked examples in the spec
stay true of the skill text.

## Risks

- A markdown construct the renderer does not know renders as a paragraph, not as a
  gap. The plans in this repository are the fixtures; a project with a richer plan
  style gets a plainer page.
- `open` hands a `file://` URL to whatever browser the operator set as default. The
  page has no active content; the browser's own file handling is outside this claim.

## Open questions for the operator

None. Spec section 14 records the recommendations taken (no links, no external renderer).

## Design review

Both reviews are recorded at the end of `2026-09-10-dux-m7-resume-any-worker.md`. From
the first: findings 10 (sizing) and 16 (scope) moved Task 7 here and trimmed Task 1;
finding 11 (what the operator is approving) added the changed-documents list and the
spec sections to Task 3. The operator's rule then moved `--fresh` to milestone 7, where
the retired respawn path needs it.
