SHELL := /bin/bash
BATS  ?= bats

.PHONY: test lint lint-shell lint-identifiers check

test:
	$(BATS) --recursive tests --filter-tags '!adapter'
	DUX_BACKEND=herdr $(BATS) tests/backend-adapter.bats
	DUX_BACKEND=tmux  $(BATS) tests/backend-adapter.bats

lint: lint-shell lint-identifiers

lint-shell:
	shellcheck -s bash bin/dux-* bin/backends/*.sh templates/hooks/pre-push tests/fakes/* tests/helpers/*.bash

lint-identifiers:
	@if [ -s tests/personal-identifiers.txt ]; then \
	  git ls-files -z | xargs -0 grep -nF -f tests/personal-identifiers.txt -- 2>/dev/null \
	    | grep -v '^tests/personal-identifiers.txt' && { echo "personal identifiers found"; exit 1; } || true; \
	fi

check: lint test
