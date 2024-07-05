# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

SHELL := $(shell which bash)
SEED ?= $(shell /bin/bash -c "echo $$RANDOM")

all: test

check: luacheck

luacheck:
	luacheck --config .luacheckrc --codes .

.PHONY: test
test:
	luatest -v --shuffle all:${SEED}

deps:
	tt rocks install luatest 1.0.1
	tt rocks install luacheck 0.26.0
	tt rocks make
