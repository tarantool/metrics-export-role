# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

# Look for .rocks/bin directories upward starting from the project
# directory.
#
# It is useful for luacheck and luatest.
#
# Note: The PROJECT_DIR holds a real path.
define ENABLE_ROCKS_BIN
	$(if $(wildcard $1/.rocks/bin),
		$(eval ROCKS_PATH := $(if $(ROCKS_PATH),$(ROCKS_PATH):,)$1/.rocks/bin)
	)
	$(if $1,
		$(eval $(call ENABLE_ROCKS_BIN,$(patsubst %/,%,$(dir $1))))
	)
endef
$(eval $(call ENABLE_ROCKS_BIN,$(PROJECT_DIR)))

# Add found .rocks/bin to PATH.
PATH := $(if $(ROCKS_PATH),$(ROCKS_PATH):$(PATH),$(PATH))

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
