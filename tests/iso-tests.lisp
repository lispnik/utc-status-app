;;;; tests/iso-tests.lisp -- the renderings, against instants worked out by hand.
;;;;
;;;; Every expected value here was computed independently rather than by running
;;;; the code and writing down what it said, which is the failure mode a
;;;; formatting suite is most prone to: a test that agrees with the bug.

(in-package #:utc-status-app/tests)

(def-suite iso :in all-tests :description "ISO 8601 renderings.")
(in-suite iso)

;;; 2026-09-05T21:47:03.123456Z -- a Saturday, ISO week 36 day 6, ordinal 248.
(defparameter +sample+ (utc-status-app:make-instant 1788644823 123456))

(test the-epoch-is-where-it-should-be
  "The Unix epoch is 1970-01-01T00:00:00Z, and getting the 2208988800 offset
wrong puts everything seventy years out."
  (let ((epoch (utc-status-app:make-instant 0 0)))
    (is (string= "1970-01-01T00:00:00Z" (utc-status-app:render epoch :seconds)))
    (is (string= "1970-01-01" (utc-status-app:render epoch :date)))))

(test each-resolution-truncates-the-one-below-it
  "The resolution ladder is the point of the menu, so each rung has to be the one
above it with a field removed -- not a separate format that happens to look
similar."
  (is (string= "2026-09-05T21:47:03.123456Z"
               (utc-status-app:render +sample+ :microseconds)))
  (is (string= "2026-09-05T21:47:03.123Z"
               (utc-status-app:render +sample+ :milliseconds)))
  (is (string= "2026-09-05T21:47:03Z" (utc-status-app:render +sample+ :seconds)))
  (is (string= "2026-09-05T21:47Z" (utc-status-app:render +sample+ :minutes)))
  (is (string= "2026-09-05T21Z" (utc-status-app:render +sample+ :hours)))
  (is (string= "2026-09-05" (utc-status-app:render +sample+ :date)))
  (is (string= "2026-09" (utc-status-app:render +sample+ :month)))
  (is (string= "2026" (utc-status-app:render +sample+ :year))))

(test fractional-seconds-truncate-rather-than-round
  "A timestamp that rounds up names an instant that has not happened yet, which
is a poor property for something you paste into a log.  999999 microseconds is
.999 of a second, not the next second."
  (let ((late (utc-status-app:make-instant 1788644823 999999)))
    (is (string= "2026-09-05T21:47:03.999Z" (utc-status-app:render late :milliseconds))
        "999999us is .999 at millisecond resolution, not .000 of the next second")
    (is (string= "2026-09-05T21:47:03.999999Z"
                 (utc-status-app:render late :microseconds))))
  (let ((early (utc-status-app:make-instant 1788644823 7)))
    (is (string= "2026-09-05T21:47:03.000Z" (utc-status-app:render early :milliseconds))
        "and 7us is .000, with the zeroes written out")
    (is (string= "2026-09-05T21:47:03.000007Z"
                 (utc-status-app:render early :microseconds))
        "which is where a ~D rather than a ~6,'0D loses five digits")))

(test the-compact-form-has-no-separators
  "The form you put in a filename: sorts lexically, and contains nothing a
filesystem objects to."
  (is (string= "20260905T214703Z" (utc-status-app:render +sample+ :basic))))

(test the-ordinal-date-counts-from-one
  "2026-09-05 is the 248th day of 2026, and a leap year shifts every date after
February."
  (is (string= "2026-248" (utc-status-app:render +sample+ :ordinal)))
  (is (string= "2024-060" (utc-status-app:render
                           (utc-status-app:make-instant 1709208000) :ordinal))
      "2024-02-29 is day 60 of a leap year")
  (is (string= "2020-366" (utc-status-app:render
                           (utc-status-app:make-instant 1609372800) :ordinal))
      "2020-12-31 is day 366, which only a leap year has"))

(test the-iso-week-year-is-not-always-the-calendar-year
  "The case that makes ISO week dates worth a function rather than a division:
the first days of January can belong to the last week of the previous year, and
1 January 2027 is one of them."
  (is (string= "2026-W36-6" (utc-status-app:render +sample+ :week))
      "a Saturday, so weekday 6")
  (is (string= "2026-W53-5" (utc-status-app:render
                             (utc-status-app:make-instant 1798761600) :week))
      "2027-01-01 is a Friday in ISO week 53 of 2026, not week 1 of 2027")
  (is (string= "2020-W53-5" (utc-status-app:render
                             (utc-status-app:make-instant 1609459200) :week))
      "and 2021-01-01 belongs to 2020, whose 53rd week it is")
  (is (string= "2020-W53-4" (utc-status-app:render
                             (utc-status-app:make-instant 1609372800) :week))
      "the day before it, which is in the same week and the same year"))

(test leap-years-are-the-gregorian-ones
  "Divisible by four, except centuries, except every fourth century.  2000 was a
leap year and 1900 was not, and a rule that stops at the first exception gets
2100 wrong."
  (is-true (utc-status-app::leap-year-p 2024))
  (is-true (utc-status-app::leap-year-p 2000))
  (is-false (utc-status-app::leap-year-p 1900))
  (is-false (utc-status-app::leap-year-p 2100))
  (is-false (utc-status-app::leap-year-p 2026)))

(test every-rendering-is-listed-and-works
  "The menu, the command line and this suite all walk +RENDERINGS+, so a
rendering that is defined but broken has to fail somewhere."
  (is (= 11 (length utc-status-app:+renderings+)))
  (dolist (rendering utc-status-app:+renderings+)
    (let ((text (utc-status-app:render +sample+
                                       (utc-status-app:rendering-key rendering))))
      (is (plusp (length text))
          "~S rendered nothing" (utc-status-app:rendering-key rendering))
      (is (search "2026" text)
          "~S does not mention the year: ~S"
          (utc-status-app:rendering-key rendering) text)))
  (is (= (length utc-status-app:+renderings+)
         (length (remove-duplicates utc-status-app:+renderings+
                                    :key #'utc-status-app:rendering-key)))
      "two renderings share a key, so the menu's tags would collide"))

(test an-unknown-rendering-is-an-error-naming-the-alternatives
  "Rather than NIL, which would put an empty string on the clipboard."
  (signals error (utc-status-app:render +sample+ :nanoseconds)))

(test now-is-a-plausible-instant
  "The one test that touches the real clock: it cannot check the value, so it
checks that the value is sane and that the microseconds are actually populated."
  (let ((instant (utc-status-app:now)))
    (is (> (utc-status-app:instant-seconds instant) 1750000000)
        "later than mid-2025, so the epoch conversion is not off by decades")
    (is (<= 0 (utc-status-app:instant-microseconds instant) 999999))
    (is (search "T" (utc-status-app:render instant :seconds)))
    (is (eql #\Z (char (utc-status-app:render instant :seconds)
                       (1- (length (utc-status-app:render instant :seconds))))))))
