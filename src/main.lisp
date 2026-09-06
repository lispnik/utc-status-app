;;;; src/main.lisp -- the binary's entry point.
;;;;
;;;; Kept out of #:utc-status-app itself so that loading the library into a REPL
;;;; does not drag in argument parsing, and so the build has exactly one file
;;;; that knows about the command line.

(in-package #:utc-status-app)

(defparameter +usage+
  "utc-status -- a menu-bar clock showing UTC.

  utc-status                 run until Quit is chosen from the menu
  utc-status --label \" UTC\"   append a label to the menu-bar title
  utc-status --timeout 30    stop after 30 seconds, whatever happens
  utc-status --print KEY     print one rendering of the current instant and exit
  utc-status --list          list the renderings and exit
  utc-status --help          this

With no arguments it puts a clock in the menu bar.  The clock is UTC, laid out
the way the system clock is laid out; clicking it offers ISO 8601 renderings at
descending resolution, and choosing one copies it to the clipboard.")

(defun %argument (name arguments)
  "The value following NAME in ARGUMENTS, or NIL."
  (let ((tail (member name arguments :test #'string=)))
    (second tail)))

(defun main ()
  "The binary's entry point.

Errors are reported and turned into a non-zero exit rather than dropping into
the debugger: a menu-bar application launched from the Finder has no terminal to
show a backtrace in, and a debugger prompt nobody can see is a hang."
  (let ((arguments (rest sb-ext:*posix-argv*)))
    (handler-case
        (cond
          ((or (member "--help" arguments :test #'string=)
               (member "-h" arguments :test #'string=))
           (write-line +usage+)
           (sb-ext:exit :code 0))
          ((member "--list" arguments :test #'string=)
           (let ((instant (now)))
             (dolist (rendering +renderings+)
               (format t "~12A ~28A ~A~%"
                       (string-downcase (rendering-key rendering))
                       (render instant (rendering-key rendering))
                       (rendering-description rendering))))
           (sb-ext:exit :code 0))
          ((member "--print" arguments :test #'string=)
           (let* ((name (%argument "--print" arguments))
                  (key (and name (intern (string-upcase name) :keyword))))
             (unless (and key (find-rendering key))
               (format *error-output* "~&No such rendering: ~A.  Try --list.~%" name)
               (sb-ext:exit :code 2))
             (write-line (render-now key)))
           (sb-ext:exit :code 0))
          (t
           (run :timeout (let ((seconds (%argument "--timeout" arguments)))
                           (when seconds (parse-integer seconds)))
                :label (%argument "--label" arguments))
           (sb-ext:exit :code 0)))
      ;; `utc-status --list | head' closes the pipe under us, and complaining
      ;; about it is noise: every well-behaved command-line tool exits quietly
      ;; when its reader has gone away.  Caught before the general handler
      ;; because a stream error IS an error and would otherwise be reported.
      (stream-error () (sb-ext:exit :code 0 :abort t))
      (error (condition)
        (format *error-output* "~&utc-status: ~A~%" condition)
        (sb-ext:exit :code 1)))))
