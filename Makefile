SHELL := /bin/bash

VERSION := $(shell tr -d '[:space:]' < VERSION)
PAYLOAD := $(CURDIR)/build/rtide-$(VERSION)
BASH_SOURCES := install.sh \
	bin/rtide bin/rtide-mcp bin/rtide-mem bin/rtide-open \
	bin/rtide-provider bin/rtide-tweb-common bin/tweb-render bin/tweb-run \
	scripts/check-version-bump scripts/install-user scripts/rtide-dev \
	scripts/rtide-launcher scripts/stage-package
PYTHON_SOURCES := bin/rtide-agent bin/rtide-dictate scripts/bump-version \
	scripts/package-tool tests/test-agent-status.py

.PHONY: all check test build dev install stage verify-install bump-patch bump-minor bump-major

all: build

check:
	bash -n $(BASH_SOURCES)
	python3 -c 'import ast, pathlib; [ast.parse(pathlib.Path(p).read_text(), filename=p) for p in "$(PYTHON_SOURCES)".split()]'
	bash scripts/check-version-bump
	git diff --check

test: check
	./tests/test-output-routing.sh
	./tests/test-fork.sh
	python3 -m unittest tests/test-agent-status.py
	./tests/test-installation.sh

build: test
	python3 scripts/package-tool build --root "$(CURDIR)" --build-dir "$(CURDIR)/build" --dist-dir "$(CURDIR)/dist"
	@printf 'BUILD OK: dist/rtide-%s.tar.gz\n' "$(VERSION)"

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
