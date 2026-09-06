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

(test the-menu-has-an-item-per-rendering-and-a-quit
  "Built without a status bar: an NSMenu is an ordinary object, so the shape of
the menu can be checked in a process that never touches the menu bar."
  (progn
    (objc:with-autorelease-pool ()
      (let* ((controller (make-instance 'utc-status-app::controller))
             (target (objc:objc-object-pointer controller))
             (menu (utc-status-app::build-menu target)))
        (is (= (+ (length utc-status-app:+renderings+) 2)
               (objc:invoke menu "numberOfItems"))
            "one item per rendering, a separator, and Quit")
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
