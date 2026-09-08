# Dux fix: the denylist is decided at install Implementation Plan

> **For the implementer:** one task at a time, in order. Tick each `- [ ]` box as it
> lands and keep the "where this stands" block current: the plan file is the state of
> the milestone, not the conversation. Break-verify at the task boundary, before the
> next task starts. Do not run a code review of your own work: `/ship` owns the
> branch's one review and its security pass (constitution principle 9), and a review
> outside the gate is how the gate gets skipped.

**Where this stands**
- Rewritten 2026-09-07 on `fix/denylist-at-install` from `main` at bde55f4, on a branch
  renamed from `fix/denylist-match-ceiling` when the design changed. The first
  design, a per-entry match ceiling in the lint, was rejected by the operator the same
  day: it stacked a third guard on two that exist only because this repo's own name was
  written into its own denylist, and the tool is meant to be simple to install and use.
  This version cuts that at the root. Reviewed once by a fresh independent session,
  all six findings folded in, approved by the operator the same day. 4 of 4 tasks
  done, `make check-branch` green on the branch and on a clean clone of it, and in
  the ship gate, which has had one fix pass answering its code review.
- PRs #15 and #16 logged two small follow-ups in the identifier lint, a `cat` that fuses
  two list files and one stale comment; both are carried here unchanged as Tasks 1 and 2.
- When this merges, `dux-install` never writes this repository's own name into the
  denylist, skips a name too short to match and says so once, and the lint loses the
  length floor and the machinery around it. Less code than today.

**Divergence, 2026-09-07, three of them.** Task 3's acceptance said `bin/dux-install`
would end up shorter than today. It ends up longer, 104 lines against 80: the code in it
shrank and the comment explaining why "self" is a repository and not a directory grew.
The criterion was the wrong measure and now says what it meant, that the file holds no
`git grep`, no content condition and no temporary file.

Task 4's commit body says four tests went with the floor. The diff deletes two, trims one
assertion from a third, and keeps a fourth under the divergence below. The commit message
overstates it; this line is the correction, since rewriting a landed commit mid-gate would
put the phases behind it on other code.

Task 4 was to delete the test that a short generic
account name is dropped. It is kept and renamed instead. Without the floor it proves
something no other test does, that a two-character generic word is dropped before the
search rather than flooding 56 lines, and it was break-verified by taking `ci` off
`GENERIC_ACCOUNTS`. Nothing else in the plan changed.

**Estimated diff:** ~110 added lines and ~130 removed across 4 tasks, the plan excluded;
the plan itself stays about the same length. The cap is 2,500 lines or 12 tasks (constitution
principle 1). Sizing procedure: roadmap, "How a milestone is sized". Task 3 is the only
real change and it lands as two commits: the installer half, then the floor removal.

**Goal:** Today the identifier lint carries a length floor, a refusal message, and a
conditional self-skip in the installer, all there because registering this checkout as a
project called `dux` put a three-letter substring into the denylist and matched every
file. After this change the installer simply never writes the name of the repository it
is installing into, tells the operator once about any project name too short to protect,
and the lint checks what it is given. The lint also survives a hand-edited list file
saved without a final newline, which today makes the whole list silently match nothing.

**Spec:** `docs/specs/2026-09-03-dux-orchestrator-design.md` section 18, the bullet "No
personal identifiers in tracked files", and the `dux-project add` paragraph in section 5.
Task 3 amends both with the text in the Design section, before its own code.

## Design

Three follow-ups, one branch, one PR. Tasks 1 and 2 are unchanged from the first draft.

### Item 1: the list files are joined with a newline between them

`Makefile` merges the two list locations with `cat a b`. `cat` inserts nothing between
files, so a first file whose last line has no newline fuses its last entry to the second
file's first entry. In the main checkout both paths are the same file, so one
unterminated entry fuses with itself and the list stops matching while the target
exits 0. Verified here with BSD `cat`: two files `alice` (no newline) and `carol` print
`alicecarol`.

The shape the audit suggested is confirmed and is the one to use, with two facts that
matter: each `cat` needs its own `2>/dev/null`, because inside a brace group a missing
file is one command's error, not the group's; and the group's exit status is the last
`echo`'s, so the trailing `|| true` keeps the meaning it has today.

```
{ cat "tests/$$f.txt" 2>/dev/null; echo; cat "$$dl/tests/$$f.txt" 2>/dev/null; echo; } \
  | grep -v '^$$' | sort -u | grep -vxF -f "$$tmp/generic" > "$$tmp/$$f" || true; \
```

Verified with BSD tools: `alice` unterminated plus `carol` gives two entries; the same
unterminated file read twice gives one; a missing second file gives the first file's
entries; two missing files give an empty list, which the existing `[ -s ]` skips.

### Item 2: one comment

`tests/identifiers.bats` line 82 says a worktree never has the list files. A fresh
worktree does not inherit them, but `dux-install` run inside a worktree writes them
there, and the test two below it proves that. The comment is reworded to say both.

`Makefile` lines 112 to 135 need nothing. The same sentence there is followed, in the
same paragraph, by the correction that `dux-install` writes the lists beside its own
`bin/` and that both places are read. It is left alone.

### Item 3: the installer decides what is worth writing; the lint has no floor

The denylist exists so a private project's name never lands in Dux's tracked files.
Dux's own name cannot leak into Dux: it is the repository's name, in the README and in
every script. It should never have been an entry, and everything below follows from
treating it that way.

**The installer never writes the name of the repository it is installing into.** Today
the skip is conditional: the name is dropped only when `git grep` finds it in tracked
content, which is exactly the case where a leak would be hidden. The condition goes.
"This repository" means the repository `DUX_ROOT` is inside, identified by its git common
directory (the `.git` a main checkout and all its worktrees share), so `dux-install` run
from a worktree of Dux reaches the same answer as from the main checkout. Today it does
not: a worktree's path is not the registered path, so a worktree install writes the name,
and with the floor gone that would flood. `git rev-parse --git-common-dir` prints `.git`
relative from a main checkout and an absolute path from a worktree, so both sides are
resolved with `cd` and `pwd -P` before comparing. When `DUX_ROOT` is not in a repository,
nothing is "self" and every name is written. A registered path that is missing or is not
a repository is not "self" and its name is written, as today.

The existing log line stays as it is: `dux: left this repo's own project out of the
denylist: <name>`. It fires once per dropped name.

**The installer skips a project name shorter than four characters and says so.** Names
are ASCII by `dux-project`'s own rule, so bytes and characters agree. The line, exactly,
one per skipped name, after the self check so a name that is both is reported as self:

```
dux: left <name> out of the denylist: shorter than four characters, and the lint would match nearly every file; register it under a longer name with dux-project add --name
```

It is a `log` line, not a finding. A finding exits 2 and stops the install, but the skills
are already linked and the config seeded by then, and nothing on the machine is wrong: the
name is simply too short to protect. Stopping would leave a half-done install that fails
at the same name on every rerun until the operator re-registers, for a case that costs
them nothing today. Telling them once, at the moment they install, is the whole job.

**The `Makefile` loses the floor.** `DENYLIST_MIN`, the per-entry length loop, its two
refusal lines, the early exit, and the comment block above it all go. The
`GENERIC_ACCOUNTS` comment loses its two sentences about the floor. With the installer
refusing to write a short name, the only registered name that reaches a list unchecked is
the home path, which the installer writes as it always has, and the only other way in is a
hand edit. An operator who hand-edits a git-ignored file gets whatever they wrote.

**What this trades away, plainly.** A project whose name is three characters or fewer gets
no identifier coverage at all. The operator learns that on the install that skips it,
and can re-register under a longer name: remove the line from `data/projects.md` by hand,
then `dux-project add <path> --name <longer>`; `dux-project` has no rename or remove yet,
which is logged separately. Second, this checkout registered under a personal alias
(`zz-dux`, say) no longer keeps that alias in Dux's own denylist; the old conditional
skip preserved that one case, and it is dropped on purpose. Anyone who commits their own
alias into Dux typed it themselves. Third, any other project registered at a worktree of
this repository is also read as self and left out, because a worktree shares the same git
common directory. Registering a Dux worktree as a separate project is not a thing the
operator does, and if they did, its name is still this repository's name.

**On merge day, `make check` in this repo prints what it prints today.** The installed
lists were written by PR #15's installer and hold the home path and the account name, each
matching zero tracked lines; `dux` is in neither. Re-running `dux-install` writes the same
two files and logs the same one line about leaving `dux` out. Nothing needs re-running.

**Spec amendments.** The section 18 bullet is replaced by:

> - **No personal identifiers in tracked files**: no operator paths, usernames, project
>   names, or accounts. `make lint` greps for two gitignored denylists that `dux-install`
>   writes: `tests/personal-identifiers.txt`, the operator's home path and registered
>   project names, matched as substrings; and `tests/personal-names.txt`, the account
>   name and home folder name, matched as whole words. Two kinds of registered name are
>   left out, and the installer says so each time: the project whose repository is the
>   checkout being installed into, because that name is the repository's own and cannot
>   leak into it; and any name shorter than four characters, which would match nearly
>   every file. A short name gets no lint coverage until it is registered under a longer
>   one with `dux-project add --name`.

And one sentence is appended to the `dux-project add` paragraph, after "A derived name
that is unusable or already registered is a finding that names the flag.":

> A name of three characters or fewer registers, but the identifier lint leaves it
> unchecked (section 18); `--name` is how to give it a longer one. Run `dux-install`
> again after registering, which is what rewrites the denylist.

### What happens to each test that touches the floor or the self-skip

`tests/dux-install.bats`, by today's line number:

- 147 `seed_root`: kept; its comment said the skip needs the name in the content, which
  is no longer true. It stays because the self check needs the root to be a repository.
- 174 "leaves this repo's own project out": kept as it is. The comment's argument about
  flooding is replaced by the one above: the name is the repository's own.
- 192 "a skipped name that starts with a hyphen": kept as it is. The name no longer
  reaches `grep`, and the comment says so; the test stays because a leading hyphen is
  the shape that turns into an option in whatever filter the implementer picks.
- 208 "registered under a personal name keeps its entry": rewritten to its opposite,
  "this repo's own name is left out even when it appears nowhere in the tracked content".
  Same fixture, `zz-dux` at a root whose README holds nothing; asserts the name is absent
  from the list. Red against today's installer, which keeps it.
- 220 "keeps every other project name, short ones included": rewritten to "leaves a short
  project name out and says so, and keeps one at four characters". Registry holds `api`
  and `keep`; asserts `api` absent, the log line containing `left api out of the
  denylist: shorter than four characters`, and `keep` present. Red today: `api` is
  written. Its root is built with `seed_root`, not a plain `mkdir` as today, so the
  length skip is proven on the same path a real install takes: `DUX_ROOT` in a
  repository, the self check running before it. A length skip that only worked in the
  "not a repository" branch would pass a `mkdir` version of this test and do nothing on
  a real machine.
- 233 "says nothing about a skipped project when it skips none": kept, plus one
  assertion that the output does not contain `shorter than four characters`.
- New: "run from a worktree of this repo, install still leaves its own name out". A
  seeded root with `git worktree add`, the registry naming the main path, `DUX_ROOT` set
  to the worktree; asserts the name is absent from the worktree's list. Red today. Its
  seeded README carries the project name, the way test 174's does. This matters: the
  first break below puts the old content condition back, and if this fixture lacked the
  name that break would fail this test as well as 208, giving two tests one failure.

`tests/identifiers.bats`, by today's line number:

- 34 to 37, the `boundary_entry` halves: deleted with the one test that used them.
- 77 to 81: the floor's own comment, stranded above the worktree test by PR #15. Deleted.
  Task 2 rewords lines 82 to 84 just below; the two edits do not overlap.
- 154 "refuses a denylist entry too short": deleted. It proved the floor exists. The
  flood it refused is now prevented one step earlier, by the installer never writing the
  name, which the rewritten 220 test and the 174 and 208 self tests prove.
- 175 "a short name in the names denylist is kept": kept. The one assertion about the
  floor's message (`!= *"too short"*`) goes; the rest proves the names half catches a
  three-letter account name as a whole word, and that is still worth proving.
- 199 "accepts an entry at the shortest length it trusts": deleted. There is no boundary
  left to sit on; an absent entry passing is what test 39 already shows.
- 208 to 210, the comment above the ordinary-word test: reworded to drop the floor. The
  generic list is the names half's volume limit; that sentence stays.
- 219 "a generic name that is short is dropped before the length check": deleted. Test 39
  already proves a generic word in the paths list is dropped before the search runs, and
  "before the length check" has no referent.

**How the deletion is shown not to take coverage with it**, beyond the suite staying
green: with the floor removed and its tests still in place, the implementer runs
`tests/identifiers.bats` once. Test 154 must fail, and it fails at its message assertion,
since the message is gone; that alone proves nothing about the flood. So the flood is
shown by hand: in a clone, write `dux` alone into `tests/personal-identifiers.txt`, run
`make lint-identifiers`, and record the exit status and the hit count (3,565 tracked
lines today, from `git ls-files -z | xargs -0 grep -F dux | wc -l`). That is what the
floor stood in front of, and what the installer now never produces. Test 219 must still
pass, which shows it never depended on the floor. All three results go into the commit
body, then the tests are deleted. Every other deleted or loosened assertion is paired
above with the test that now covers its case.

### Not changed, and why

- `docs/ARCHITECTURE.md`: not a material change under principle 4. No script, adapter,
  state file, or flow step is added, removed, or renamed; line 50 still says
  `dux-install` writes the identifier denylist, and it does.
- `bin/dux-project`: its missing rename and remove are logged separately.
- `GENERIC_ACCOUNTS`: the list itself is untouched; only the comment above it changes.
- The names half of the denylist, matched as whole words: untouched.
- There is no match ceiling anywhere in this plan. The tracked symlink
  `tests/fakes/codex` mattered only to a ceiling's count; nothing here depends on it.
- The `grep -v '^tests/personal-'` filter: pre-existing, per commit 04a5e46. It stays.

### Fixture rules for `tests/identifiers.bats`

The file is one of the tracked files the lint searches, and every test clones committed
content. So: no fixture token is ever spelled bare in the file or in this plan, apart from
`leak-me-please`, which exists to be found and is already tracked in both; new tokens
are built by the shell from the halves and words the file already defines; and the suite
is run again after each commit, because a token absent from the working tree can be
present in what a clone sees, or the other way round. `tests/dux-install.bats` runs no
lint and its fixtures never enter a searched list, so its names may be spelled bare, as
they are today.

## Task 1: Join the list files with a newline

**Files:** `Makefile` (the `cat` line in `lint-identifiers`), `tests/identifiers.bats`.

**Interface:** no new flags or messages. The merged list is the same whether or not
either file ends in a newline. A missing file and an empty list behave as today.

**Acceptance:** a test in `tests/identifiers.bats` writes a one-entry paths list with
`printf '%s'` and no newline, puts that entry in `README.md`, adds it, and asserts the
target exits non-zero naming `README.md`. On today's `Makefile` it passes green because
the fused entry matches nothing; that is the failure being fixed. Every existing test in
the file still passes.

**Steps**

- [x] Add the test, using the same `leak-me-please` token the first test uses, and
      see it fail against the current `Makefile`.
- [x] Replace the `cat` line with the brace-group shape from the Design section.
- [x] Run `make check`, then commit, then run `bats tests/identifiers.bats` again on the
      committed state.
- [x] Break-verify: put the plain `cat` back, run, confirm the new test fails, restore,
      paste the failure into the commit body (constitution principle 3).

## Task 2: Say what the worktree test proves

**Files:** `tests/identifiers.bats` (the comment at lines 82 to 84).

**Interface:** none. Comment only.

**Acceptance:** the comment above "lint reads the denylist from the main checkout when
run in a worktree" says that a fresh worktree does not inherit the list files, that
`dux-install` run inside a worktree writes them there, and that the next test covers
that. The `Makefile` comment block at lines 112 to 135 is untouched; the Design section
says why. `make check` is green.

**Steps**

- [x] Reword the comment. Keep the sentence about the check silently passing where the
      code gets written; it is the reason the test exists.
- [x] Run `make check`; commit as `docs(tests): ...`.
- [x] Break-verify: nothing to break. This task adds no assertion, and it says so in
      the commit body rather than claiming a verification it did not run.

## Task 3: Leave this repository and short names out at install

**Files:** `docs/specs/2026-09-03-dux-orchestrator-design.md` (section 18 bullet, the
`dux-project add` paragraph), `bin/dux-install` (the denylist block and its comment),
`tests/dux-install.bats`.

This task lands before the floor is removed, and that order matters. After it the
installer writes neither this repository's name nor a short one, and the floor is still
in the `Makefile` doing no harm. The reverse order would leave a commit where the floor
is gone and the installer still writes short names.

**Interface:** `dux-install` exits 0 as before. Two `log` lines, once per dropped name,
exact text in the Design section: the existing self line and the new short-name line,
self checked first. "Self" is the resolved git common directory of `DUX_ROOT` matching
that of the registered path.

**Acceptance:** the seven installer tests behave as the Design table says and `make check`
is green. `bin/dux-install` holds no `git grep`, no content condition, and no temporary
file. Both spec passages read as quoted in Design.

**Steps**

- [x] Amend the two spec passages first.
- [x] Rewrite installer tests 208 and 220, add the worktree test and the one assertion
      in 233; see the three rewritten or new tests fail against today's installer.
- [x] Rewrite the installer's denylist block and its comment: identity by git common
      dir, unconditional self skip, length skip after it, the two log lines. Green.
- [x] Run `make check`, commit, run both bats files again on the committed state.
- [x] Break-verify, one at a time, six distinct failures pasted into the commit body,
      each failing a different assertion line, all in `tests/dux-install.bats`: put a
      content `git grep` condition back on the self skip (208's absence assertion fails);
      compare `pwd -P` of the directories instead of the common dir (the worktree test
      fails); write every name regardless of length (220's `api` absence fails); keep the
      skip but drop its log line (220's log-line assertion fails); skip at four characters
      instead of three (220's `keep` assertion fails); log the short line for every name
      (233's new assertion fails). Confirm each break landed before trusting that it
      failed, and that no break trips a different test first.

## Task 4: Drop the length floor from the lint

**Files:** `Makefile` (`DENYLIST_MIN`, its loop and comment, the `GENERIC_ACCOUNTS`
comment), `tests/identifiers.bats` (the dispositions in Design).

**Interface:** `make lint-identifiers` has no length rule; an entry of any length is
searched as today.

**Acceptance:** the four lint tests are deleted or trimmed as Design says, `make check`
is green, the `Makefile` holds no `DENYLIST_MIN` and no "too short" text. A bare `dux`
entry written by hand into a clone's paths list floods, and the commit body says so with
the count, because that is now the operator's own doing and not the tool's.

**Steps**

- [x] Remove the floor from the `Makefile` and fix the `GENERIC_ACCOUNTS` comment.
- [x] With the old tests still present, run `tests/identifiers.bats`, run the hand flood,
      and record the three results the Design section asks for.
- [x] Apply the `identifiers.bats` dispositions.
- [x] Run `make check`, commit, run both bats files again on the committed state.
- [x] No break-verification: this task adds no assertion, it deletes four and trims one.
      The commit body says so, and carries the three recorded results instead, which are
      what accounts for the deleted guard's coverage.

## Milestone acceptance

- Every box above ticked and the "where this stands" block current.
- `make check-branch` green on the branch and on a clean clone of it.
- Each task's break-verification failure is in a commit body, recorded at that task, and
  Task 2's commit says it added no assertion.
- Task 4's commit body carries the two pre-deletion results and the hand-written flood
  count, so the deleted guard's coverage is accounted for, not assumed.
- `docs/ARCHITECTURE.md` untouched, for the reason in the Design section.
- The pull request carries the actual added and removed line counts against the
  estimate, the fix-to-feature commit ratio, the trade-offs from the Design section in
  plain words, and the logged follow-ups: `dux-project` rename and remove.

## Risks

- A project named with three characters or fewer is unprotected by the lint. The
  operator hears it once, at install, and has a way to a longer name.
- A hand-edited list with a short entry floods the lint. The operator wrote the file.
- This checkout registered under a personal alias no longer has that alias in Dux's own
  denylist. Decided; the alias is the operator's own word for this repository.
- An old `data/projects.md` line with a path that has since moved is not "self" and its
  name is written, as today. No change in exposure.
- `git rev-parse --git-common-dir` needs git 2.5 or later; the `Makefile` already
  depends on it, so no new requirement.
- The change spans two commits, the installer first and the floor second. In that order
  every commit is green and the floor is never absent while the installer still writes a
  short name. The reverse order would leave exactly that gap.
- A `HOME` of `/` would put a one-character entry in the paths list, which the installer
  has never checked and still does not. Nobody on a personal machine reaches it; it is
  noted so the claim above stays honest.

## Design review

One independent review, by a fresh session that did not write this plan, on 2026-09-07.
Six findings, all folded in.

- **Important.** The first break-verification would have failed two tests, not one,
  because the new worktree test's fixture did not say whether it carried the project
  name. The same class of mistake the previous review caught. The fixture now carries it.
- **Minor.** Test 220 proved the short-name skip on a root that is not a repository, a
  path a real install never takes, so a skip that only worked there would still pass.
  It now builds its root the way the other tests do.
- **Minor.** "Only a hand edit can put a short entry in the list" was overstated: the
  home path is written unchecked, as it always has been. Softened, and noted as a risk.
- **Minor.** A project registered at a worktree of this repository is also read as self.
  Added to the trade-offs.
- **Minor.** The operator hears the short-name line only if they run the installer again
  after registering, which nothing documented. The spec sentence now says to.
- **Minor.** The one-commit argument was backwards. The change is now two commits,
  installer first, and the risk entry says why that order is the safe one.

The reviewer confirmed by running them: that identity by git common directory holds from
the main checkout, a worktree, a second worktree, a symlink and a subdirectory, and gives
nothing for a plain directory; that today's installer run from a worktree really does
write the name; that the floorless lint with `dux` in the list prints 3,564 hits; that
Task 1's fix behaves on all four list shapes; and that the remaining five breaks each
fail one distinct assertion.

Two notes the reviewer raised that this branch does not act on, logged for the pull
request: the constitution says the account name lives in the paths list when it lives in
the names list, which is older than this change; and refusing a short name in
`dux-project add` instead would leave no unprotected class at all, which was written and
backed out in PR #15 because it breaks four tests that pass short names on purpose.

## Open questions for the operator

None.
