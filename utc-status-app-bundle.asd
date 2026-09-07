;;;; utc-status-app-bundle.asd -- the .app bundle, in its own file.
;;;;
;;;; SEPARATE FROM utc-status-app.asd ON PURPOSE, and it was not at first.
;;;; :DEFSYSTEM-DEPENDS-ON is resolved when the .asd is READ, not when the system
;;;; it belongs to is built -- so with this system in the main file, loading
;;;; #:utc-status-app at all required asdf-macos-app to be present, and someone
;;;; who had cloned only objc got `Component "asdf-macos-app" not found'.  CI
;;;; never saw it, because CI always has both.
;;;;
;;;; In its own file the dependency is only resolved when the bundle is asked
;;;; for, which is what `make app' does and nothing else needs.

;;;; The .app bundle.
;;;;
;;;; A menu-bar application really wants to be a bundle: LSUIElement is what
;;;; tells the Dock and the application switcher to leave it alone, and it lives
;;;; in an Info.plist, which a bare executable does not have.  RUN sets the
;;;; activation policy to Accessory at startup anyway -- that is what makes the
;;;; loose binary work at all -- but doing it in code means the Dock icon exists
;;;; for the instant before the policy is set.  :BUNDLE-AGENT is the same thing
;;;; declared, and declared wins.
;;;;
;;;; Kept separate from #:utc-status-app/app rather than replacing it.  The bare
;;;; binary is what `utc-status --print seconds' is for, and a .app is an awkward
;;;; thing to put in a shell pipeline.
(asdf:defsystem #:utc-status-app-bundle
  :description "UTC Status.app, a menu-bar bundle."
  :defsystem-depends-on ("asdf-macos-app")
  :class :macos-app-system
  :build-operation "macos-app-op"
  :depends-on (#:utc-status-app)
  :entry-point "utc-status-app:main"
  :version "0.1.0"
  :bundle-identifier "com.lispnik.utc-status"
  :bundle-name "UTC Status"
  :bundle-executable "utc-status"
  ;; LSUIElement: no Dock icon, no application menu, but it may have UI.  The
  ;; whole point of a status-bar application.
  :bundle-agent t
  ;; NSPrincipalClass, so AppKit is initialised as it would be for any Cocoa
  ;; application rather than being brought up halfway through our own startup.
  :bundle-principal-class "NSApplication"
  :bundle-category "public.app-category.utilities"
  :bundle-copyright "MIT"
  ;; UNSIGNED, and not by preference.  An SBCL image cannot be codesigned on
  ;; this toolchain at all: SAVE-LISP-AND-DIE appends the core to a Mach-O that
  ;; Homebrew already shipped linker-signed, and codesign then refuses the file
  ;; with "main executable failed strict validation" -- for --sign - as much as
  ;; for a Developer ID, and whether or not the old signature is removed first.
  ;; Measured on SBCL 2.6.8/arm64, on the bare binary as well as in a bundle, so
  ;; it is the image and not this build.
  ;;
  ;; asdf-macos-app names this as the most fragile part of its pipeline and it
  ;; is right.  The bundle still launches -- the dumped executable keeps the
  ;; runtime's own ad hoc signature, which macOS accepts locally -- but it
  ;; cannot be notarised, so it cannot be handed to anyone else.  Set an
  ;; identity here when that is solved upstream; nothing else needs to change.
  :code-signing-identity nil
  :bundle-output-directory "build/"
  :components ((:module "src"
                :components ((:file "main")))))

