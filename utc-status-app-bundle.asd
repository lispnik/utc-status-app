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
  :version "0.2.0"
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
  ;; Drawn by tools/icon.lisp with the objc bindings this application is built
  ;; on -- see `make icon'.  asdf-macos-app converts the PNG to an .icns with
  ;; sips and iconutil, so there is no binary artwork checked in and changing it
  ;; is an edit rather than an asset pipeline.
  :bundle-icon "res/icon.png"
  :bundle-copyright "MIT"
  ;; Read from the environment, defaulting to ad hoc.
  ;;
  ;; Hardcoding a Developer ID here broke CI immediately and would break anyone
  ;; else who cloned this: `codesign' answers "no identity found" for a
  ;; certificate that is not in the keychain, and there is no reason a build
  ;; should require one.  Ad hoc runs locally and cannot be notarised, which is
  ;; the right default; notarising is the deliberate act that supplies the
  ;; identity.
  ;;
  ;;   make app SIGN_IDENTITY="Developer ID Application: You (TEAMID)"
  ;;   make notarize SIGN_IDENTITY=...
  ;;
  ;; #. rather than a plain call: ASDF does not evaluate a defsystem initarg, so
  ;; the value has to be computed when the file is READ.
  :code-signing-identity #.(let ((identity (uiop:getenv "UTC_STATUS_SIGN_IDENTITY")))
                             ;; An EMPTY value counts as absent.  GETENV answers
                             ;; "" for a variable that is set and empty, which
                             ;; make does whenever SIGN_IDENTITY is unset, and
                             ;; "" is not NIL -- so an OR here hands codesign an
                             ;; empty identity rather than falling back to ad hoc.
                             (if (and identity (plusp (length identity)))
                                 identity
                                 "-"))
  :bundle-output-directory "build/"
  :components ((:module "src"
                :components ((:file "main")))))

