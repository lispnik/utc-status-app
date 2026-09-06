;;;; tests/package.lisp

(defpackage #:utc-status-app/tests
  (:use #:common-lisp #:fiveam)
  (:export #:all-tests #:run-tests))

(in-package #:utc-status-app/tests)

(def-suite all-tests :description "Everything.")

(defun run-tests ()
  "Run the suite and return T when it passed.

FIVEAM:RUN! prints failures and returns NIL, and ASDF discards what a TEST-OP
returns, so a suite driven by RUN! alone goes green with failing tests.  The
.asd calls this and signals on NIL."
  (let ((results (run 'all-tests)))
    (explain! results)
    (results-status results)))
