;;;; src/login-item.lisp -- starting at login.
;;;;
;;;; THERE IS NO Info.plist KEY FOR THIS.  It is the first thing people look
;;;; for, and there is no LSStartAtLogin: a login item is not declared, it is
;;;; REGISTERED at run time by the application itself.
;;;;
;;;; LSSharedFileList RATHER THAN SMAppService, WHICH IS THE NEWER API AND DID
;;;; NOT WORK.  SMAppService is what Apple documents for macOS 13 and later, and
;;;; -[SMAppService mainAppService] answered NotFound here in every arrangement
;;;; tried: from the loose binary, from the bundle in place, from ~/Applications
;;;; and from /Applications, launched directly and through LaunchServices,
;;;; unsigned, Developer ID signed, and notarised and stapled.  LaunchServices
;;;; knew the application throughout -- lsregister -dump lists it -- and the
;;;; system log recorded the call reaching com.apple.libxpc.SMAppService and
;;;; answering status 3, with no reason given.
;;;;
;;;; So this uses what shipping applications use.  Hammerspoon and Syncthing
;;;; both do login items with LSSharedFileList and neither links
;;;; ServiceManagement at all; Syncthing's own selectors are addAppAsLoginItem,
;;;; deleteAppFromLoginItem and wasAppAddedAsLoginItem.  The API is deprecated
;;;; -- it has been since 10.11 -- and it is what works.
;;;;
;;;; THESE ARE C FUNCTIONS, NOT MESSAGES, so CFFI makes the calls.  The types
;;;; they trade in are toll-free bridged, which is what keeps this short: a
;;;; CFURLRef is an NSURL and a CFArrayRef is an NSArray, so the URL is built
;;;; and the snapshot walked with ordinary INVOKE, and CFFI is left with the
;;;; five calls that have no Objective-C face.

(in-package #:utc-status-app)

(cffi:defcfun ("LSSharedFileListCreate" %shared-file-list-create) :pointer
  (allocator :pointer) (list-type :pointer) (options :pointer))

(cffi:defcfun ("LSSharedFileListInsertItemURL" %shared-file-list-insert) :pointer
  (list :pointer) (after :pointer) (display-name :pointer) (icon :pointer)
  (url :pointer) (properties :pointer) (property-values :pointer))

(cffi:defcfun ("LSSharedFileListCopySnapshot" %shared-file-list-snapshot) :pointer
  (list :pointer) (seed :pointer))

(cffi:defcfun ("LSSharedFileListItemCopyResolvedURL" %shared-file-list-item-url) :pointer
  (item :pointer) (flags :uint32) (error :pointer))

(cffi:defcfun ("LSSharedFileListItemRemove" %shared-file-list-item-remove) :int
  (list :pointer) (item :pointer))

(cffi:defcfun ("CFRelease" %cf-release) :void (object :pointer))

(defun %global (name)
  "The value of an exported CFTypeRef global, or a null pointer.

The constants are pointer-sized globals rather than functions, so the symbol's
address has to be dereferenced -- taking the address itself would pass the
location of the constant instead of the constant."
  (let ((address (cffi:foreign-symbol-pointer name)))
    (if address (cffi:mem-ref address :pointer) (cffi:null-pointer))))

(defun bundle-path ()
  "This application's .app directory, or NIL when it is not in one."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let ((identifier (%bundle-identifier)))
      (when identifier
        (objc:invoke-into 'string (objc:invoke "NSBundle" "mainBundle") "bundlePath")))))

(defun login-item-available-p ()
  "Whether registering as a login item is possible here.

NIL from the loose binary: there is no .app for the list to point at, and an
entry naming a bare executable would start it with no menu bar to draw in."
  (and (bundle-path) t))

(defmacro with-login-items ((list) &body body)
  "Bind LIST to the session's login item list for the extent of BODY."
  `(let ((,list (%shared-file-list-create
                 (cffi:null-pointer)
                 (%global "kLSSharedFileListSessionLoginItems")
                 (cffi:null-pointer))))
     (if (cffi:null-pointer-p ,list)
         nil
         (unwind-protect (progn ,@body)
           (%cf-release ,list)))))

(defun %our-item (list)
  "The login item pointing at this application, RETAINED, or NIL.

The caller owns the result and must release it.  That is not ceremony: a
CFArray owns its elements, so releasing the snapshot releases every item in it,
and an item returned across that release is a dangling pointer.  Removing
through one is a memory fault -- which is exactly what this did before the
RETAIN, and only on the remove path, because checking the status never
dereferenced the item it found.

The snapshot is a CFArrayRef, which is an NSArray -- so it is walked with
INVOKE rather than with CFArrayGetValueAtIndex, and the resolved URLs are
NSURLs whose -path can simply be compared."
  (let ((snapshot (%shared-file-list-snapshot list (cffi:null-pointer)))
        (ours (bundle-path)))
    (unless (cffi:null-pointer-p snapshot)
      (unwind-protect
           (loop for index below (objc:invoke snapshot "count")
                 for item = (objc:invoke snapshot "objectAtIndex:" index)
                 for url = (%shared-file-list-item-url
                            (objc:objc-object-pointer item) 0 (cffi:null-pointer))
                 unless (cffi:null-pointer-p url)
                   do (let ((path (objc:invoke-into 'string url "path")))
                        (%cf-release url)
                        (when (and path ours (string= path ours))
                          (return (objc:retain item)))))
        (%cf-release snapshot)))))

(defun login-item-status ()
  "Whether this application starts at login: :ENABLED, :NOT-REGISTERED, or
:NOT-FOUND when it is not running from a bundle and the question is void."
  (if (not (login-item-available-p))
      :not-found
      (objc:with-autorelease-pool ()
        (with-login-items (list)
          (let ((item (%our-item list)))
            (cond (item (objc:release item) :enabled)
                  (t :not-registered)))))))

(defun register-login-item ()
  "Add this application to the login items.  Returns the resulting status.

ENSURE-APPKIT before the pool, not inside it.  WITH-AUTORELEASE-POOL needs
NSAutoreleasePool, which is Foundation, which nothing has loaded when this is
the first Objective-C call the process makes -- and entering the pool first
fails with `Cannot find class \"NSAutoreleasePool\"', which reads like a broken
binding rather than an uninitialised runtime.  Every exported entry point in
this file initialises before it allocates."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let ((path (or (bundle-path)
                    (error "Not running from a bundle, so there is nothing to register."))))
      (with-login-items (list)
        (let ((url (objc:invoke "NSURL" "fileURLWithPath:" path)))
          (let ((item (%shared-file-list-insert
                       list (%global "kLSSharedFileListItemLast")
                       (cffi:null-pointer) (cffi:null-pointer)
                       (objc:objc-object-pointer url)
                       (cffi:null-pointer) (cffi:null-pointer))))
            (when (cffi:null-pointer-p item)
              (error "The login item list refused ~A." path))
            (%cf-release item))))))
  (login-item-status))

(defun unregister-login-item ()
  "Remove this application from the login items.  Returns the resulting status."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (with-login-items (list)
      (let ((item (%our-item list)))
        (when item
          (unwind-protect
               (%shared-file-list-item-remove list (objc:objc-object-pointer item))
            (objc:release item))))))
  (login-item-status))
