SHELL := /bin/bash
BATS  ?= bats

.PHONY: test lint check

test:
	$(BATS) --recursive tests

lint:
	shellcheck -s bash bin/dux-* bin/backends/*.sh tests/fakes/* tests/helpers/*.bash

check: lint test
