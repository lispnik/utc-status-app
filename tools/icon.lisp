;;;; tools/icon.lisp -- the application icon, drawn with the objc bindings.
;;;;
;;;; A build tool, not part of the application: it is loaded by `make icon' and
;;;; never enters the dumped image, which has no reason to carry drawing code
;;;; it will never run.
;;;;
;;;; The point is that the artwork is CODE.  There is no PNG checked in that
;;;; someone has to open Photoshop to change; the icon is a function, the
;;;; toolchain draws its own, and changing the colour is an edit rather than an
;;;; asset pipeline.
;;;;
;;;; Drawing offscreen means supplying a graphics context by hand.  A view gets
;;;; one from AppKit before -drawRect: is called; nothing does that here, so the
;;;; bitmap, the context and the save/restore are all explicit -- and NSColor
;;;; and NSBezierPath draw into whatever context is current, so forgetting the
;;;; -setCurrentContext: means every call silently draws nowhere.

(defpackage #:utc-status-icon
  (:use #:common-lisp)
  (:export #:render-icon #:main))

(in-package #:utc-status-icon)

(defparameter +appkit+
  "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit")

(defun ensure-appkit ()
  (objc:ensure-objc-initialized :modules (list +appkit+)))

(defun color (red green blue &optional (alpha 1))
  (objc:invoke "NSColor" "colorWithSRGBRed:green:blue:alpha:"
               (float red 1d0) (float green 1d0) (float blue 1d0) (float alpha 1d0)))

(defmacro with-bitmap ((rep size) &body body)
  "Draw BODY into a SIZE x SIZE bitmap bound to REP.

The context is pushed and popped rather than merely set: AppKit keeps a stack,
and a build that leaves a stale context current makes the NEXT drawing go
somewhere surprising."
  `(let ((,rep (objc:invoke (objc:invoke "NSBitmapImageRep" "alloc")
                            "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"
                            (cffi:null-pointer) ,size ,size 8 4 t nil
                            "NSCalibratedRGBColorSpace" 0 0)))
     (objc:invoke "NSGraphicsContext" "saveGraphicsState")
     (unwind-protect
          (progn
            (objc:invoke "NSGraphicsContext" "setCurrentContext:"
                         (objc:invoke "NSGraphicsContext"
                                      "graphicsContextWithBitmapImageRep:" ,rep))
            ,@body)
       (objc:invoke "NSGraphicsContext" "restoreGraphicsState"))
     ;; The bitmap, not the body's value: the caller wants the thing that was
     ;; drawn into, and it does not outlive this form otherwise.
     ,rep))

(defun rounded-rect (x y width height radius)
  (objc:invoke "NSBezierPath" "bezierPathWithRoundedRect:xRadius:yRadius:"
               (vector (float x 1d0) (float y 1d0)
                       (float width 1d0) (float height 1d0))
               (float radius 1d0) (float radius 1d0)))

(defun draw-monogram (text size &key font-fraction colour)
  "Centre TEXT in a SIZE x SIZE canvas.

Centred by MEASURING it -- -sizeWithAttributes: -- rather than by guessing at
offsets.  A monogram that is two pixels off centre looks wrong at 1024 and
looks broken at 32.

TEXT is turned into an NSString explicitly.  INVOKE takes a Lisp string as an
ARGUMENT and converts it, but a Lisp string as the RECEIVER names a CLASS -- so
sending -sizeWithAttributes: to \"TZ\" asks for a class called TZ and fails with
CANNOT FIND CLASS, which is a confusing way to be told to convert your string."
  (let* ((string (objc:string-to-ns-string text))
         (font (objc:invoke "NSFont" "boldSystemFontOfSize:"
                            (float (* size font-fraction) 1d0)))
         (attributes (objc:alloc-init-object "NSMutableDictionary")))
    (objc:invoke attributes "setObject:forKey:" font "NSFont")
    (objc:invoke attributes "setObject:forKey:" colour "NSColor")
    (let* ((extent (objc:invoke-into 'vector string "sizeWithAttributes:" attributes))
           ;; Horizontally, the measured width is the right thing.
           (x (/ (- size (aref extent 0)) 2))
           ;; Vertically it is not.  -drawAtPoint: puts the LINE BOX at the
           ;; point, and a line box reserves room for descenders -- which "TZ"
           ;; has none of, so centring on that height hangs the letters low by
           ;; half a descender.  Centre the INK instead: the cap height, sitting
           ;; on a baseline that is |descender| above the draw point.
           (cap-height (objc:invoke font "capHeight"))
           (descender (objc:invoke font "descender"))
           (y (- (/ (- size cap-height) 2) (abs descender))))
      (objc:invoke string "drawAtPoint:withAttributes:"
                   (vector (float x 1d0) (float y 1d0)) attributes))
    (objc:invoke attributes "release")))

(defun render-icon (path &key (size 1024))
  "Draw the icon at SIZE x SIZE and write it to PATH as a PNG.  Returns PATH."
  (ensure-appkit)
  (objc:with-autorelease-pool ()
    (let ((rep (with-bitmap (rep size)
      (let ((inset (* size 0.06)))
        ;; The plate.  macOS does not mask an application icon, so the rounded
        ;; corners have to be drawn; a full-bleed square would look like a
        ;; mistake beside every other icon in the Dock.
        (objc:invoke (color 0.10 0.13 0.22) "set")
        (objc:invoke (rounded-rect inset inset
                                   (- size (* 2 inset)) (- size (* 2 inset))
                                   (* size 0.22))
                     "fill"))
      (draw-monogram "TZ" size :font-fraction 0.42 :colour (color 0.98 0.85 0.45)))))
    (let* ((data (objc:invoke rep "representationUsingType:properties:"
                              4 (objc:invoke "NSDictionary" "dictionary")))
           (length (objc:invoke data "length"))
           (bytes (objc:invoke data "bytes"))
           (octets (make-array length :element-type '(unsigned-byte 8))))
      (dotimes (i length)
        (setf (aref octets i) (cffi:mem-aref bytes :unsigned-char i)))
      (with-open-file (out path :direction :output :element-type '(unsigned-byte 8)
                                :if-exists :supersede)
        (write-sequence octets out)))))
  path)

(defun main ()
  (let ((path (or (second sb-ext:*posix-argv*) "res/icon.png")))
    (ensure-directories-exist path)
    (format t "~&wrote ~a~%" (render-icon path))))
