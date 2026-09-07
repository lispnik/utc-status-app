;;;; src/layout.lisp -- laying the UTC clock out the way the system clock is.
;;;;
;;;; The brief was that the menu-bar text should have "the same layout as the
;;;; system clock text", and the honest reading of that is not a format string
;;;; copied from a screenshot of one Mac.  The system clock's shape is a set of
;;;; preferences -- day of week, date, seconds, and the 12/24 hour choice -- so
;;;; this reads those preferences and builds the same shape from them.  Change
;;;; the setting and this follows on the next launch.
;;;;
;;;; THE ORDER OF THE FIELDS IS THE LOCALE'S, NOT OURS.  Rather than concatenate
;;;; "EEE" and "MMM d" and a time in the order an English speaker expects,
;;;; the preferences become a Unicode date-field SKELETON -- an unordered set of
;;;; the fields wanted -- and +dateFormatFromTemplate:options:locale: turns that
;;;; into the pattern the locale actually uses.  In en_US that gives "EEE MMM d",
;;;; in en_GB "EEE d MMM", and neither is written down here.
;;;;
;;;; `j' IS THE HOUR FIELD TO ASK FOR, and this is the subtle one.  `H' forces
;;;; 24-hour and `h' forces 12; `j' means "whichever this locale uses", which is
;;;; what respects the 24-Hour Time switch in Settings.  Ask for `H' and a user
;;;; who wants 12-hour time gets 24 anyway, silently and forever.
;;;;
;;;; The one thing deliberately NOT copied is the AM/PM marker: the system's
;;;; clock reads AM or PM in local time, and this one reads it in UTC, so on a
;;;; 12-hour Mac the two disagree by design.  See *LABEL* for the escape hatch.

(in-package #:utc-status-app)

(defvar *label* nil
  "Text appended to the menu-bar title, or NIL for none.

NIL by default because the brief asked for the system clock's layout, and a
suffix is not that layout.  It is worth knowing what that costs: on a 24-hour
Mac the two clocks are the same shape and differ only by the offset, so the one
that says 14:30 when it is 09:30 locally looks like a broken clock rather than a
UTC one.  Set this to \"Z\" or \" UTC\" if that trade is the wrong way round for
you.")

;;; Reading the system clock's preferences ----------------------------------------

(defparameter +clock-domain+ "com.apple.menuextra.clock"
  "Where the menu-bar clock keeps its settings.")

(defun %defaults-for (domain)
  (objc:invoke (objc:invoke "NSUserDefaults" "alloc") "initWithSuiteName:" domain))

(defun %bool-default (defaults key &optional default)
  "KEY from DEFAULTS as a boolean, or DEFAULT when the key is absent.

-boolForKey: cannot express absence: it answers NO for a key that was never
written, which is a different thing from one written as false.  ShowSeconds is
absent on a Mac that has never been asked about seconds, and its default is
false; ShowDayOfWeek is absent on one that has never been asked, and its default
is TRUE.  So absence has to be detected with -objectForKey: first."
  (let ((object (objc:invoke defaults "objectForKey:" key)))
    (if (cffi:null-pointer-p (objc:objc-object-pointer object))
        default
        (objc:invoke-bool defaults "boolForKey:" key))))

(defun clock-preferences ()
  "How the system clock is configured, as a plist.

    (clock-preferences)
    => (:DAY-OF-WEEK T :DATE T :SECONDS NIL)

ShowDate is a tri-state and not a boolean: 0 means \"when there is room\", 1
means always and 2 means never.  Only 2 is treated as no.

The first version of this treated only 1 as yes, and it was wrong on this
machine and probably on most: 0 is the default, and the menu bar was in fact
showing the date, so the UTC clock read \"Sun 02:01\" beside a system clock
reading \"Sat Sep 5 21:00\".  Two clocks of different shapes is exactly what
matching the layout was supposed to avoid, and \"when there is room\" resolves
to yes far more often than not."
  (objc:ensure-objc-initialized)
  (objc:with-autorelease-pool ()
    (let ((defaults (%defaults-for +clock-domain+)))
      (list :day-of-week (%bool-default defaults "ShowDayOfWeek" t)
            :date (/= 2 (objc:invoke defaults "integerForKey:" "ShowDate"))
            :seconds (%bool-default defaults "ShowSeconds" nil)))))

;;; Our own preferences -------------------------------------------------------------
;;;
;;; The system clock's settings say what SHAPE the title has.  These two say what
;;; this clock does differently, and they are ours: written to our own defaults
;;; domain by the menu, and authoritative over the system's when present.
;;;
;;; Absent means "follow the system", which is the state before anyone has
;;; touched the menu.  That is why these are read with -objectForKey: first
;;; rather than -boolForKey:, which cannot tell an absent key from a false one.

(defparameter +preferences-domain+ "com.lispnik.utc-status"
  "Where this application keeps its own settings.")

(defun %bundle-identifier ()
  "This process's bundle identifier, or NIL when it is not in a bundle."
  (let* ((bundle (objc:invoke "NSBundle" "mainBundle"))
         (identifier (objc:invoke bundle "bundleIdentifier")))
    (unless (cffi:null-pointer-p (objc:objc-object-pointer identifier))
      (objc:invoke-into 'string identifier "description"))))

(defun %our-defaults ()
  "NSUserDefaults for OUR OWN preferences, which is not the same object in and
out of a bundle.

-initWithSuiteName: RETURNS NIL FOR YOUR OWN BUNDLE IDENTIFIER.  A suite is
another application's domain; asking for your own is meaningless, and Foundation
says so and hands back nil rather than erroring:

  Using your own bundle identifier as an NSUserDefaults suite name does not
  make sense and will not work.

The next message sent to that nil is the crash, and it happens only inside the
bundle -- the loose binary has no identifier, so the suite is somebody else's
and works.  Which is exactly the sort of bug that ships.

So: -standardUserDefaults when our identifier is the bundle's, the named suite
otherwise.  Both write com.lispnik.utc-status.plist, so a preference set by one
is read by the other."
  (if (equal (%bundle-identifier) +preferences-domain+)
      (objc:invoke "NSUserDefaults" "standardUserDefaults")
      (%defaults-for +preferences-domain+)))

(defun preference (key)
  "Our setting for KEY as :ON, :OFF, or NIL for \"follow the system\"."
  (objc:ensure-objc-initialized)
  (objc:with-autorelease-pool ()
    (let* ((defaults (%our-defaults))
           (object (objc:invoke defaults "objectForKey:" key)))
      (unless (cffi:null-pointer-p (objc:objc-object-pointer object))
        (if (objc:invoke-bool defaults "boolForKey:" key) :on :off)))))

(defun (setf preference) (state key)
  "Set KEY to :ON or :OFF, or to NIL to go back to following the system."
  (objc:ensure-objc-initialized)
  (objc:with-autorelease-pool ()
    (let ((defaults (%our-defaults)))
      (if (null state)
          (objc:invoke defaults "removeObjectForKey:" key)
          (objc:invoke defaults "setBool:forKey:" (eq state :on) key))
      ;; -synchronize is deprecated and still the only way to be sure the write
      ;; has landed before the process is killed -- which, for a menu-bar
      ;; application people quit from its own menu, is a real possibility.
      (objc:invoke defaults "synchronize")))
  state)

(defparameter +seconds-key+ "ShowSeconds")
(defparameter +label-key+ "ShowLabel")

(defun effective-preferences ()
  "The system clock's layout, with our overrides applied.

    (effective-preferences)
    => (:DAY-OF-WEEK T :DATE T :SECONDS NIL :LABEL NIL)

:SECONDS is ours when we have an opinion and the system's otherwise, which is
what makes the menu item behave like a checkbox: the first click writes the
opposite of whatever is on screen."
  (let ((system (clock-preferences))
        (seconds (preference +seconds-key+))
        (label (preference +label-key+)))
    (list :day-of-week (getf system :day-of-week)
          :date (getf system :date)
          :seconds (if seconds (eq seconds :on) (getf system :seconds))
          :label (eq label :on))))

;;; Turning them into a format ------------------------------------------------------

(defun clock-skeleton (&optional (preferences (effective-preferences)))
  "The Unicode date-field skeleton for PREFERENCES.

    (clock-skeleton '(:day-of-week t :date nil :seconds nil))   => \"EEEjmm\"
    (clock-skeleton '(:day-of-week t :date t :seconds t))       => \"EEEMMMdjmmss\"

A skeleton says WHICH fields are wanted, not in what order or with what
punctuation; the locale decides those.  Pure, so the suite can check every
combination without a window server."
  (concatenate 'string
               (if (getf preferences :day-of-week) "EEE" "")
               (if (getf preferences :date) "MMMd" "")
               "jmm"
               (if (getf preferences :seconds) "ss" "")))

(defun normalise-pattern (pattern)
  "PATTERN with the connectives a menu-bar clock does not use taken out.

    (normalise-pattern \"EEE, MMM d 'at' HH:mm\")   => \"EEE MMM d  HH:mm\"

+dateFormatFromTemplate: builds a pattern for prose -- it joins the date and the
time with a word, and separates the weekday with a comma -- and the menu bar
does neither: it writes \"Sat Sep 5  21:00\".  So the quoted literals come out,
and so do the commas.

Removing every QUOTED literal rather than the string \"at\" is what makes this
work outside English: German joins with 'um', French with 'a'.  A doubled quote
is ICU's escape for a literal apostrophe and is kept, which matters for locales
whose month names contain one.

The two spaces in the result are not an accident -- 'at' had a space on each
side, and the menu bar has that same wider gap before the time."
  (with-output-to-string (out)
    (let ((index 0)
          (length (length pattern)))
      (loop while (< index length)
            for character = (char pattern index)
            do (cond
                 ;; '' is an escaped apostrophe, not the start of a literal.
                 ((and (char= character #\') (< (1+ index) length)
                       (char= (char pattern (1+ index)) #\'))
                  (write-char #\' out)
                  (incf index 2))
                 ;; A quoted literal: skip to the closing quote.
                 ((char= character #\')
                  (incf index)
                  (loop while (and (< index length) (char/= (char pattern index) #\'))
                        do (incf index))
                  (incf index))
                 ((char= character #\,) (incf index))
                 (t (write-char character out) (incf index)))))))

(defvar *formatter* nil
  "The cached NSDateFormatter, built once rather than once a second.")

(defvar *formatter-preferences* nil
  "The preferences *FORMATTER* was built from, so a change can be noticed.")

(defun %make-formatter (&optional (preferences (effective-preferences)))
  "An NSDateFormatter laid out like the system clock, but fixed to UTC."
  (objc:ensure-objc-initialized)
  (let* ((locale (objc:invoke "NSLocale" "currentLocale"))
         (pattern (objc:invoke-into
                   'string "NSDateFormatter" "dateFormatFromTemplate:options:locale:"
                   (clock-skeleton preferences) 0 locale))
         (formatter (objc:alloc-init-object "NSDateFormatter")))
    (objc:invoke formatter "setLocale:" locale)
    (objc:invoke formatter "setDateFormat:" (normalise-pattern pattern))
    (objc:invoke formatter "setTimeZone:"
                 (objc:invoke "NSTimeZone" "timeZoneWithAbbreviation:" "UTC"))
    formatter))

(defun ensure-formatter (&key rebuild (preferences (effective-preferences)))
  "The cached formatter, rebuilt when there is none, when REBUILD is true, or
when PREFERENCES differ from the ones it was built from.

The last clause is what makes the clock follow a setting changed while it is
running.  Polling rather than a notification, and that is a deliberate second
choice: NSUserDefaultsDidChangeNotification is posted for changes made in THIS
process, and the interesting change -- someone turning on 24-hour time in System
Settings -- happens in another one.  Comparing the plists on a timer is
unglamorous and actually works."
  (when (or rebuild
            (null *formatter*)
            (not (equal preferences *formatter-preferences*)))
    (setf *formatter* (objc:retain (%make-formatter preferences))
          *formatter-preferences* preferences))
  *formatter*)

(defun menu-bar-title (&optional (instant (now)))
  "INSTANT laid out the way the system clock lays out the local time.

    (menu-bar-title)   => \"Sat 21:47\"

The value that goes in the menu bar, and the only place in this application
where the time is not ISO 8601 -- because matching the system clock is the point
of it."
  (objc:with-autorelease-pool ()
    (let* ((seconds (+ (float (instant-seconds instant) 1d0)
                       (/ (instant-microseconds instant) 1000000d0)))
           (date (objc:invoke "NSDate" "dateWithTimeIntervalSince1970:" seconds))
           (preferences (effective-preferences))
           (text (objc:invoke-into 'string (ensure-formatter :preferences preferences)
                                   "stringFromDate:" date))
           (label (or *label* (and (getf preferences :label) " UTC"))))
      (if label (concatenate 'string text label) text))))
