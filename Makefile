# Makefile for utc-status-app.
#
#   make            build bin/utc-status
#   make app        build "build/UTC Status.app"
#   make test       run the FiveAM suite
#   make env        print what the layout code decided on this machine
#   make run        build and run the application
#   make deps       restore ocicl-vendored dependencies
#   make repl       an SBCL with the library loaded
#   make install    copy the binary to $(PREFIX)/bin
#   make notarize         submit the signed bundle to Apple and staple the ticket
#   make install-app      copy the bundle to $(APPS)
#   make install-agent    install and start it at login, via launchd
#   make install-app-agent  the same, but starting the .app bundle
#   make uninstall-agent  stop it and remove the LaunchAgent
#   make agent-status     what launchd thinks of it
#   make clean      remove the binary, fasls, and this tree's ASDF cache
#
# The objc bindings are not on ocicl -- they are a sibling checkout -- so every
# target builds a source registry from this tree plus that one.  OBJC_DIR
# overrides where it looks.

LISP ?= sbcl
OBJC_DIR ?= $(HOME)/Projects/common-lisp/objc
MACOS_APP_DIR ?= $(HOME)/Projects/common-lisp/asdf-macos-app

PREFIX ?= $(HOME)/.local
APPS ?= $(HOME)/Applications
# What the LaunchAgent will start.  The plain binary by default; `make
# install-app-agent' points it at the bundle instead.
EXEC ?= $(PREFIX)/bin/utc-status
LOGS ?= $(HOME)/Library/Logs
LABEL = com.lispnik.utc-status
# The notarytool keychain profile, stored once with
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) \
#     --apple-id <you> --team-id <your team>
# which prompts for an app-specific password from appleid.apple.com -- not your
# Apple ID password.
NOTARY_PROFILE ?= utc-status
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
                    (list :tree (truename "$(MACOS_APP_DIR)")) \
                    :ignore-inherited-configuration))

.PHONY: agent-plist icon notarize all build app test test-clipboard run deps repl env clean \
        install uninstall install-app install-agent install-app-agent \
        uninstall-agent agent-status

all: build

build: bin/utc-status

# "build/UTC Status.app" cannot be a Make target: the space makes it two words to
# every rule.  So the bundle is phony and its freshness is tracked by a stamp,
# which is also what keeps `make app' from rebuilding a 46MB image every time.
APP = build/UTC Status.app
APP_STAMP = build/.app-stamp

app: $(APP_STAMP)

$(APP_STAMP): utc-status-app-bundle.asd $(wildcard src/*.lisp) res/icon.png
	$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:make :utc-status-app-bundle)'
	@touch $(APP_STAMP)
	@echo "built $(APP)"

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
# The icon is drawn by tools/icon.lisp, using the objc bindings this application
# is built on -- so there is no checked-in artwork and no asset pipeline, and
# changing it is an edit.
res/icon.png: tools/icon.lisp
	@mkdir -p res
	$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :objc)' \
	  --load tools/icon.lisp \
	  --eval '(utc-status-icon:render-icon "res/icon.png")'
	@echo "drew res/icon.png"

icon: res/icon.png

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

# Submit to Apple's notary service and staple the ticket into the bundle.
#
# The two guards are here because both failures are slow and neither is obvious.
# An AD HOC signature is refused by Apple, but only after the upload; and a
# runtime that links Homebrew's libzstd notarises PERFECTLY WELL and then dies
# with a dyld error on a Mac that has no Homebrew -- Apple checks the signature,
# not whether your dylibs exist on someone else's disk.  Both are cheap to check
# here and expensive to discover later.
notarize: app
	@codesign -dvv "$(APP)" 2>&1 | grep -q adhoc && { \
	  echo "error: $(APP) is signed ad hoc, and Apple will refuse it." >&2; \
	  echo "  set :code-signing-identity to a Developer ID in utc-status-app-bundle.asd" >&2; \
	  exit 1; } || true
	@otool -L "$(APP)/Contents/MacOS/utc-status" | tail -n +2 \
	  | grep -v "^\s*/usr/lib/\|^\s*/System/" | grep . && { \
	  echo "error: the executable links something outside /usr/lib and /System." >&2; \
	  echo "  it will notarise and then fail to launch elsewhere; rebuild SBCL" >&2; \
	  echo "  --without-sb-core-compression" >&2; \
	  exit 1; } || true
	$(LISP) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :asdf-macos-app)' \
	  --eval '(macos-app:notarize "$(APP)" :keychain-profile "$(NOTARY_PROFILE)")'
	@echo
	@echo "Gatekeeper:"
	@spctl -a -vvv -t install "$(APP)"
	@xcrun stapler validate "$(APP)"

install-app: app
	@mkdir -p "$(APPS)"
	rm -rf "$(APPS)/UTC Status.app"
	cp -R "$(APP)" "$(APPS)/"
	@echo "installed $(APPS)/UTC Status.app"

# Phony rather than a file target: the plist's contents depend on EXEC, which is
# a variable and not a prerequisite, so a file target would happily keep a plist
# pointing at whatever was installed first.
agent-plist:
	@mkdir -p $(AGENT_DIR) $(LOGS)
	sed -e 's|@BINARY@|$(EXEC)|g' \
	    -e 's|@LOGS@|$(LOGS)|g' \
	    etc/$(LABEL).plist.in > $(AGENT)
	@plutil -lint $(AGENT)

# bootout before bootstrap, and ignore its failure: bootstrapping a label that
# is already loaded is an error ("service already loaded"), so an install that
# cannot be repeated is an install that breaks the second time you run it.
install-agent: install agent-plist
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	launchctl bootstrap $(DOMAIN) $(AGENT)
	@echo "loaded $(LABEL); it will start at login, and is running now"
	@echo "logs: $(LOGS)/utc-status.log"

# The bundle rather than the bare binary: same launchd machinery, and the app
# gets LSUIElement from its Info.plist rather than only from the activation
# policy set at startup.
install-app-agent: install-app
	@$(MAKE) agent-plist EXEC="$(APPS)/UTC Status.app/Contents/MacOS/utc-status"
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	launchctl bootstrap $(DOMAIN) $(AGENT)
	@echo "loaded $(LABEL), starting the bundle at login"

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
	rm -rf build
	rm -rf *.fasl
	rm -rf $(HOME)/.cache/common-lisp/*/$(CURDIR)
