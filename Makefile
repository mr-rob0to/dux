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

.PHONY: test unit matrix check check-branch check-bash32 lint lint-shell lint-identifiers \
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

lint: lint-shell lint-identifiers

lint-shell:
	shellcheck -s bash bin/dux-* bin/backends/*.sh bin/workers/*.sh templates/hooks/pre-push tests/fakes/* tests/helpers/*.bash skills/ship/ship-guard

# Account names that are also ordinary English words or shared CI defaults. A
# denylist entry equal to one of these is dropped before the search: this repo's
# CI account is named after one of them, and matching it fails every tracked file
# that uses the word normally.
GENERIC_ACCOUNTS := runner ubuntu root admin build ci user vagrant jenkins docker

# tests/personal-identifiers.txt holds paths and project names, matched literally.
# tests/personal-names.txt holds bare account names, matched only as whole words,
# so a name never matches inside a longer word. Both are git-ignored, written by
# bin/dux-install; a missing or empty one is skipped.
#
# An entry shorter than DENYLIST_MIN cannot be matched without flooding: this
# repo is registered as a project called "dux", that name reached the paths list,
# and every tracked file matched. A check that fires on every line is a check
# nobody reads, so a short entry is refused by name instead.
#
# Only the paths list. It is matched as a substring, which is what floods; the
# names list is matched as a whole word, where a three-letter account name is
# an ordinary entry and not a problem. The two lists also come from different
# places, so one refusal message could not tell the truth about both: the paths
# list is built from data/projects.md, the names list from whoami and the home
# directory name, which an operator cannot rename to clear a build.
DENYLIST_MIN := 4
lint-identifiers:
	@tmp="$$(mktemp -d)"; rc=0; \
	printf '%s\n' $(GENERIC_ACCOUNTS) > "$$tmp/generic"; \
	for f in personal-identifiers personal-names; do \
	  : > "$$tmp/$$f"; \
	  [ -s "tests/$$f.txt" ] || continue; \
	  grep -v '^$$' "tests/$$f.txt" | grep -vxF -f "$$tmp/generic" > "$$tmp/$$f" || true; \
	  [ "$$f" = personal-identifiers ] || continue; \
	  while IFS= read -r e; do \
	    [ "$$(printf '%s' "$$e" | wc -c)" -lt $(DENYLIST_MIN) ] || continue; \
	    echo "denylist entry [$$e] is too short to match safely as a substring; at least $(DENYLIST_MIN) characters"; \
	    echo "  tests/$$f.txt is written by dux-install from data/projects.md; rename or drop that project there, then run dux-install again"; \
	    rc=1; \
	  done < "$$tmp/$$f"; \
	done; \
	[ "$$rc" -eq 0 ] || { rm -rf "$$tmp"; exit 1; }; \
	if [ -s "$$tmp/personal-identifiers" ]; then \
	  git ls-files -z | xargs -0 grep -nF -f "$$tmp/personal-identifiers" -- 2>/dev/null \
	    | grep -v '^tests/personal-' && rc=1 || true; \
	fi; \
	if [ -s "$$tmp/personal-names" ]; then \
	  git ls-files -z | xargs -0 grep -nwF -f "$$tmp/personal-names" -- 2>/dev/null \
	    | grep -v '^tests/personal-' && rc=1 || true; \
	fi; \
	rm -rf "$$tmp"; \
	[ "$$rc" -eq 0 ] || { echo "personal identifiers found"; exit 1; }
