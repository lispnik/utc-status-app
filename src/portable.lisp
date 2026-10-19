;;;; src/portable.lisp -- what SBCL and ECL spell differently.
;;;;
;;;; The Developer ID bundle is SBCL, from asdf-macos-app; the Mac App Store
;;;; bundle is ECL (see tools/build-ecl.lisp).  Everything else here is portable
;;;; Common Lisp over objc, which runs on both, so these are the process's
;;;; edges: its arguments, its exit, the time of day to the microsecond, and
;;;; where an ECL bundle's output goes.

(in-package #:utc-status-app)

(defun command-arguments ()
  "The arguments after the program name."
  (rest #+sbcl sb-ext:*posix-argv*
        #+ecl (ext:command-args)
        #-(or sbcl ecl) (uiop:raw-command-line-arguments)))

(defun exit-now (code)
  "End the process with CODE at once: no unwinding, no exit hooks.

_exit(2) through CFFI, so it is the same act on both implementations."
  (cffi:foreign-funcall "_exit" :int code :void))

(defun time-of-day ()
  "(VALUES SECONDS MICROSECONDS) since the epoch, from gettimeofday(2).

SB-EXT:GET-TIME-OF-DAY is SBCL's; this is the same call through CFFI.  On
Darwin a struct timeval is a 64-bit tv_sec and a 32-bit tv_usec, padded to
sixteen bytes."
  (cffi:with-foreign-object (tv :uint8 16)
    (cffi:foreign-funcall "gettimeofday" :pointer tv :pointer (cffi:null-pointer) :int)
    (values (cffi:mem-ref tv :int64 0) (cffi:mem-ref tv :int32 8))))

(defun redirect-output-to-log ()
  "Inside an ECL bundle, send output to ~/Library/Logs/<bundle name>.log.

asdf-macos-app's toplevel does this for the SBCL bundle; the ECL bundle is
assembled without it, and a process LaunchServices starts has /dev/null for
standard output.  Only when output is not a terminal, so running the executable
from a shell still prints there; MACOS_APP_LOG, if set, names the file instead,
as it does for the SBCL bundle -- /dev/stderr, say, since the sandboxed
bundle's own log is in a container no other process may read."
  #+ecl
  (let ((override (uiop:getenv "MACOS_APP_LOG")))
    (unless (and (not override) (= 1 (cffi:foreign-funcall "isatty" :int 1 :int)))
      (let* ((name (ignore-errors
                    (objc:invoke-into 'string (objc:invoke "NSBundle" "mainBundle")
                                      "objectForInfoDictionaryKey:" "CFBundleName")))
             (path (cond ((and override (plusp (length override))) override)
                         ((and name (plusp (length name)))
                          (merge-pathnames (format nil "Library/Logs/~A.log" name)
                                           (user-homedir-pathname))))))
        (when path
          (let ((stream (open path :direction :output :if-exists :append
                                   :if-does-not-exist :create)))
            (setf *standard-output* stream
                  *error-output* stream)))))))
