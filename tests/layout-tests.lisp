;;;; tests/layout-tests.lisp -- the menu-bar layout, and the clipboard.
;;;;
;;;; Split from the ISO tests because these need macOS: the skeleton is pure and
;;;; always runs, the rest touches NSDateFormatter and NSPasteboard.  The
;;;; pasteboard tests are gated, because the general pasteboard is the user's --
;;;; a suite that overwrites it during an ordinary `make test' has destroyed
;;;; something it was never asked to touch.

(in-package #:utc-status-app/tests)

(def-suite layout :in all-tests :description "Menu-bar layout and the clipboard.")
(in-suite layout)

(test the-skeleton-asks-for-exactly-the-fields-configured
  "A Unicode skeleton is an unordered set of the fields wanted, and the locale
decides the order and the punctuation -- so this checks membership, which is all
a skeleton means.

`j' rather than `H' or `h' is the assertion that matters.  It is the field that
means \"whichever hour cycle this locale uses\", so it follows the 24-Hour Time
switch; either of the other two hard-codes a cycle and quietly ignores the user's
choice forever."
  (flet ((skeleton (&rest preferences)
           (utc-status-app:clock-skeleton preferences)))
    (is (string= "EEEjmm" (skeleton :day-of-week t :date nil :seconds nil)))
    (is (string= "jmm" (skeleton :day-of-week nil :date nil :seconds nil)))
    (is (string= "EEEMMMdjmmss" (skeleton :day-of-week t :date t :seconds t)))
    (is (string= "MMMdjmm" (skeleton :day-of-week nil :date t :seconds nil)))
    (is (string= "jmmss" (skeleton :day-of-week nil :date nil :seconds t))))
  (dolist (preferences '((:day-of-week t :date t :seconds t)
                         (:day-of-week nil :date nil :seconds nil)))
    (let ((skeleton (utc-status-app:clock-skeleton preferences)))
      (is (search "j" skeleton) "the hour field must be j, not H or h: ~S" skeleton)
      (is (not (find #\H skeleton)) "H would force 24-hour: ~S" skeleton)
      (is (not (find #\h skeleton)) "h would force 12-hour: ~S" skeleton))))

(test the-preferences-read-as-booleans
  "Whatever this Mac is set to, the three answers have to be generalised
booleans -- a nil-vs-absent confusion here shows up as a missing field in the
menu bar and nowhere else."
  (progn
    (let ((preferences (utc-status-app:clock-preferences)))
      (is (member (getf preferences :day-of-week) '(t nil)))
      (is (member (getf preferences :date) '(t nil)))
      (is (member (getf preferences :seconds) '(t nil))))))

(test the-menu-bar-title-is-utc-and-not-local
  "The assertion the whole application rests on.  The title is compared against
the same instant formatted by the same formatter in UTC, so this fails if the
formatter's timezone is ever left at the system's -- which is the default, and
would be invisible to anyone in Britain in winter."
  (progn
    (let* ((instant (utc-status-app:make-instant 1788644823 0))
           (title (utc-status-app:menu-bar-title instant)))
      (is (plusp (length title)))
      ;; 21:47 UTC.  In a 24-hour locale the hour is written 21; in a 12-hour one
      ;; it is 9 with a PM marker.  Either is fine -- what is not fine is the
      ;; local hour, which on this machine is neither.
      (is (or (search "21" title) (search "9" title))
          "~S does not contain the UTC hour" title))))

(test the-formatter-is-built-once
  "It is asked for twice a second, and rebuilding an NSDateFormatter that often
is the kind of waste that only shows up as battery."
  (progn
    (let ((first (utc-status-app:menu-bar-title))
          (second (utc-status-app::ensure-formatter))
          (third (utc-status-app::ensure-formatter)))
      (declare (ignore first))
      (is (cffi:pointer-eq (objc:objc-object-pointer second)
                           (objc:objc-object-pointer third))
          "ENSURE-FORMATTER handed back a different formatter the second time"))))

;;; The clipboard --------------------------------------------------------------------
;;;
;;; Gated behind an environment variable.  The general pasteboard belongs to
;;; whoever is at the keyboard, and a test suite that overwrites it has thrown
;;; away whatever they had copied -- which is exactly the sort of small rudeness
;;; that makes people stop running the tests.

(defun clipboard-tests-allowed-p ()
  (let ((value (uiop:getenv "UTC_STATUS_TEST_CLIPBOARD")))
    (and value (string/= value "") (string/= value "0"))))

(test copying-puts-the-rendering-on-the-pasteboard
  "Skipped unless UTC_STATUS_TEST_CLIPBOARD is set, because it overwrites the
clipboard of whoever runs it."
  (if (not (clipboard-tests-allowed-p))
      (skip "set UTC_STATUS_TEST_CLIPBOARD=1 to let the suite use the clipboard")
      (progn
        (let ((text (utc-status-app:render
                     (utc-status-app:make-instant 1788644823 123456) :microseconds)))
          (utc-status-app:copy-to-clipboard text)
          (is (string= text (utc-status-app:clipboard-string))
              "what came back off the pasteboard is not what went on")))))

(test the-pattern-loses-its-prose-connectives
  "+dateFormatFromTemplate: writes a pattern for prose -- \"EEE, MMM d 'at'
HH:mm\" -- and the menu bar writes \"Sat Sep 5  21:00\".  The difference is a
comma and a quoted word, and both come out.

Stripping every QUOTED literal rather than the English word \"at\" is what makes
it work elsewhere: German joins with 'um', French with 'a'.  Pure, so every case
here is checked without asking macOS for anything."
  (is (string= "EEE MMM d  HH:mm"
               (utc-status-app:normalise-pattern "EEE, MMM d 'at' HH:mm"))
      "the two spaces are the gap the menu bar leaves before the time")
  (is (string= "EEE HH:mm" (utc-status-app:normalise-pattern "EEE HH:mm"))
      "a pattern with no connectives is left alone")
  (is (string= "EEE MMM d  HH:mm:ss"
               (utc-status-app:normalise-pattern "EEE, MMM d 'at' HH:mm:ss")))
  (is (string= "d MMMM  HH:mm" (utc-status-app:normalise-pattern "d MMMM 'um' HH:mm"))
      "German joins with a different word, and the rule is quoting, not the word")
  (is (string= "HH'h'" (utc-status-app:normalise-pattern "HH''h''"))
      "a doubled quote is an escaped apostrophe and survives")
  (is (string= "" (utc-status-app:normalise-pattern "'at'"))
      "a pattern that is nothing but a literal comes back empty rather than looping"))
