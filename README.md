# utc-status

[![macOS](https://github.com/lispnik/utc-status-app/actions/workflows/ci-macos.yml/badge.svg)](https://github.com/lispnik/utc-status-app/actions/workflows/ci-macos.yml)

A macOS menu-bar clock showing UTC, written in Common Lisp.

The title is the current time in UTC, laid out the way your system clock is laid
out. Clicking it opens a menu of ISO 8601 renderings at descending resolution;
choosing one copies that rendering of the current instant to the clipboard.

```
Sun Sep 6  02:05          <- ours, UTC
Sat Sep 5  21:05          <- the system clock, local
```

Built on [objc](https://github.com/lispnik/objc), the LispWorks Objective-C
interface reimplemented for SBCL. The status item, its menu, the timer and the
pasteboard are all Objective-C objects driven from Lisp, and the menu's actions
are Lisp methods on a Lisp-defined class.

## Building and running

```
make            # build bin/utc-status
make test       # the FiveAM suite
make run        # build and run
```

The objc bindings are a sibling checkout rather than an ocicl package, so clone
both and the defaults line up:

```
git clone https://github.com/lispnik/objc.git
git clone https://github.com/lispnik/utc-status-app.git
cd objc && ocicl install     # every dependency of BOTH projects is listed here
cd ../utc-status-app && make
```

The Makefile builds a source registry from this tree plus that one, with
`:ignore-inherited-configuration` so a missing dependency fails loudly rather
than resolving to whatever is in your `~/.sbclrc`. `OBJC_DIR` overrides where it
looks and defaults to `~/Projects/common-lisp/objc`.

`ocicl install` belongs in the **objc** checkout: this project has no `ocicl.csv`
of its own, and every Lisp dependency it has — cffi, alexandria, closer-mop,
bordeaux-threads, trivial-features, float-features, fiveam — comes from objc's.

`make env` prints what the layout code decided on your machine, which is the
first thing to look at if the menu-bar text is not the shape you expected:

```
$ make env
machine:     ARM64
lisp:        SBCL 2.6.8
preferences: (:DAY-OF-WEEK T :DATE T :SECONDS NIL)
skeleton:    "EEEMMMdjmm"
title:       "Sun Sep 6  07:15"
```

```
./bin/utc-status                  # the menu-bar clock
./bin/utc-status --label " UTC"   # append a label to the title
./bin/utc-status --list           # every rendering of right now
./bin/utc-status --print seconds  # one rendering, for a script
./bin/utc-status --timeout 30     # stop after 30 seconds, whatever happens
```

`--list` and `--print` need no window server, so the renderings are usable from
a shell:

```
$ ./bin/utc-status --print basic
20260906T020523Z
```

## Starting it at login

```
make install-agent      # install to ~/.local/bin and load the LaunchAgent
make agent-status       # what launchd thinks of it
make uninstall-agent    # stop it and remove the agent
```

A **LaunchAgent**, not a LaunchDaemon: an agent runs in your GUI session, which
is the only place a status item can exist. A daemon runs before login, in no
session, with no menu bar to put anything in.

Three details in `etc/com.lispnik.utc-status.plist.in` are deliberate:

**`KeepAlive` is `{SuccessfulExit: false}`, not `true`.** A bare `true` is the
obvious thing and is a trap: choosing Quit from the menu exits 0, and launchd
would put the item straight back in the menu bar. A Quit that does not quit is
worse than no Quit at all. This restarts it only while it keeps *failing*.

**The agent points at `$(PREFIX)/bin`, not at `./bin`.** `make install-agent`
copies the binary to `~/.local/bin` first, so that `make clean` — or moving this
checkout — does not leave launchd trying to start something that is no longer
there.

**Every path in it is absolute.** A plist cannot expand `~` or `$HOME`, and one
with a relative path fails by never starting. That is why the file is a template
with `@BINARY@` and `@LOGS@` filled in at install time rather than a plist you
copy.

`install-agent` boots the label out before bootstrapping it, and ignores the
failure: bootstrapping a label that is already loaded is an error, so without
that the second `make install-agent` would fail.

Output goes to `~/Library/Logs/utc-status.log`. It is normally empty — if the
clock is not in your menu bar, that file and `make agent-status` are the two
places to look, along with [the note about a crowded menu
bar](#known-it-may-not-appear-on-a-crowded-menu-bar).

## The renderings

| Key | Example | For |
|---|---|---|
| `microseconds` | `2026-09-06T02:05:23.043479Z` | full precision, as the clock has it |
| `milliseconds` | `2026-09-06T02:05:23.043Z` | what most log formats use |
| `seconds` | `2026-09-06T02:05:23Z` | the everyday ISO 8601 timestamp |
| `minutes` | `2026-09-06T02:05Z` | reduced accuracy |
| `hours` | `2026-09-06T02Z` | reduced accuracy |
| `date` | `2026-09-06` | the calendar date alone |
| `month` | `2026-09` | |
| `year` | `2026` | |
| `basic` | `20260906T020523Z` | no separators — sorts, and is safe in a filename |
| `week` | `2026-W36-7` | ISO week date |
| `ordinal` | `2026-249` | ISO ordinal date |

The menu shows each of these as a live example, retitled just before it opens, so
the line you click is the string you get.

## What "the same layout as the system clock" means here

Not a format string copied from one Mac. The system clock's shape is a set of
preferences — day of week, date, seconds, and the 12/24-hour choice — so this
reads `com.apple.menuextra.clock` and builds the same shape from them. Change a
setting and this follows on the next launch.

Two details make that work outside one machine:

**The field order is the locale's.** Rather than concatenating "EEE" and "MMM d"
in the order an English speaker expects, the preferences become a Unicode
date-field *skeleton* — an unordered set of the fields wanted — and
`+dateFormatFromTemplate:options:locale:` turns that into the pattern the locale
actually uses. `en_US` gives `EEE MMM d`, `en_GB` gives `EEE d MMM`, and neither
is written down anywhere here.

**The hour field is `j`, not `H` or `h`.** `H` forces 24-hour and `h` forces 12;
`j` means "whichever this locale uses", which is what follows the 24-Hour Time
switch in Settings. Asking for `H` gives a 12-hour user 24-hour time silently and
forever.

One thing has to be undone afterwards: `dateFormatFromTemplate:` writes a pattern
for *prose*, joining the date and time with a word — `EEE, MMM d 'at' HH:mm` —
and the menu bar does no such thing. So the quoted literals and the commas are
stripped. Removing every *quoted* literal rather than the English word "at" is
what keeps it working in German (`'um'`) and French (`'à'`).

## Known: it may not appear on a crowded menu bar

The item can be created, report itself visible, be given a real frame — and still
not be on screen, because macOS has run out of menu bar. This happened while the
app was being written: with a long application menu (IntelliJ's runs to about
850px on a 1470pt screen) and a full status area, the item was placed at x=424,
underneath the active application's menu titles, where nothing draws it.

Nothing warns you. If the clock does not appear, make room: quit some menu-bar
items, or use something like Ice or Bartender, or check with a frontmost
application whose menu is shorter.

## Design

Three systems in one `.asd`:

| System | Contents |
|---|---|
| `utc-status-app` | the library |
| `utc-status-app/app` | `program-op` → `bin/utc-status`, entry point `utc-status-app:main` |
| `utc-status-app/tests` | the FiveAM suite |

`src/iso.lisp` has no Objective-C in it. Everything there is a pure function of
an instant, which is what lets the suite check the formatting on any machine in
any timezone — and it is why the renderings are a table rather than a `case`
inside the menu handler: the menu, the command line and the tests all walk the
same list, and three places that each know the renderings is three places to
forget one.

`:build-pathname` is resolved against the *system's* pathname, so the components
live in a `:module` rather than under a system-level `:pathname` — otherwise the
binary lands in `src/bin/utc-status`.

### Four things about the AppKit side that are not obvious

Three of them fail silently.

**The application must be an accessory.** `NSApplicationActivationPolicyRegular`
is the default and is right for something that owns windows. A Regular
application with no windows that has never been activated does not get its
status item's menu tracked — the item draws, and clicking it does nothing.

**It must use `-[NSApplication run]`, not a pump loop.** A status item's menu is
tracked in AppKit's own nested run-loop mode while the mouse is down. A loop
that pumps `kCFRunLoopDefaultMode` by hand — the right way to keep a *window*
alive from a REPL — starves that tracking, and the symptom is identical to the
wrong activation policy.

**The timer must be added in `NSRunLoopCommonModes`.** A timer scheduled the
ordinary way runs in the default mode only, so it stops while a menu is open —
and this menu shows timestamps, so the one moment the clock must not freeze is
exactly the moment it would. `+scheduledTimerWithTimeInterval:` does the ordinary
thing, which is why the timer is created unscheduled and added by hand.

**`-stop:` alone does not end `-run`.** It sets a flag the loop notices only when
it next finishes processing an event, so an idle loop sits there. A dummy event
posted behind the stop guarantees there is an event to finish.

`--timeout` is a fifth timer rather than a watchdog thread, and that was not the
first design. The thread version *looked* correct and did not work: it woke on
schedule, saw the application still running, and sent
`-performSelectorOnMainThread:` without raising — and the application carried on,
with nothing anywhere to say why. A one-shot timer needs no cross-thread
messaging, no reasoning about which thread may call `-stop:`, and is stopped by
the same `-invalidate` as the clock.

### And two about the rest

**AppKit has to be asked for.** `ensure-objc-initialized` loads Foundation and
nothing else, which is the right default for a binding — but everything visible
here is AppKit, and the symptom of forgetting is `Cannot find class "NSMenu"`,
which reads like a fault in the bindings and is a missing framework. It is worth
the file it gets (`src/frameworks.lisp`) because of how it was found: the menu
tests were passing only when the clipboard test happened to run first and load
AppKit on their behalf, so the suite was green in one order and skipped in
another. Every entry point that touches an AppKit class now calls
`ensure-appkit` rather than trusting that something else already did.

**`-clearContents` is not tidiness.** A pasteboard holds one item per type, and
the owner of each type is whoever wrote it last. Writing a string without
clearing leaves every other representation of the *previous* contents in place,
so an application that prefers a richer type pastes the old value while a plain
text editor pastes the new one — copy works everywhere except the one
application the user cares about.

## Tests

97 checks — 95 without the clipboard ones. The formatting half is checked against instants worked out
independently rather than by running the code and recording what it said, which
is the failure a formatting suite is most prone to: a test that agrees with the
bug. Beyond the obvious coverage:

- fractional seconds **truncate rather than round**, because a timestamp that
  rounds up names an instant that has not happened yet;
- the ISO week year is not the calendar year — 2027-01-01 is `2026-W53-5`;
- the skeleton uses `j` and never `H` or `h`;
- the menu-bar title is UTC and not local;
- and choosing a menu item is tested by sending `-copyRendering:` with a real
  menu item as the sender, which exercises the tag lookup and the pasteboard
  write, leaving only the mouse untested.

There is deliberately no "skip if Objective-C is unavailable" wrapper. An
earlier version had one, and it turned the missing-AppKit bug above into two
quiet skips rather than two failures. This is macOS-only software; a class that
will not resolve is a failure, and should read as one.

The clipboard tests are gated behind `UTC_STATUS_TEST_CLIPBOARD`, and `make test`
leaves them out. The general pasteboard belongs to whoever is at the keyboard,
and a suite that overwrites it has thrown away whatever they had copied. `make
test-clipboard` opts in.

## License

MIT.
