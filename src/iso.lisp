;;;; src/iso.lisp -- instants, and ISO 8601 renderings of them.
;;;;
;;;; The half of this application with no Objective-C in it.  Everything here is
;;;; a pure function of an instant, which is what lets the suite check the
;;;; formatting on any machine, in any timezone, without a window server -- and
;;;; it is why the renderings are a table rather than a COND inside the menu
;;;; handler.
;;;;
;;;; EVERYTHING IS UTC.  There is no timezone parameter and no local time
;;;; anywhere: DECODE-UNIVERSAL-TIME is always called with a zone of 0.  A clock
;;;; that is sometimes local is worse than no clock, and the point of this
;;;; application is that the number in the menu bar is the one you would put in a
;;;; log or a commit message.
;;;;
;;;; CL's universal time is seconds since 1900-01-01, and the system clock is
;;;; seconds since 1970-01-01.  The difference is 2208988800 and forgetting it
;;;; puts you 70 years out -- far enough that it is obvious, unlike a timezone
;;;; error, which is not.

(in-package #:utc-status-app)

(defconstant +unix-epoch-in-universal-time+ 2208988800
  "Universal time at 1970-01-01T00:00:00Z, for converting the system clock.")

;;; An instant ------------------------------------------------------------------

(defstruct (instant (:constructor make-instant (seconds &optional (microseconds 0))))
  "A point in time: SECONDS since the Unix epoch, plus MICROSECONDS.

Split rather than a rational so the fractional renderings can truncate rather
than round -- a timestamp that rounds up can name an instant that has not
happened yet, which is a poor property for something you paste into a log."
  (seconds 0 :type integer)
  (microseconds 0 :type (integer 0 999999)))

(defun now ()
  "The current instant, to microsecond resolution.

SB-EXT:GET-TIME-OF-DAY rather than GET-UNIVERSAL-TIME, which has a resolution of
one second and so cannot serve the two fractional renderings."
  (multiple-value-bind (seconds microseconds) (sb-ext:get-time-of-day)
    (make-instant seconds microseconds)))

(defun instant-parts (instant)
  "INSTANT decoded in UTC.

Returns (VALUES SECOND MINUTE HOUR DAY MONTH YEAR ISO-WEEKDAY), where the
weekday is 1 for Monday through 7 for Sunday, as ISO 8601 numbers them.  Common
Lisp's own day-of-week is 0 for Monday, which is the same order and off by one
-- a difference small enough to be worth converting once, here, rather than
remembering at each use."
  (multiple-value-bind (second minute hour day month year day-of-week)
      (decode-universal-time (+ (instant-seconds instant)
                                +unix-epoch-in-universal-time+)
                             0)
    (values second minute hour day month year (1+ day-of-week))))

;;; Calendar arithmetic the ISO renderings need ------------------------------------

(defun leap-year-p (year)
  "Whether YEAR is a leap year in the proleptic Gregorian calendar."
  (and (zerop (mod year 4))
       (or (plusp (mod year 100))
           (zerop (mod year 400)))))

(defparameter +days-before-month+
  #(0 0 31 59 90 120 151 181 212 243 273 304 334)
  "Days elapsed before the first of each month in a common year, indexed by
month number, so index 0 is unused.")

(defun day-of-year (instant)
  "INSTANT's ordinal date: 1 on the first of January, 366 at most."
  (multiple-value-bind (second minute hour day month year) (instant-parts instant)
    (declare (ignore second minute hour))
    (+ (aref +days-before-month+ month)
       day
       (if (and (> month 2) (leap-year-p year)) 1 0))))

(defun weeks-in-iso-year (year)
  "How many ISO weeks YEAR has: 52, or 53 in a long year.

A year is long when it starts on a Thursday, or is a leap year starting on a
Wednesday.  Both cases are what this arithmetic detects."
  (flet ((p (y) (mod (+ y (floor y 4) (- (floor y 100)) (floor y 400)) 7)))
    (if (or (= (p year) 4) (= (p (1- year)) 3)) 53 52)))

(defun iso-week (instant)
  "INSTANT's ISO week date as (VALUES YEAR WEEK WEEKDAY).

The year is not always the calendar year: the last days of December can belong
to week 1 of the next year, and the first days of January to the last week of the
previous one.  That is the whole reason this function exists rather than a
division."
  (multiple-value-bind (second minute hour day month year weekday) (instant-parts instant)
    (declare (ignore second minute hour day month))
    (let ((week (floor (+ (- (day-of-year instant) weekday) 10) 7)))
      (cond ((< week 1)
             (values (1- year) (weeks-in-iso-year (1- year)) weekday))
            ((> week (weeks-in-iso-year year))
             (values (1+ year) 1 weekday))
            (t (values year week weekday))))))

;;; The renderings ------------------------------------------------------------------

(defstruct (rendering (:constructor make-rendering (key label description function)))
  "One way of writing an instant down.

KEY names it in code, LABEL names it to a person, DESCRIPTION says what it is
for, and FUNCTION does the work.  A table rather than a case statement because
the menu, the tests and the command line all need to walk the same list, and
three places that each know the renderings is three places to forget one."
  (key nil :type keyword)
  (label "" :type string)
  (description "" :type string)
  (function nil :type function))

(defun %date (instant)
  (multiple-value-bind (second minute hour day month year) (instant-parts instant)
    (declare (ignore second minute hour))
    (format nil "~4,'0D-~2,'0D-~2,'0D" year month day)))

(defun %time (instant &key (precision :seconds))
  "The time part of INSTANT, with no zone designator."
  (multiple-value-bind (second minute hour) (instant-parts instant)
    (ecase precision
      (:hours (format nil "~2,'0D" hour))
      (:minutes (format nil "~2,'0D:~2,'0D" hour minute))
      (:seconds (format nil "~2,'0D:~2,'0D:~2,'0D" hour minute second))
      (:milliseconds
       (format nil "~2,'0D:~2,'0D:~2,'0D.~3,'0D" hour minute second
               ;; TRUNCATE, not ROUND: see the note on the INSTANT structure.
               (truncate (instant-microseconds instant) 1000)))
      (:microseconds
       (format nil "~2,'0D:~2,'0D:~2,'0D.~6,'0D" hour minute second
               (instant-microseconds instant))))))

(defun %stamp (instant precision)
  "A full ISO 8601 timestamp at PRECISION, with the Z zone designator."
  (format nil "~AT~AZ" (%date instant) (%time instant :precision precision)))

(defparameter +renderings+
  (list
   (make-rendering :microseconds "Microseconds" "full precision, as the clock has it"
                   (lambda (instant) (%stamp instant :microseconds)))
   (make-rendering :milliseconds "Milliseconds" "what most log formats use"
                   (lambda (instant) (%stamp instant :milliseconds)))
   (make-rendering :seconds "Seconds" "the everyday ISO 8601 timestamp"
                   (lambda (instant) (%stamp instant :seconds)))
   (make-rendering :minutes "Minutes" "reduced accuracy, to the minute"
                   (lambda (instant) (%stamp instant :minutes)))
   (make-rendering :hours "Hours" "reduced accuracy, to the hour"
                   (lambda (instant) (%stamp instant :hours)))
   (make-rendering :date "Date" "the calendar date alone"
                   (lambda (instant) (%date instant)))
   (make-rendering :month "Month" "year and month"
                   (lambda (instant)
                     (multiple-value-bind (s m h d month year) (instant-parts instant)
                       (declare (ignore s m h d))
                       (format nil "~4,'0D-~2,'0D" year month))))
   (make-rendering :year "Year" "the year alone"
                   (lambda (instant)
                     (multiple-value-bind (s m h d mo year) (instant-parts instant)
                       (declare (ignore s m h d mo))
                       (format nil "~4,'0D" year))))
   (make-rendering :basic "Compact" "no separators -- sorts, and is safe in a filename"
                   (lambda (instant)
                     (multiple-value-bind (second minute hour day month year)
                         (instant-parts instant)
                       (format nil "~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0DZ"
                               year month day hour minute second))))
   (make-rendering :week "Week date" "ISO week date: year, week, day"
                   (lambda (instant)
                     (multiple-value-bind (year week weekday) (iso-week instant)
                       (format nil "~4,'0D-W~2,'0D-~D" year week weekday))))
   (make-rendering :ordinal "Ordinal date" "ISO ordinal date: year and day of year"
                   (lambda (instant)
                     (multiple-value-bind (s m h d mo year) (instant-parts instant)
                       (declare (ignore s m h d mo))
                       (format nil "~4,'0D-~3,'0D" year (day-of-year instant))))))
  "Every rendering the menu offers, in the order it offers them.

Descending resolution first -- microseconds down to the year, which is the ladder
the menu is really about -- and then the three ISO forms that are a different
shape rather than a different resolution.")

(defun find-rendering (key)
  "The rendering called KEY, or NIL."
  (find key +renderings+ :key #'rendering-key))

(defun render (instant key)
  "INSTANT written in the rendering called KEY.

    (render (make-instant 1788644823 123456) :seconds)
    => \"2026-09-05T21:47:03Z\""
  (let ((rendering (or (find-rendering key)
                       (error "No such rendering: ~S.  Try one of ~{~S~^, ~}."
                              key (mapcar #'rendering-key +renderings+)))))
    (funcall (rendering-function rendering) instant)))

(defun render-now (key)
  "The current instant, written in the rendering called KEY."
  (render (now) key))
