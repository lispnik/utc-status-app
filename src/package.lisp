;;;; src/package.lisp

(defpackage #:utc-status-app
  (:use #:common-lisp)
  (:export
   ;; The pure half: instants in, ISO 8601 strings out.  No Objective-C here,
   ;; which is what lets the suite run anywhere.
   #:now
   #:instant #:instant-seconds #:instant-microseconds #:make-instant
   #:+renderings+
   #:rendering #:rendering-key #:rendering-label #:rendering-description
   #:find-rendering #:render #:render-now
   ;; Matching the system clock's layout.
   #:clock-preferences #:clock-skeleton #:normalise-pattern #:menu-bar-title
   ;; The clipboard.
   #:copy-to-clipboard #:clipboard-string
   ;; The application.
   #:run #:main #:*label*))
