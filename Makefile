SHELL := /bin/bash

VERSION := $(shell tr -d '[:space:]' < VERSION)
PAYLOAD := $(CURDIR)/build/rtide-$(VERSION)
BASH_SOURCES := install.sh \
	bin/rtide bin/rtide-mcp bin/rtide-mem bin/rtide-open \
	bin/rtide-forks \
	bin/rtide-picker \
	bin/rtide-memory-index \
	bin/rtide-progress \
	bin/rtide-provider bin/rtide-tweb-common bin/tweb-render bin/tweb-run \
	scripts/check-version-bump scripts/install-user scripts/rtide-dev \
	scripts/rtide-launcher scripts/stage-package
PYTHON_SOURCES := bin/rtide-agent bin/rtide-dictate bin/rtide-fork-status scripts/bump-version \
	bin/rtide-forks bin/rtide-memory-index scripts/package-tool \
	tests/test-agent-status.py tests/test-fork-manager.py tests/test-memory-index.py \
	tests/test-progress.py

.PHONY: all check test build clean dev install stage verify-install bump-patch bump-minor bump-major

all: build

check:
	bash -n $(BASH_SOURCES)
	python3 -c 'import ast, pathlib; [ast.parse(pathlib.Path(p).read_text(), filename=p) for p in "$(PYTHON_SOURCES)".split()]'
	bash scripts/check-version-bump
	git diff --check

test: check
	./tests/test-picker-contract.sh
	./tests/test-fork-snapshot.sh
	./tests/test-fork-launch-status.sh
	./tests/test-permissions.sh
	./tests/test-output-routing.sh
	./tests/test-fork.sh
	python3 -m unittest tests/test-agent-status.py
	python3 -m unittest tests/test-fork-manager.py
	python3 -m unittest tests/test-memory-index.py
	python3 -m unittest tests/test-progress.py
	./tests/test-installation.sh

build: test
	python3 scripts/package-tool build --root "$(CURDIR)" --build-dir "$(CURDIR)/build" --dist-dir "$(CURDIR)/dist"
	@printf 'BUILD OK: dist/rtide-%s.tar.gz\n' "$(VERSION)"

clean:
	find "$(CURDIR)/build" "$(CURDIR)/dist" -mindepth 1 -delete 2>/dev/null || true
	rmdir "$(CURDIR)/build" "$(CURDIR)/dist" 2>/dev/null || true
	@printf 'CLEAN OK: removed generated build and distribution artifacts\n'

dev:
	bash scripts/rtide-dev "$(or $(DIR),.)" $(ARGS)

install: build
	bash scripts/install-user "$(PAYLOAD)"
	$(MAKE) verify-install

stage: build
	@test -n "$(DESTDIR)" || { echo 'DESTDIR is required: make stage DESTDIR=/tmp/pkg PREFIX=/usr' >&2; exit 2; }
	DESTDIR="$(DESTDIR)" PREFIX="$(or $(PREFIX),/usr/local)" bash scripts/stage-package "$(PAYLOAD)"

verify-install:
	@expected="rtide $(VERSION)"; command="$${RTIDE_BIN_DIR:-$$HOME/.local/bin}/rtide"; actual="$$($$command --version)"; \
	[[ "$$actual" == "$$expected" ]] || { \
		printf 'INSTALL ERROR: got %s, expected %s\n' "$$actual" "$$expected" >&2; exit 1; \
	}; \
	root="$${RTIDE_INSTALL_ROOT:-$$HOME/.local/lib/rtide}"; \
	[[ "$$(readlink "$$root/current")" == "versions/$(VERSION)" ]] || { \
		echo 'INSTALL ERROR: active release link is incorrect' >&2; exit 1; \
	}; \
	printf '%s\nINSTALL OK: immutable release is active\n' "$$actual"

bump-patch:
	python3 scripts/bump-version patch

bump-minor:
	python3 scripts/bump-version minor

bump-major:
	python3 scripts/bump-version major
