SHELL := /bin/bash
BATS  ?= bats

.PHONY: test lint lint-shell lint-identifiers check check-bash32

test:
	$(BATS) --recursive tests --filter-tags '!adapter,!worker,!e2e'
	DUX_BACKEND=herdr $(BATS) tests/backend-adapter.bats
	DUX_BACKEND=tmux  $(BATS) tests/backend-adapter.bats
	DUX_WORKER_HARNESS=claude $(BATS) tests/worker-adapter.bats
	DUX_WORKER_HARNESS=codex  $(BATS) tests/worker-adapter.bats
	DUX_BACKEND=herdr DUX_WORKER_HARNESS=claude $(BATS) tests/e2e-dispatch.bats
	DUX_BACKEND=tmux  DUX_WORKER_HARNESS=claude $(BATS) tests/e2e-dispatch.bats

# macOS only: run the whole suite with /bin/bash (3.2) first on PATH, since
# every script's shebang resolves bash through PATH.
check-bash32:
	@mkdir -p tests/tmp/bash32 && ln -sf /bin/bash tests/tmp/bash32/bash
	PATH="$(CURDIR)/tests/tmp/bash32:$$PATH" $(MAKE) test

lint: lint-shell lint-identifiers

lint-shell:
	shellcheck -s bash bin/dux-* bin/backends/*.sh bin/workers/*.sh templates/hooks/pre-push tests/fakes/* tests/helpers/*.bash

# Account names that are also ordinary English words or shared CI defaults. A
# denylist entry equal to one of these is dropped before the search: this repo's
# CI account is named after one of them, and matching it fails every tracked file
# that uses the word normally.
GENERIC_ACCOUNTS := runner ubuntu root admin build ci user vagrant jenkins docker

# tests/personal-identifiers.txt holds paths and project names, matched literally.
# tests/personal-names.txt holds bare account names, matched only as whole words,
# so a name never matches inside a longer word. Both are git-ignored, written by
# bin/dux-install; a missing or empty one is skipped.
lint-identifiers:
	@tmp="$$(mktemp -d)"; rc=0; \
	printf '%s\n' $(GENERIC_ACCOUNTS) > "$$tmp/generic"; \
	for f in personal-identifiers personal-names; do \
	  : > "$$tmp/$$f"; \
	  [ -s "tests/$$f.txt" ] || continue; \
	  grep -v '^$$' "tests/$$f.txt" | grep -vxF -f "$$tmp/generic" > "$$tmp/$$f" || true; \
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
	[ "$$rc" -eq 0 ] || { echo "personal identifiers found"; exit 1; }

check: lint test
