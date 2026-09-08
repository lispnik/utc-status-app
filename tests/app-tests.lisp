;;;; tests/app-tests.lisp -- the menu, and what choosing an item does.
;;;;
;;;; The interactive path, tested without a click.  Choosing a menu item is
;;;; AppKit sending -copyRendering: to the controller with the item as the
;;;; sender, so the test sends exactly that -- which exercises the real method,
;;;; the real tag lookup and the real pasteboard write, and leaves only the
;;;; mouse untested.

(in-package #:utc-status-app/tests)

(def-suite app :in all-tests :description "The menu and its actions.")
(in-suite app)

(defmacro with-saved-preferences (&body body)
  "Run BODY and put our defaults back afterwards.

The toggles write to a real defaults domain, and a suite that leaves a user's
preference flipped is the same discomfort as one that eats their clipboard."
  `(let ((seconds (utc-status-app:preference utc-status-app:+seconds-key+))
         (label (utc-status-app:preference utc-status-app:+label-key+)))
     (unwind-protect (progn ,@body)
       (setf (utc-status-app:preference utc-status-app:+seconds-key+) seconds
             (utc-status-app:preference utc-status-app:+label-key+) label))))

(test the-menu-has-an-item-per-rendering-plus-the-toggles-and-quit
  "Built without a status bar: an NSMenu is an ordinary object, so the shape of
the menu can be checked in a process that never touches the menu bar.

The count is spelled out rather than written as a number, so adding a rendering
or a toggle changes it in one place and the arithmetic stays legible."
  (progn
    (objc:with-autorelease-pool ()
      (let* ((controller (make-instance 'utc-status-app::controller))
             (target (objc:objc-object-pointer controller))
             (menu (utc-status-app::build-menu target)))
        (is (= (+ (length utc-status-app:+renderings+) ; one each
                  2                                    ; two separators
                  2                                    ; Show Seconds, Show UTC Label
                  ;; Start at Login, only when there is a bundle to register.
                  ;; The suite runs from a bare sbcl, so it is absent here --
                  ;; stated rather than left as an arithmetic coincidence.
                  (if (utc-status-app:login-item-available-p) 1 0)
                  1)                                   ; Quit
               (objc:invoke menu "numberOfItems")))
        (dolist (tag (list utc-status-app::+tag-seconds+
                           utc-status-app::+tag-label+
                           utc-status-app::+tag-quit+))
          (is (not (cffi:null-pointer-p
                    (objc:objc-object-pointer (objc:invoke menu "itemWithTag:" tag))))
              "no item is tagged ~D" tag))
        (loop for rendering in utc-status-app:+renderings+
              for index from 0
              for item = (objc:invoke menu "itemWithTag:" index)
              do (is (not (cffi:null-pointer-p (objc:objc-object-pointer item)))
                     "no item is tagged ~D, so ~S could never be chosen"
                     index (utc-status-app:rendering-key rendering)))))))

(test refreshing-the-menu-puts-live-timestamps-on-it
  "The menu is its own documentation: each item is retitled with what choosing
it would copy, just before the menu is shown."
  (progn
    (objc:with-autorelease-pool ()
      (let* ((controller (make-instance 'utc-status-app::controller))
             (target (objc:objc-object-pointer controller))
             (menu (utc-status-app::build-menu target)))
        (utc-status-app::refresh-menu menu)
        (let ((title (objc:invoke-into 'string (objc:invoke menu "itemWithTag:" 2)
                                       "title")))
          (is (search "T" title) "~S is not a timestamp" title)
          (is (eql #\Z (char title (1- (length title))))
              "~S does not end in Z, so it is not being written as UTC" title))))))

(test choosing-an-item-copies-that-rendering
  "The whole interaction, minus the mouse: AppKit would send -copyRendering:
with the chosen item as the sender, so that is what is sent here.

Skipped unless UTC_STATUS_TEST_CLIPBOARD is set -- it writes the clipboard of
whoever runs it."
  (if (not (clipboard-tests-allowed-p))
      (skip "set UTC_STATUS_TEST_CLIPBOARD=1 to let the suite use the clipboard")
      (progn
        (objc:with-autorelease-pool ()
          (let* ((controller (make-instance 'utc-status-app::controller))
                 (target (objc:objc-object-pointer controller))
                 (menu (utc-status-app::build-menu target)))
            ;; Tag 5 is :DATE, whose rendering has no time in it -- so this
            ;; asserts the tag really selected a rendering rather than defaulting
            ;; to the first, which a timestamp-shaped check would not notice.
            (let ((item (objc:invoke menu "itemWithTag:" 5)))
              (objc:invoke target "copyRendering:" item))
            (let ((copied (utc-status-app:clipboard-string)))
              (is (= 10 (length copied))
                  "~S is not a bare date, so the tag did not choose :DATE" copied)
              (is (not (find #\T copied))
                  "~S has a time in it, so a different rendering was copied" copied)
              (is (string= copied (utc-status-app:render-now :date))
                  "~S is not today's date in UTC" copied)))))))

(test a-preference-overrides-the-system-and-absence-follows-it
  "Ours is authoritative when present and invisible when not, which is what makes
the menu item behave like a checkbox: the first click writes the opposite of
whatever is on screen, whichever way the system had it."
  (with-saved-preferences
    (let ((system (getf (utc-status-app:clock-preferences) :seconds)))
      (setf (utc-status-app:preference utc-status-app:+seconds-key+) nil)
      (is (eq (getf (utc-status-app:effective-preferences) :seconds) system)
          "with nothing of ours set, the system's answer is the answer")
      (setf (utc-status-app:preference utc-status-app:+seconds-key+) :on)
      (is-true (getf (utc-status-app:effective-preferences) :seconds))
      (setf (utc-status-app:preference utc-status-app:+seconds-key+) :off)
      (is-false (getf (utc-status-app:effective-preferences) :seconds)
                "OFF has to differ from absent, or a user cannot turn seconds ~
off on a Mac whose clock shows them"))))

(test the-seconds-preference-reaches-the-title
  "Not just the plist: the skeleton gains ss, and the formatter is rebuilt rather
than serving the one it cached before the setting changed."
  (with-saved-preferences
    (let ((instant (utc-status-app:make-instant 1788644823 0)))
      (setf (utc-status-app:preference utc-status-app:+seconds-key+) :off)
      (let ((without (utc-status-app:menu-bar-title instant)))
        (setf (utc-status-app:preference utc-status-app:+seconds-key+) :on)
        (let ((with (utc-status-app:menu-bar-title instant)))
          (is (search "ss" (utc-status-app:clock-skeleton))
              "the skeleton asks for seconds")
          (is (string/= without with)
              "the title did not change, so the formatter was not rebuilt: ~
~S both times" without)
          (is (> (length with) (length without))
              "turning seconds on made the title no longer: ~S then ~S"
              without with))))))

(test the-label-preference-appends-utc
  "The escape hatch from two identically shaped clocks that disagree by hours."
  (with-saved-preferences
    (let ((instant (utc-status-app:make-instant 1788644823 0))
          (utc-status-app:*label* nil))
      (setf (utc-status-app:preference utc-status-app:+label-key+) :off)
      (let ((plain (utc-status-app:menu-bar-title instant)))
        (setf (utc-status-app:preference utc-status-app:+label-key+) :on)
        (let ((labelled (utc-status-app:menu-bar-title instant)))
          (is (string= (concatenate 'string plain " UTC") labelled)
              "~S is not ~S with a label on the end" labelled plain))))))

(test toggling-flips-the-preference-and-the-checkmark
  "The menu action AppKit would send, and the state the item shows afterwards.
NSControlStateValueOn is 1, Off is 0."
  (with-saved-preferences
    (objc:with-autorelease-pool ()
      (let* ((controller (make-instance 'utc-status-app::controller))
             (target (objc:objc-object-pointer controller))
             (menu (utc-status-app::build-menu target))
             (item (objc:invoke menu "itemWithTag:" utc-status-app::+tag-label+)))
        (setf (utc-status-app:preference utc-status-app:+label-key+) :off)
        (utc-status-app::refresh-menu menu)
        (is (= 0 (objc:invoke item "state")) "unchecked when the label is off")
        (objc:invoke target "toggleLabel:" item)
        (is-true (getf (utc-status-app:effective-preferences) :label)
                 "the action did not turn the label on")
        (utc-status-app::refresh-menu menu)
        (is (= 1 (objc:invoke item "state")) "checked once it is on")
        (objc:invoke target "toggleLabel:" item)
        (is-false (getf (utc-status-app:effective-preferences) :label)
                  "a second click did not turn it back off")))))

(test the-login-item-is-offered-only-from-a-bundle
  "SMAppService's -mainAppService describes THIS process's application, and a
bare executable is not one: -status answers NotFound and there is nothing to
register.  So the menu omits the item rather than offering one that always
fails.

The suite runs from a bare sbcl, which is exactly that case -- so this asserts
the unavailable branch, and the bundle is where the other one is exercised."
  (progn
    (is (member (utc-status-app:login-item-status)
                '(:enabled :not-registered :requires-approval :not-found))
        "~S is not an SMAppServiceStatus" (utc-status-app:login-item-status))
    (is (eq (eq (utc-status-app:login-item-status) :not-found)
            (not (utc-status-app:login-item-available-p)))
        "availability and :NOT-FOUND must be the same question")
    (objc:with-autorelease-pool ()
      (let* ((controller (make-instance 'utc-status-app::controller))
             (target (objc:objc-object-pointer controller))
             (menu (utc-status-app::build-menu target))
             (item (objc:invoke menu "itemWithTag:" utc-status-app::+tag-login+)))
        (is (eq (utc-status-app:login-item-available-p)
                (not (cffi:null-pointer-p (objc:objc-object-pointer item))))
            "the item is present exactly when registering is possible")))))
