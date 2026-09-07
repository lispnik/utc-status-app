;;;; src/app.lisp -- the menu-bar item, its menu, and the clock that drives it.
;;;;
;;;; FOUR THINGS HERE ARE NOT OBVIOUS, AND THREE OF THEM FAIL SILENTLY.
;;;;
;;;; THE APPLICATION MUST BE AN ACCESSORY.  NSApplicationActivationPolicyRegular
;;;; is the default and is right for something that owns windows: it gets a Dock
;;;; icon, and its windows can come to the front.  A menu-bar item is not a
;;;; window, and a Regular application with no windows that has never been
;;;; activated does not get its status item's menu tracked -- the item draws, and
;;;; clicking it does nothing at all.  Accessory (1) means "no Dock icon, no menu
;;;; bar of my own, but I do have UI", which is exactly this.
;;;;
;;;; IT MUST USE -[NSApplication run], NOT A PUMP LOOP.  A status item's menu is
;;;; tracked in AppKit's own nested run-loop mode while the mouse is down.  A
;;;; loop that pumps kCFRunLoopDefaultMode by hand -- which is the right way to
;;;; keep a window alive from a REPL -- starves that tracking, and the symptom is
;;;; the same as the wrong activation policy: the item is there, the click opens
;;;; nothing.
;;;;
;;;; THE TIMER MUST BE ADDED IN NSRunLoopCommonModes.  A timer scheduled the
;;;; ordinary way runs in the default mode only, so it stops while a menu is
;;;; open -- and this menu shows timestamps, so the one moment the clock must not
;;;; freeze is exactly the moment it would.  +scheduledTimerWithTimeInterval:
;;;; does the ordinary thing, which is why the timer here is created unscheduled
;;;; and added to the run loop by hand.
;;;;
;;;; And the fourth, which fails loudly: -stop: alone does not end -run.  It sets
;;;; a flag the loop notices only when it next finishes processing an event, so
;;;; an idle loop sits there.  Posting a dummy event behind the stop guarantees
;;;; there is an event to finish.

(in-package #:utc-status-app)

(defconstant +activation-policy-accessory+ 1
  "NSApplicationActivationPolicyAccessory.  See the header.")

(defparameter +variable-status-item-length+ -1d0
  "NSVariableStatusItemLength: the item is as wide as its title.")

(defparameter +run-loop-common-modes+ "kCFRunLoopCommonModes"
  "The mode set that includes menu tracking.  See the header.")

(defparameter +tick-seconds+ 0.5d0
  "How often the clock is recomputed.

Twice a second rather than once, so a title that changes on the second is at
most half a second late; the title is only actually written when the text
changes, so the cost of the extra tick is a string comparison.")

(defvar *status-item* nil "The NSStatusItem, while the application is running.")
(defvar *menu* nil "Its NSMenu.")
(defvar *timer* nil "The NSTimer driving the clock.")
(defvar *timeout-timer* nil "The one-shot NSTimer behind :TIMEOUT, if asked for.")
(defvar *title* nil "The last title written, so an unchanged one is not rewritten.")
(defvar *running* nil "T while the application's run loop should keep going.")

(defparameter +preference-recheck-ticks+ 20
  "Ticks between re-reads of the clock's settings: 20 x 0.5s, so ten seconds.

The settings live in another process's defaults domain, changed by System
Settings, and nothing tells us when that happens -- see ENSURE-FORMATTER.  Ten
seconds is far below anyone's patience for a preference to take effect and far
above the cost of reading two small plists.")

(defvar *ticks* 0 "Ticks since startup, for the preference re-check.")

;;; Menu item tags.  The renderings take 0 upwards, so everything else is
;;; negative and there is no arithmetic to get wrong when a rendering is added.
(defconstant +tag-quit+ -1)
(defconstant +tag-seconds+ -2)
(defconstant +tag-label+ -3)

;;; The controller, whose methods are what AppKit calls ------------------------------

(objc:define-objc-class controller ()
  ()
  (:objc-class-name "LispUTCStatusController"))

(objc:define-objc-method ("tick:" :void)
    ((self controller) (timer objc:objc-object-pointer))
  (declare (ignore timer))
  ;; Every tick redraws; every twentieth also asks whether the settings moved
  ;; under us.  ENSURE-FORMATTER rebuilds only when they actually differ, so the
  ;; usual case is two plist reads and an EQUAL.
  (when (zerop (mod (incf *ticks*) +preference-recheck-ticks+))
    (ensure-formatter))
  (update-title))

(objc:define-objc-method ("toggleSeconds:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (setf (preference +seconds-key+)
        (if (getf (effective-preferences) :seconds) :off :on))
  (retitle-now))

(objc:define-objc-method ("toggleLabel:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (setf (preference +label-key+)
        (if (getf (effective-preferences) :label) :off :on))
  (retitle-now))

(objc:define-objc-method ("copyRendering:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  ;; The menu item's tag is its index into +RENDERINGS+.  A tag rather than one
  ;; selector per rendering: the renderings are a table, and a table wants one
  ;; handler that reads which row it was.
  (let* ((index (objc:invoke sender "tag"))
         (rendering (nth index +renderings+)))
    (when rendering
      ;; The instant of the CLICK, not the instant the menu was opened -- the
      ;; brief says the current timestamp, and a menu can sit open for a while.
      (copy-to-clipboard (render (now) (rendering-key rendering))))))

(objc:define-objc-method ("menuNeedsUpdate:" :void)
    ((self controller) (menu objc:objc-object-pointer))
  ;; Called just before the menu is displayed, so the timestamps on it are the
  ;; ones you would get by choosing them rather than the ones from whenever the
  ;; menu was built.
  (refresh-menu menu))

(objc:define-objc-method ("quit:" :void)
    ((self controller) (sender objc:objc-object-pointer))
  (declare (ignore sender))
  (setf *running* nil)
  (stop-the-application))

;;; The clock ------------------------------------------------------------------------

(defun retitle-now ()
  "Rebuild the formatter and repaint the title immediately.

For the two menu toggles: waiting up to ten seconds for the periodic re-check
would make a menu item look broken, and the change is ours so there is nothing
to poll for."
  (ensure-formatter :rebuild t)
  (setf *title* nil)                    ; force the write, not just the compare
  (update-title)
  (refresh-menu))

(defun update-title (&optional (instant (now)))
  "Write INSTANT into the menu-bar button, if it reads differently than last time."
  (when *status-item*
    (let ((text (menu-bar-title instant)))
      (unless (equal text *title*)
        (setf *title* text)
        (objc:invoke (objc:invoke *status-item* "button") "setTitle:" text))))
  *title*)

;;; The menu --------------------------------------------------------------------------

(defun %menu-item (title action target &key (tag 0) (enabled t))
  "An NSMenuItem titled TITLE whose ACTION is sent to TARGET when chosen."
  (let ((item (objc:invoke (objc:invoke "NSMenuItem" "alloc")
                           "initWithTitle:action:keyEquivalent:"
                           title
                           (if action (objc:coerce-to-selector action) (cffi:null-pointer))
                           "")))
    (when target (objc:invoke item "setTarget:" target))
    (objc:invoke item "setTag:" tag)
    (objc:invoke item "setEnabled:" enabled)
    (objc:autorelease item)))

(defun build-menu (target)
  "The menu: one item per rendering, then Quit.  Returns the NSMenu."
  (ensure-appkit)
  (let ((menu (objc:alloc-init-object "NSMenu")))
    ;; -setAutoenablesItems: NO, or AppKit decides for itself which items are
    ;; enabled by looking for a responder that implements each action -- and
    ;; disables the header, then re-enables nothing, leaving a menu of grey text.
    (objc:invoke menu "setAutoenablesItems:" nil)
    (loop for rendering in +renderings+
          for index from 0
          do (objc:invoke menu "addItem:"
                          (%menu-item (rendering-label rendering) "copyRendering:" target
                                      :tag index)))
    (objc:invoke menu "addItem:" (objc:invoke "NSMenuItem" "separatorItem"))
    (objc:invoke menu "addItem:"
                 (%menu-item "Show Seconds" "toggleSeconds:" target :tag +tag-seconds+))
    (objc:invoke menu "addItem:"
                 (%menu-item "Show UTC Label" "toggleLabel:" target :tag +tag-label+))
    (objc:invoke menu "addItem:" (objc:invoke "NSMenuItem" "separatorItem"))
    (objc:invoke menu "addItem:"
                 (%menu-item "Quit" "quit:" target :tag +tag-quit+))
    (objc:invoke menu "setDelegate:" target)
    menu))

(defun refresh-menu (&optional (menu *menu*))
  "Retitle each rendering's item with what choosing it would copy, right now.

The menu is its own documentation this way: every line is a live example of the
format, and the line you click is the string you get."
  (when menu
    (let ((instant (now))
          (preferences (effective-preferences)))
      (loop for rendering in +renderings+
            for index from 0
            for item = (objc:invoke menu "itemWithTag:" index)
            unless (cffi:null-pointer-p (objc:objc-object-pointer item))
              do (objc:invoke item "setTitle:"
                              (render instant (rendering-key rendering))))
      ;; NSControlStateValueOn is 1 and Off is 0.  A checkmark rather than a
      ;; title that says "on", because a menu item that reports its own state is
      ;; what a person expects to be able to click.
      (loop for (tag key) in (list (list +tag-seconds+ :seconds)
                                   (list +tag-label+ :label))
            for item = (objc:invoke menu "itemWithTag:" tag)
            unless (cffi:null-pointer-p (objc:objc-object-pointer item))
              do (objc:invoke item "setState:" (if (getf preferences key) 1 0))))))

;;; Running ---------------------------------------------------------------------------

(defun stop-the-application ()
  "End -[NSApplication run].  See the header on why the posted event is needed."
  (let ((app (objc:invoke "NSApplication" "sharedApplication")))
    (objc:invoke app "stop:" (cffi:null-pointer))
    (objc:invoke app "postEvent:atStart:"
                 (objc:invoke "NSEvent"
                              "otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"
                              15         ; NSEventTypeApplicationDefined
                              #(0d0 0d0) ; NSPoint, by value
                              0 0d0 0 (cffi:null-pointer) 0 0 0)
                 t))
  (values))

(defun start-timer (target)
  "A repeating timer that ticks the clock, live even while the menu is open."
  (let ((timer (objc:invoke "NSTimer"
                            "timerWithTimeInterval:target:selector:userInfo:repeats:"
                            +tick-seconds+ target (objc:coerce-to-selector "tick:")
                            (cffi:null-pointer) t)))
    (objc:invoke (objc:invoke "NSRunLoop" "currentRunLoop") "addTimer:forMode:"
                 timer +run-loop-common-modes+)
    timer))

(defun start-timeout (target seconds)
  "A one-shot timer that quits after SECONDS.  Returns the NSTimer.

Common modes like the clock's, so a timeout still expires while a menu is being
held open -- otherwise a test that leaves the menu down would hang exactly when
the timeout is there to stop it."
  (let ((timer (objc:invoke "NSTimer"
                            "timerWithTimeInterval:target:selector:userInfo:repeats:"
                            (float seconds 1d0) target
                            (objc:coerce-to-selector "quit:")
                            (cffi:null-pointer) nil)))
    (objc:invoke (objc:invoke "NSRunLoop" "currentRunLoop") "addTimer:forMode:"
                 timer +run-loop-common-modes+)
    timer))

(defun run (&key timeout label)
  "Put the UTC clock in the menu bar and run until Quit is chosen.  Returns T.

    (utc-status-app:run)
    (utc-status-app:run :timeout 30 :label \" UTC\")

Must be called on thread 1, which in a plain sbcl is the REPL's thread: AppKit
refuses to run anywhere else.  TIMEOUT, in seconds, stops it anyway, so a test
or a demo cannot wedge.  LABEL is appended to the title; see *LABEL*."
  (ensure-appkit)
  (when label (setf *label* label))
  (objc.runloop:shared-application)
  (objc.runloop:set-activation-policy +activation-policy-accessory+)
  (let* ((controller (make-instance 'controller))
         (target (objc:objc-object-pointer controller))
         (bar (objc:invoke "NSStatusBar" "systemStatusBar")))
    (setf *status-item* (objc:invoke bar "statusItemWithLength:"
                                     +variable-status-item-length+)
          *menu* (build-menu target)
          *title* nil
          *running* t)
    (objc:invoke *status-item* "setMenu:" *menu*)
    (update-title)
    (setf *timer* (start-timer target))
    ;; The timeout is a timer on the main run loop rather than a watchdog thread.
    ;; The thread version worked -- it woke on time and sent
    ;; -performSelectorOnMainThread: without error -- and the application went on
    ;; running anyway, with nothing to say why.  A second timer needs no
    ;; cross-thread messaging, no lock, and no reasoning about which thread may
    ;; call -stop:, and it is stopped by the same -invalidate as the clock.
    (when timeout
      (setf *timeout-timer* (start-timeout target timeout)))
    (unwind-protect
         (objc:invoke (objc:invoke "NSApplication" "sharedApplication") "run")
      (setf *running* nil)
      (dolist (timer (list *timer* *timeout-timer*))
        (when timer (objc:invoke timer "invalidate")))
      (setf *timer* nil *timeout-timer* nil)
      (when *status-item*
        (objc:invoke bar "removeStatusItem:" *status-item*)
        (setf *status-item* nil))
      (setf *menu* nil)))
  t)
