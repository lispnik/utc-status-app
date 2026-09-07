;;;; utc-status-app.asd -- a macOS menu-bar UTC clock, in Common Lisp.
;;;;
;;;; Three systems.  #:utc-status-app is the library, and its formatting half is
;;;; deliberately free of Objective-C so it can be tested without a window
;;;; server.  #:utc-status-app/app builds bin/utc-status.  #:utc-status-app/tests
;;;; is the FiveAM suite.

(asdf:defsystem #:utc-status-app
  :description "A macOS menu-bar clock showing UTC, with ISO 8601 renderings you can copy."
  :long-description
  "An NSStatusItem whose title is the current time in UTC, laid out the way the
system clock is laid out -- the same day-of-week, date and seconds settings, read
from com.apple.menuextra.clock, so it matches whatever the user has chosen.

Clicking it opens a menu of ISO 8601 renderings at descending resolution, from
microseconds to the year.  Choosing one copies that rendering of the current
instant to the clipboard.

Built on the objc bindings rather than on a bridge: the status item, its menu,
the timer and the pasteboard are all Objective-C objects driven from Lisp, and
the menu's actions are Lisp methods on a Lisp-defined class."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:objc #:cffi)
  :components ((:module "src"
                :serial t
                :components
                ((:file "package")
                 (:file "frameworks")
                 (:file "iso")
                 (:file "layout")
                 (:file "clipboard")
                 (:file "app")))))

(asdf:defsystem #:utc-status-app/app
  :description "bin/utc-status, the menu-bar application."
  :depends-on (#:utc-status-app)
  :build-operation "program-op"
  ;; ASDF resolves :BUILD-PATHNAME against the SYSTEM's pathname, so a
  ;; system-level :PATHNAME "src/" would put the binary in src/bin/utc-status.
  ;; The components live in a :MODULE for that reason; see the same note in
  ;; objc.asd.
  :build-pathname "bin/utc-status"
  :entry-point "utc-status-app:main"
  :components ((:module "src"
                :components ((:file "main")))))

;;;; The .app bundle.
;;;;
;;;; A menu-bar application really wants to be a bundle: LSUIElement is what
;;;; tells the Dock and the application switcher to leave it alone, and it lives
;;;; in an Info.plist, which a bare executable does not have.  RUN sets the
;;;; activation policy to Accessory at startup anyway -- that is what makes the
;;;; loose binary work at all -- but doing it in code means the Dock icon exists
;;;; for the instant before the policy is set.  :BUNDLE-AGENT is the same thing
;;;; declared, and declared wins.
;;;;
;;;; Kept separate from #:utc-status-app/app rather than replacing it.  The bare
;;;; binary is what `utc-status --print seconds' is for, and a .app is an awkward
;;;; thing to put in a shell pipeline.
(asdf:defsystem #:utc-status-app/bundle
  :description "UTC Status.app, a menu-bar bundle."
  :defsystem-depends-on ("asdf-macos-app")
  :class :macos-app-system
  :build-operation "macos-app-op"
  :depends-on (#:utc-status-app)
  :entry-point "utc-status-app:main"
  :version "0.1.0"
  :bundle-identifier "com.lispnik.utc-status"
  :bundle-name "UTC Status"
  :bundle-executable "utc-status"
  ;; LSUIElement: no Dock icon, no application menu, but it may have UI.  The
  ;; whole point of a status-bar application.
  :bundle-agent t
  ;; NSPrincipalClass, so AppKit is initialised as it would be for any Cocoa
  ;; application rather than being brought up halfway through our own startup.
  :bundle-principal-class "NSApplication"
  :bundle-category "public.app-category.utilities"
  :bundle-copyright "MIT"
  ;; UNSIGNED, and not by preference.  An SBCL image cannot be codesigned on
  ;; this toolchain at all: SAVE-LISP-AND-DIE appends the core to a Mach-O that
  ;; Homebrew already shipped linker-signed, and codesign then refuses the file
  ;; with "main executable failed strict validation" -- for --sign - as much as
  ;; for a Developer ID, and whether or not the old signature is removed first.
  ;; Measured on SBCL 2.6.8/arm64, on the bare binary as well as in a bundle, so
  ;; it is the image and not this build.
  ;;
  ;; asdf-macos-app names this as the most fragile part of its pipeline and it
  ;; is right.  The bundle still launches -- the dumped executable keeps the
  ;; runtime's own ad hoc signature, which macOS accepts locally -- but it
  ;; cannot be notarised, so it cannot be handed to anyone else.  Set an
  ;; identity here when that is solved upstream; nothing else needs to change.
  :code-signing-identity nil
  :bundle-output-directory "build/"
  :components ((:module "src"
                :components ((:file "main")))))

(asdf:defsystem #:utc-status-app/tests
  :description "The FiveAM suite."
  :depends-on (#:utc-status-app #:fiveam)
  :serial t
  :components ((:module "tests"
                :serial t
                :components
                ((:file "package")
                 (:file "iso-tests")
                 (:file "layout-tests")
                 (:file "app-tests"))))
  ;; FIVEAM:RUN! prints failures but returns NIL, and ASDF discards what a
  ;; TEST-OP returns -- which is how a suite goes green with failing tests.
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call :utc-status-app/tests :run-tests)
               (error "The test suite failed."))))
