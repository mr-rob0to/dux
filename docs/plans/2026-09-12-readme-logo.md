# Put the Dux logo at the top of the README

> **For the implementer:** one task, then `/ship`. Tick each `- [ ]` box as it lands and
> keep the "where this stands" block current: the plan file is the state of the work, not
> the conversation. Do not run a code review of your own work: `/ship` owns the branch's
> one review and its security pass (constitution principle 9).

**Where this stands**
- Drafted 2026-09-12 by a Dux plan worker. One independent design review by a fresh
  session, eleven findings, six fixed; each is at the bottom.
- Picks up the README's commented-out logo placeholder, which has waited for an image
  since the README rewrite (pull request #25). The operator now has one.
- Merges as one ship PR of one task: the image file and three README lines.

**Estimated diff:** 1 line added and 4 removed in `README.md`, plus one new binary file of
3,297,426 bytes, across 1 task. Well under the cap.

**Goal:** Anyone opening the repository on GitHub sees the Dux banner, mascot and worker
robots on the left and the wordmark on the right, centered above the heading. Today they
see the heading alone and the placeholder comment is invisible.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 18, amended in this
pull request: a **Logo** bullet names the file, what it is, how the README shows it, and
that it is only ever replaced whole.

**Deviations:** none. This task adds no test: constitution principle 3 binds scripts and
guards, and the task changes a picture and three lines of prose. What stands in for a
test is a check of the thing the operator will look at, GitHub's rendering of the branch
README; Task 1 runs it inside the gate and pastes the output into the pull request body.

## What the spec does not carry

- **The pin.** Source: the PNG the task brief names, in the operator's downloads folder.
  Its path is not written here because an operator path in a tracked file fails the
  identifier lint. Pin instead:
  sha256 `815c56d76c1cb6d074a84ec91bcf179068dc8dc316e8fc147141f9b53fad9d3c`,
  3,297,426 bytes, 1774 by 887 pixels, 8-bit RGBA, transparent background (checked
  2026-09-12: the corners and about seven in ten sampled pixels are fully transparent).
- **Why 480 wide.** The image is exactly 2:1, so it renders 480 by 240, about half the
  README column on a desktop browser: the wordmark reads at a glance and the three worker
  robots are still recognisable. 120 wide, the old square guidance, would make the
  wordmark 60 pixels tall and the robots smudges. Anything past about 600 pushes the
  heading and badges below the first screen on a laptop.
- **The `<img>` tag stays**, not Markdown image syntax: a Markdown image cannot carry a
  width, and the block is already HTML. The placeholder comment's square-icon guidance
  is dropped with the comment; the full banner is settled by the operator, do not reopen.

## Task 1: the image and the three README lines

**Files:** `docs/assets/dux-logo.png` (new), `README.md`, and this plan file (boxes and
header).

**Interface:** none new. No script is edited.

**Acceptance:** `docs/assets/dux-logo.png` is tracked as a regular, non-executable file
(`git ls-files -s` shows mode `100644`) with the sha256 and size pinned above. In
`README.md` the four lines of the LOGO comment, from `<!-- LOGO:` to its closing `-->`,
are replaced by exactly `<img src="docs/assets/dux-logo.png" alt="Dux" width="480" />` in
the same place, inside the opening `<div align="center">` and above `# Dux`;
`git diff --stat` shows `README.md` with 1 insertion and 4 deletions, and no file other
than the image, the README and this plan changes. GitHub's rendering of the branch README
carries that tag and the raw URL for the image answers as `image/png`. `make check` is
green with the image tracked, `bin/dux-doctor` passes, and the task went through the full
`/ship` gate.

**Steps**

- [ ] If the brief names no source file, write `blocked:` saying so and stop; do not search
      for one. Otherwise `mkdir -p docs/assets`, copy the source to
      `docs/assets/dux-logo.png`, and confirm with `shasum -a 256`, `wc -c` and
      `git ls-files -s` (after `git add`) that the copy matches the pin and is `100644`.
      A mismatch is `blocked:`, not a retry with another file.
- [ ] `README.md`: delete the four LOGO comment lines and put the `<img>` line from
      Acceptance where the comment was, keeping the blank lines around it. Confirm with
      `git diff --stat` that the README change is 1 insertion and 4 deletions.
- [ ] `make check` green: the identifier lint now reads the image as a tracked file, and it
      passes because neither denylist matches its bytes (checked 2026-09-12 against the
      live lists). `bin/dux-doctor` passing. Then `/ship`, **the whole gate**. The skill
      says a docs-only branch skips the gate; under Dux that rule does not apply, and the
      signal is `DUX_SHIP_RECORD` set in this worker's environment. Dux counts a ship task
      done only on a receipt with all five phases (spec sections 5.4 and 11); a skipped
      gate leaves no receipt and the task ends with the PR unproved.
- [ ] Rendered check, inside `/ship` step 8, after the push and before the body is written,
      pasted as the Evidence line of the body's Verification section as the commands
      printed it: `gh api "repos/<owner>/<repo>/readme?ref=<branch>"
      -H "Accept: application/vnd.github.html" | grep -o '<img[^>]*dux-logo[^>]*>'` prints
      one tag with `src="docs/assets/dux-logo.png"` (GitHub leaves a relative `src` as it
      is), and `curl -sI https://raw.githubusercontent.com/<owner>/<repo>/<branch>/docs/assets/dux-logo.png`
      prints `200` and `content-type: image/png`. A miss is a fix pass under the gate.
      Nothing goes into a commit body after the gate has started: the receipt is tied to
      the head, and an amend would break it.
- [ ] No assertion was added, so there is nothing to break-verify. Say so in one line in
      the same Verification section.

## Left as written

- `README.md` lines 25 to 28 today, 22 to 25 after the edit, the DEMO comment: a
  different asset, out of scope.
- The `/ship` skill's docs-only skip and `bin/dux-result`'s receipt requirement disagree
  for exactly this kind of ship task, one whose whole diff is prose and pictures. Task 1
  steps around it; settling it in the skill or in the prover is its own change.

## Milestone acceptance

Constitution gates as usual: full suite green, shellcheck and identifier lint clean,
`bin/dux-doctor` passing, `/ship` the only gate. `docs/ARCHITECTURE.md` names no README
asset, so it does not change.

## Risks

- The image is the repository's first binary and, at 3.3 MB, its largest file; every clone
  carries it from now on. Accepted: byte-identical is the operator's call. A lossless
  shrink of the same picture is its own task if the operator wants one.
- The wordmark is dark plum on a transparent background, so on GitHub's dark theme it has
  less contrast than on the light one. The full banner as-is is settled; a dark-theme
  variant through a `<picture>` element is its own change.
- The file carries an Adobe XMP text chunk holding a document id and a public
  content-credentials URL. Neither denylist matches it and it names no person, so the lint
  passes; it stays because the file must be byte-identical.
- The ship worker takes the docs-only skip and the task ends unproved. Named in Task 1.

## Open questions for the operator

None.

## Design review

One independent review by a fresh session on 2026-09-12, read-only. Findings are plain
bullets, not boxes: `bin/dux-result` counts every box below the last `## Task` heading as
that task's, and an unticked one here would fail the milestone.

- **Critical, fixed.** The rendered check ran "after `/ship` has pushed" and went "into
  the commit body". The receipt is tied to the head and refuses a second `ci` line, so no
  commit may change once the gate starts, and a hand push then amend before the gate trips
  the skill's ancestor stop. The check now runs inside step 8, between the push and the
  body, and its output goes into the pull request body, which the skill already asks for.
- **Important, fixed.** The check expected the rendered `src` to be a
  `raw.githubusercontent.com` URL. GitHub leaves a relative `src` untouched (probed live
  on two public repositories), so a correct README would have read as a failure. The
  step now expects the relative path in the tag and builds the raw URL by hand.
- **Important, fixed.** Acceptance said "no other text file changed", which forbids
  ticking this plan's own boxes, and the prover rejects an unticked box. Now: nothing
  changes but the image, the README and this plan.
- **Minor, fixed.** The DEMO comment sits at lines 25 to 28 today, not 26 to 29, and
  moves up three after the edit.
- **Minor, fixed.** "The skill offers to skip" understated it: the skill instructs. The
  step now says the rule does not apply under Dux and names the signal the worker can
  check, `DUX_SHIP_RECORD`.
- **Minor, fixed.** Acceptance asked for a regular, non-executable file and no step
  checked it. Step 1 now reads the mode back with `git ls-files -s`.
- **Note, taken.** Principle 3 binds scripts and guards, so there was no deviation to
  declare. Deviations now says none and keeps the one line on what stands in for a test.
- **Note, taken.** "What is settled" restated four facts the spec bullet now owns. The
  section is now only the pin, the width arithmetic and the tag choice.
- **Note, taken.** The spec bullet said byte-for-byte twice. Tightened.
- **Note, taken.** Findings written as plain bullets, with the reason above.
- **Note, left.** The steps say `make check`, as the precedent plan does; `/ship` step 4
  runs the project's own gate, `make check-branch`, regardless.

Everything else the reviewer checked held: the plan-shape proof on the two staged files,
the ship-shape proof after the task lands (two entries outside the plan documents, five
boxes under one heading, nothing in a later section counted as a box), the 1 insertion
and 4 deletions simulated on a copy of the README with the block structure intact, the
identifier lint green on the staged files with both denylists present, that no bats test
walks every tracked file, that the raw host serves a PNG as `image/png` without a token,
and that Task 1 is under the 60-line cap.
