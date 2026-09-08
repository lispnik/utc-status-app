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
   #:clock-preferences #:effective-preferences #:preference
   #:clock-skeleton #:normalise-pattern #:menu-bar-title
   #:+seconds-key+ #:+label-key+
   ;; Starting at login.
   #:login-item-status #:login-item-available-p
   #:register-login-item #:unregister-login-item #:bundle-path
   ;; The clipboard.
   #:copy-to-clipboard #:clipboard-string
   ;; The application.
   #:run #:main #:*label*))
