SHELL := /bin/bash
BATS  ?= bats

# Test files run side by side. This goes through make's own -j, so there is no
# GNU parallel to install: every file is its own target. JOBS=1 puts them back
# in a line when a failure is easier to read that way.
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

# A file tagged adapter, worker or e2e is run by an explicit matrix line below,
# once per combination it needs. Everything else runs once. This is the same
# split the old `--filter-tags '!adapter,!worker,!e2e'` made, read from the
# files instead of restated, so adding a file keeps it correct.
# /dev/null in the grep list stops grep reading stdin if the list is ever empty.
ALL_BATS   := $(shell find tests -name '*.bats' | sort)
# Two things make quoting here awkward: it reads a ( inside $(shell ...) as its
# own, so the alternatives are spelled out rather than grouped, and it reads an
# unescaped # as the start of a comment even inside quotes, so the one the tag
# line begins with is written \#.
TAGGED     := $(shell grep -lE '^\# bats file_tags=adapter|^\# bats file_tags=worker|^\# bats file_tags=e2e' $(ALL_BATS) /dev/null 2>/dev/null | sort)
UNIT_FILES := $(filter-out $(TAGGED),$(ALL_BATS))
UNIT_JOBS  := $(patsubst tests/%.bats,job/%,$(UNIT_FILES))

MATRIX_JOBS := \
  job-m/backend-herdr job-m/backend-tmux \
  job-m/worker-claude job-m/worker-codex \
  job-m/e2e-dispatch-herdr job-m/e2e-dispatch-tmux \
  job-m/e2e-supervise-herdr job-m/e2e-supervise-tmux

# One directory per run, so two runs in the same worktree cannot erase or
# overwrite each other's output. `test` picks the name and passes it down.
LOGS ?= tests/tmp/logs/adhoc

# One job: run a bats file with an environment, quietly. A passing file prints
# one line. A failing file prints its whole log, so a parallel run still reads
# like a serial one at the point where it matters.
# $(1) job name, $(2) environment, $(3) bats arguments
define run_bats
@mkdir -p "$$(dirname "$(LOGS)/$(1).log")"; \
if env $(2) $(BATS) $(3) > "$(LOGS)/$(1).log" 2>&1; then \
  printf '  ok    %-26s %3s tests\n' "$(1)" "$$(grep -c '^ok ' "$(LOGS)/$(1).log")"; \
else \
  printf '  FAIL  %s\n' "$(1)"; cat "$(LOGS)/$(1).log"; exit 1; \
fi
endef

.PHONY: test unit matrix check check-branch check-bash32 lint lint-shell lint-identifiers lint-pipes \
        $(UNIT_JOBS) $(MATRIX_JOBS)

test:
	@$(MAKE) --no-print-directory -j$(JOBS) \
	  LOGS=tests/tmp/logs/$$(date +%Y%m%d-%H%M%S)-$$$$ unit matrix

unit:   $(UNIT_JOBS)
matrix: $(MATRIX_JOBS)

$(UNIT_JOBS): job/%:
	$(call run_bats,$*,,tests/$*.bats)

job-m/backend-herdr:
	$(call run_bats,backend-herdr,DUX_BACKEND=herdr,tests/backend-adapter.bats)
job-m/backend-tmux:
	$(call run_bats,backend-tmux,DUX_BACKEND=tmux,tests/backend-adapter.bats)
job-m/worker-claude:
	$(call run_bats,worker-claude,DUX_WORKER_HARNESS=claude,tests/worker-adapter.bats)
job-m/worker-codex:
	$(call run_bats,worker-codex,DUX_WORKER_HARNESS=codex,tests/worker-adapter.bats)
job-m/e2e-dispatch-herdr:
	$(call run_bats,e2e-dispatch-herdr,DUX_BACKEND=herdr DUX_WORKER_HARNESS=claude,tests/e2e-dispatch.bats)
job-m/e2e-dispatch-tmux:
	$(call run_bats,e2e-dispatch-tmux,DUX_BACKEND=tmux DUX_WORKER_HARNESS=claude,tests/e2e-dispatch.bats)
job-m/e2e-supervise-herdr:
	$(call run_bats,e2e-supervise-herdr,DUX_BACKEND=herdr,tests/e2e-supervise.bats)
job-m/e2e-supervise-tmux:
	$(call run_bats,e2e-supervise-tmux,DUX_BACKEND=tmux,tests/e2e-supervise.bats)

# macOS only: run the whole suite with /bin/bash (3.2) first on PATH, since
# every script's shebang resolves bash through PATH.
check-bash32:
	@mkdir -p tests/tmp/bash32 && ln -sf /bin/bash tests/tmp/bash32/bash
	PATH="$(CURDIR)/tests/tmp/bash32:$$PATH" $(MAKE) test

# check is the loop to run after a task. check-branch is the one to run once
# before /ship: it adds the bash 3.2 pass, which is the same suite again.
# The two passes are separate $(MAKE) lines rather than prerequisites so that
# they stay in order even when the caller asked for a parallel build: the 3.2
# pass puts its own bash first on PATH, and reading a failure is easier when
# only one of the two is running.
check: lint test
check-branch:
	@$(MAKE) --no-print-directory check
	@$(MAKE) --no-print-directory check-bash32

SHELL_FILES = bin/dux-* bin/backends/*.sh bin/workers/*.sh templates/hooks/pre-push \
              tests/fakes/* tests/helpers/*.bash tests/repeat skills/ship/ship-guard skills/ship/ship-env

lint: lint-shell lint-identifiers lint-pipes

# tests/lint-pipes.awk says what this rejects and why.
LINT_FILES ?= $(SHELL_FILES)

lint-pipes:
	@awk -f tests/lint-pipes.awk $(LINT_FILES) \
	|| { echo "the lines above stop reading before their producer is done; use take_bytes, take_line, or grep ... >/dev/null" >&2; exit 1; }

lint-shell:
	shellcheck -s bash $(SHELL_FILES)

# Account names that are also ordinary English words or shared CI defaults. A
# denylist entry equal to one of these is dropped before the search: this repo's
# CI account is named after one of them, and matching it fails every tracked file
# that uses the word normally.
#
# This list is the volume limit the names half has. A whole word floods too when
# the word is ordinary. Counted on this repo: run 1624 lines, test 1171, dev 643,
# git 527, log 435, tmp 204.
# An operator whose account is one of those would get that on every lint run,
# and the way out of an unreadable check is to delete the file it comes from.
GENERIC_ACCOUNTS := runner ubuntu root admin build ci user vagrant jenkins docker \
                    dev git log run tmp test www ftp

# tests/personal-identifiers.txt holds paths and project names, matched literally.
# tests/personal-names.txt holds bare account names, matched only as whole words,
# so a name never matches inside a longer word. Both are git-ignored, written by
# bin/dux-install; a missing or empty one is skipped.
#
# Being git-ignored means a worktree never has them, and every feature branch is
# written in a worktree, so the check was silently passing in the one place the
# code gets written. The lists are read from the main checkout instead, which
# `git rev-parse --git-common-dir` names: it prints the main repository's .git
# from inside a worktree, and a bare .git from the main checkout, so one path
# serves both. Both places are read and the entries merged, because dux-install
# writes the lists beside its own bin/ directory: run from a worktree it puts
# them in that worktree, and reading only one of the two locations leaves the
# other one ignored either way. CI has neither file and is still skipped, which
# is the case the skip is actually for.
#
# Without a git repository the whole target is a lie: the search below is
# `git ls-files`, its failure is swallowed, and the target would exit 0 having
# read nothing. So that is refused rather than skipped. The one case still not
# handled is this repo vendored as a submodule of another, where git names the
# superproject's .git/modules and the lists are not found. That skips, which is
# what it already did before the lists were resolved at all.
#
# The two locations are read with an echo after each, not by handing both to one
# cat. cat joins files with nothing between them, so a list hand-edited and saved
# without a final newline fuses its last entry to the next file's first, and in a
# main checkout, where both paths are the same file, to its own first entry. The
# fused token matches nothing and the whole list stops working while the target
# reports success. The blank line each echo leaves is dropped by the grep below.
#
# There is no length rule here. What is worth writing is decided once, by
# bin/dux-install, which leaves out the project whose repository is the checkout
# it is installing into and any name shorter than four characters, and says so
# each time. This target checks whatever it is given.
lint-identifiers:
	@tmp="$$(mktemp -d)"; rc=0; \
	[ "$$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
	  || { echo "cannot check identifiers: not inside a git work tree"; rm -rf "$$tmp"; exit 1; }; \
	dl="$$(dirname "$$(git rev-parse --git-common-dir)")"; \
	printf '%s\n' $(GENERIC_ACCOUNTS) > "$$tmp/generic"; \
	for f in personal-identifiers personal-names; do \
	  : > "$$tmp/$$f"; \
	  { cat "tests/$$f.txt" 2>/dev/null; echo; cat "$$dl/tests/$$f.txt" 2>/dev/null; echo; } \
	    | grep -v '^$$' | sort -u | grep -vxF -f "$$tmp/generic" > "$$tmp/$$f" || true; \
	done; \
	if [ -s "$$tmp/personal-identifiers" ]; then \
	  git ls-files -z | xargs -0 grep -nF -f "$$tmp/personal-identifiers" -- 2>/dev/null \
	    | grep -v '^tests/personal-' && rc=1 || true; \
	fi; \
	if [ -s "$$tmp/personal-names" ]; then \
	  git ls-files -z | xargs -0 grep -nwF -f "$$tmp/personal-names" -- 2>/dev/null \
	    | grep -v '^tests/personal-' && rc=1 || true; \
	fi; \
	rm -rf "$$tmp"; \
	[ "$$rc" -eq 0 ] || { echo "personal identifiers found"; \
	  echo "  the lists in tests/personal-*.txt are written by dux-install, from data/projects.md and this account; an entry that looks wrong rather than leaked is stale, so run the installer again"; exit 1; }
