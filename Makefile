# Makefile for utc-status-app.
#
#   make            build bin/utc-status
#   make test       run the FiveAM suite
#   make env        print what the layout code decided on this machine
#   make run        build and run the application
#   make deps       restore ocicl-vendored dependencies
#   make repl       an SBCL with the library loaded
#   make install    copy the binary to $(PREFIX)/bin
#   make install-agent    install and start it at login, via launchd
#   make uninstall-agent  stop it and remove the LaunchAgent
#   make agent-status     what launchd thinks of it
#   make clean      remove the binary, fasls, and this tree's ASDF cache
#
# The objc bindings are not on ocicl -- they are a sibling checkout -- so every
# target builds a source registry from this tree plus that one.  OBJC_DIR
# overrides where it looks.

LISP ?= sbcl
OBJC_DIR ?= $(HOME)/Projects/common-lisp/objc

PREFIX ?= $(HOME)/.local
LOGS ?= $(HOME)/Library/Logs
LABEL = com.lispnik.utc-status
AGENT_DIR = $(HOME)/Library/LaunchAgents
AGENT = $(AGENT_DIR)/$(LABEL).plist
# launchd's per-user GUI domain.  `gui/<uid>' and not `user/<uid>': the latter
# exists whether or not anyone is logged in graphically, and a status item put
# there has no menu bar to appear in.
DOMAIN = gui/$(shell id -u)

# :IGNORE-INHERITED-CONFIGURATION so a missing dependency fails here rather than
# resolving to whatever happens to be in the developer's ~/.sbclrc -- the same
# reason objc's own Makefile does it.  ocicl/ is vendored per-tree, so both
# trees' ocicl directories go in.
REGISTRY = (asdf:initialize-source-registry \
              (list :source-registry \
                    (list :tree (truename "./")) \
                    (list :tree (truename "$(OBJC_DIR)")) \
                    :ignore-inherited-configuration))

.PHONY: all build test test-clipboard run deps repl env clean \
        install uninstall install-agent uninstall-agent agent-status

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

# What the layout code decided on this machine.  Its own target so CI can report
# it in one line, and so the source registry is defined once rather than being
# spelled out again in a workflow.
env:
	@$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :utc-status-app)' \
	  --eval '(format t "~&machine:     ~A~%lisp:        ~A ~A~%preferences: ~S~%skeleton:    ~S~%title:       ~S~%" (machine-type) (lisp-implementation-type) (lisp-implementation-version) (utc-status-app:clock-preferences) (utc-status-app:clock-skeleton) (utc-status-app:menu-bar-title))'

repl:
	$(LISP) --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :utc-status-app)'

# Installing ------------------------------------------------------------------
#
# The agent points at $(PREFIX)/bin rather than at ./bin, so that `make clean'
# -- or moving this checkout -- does not leave launchd trying to start a binary
# that is no longer there.

install: build
	@mkdir -p $(PREFIX)/bin
	cp bin/utc-status $(PREFIX)/bin/utc-status
	@echo "installed $(PREFIX)/bin/utc-status"

uninstall:
	rm -f $(PREFIX)/bin/utc-status

$(AGENT): etc/$(LABEL).plist.in
	@mkdir -p $(AGENT_DIR) $(LOGS)
	sed -e 's|@BINARY@|$(PREFIX)/bin/utc-status|g' \
	    -e 's|@LOGS@|$(LOGS)|g' \
	    etc/$(LABEL).plist.in > $@
	@plutil -lint $@

# bootout before bootstrap, and ignore its failure: bootstrapping a label that
# is already loaded is an error ("service already loaded"), so an install that
# cannot be repeated is an install that breaks the second time you run it.
install-agent: install $(AGENT)
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	launchctl bootstrap $(DOMAIN) $(AGENT)
	@echo "loaded $(LABEL); it will start at login, and is running now"
	@echo "logs: $(LOGS)/utc-status.log"

uninstall-agent:
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	rm -f $(AGENT)
	@echo "removed $(LABEL)"

agent-status:
	@launchctl print $(DOMAIN)/$(LABEL) 2>/dev/null \
	  | grep -E "state|program|last exit|runs" \
	  || echo "$(LABEL) is not loaded"

clean:
	rm -f bin/utc-status
	rm -rf *.fasl
	rm -rf $(HOME)/.cache/common-lisp/*/$(CURDIR)
