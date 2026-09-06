;;;; src/frameworks.lisp -- the frameworks this application needs loaded.
;;;;
;;;; ENSURE-OBJC-INITIALIZED loads libobjc and Foundation and nothing else, which
;;;; is the right default for a binding: Foundation is where NSString and NSDate
;;;; live and most programs need no more.  Everything visible here -- the status
;;;; item, the menu, the pasteboard -- is AppKit, and AppKit has to be asked for.
;;;;
;;;; The symptom of forgetting is `Cannot find class "NSMenu"', which reads like a
;;;; fault in the bindings and is a missing framework.  It found this file: the
;;;; menu tests were passing only when the clipboard test happened to run first
;;;; and load AppKit on their behalf, so the suite was green in one order and
;;;; skipped in another.

(in-package #:utc-status-app)

(defparameter +appkit+
  "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
  "Where AppKit is.  NSStatusBar, NSMenu, NSPasteboard and NSApplication.")

(defun ensure-appkit ()
  "Initialise Objective-C with AppKit loaded.  Idempotent, and cheap to repeat.

Every entry point that touches an AppKit class calls this rather than trusting
that something else already has -- which is what makes COPY-TO-CLIPBOARD usable
on its own from a REPL, and what stops the suite depending on the order its
tests happen to run in."
  (objc:ensure-objc-initialized :modules (list +appkit+)))
