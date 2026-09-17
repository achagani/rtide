SHELL := /bin/bash

VERSION := $(shell tr -d '[:space:]' < VERSION)
PAYLOAD := $(CURDIR)/build/rtide-$(VERSION)
BASH_SOURCES := install.sh \
	bin/rtide \
	libexec/rtide/mcp libexec/rtide/memory libexec/rtide/open \
	libexec/rtide/pane-popup libexec/rtide/picker.sh \
	libexec/rtide/ui.sh \
	libexec/rtide/provider libexec/rtide/render libexec/rtide/run \
	libexec/rtide/tweb-common.sh libexec/rtide/runtime-paths.sh \
	libexec/rtide/guard-bin/tweb \
	libexec/rtide/uninstall \
	scripts/check-version-bump scripts/install-user scripts/rtide-dev \
	scripts/rtide-launcher scripts/stage-package scripts/install-deps \
	scripts/install-voice scripts/install-lazyvim scripts/install-tweb
PYTHON_SOURCES := libexec/rtide/agent libexec/rtide/composer.py libexec/rtide/dictate \
 libexec/rtide/output-controls tests/test-output-controls.py \
 scripts/install-tmux tests/test-install-tmux.py \
	libexec/rtide/fork-status libexec/rtide/forks libexec/rtide/memory-index \
	libexec/rtide/progress libexec/rtide/settings libexec/rtide/workspace-status \
	libexec/rtide/deps scripts/bump-version scripts/package-tool \
	tests/test-agent-status.py tests/test-composer.py tests/test-fork-manager.py \
	tests/test-memory-index.py tests/test-progress.py tests/test-workspace-status.py \
	tests/test-deps.py

.PHONY: all check test build clean dev install stage verify-install bump-patch bump-minor bump-major

all: build

check:
	bash -n $(BASH_SOURCES)
	python3 -c 'import ast, pathlib; [ast.parse(pathlib.Path(p).read_text(), filename=p) for p in "$(PYTHON_SOURCES)".split()]'
	bash scripts/check-version-bump
	git diff --check

test: check
	python3 tests/test-output-controls.py
	python3 tests/test-settings.py
	python3 tests/test-deps.py
	python3 tests/test-install-tmux.py
	./tests/test-picker-contract.sh
	./tests/test-tui-design.sh
	./tests/test-review-startup.sh
	./tests/test-runtime-sockets.sh
	./tests/test-autoinit-safety.sh
	./tests/test-fork-snapshot.sh
	./tests/test-fork-launch-status.sh
	./tests/test-pane-popup-safety.sh
	./tests/test-permissions.sh
	./tests/test-libexec-isolation.sh
	./tests/test-output-routing.sh
	./tests/test-tweb-recovery.sh
	./tests/test-fork.sh
	python3 -m unittest tests/test-fork-menu-e2e.py
	python3 -m unittest tests/test-agent-status.py
	python3 -m unittest tests/test-composer.py
	./tests/test-provider.sh
	python3 -m unittest tests/test-fork-manager.py
	python3 -m unittest tests/test-memory-index.py
	python3 -m unittest tests/test-progress.py
	python3 -m unittest tests/test-workspace-status.py
	./tests/test-installation.sh

build: test
	python3 scripts/package-tool build --root "$(CURDIR)" --build-dir "$(CURDIR)/build" --dist-dir "$(CURDIR)/dist"
	@printf 'BUILD OK: dist/rtide-%s.tar.gz\n' "$(VERSION)"

clean:
	find "$(CURDIR)/build" "$(CURDIR)/dist" -mindepth 1 -delete 2>/dev/null || true
	rmdir "$(CURDIR)/build" "$(CURDIR)/dist" 2>/dev/null || true
	@printf 'CLEAN OK: removed generated build and distribution artifacts\n'

dev:
	RTIDE_DEV_PERMISSION_POLICY="$(or $(PERMISSION),unrestricted)" bash scripts/rtide-dev "$(or $(DIR),.)" $(ARGS)

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
