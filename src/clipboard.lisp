;;;; src/clipboard.lisp -- putting a timestamp on the pasteboard.
;;;;
;;;; -clearContents IS NOT OPTIONAL AND IS NOT TIDINESS.  A pasteboard holds one
;;;; item per type, and the owner of each type is whoever wrote it last.  Writing
;;;; a string without clearing first leaves every other representation of the
;;;; PREVIOUS contents in place -- the RTF, the HTML, the file URL -- so an
;;;; application that prefers a richer type pastes the old value while a plain
;;;; text editor pastes the new one.  The bug that produces is that copy works
;;;; everywhere except the one application the user cares about.
;;;;
;;;; -clearContents also returns the new change count, which is the only honest
;;;; way to know a write landed: -setString:forType: answers NO for a type the
;;;; pasteboard rejects, and answering NO is the whole of the error reporting.

(in-package #:utc-status-app)

(defparameter +pasteboard-type-string+ "public.utf8-plain-text"
  "NSPasteboardTypeString.

The constant is a symbol in AppKit rather than a value we can read without
looking it up, and its value is this UTI.  Written out because looking up a
string constant through the dynamic loader to get a string is a lot of
machinery for a string that has not changed since 10.6.")

(defun copy-to-clipboard (text)
  "Put TEXT on the general pasteboard as plain text.  Returns TEXT.

Signals an error if the pasteboard refuses the write, rather than returning
quietly -- a copy that silently did nothing is indistinguishable from one that
worked until the user tries to paste."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let ((pasteboard (objc:invoke "NSPasteboard" "generalPasteboard")))
      (objc:invoke pasteboard "clearContents")
      (unless (objc:invoke-bool pasteboard "setString:forType:"
                                text +pasteboard-type-string+)
        (error "The pasteboard refused ~S." text))
      text)))

(defun clipboard-string ()
  "What is on the general pasteboard as plain text, or NIL.

Here so the suite can check that a copy actually happened, rather than checking
that the copying function returned without complaining."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let* ((pasteboard (objc:invoke "NSPasteboard" "generalPasteboard"))
           (string (objc:invoke pasteboard "stringForType:" +pasteboard-type-string+)))
      (unless (cffi:null-pointer-p (objc:objc-object-pointer string))
        (objc:invoke-into 'string string "description")))))
