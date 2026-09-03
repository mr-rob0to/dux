SHELL := /bin/bash
BATS  ?= bats

.PHONY: test lint check

test:
	$(BATS) --recursive tests --filter-tags '!adapter'
	DUX_BACKEND=herdr $(BATS) tests/backend-adapter.bats
	DUX_BACKEND=tmux  $(BATS) tests/backend-adapter.bats

lint:
	shellcheck -s bash bin/dux-* bin/backends/*.sh tests/fakes/* tests/helpers/*.bash

check: lint test
