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
  :version "0.2.0"
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
