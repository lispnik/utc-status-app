# Makefile for utc-status-app.
#
#   make            build bin/utc-status
#   make test       run the FiveAM suite
#   make run        build and run the application
#   make deps       restore ocicl-vendored dependencies
#   make repl       an SBCL with the library loaded
#   make clean      remove the binary, fasls, and this tree's ASDF cache
#
# The objc bindings are not on ocicl -- they are a sibling checkout -- so every
# target builds a source registry from this tree plus that one.  OBJC_DIR
# overrides where it looks.

LISP ?= sbcl
OBJC_DIR ?= $(HOME)/Projects/common-lisp/objc

# :IGNORE-INHERITED-CONFIGURATION so a missing dependency fails here rather than
# resolving to whatever happens to be in the developer's ~/.sbclrc -- the same
# reason objc's own Makefile does it.  ocicl/ is vendored per-tree, so both
# trees' ocicl directories go in.
REGISTRY = (asdf:initialize-source-registry \
              (list :source-registry \
                    (list :tree (truename "./")) \
                    (list :tree (truename "$(OBJC_DIR)")) \
                    :ignore-inherited-configuration))

.PHONY: all build test test-clipboard run deps repl clean

all: build

build: bin/utc-status

bin/utc-status: utc-status-app.asd $(wildcard src/*.lisp)
	@mkdir -p bin
	$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:make :utc-status-app/app)'
	@echo "built $@"

test:
	$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :utc-status-app/tests)' \
	  --eval '(uiop:quit (if (utc-status-app/tests:run-tests) 0 1))'

# The clipboard tests overwrite the pasteboard of whoever runs them, so they are
# opt-in rather than part of `make test'.
test-clipboard:
	UTC_STATUS_TEST_CLIPBOARD=1 $(MAKE) test

run: build
	./bin/utc-status

deps:
	ocicl install

repl:
	$(LISP) --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :utc-status-app)'

clean:
	rm -f bin/utc-status
	rm -rf *.fasl
	rm -rf $(HOME)/.cache/common-lisp/*/$(CURDIR)
