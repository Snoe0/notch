# Notch

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A scratchpad, a short to-do list, and media controls that live in your MacBook's
notch. Rest the cursor on the notch and a panel springs out of it; move away and
it disappears. No Dock icon, no window to manage.

- **Notes** — everything you type goes to `~/Documents/NotchNotes/scratchpad.md`
  as plain markdown, saved as you go.
- **To-dos** — a short checklist in `~/Documents/NotchNotes/todos.md`. Click to
  tick, hover to delete, type at the bottom to add.
- **Media** — title, artist, and ⏮ ⏯ ⏭ for Music.app and Spotify, in the strip
  beside the notch.

<!-- Screenshot pending — capture the open panel and save it to docs/screenshot.png, then uncomment:
![The Notch panel open under the notch](docs/screenshot.png)
-->

## Requirements

macOS 14 or later, on a Mac with a physical notch. On any other Mac the app
launches, finds no notch, and stays dormant.

## Install

Download `Notch.dmg` from the
[latest release](https://github.com/yurikorolev/notch/releases/latest), open it,
and drag Notch to Applications.

Until notarized builds ship, the release DMG is ad-hoc signed, so Gatekeeper
will refuse a plain double-click. Right-click Notch in Applications → **Open**,
then confirm. That is only needed once.

## Build from source

```bash
swift test              # geometry, storage, to-do parsing, state machine
./Scripts/bundle.sh     # produces build/Notch.app, ad-hoc signed
open build/Notch.app
```

`./Scripts/make-dmg.sh` wraps the bundled app into `build/Notch.dmg` with the
usual drag-to-Applications layout.

Note that Launch at Login only works for a properly signed app in
`/Applications`; `SMAppService.register()` fails for an ad-hoc build run from a
scratch directory, and the failure is logged rather than fatal.

## Use

- Rest the cursor on the notch — the panel springs open after a beat
- Click it to pin it, then type
- Escape or a click elsewhere closes it
- Menu bar → Reveal Notes in Finder opens the notes folder

## Permissions

### Automation (Music and Spotify)

The first time the panel opens, macOS asks whether **Notch wants to control
Music** — and separately whether it wants to control **Spotify**, one prompt per
app, the first time that app is queried. Notch reads now-playing state and sends
transport commands over AppleScript; there is no other supported way to do this
since macOS 15.4 gated the private MediaRemote framework behind an entitlement.

Deny it and nothing breaks: the media strip stays in its quiet idle state
(dimmed buttons, no text) and the rest of the panel works as usual. macOS does
not re-prompt after a denial; to get the prompt back:

```bash
tccutil reset AppleEvents com.yurikorolev.Notch
```

Automation prompts appear on first panel open rather than at launch, because
Notch only polls the media apps while the panel is actually open.

### Input Monitoring — not required

Notch does **not** ask for Input Monitoring, and this took some work.

Hover detection originally used `NSEvent.addGlobalMonitorForEvents`, and on
macOS 15.4+ *all* global event monitoring is gated behind
`kTCCServiceListenEvent` — not just keyboard monitoring, as was the case
historically. Denying it left the panel permanently shut, because the hover
monitor received no events. That is a heavy permission for a notes app to
demand.

`NSTrackingArea` was the obvious permission-free alternative, but it needs a
window under the cursor that accepts mouse events — which would mean swallowing
clicks over the notch — and in practice such a window only starts reporting
after it receives a real mouse event, so hover did not register until the notch
was clicked.

What works is reading the cursor position directly. `NSEvent.mouseLocation` is
not TCC-gated; only *monitoring events* is. A point-in-rect test 30 times a
second costs less than either alternative and needs no permission at all.

If you ran an early build and granted Input Monitoring, you can take it back
under System Settings → Privacy & Security → Input Monitoring, or with
`tccutil reset ListenEvent com.yurikorolev.Notch`.

## Files

Everything lives in `~/Documents/NotchNotes/`:

- `scratchpad.md` — the notes column, saved verbatim.
- `todos.md` — one `- [ ] item` / `- [x] item` line per to-do.

Both are plain markdown and can be edited in any editor; Notch watches the
directory and reloads external changes. One caveat: `todos.md` is *rewritten*
from the app's in-memory list on every save, so lines that are not checklist
items — headings, prose, blank-line structure — are not preserved.

## How it works

The parts worth knowing before changing anything:

**The window never resizes.** One `NSPanel` is created at the full expanded
size and pinned under the notch. Opening and closing animate SwiftUI content
*inside* that fixed window. Animating `NSWindow.frame` instead stutters and
fights the menu bar.

**Hover is polled, not monitored.** While collapsed the panel sets
`ignoresMouseEvents = true` so it never swallows clicks meant for menu bar items
beside the notch — and a window ignoring mouse events cannot detect its own
hover. `CursorWatcher` therefore polls `NSEvent.mouseLocation` against an active
rect that grows from the notch to the whole panel once it opens. See the
Permissions section above for why the event-monitor and tracking-area routes
were abandoned.

**Typing does not steal activation.** `NotchPanel` combines `.nonactivatingPanel`
with `canBecomeKey → true`. Neither alone is enough. Together they let the panel
take keystrokes while the frontmost app keeps its active appearance.

**Collapsing orders the panel out** rather than just hiding its content. That is
what releases key status — `resignKey()` must never be called directly.

**The file watcher watches the directory, not the file.** Atomic writes replace
the file's inode, which would silently orphan a file-level watcher.

**Notch geometry is measured, not assumed.** Real hardware reports asymmetric
auxiliary areas — 665pt left and 662pt right on the 14" this was built on — so
the notch rect is derived from where those areas end rather than by centring on
the screen. Centring puts it 1.5pt off.

**Media is AppleScript, polled only while open.** `MediaController` shells out
to `osascript` off the main thread every couple of seconds, and only while the
panel is open — so a collapsed Notch costs nothing and never triggers a
permission prompt out of nowhere. Script errors, a quit app, or a denied
Automation prompt all degrade to the same idle state. Notes and to-dos share one
persistence helper (`PersistedFile`) for the debounced atomic write, the
directory watcher, and the suppression of external reloads while you are typing.

## Contributing

Issues and pull requests are welcome. Run `swift test` before opening one — the
pure parts (`NotchGeometry`, `ScratchpadStore`, `TodoStore`, `MediaController`'s
source selection, `NotchStateMachine`) are covered headlessly and should stay
that way.

- `Sources/NotchKit` — geometry, storage, state machine, panel, views
- `Sources/Notch` — `@main` shell and menu bar
- `Tests/NotchKitTests` — headless tests for the pure parts

The AppKit-free parts are what make testing possible without putting a window on
screen. Keep it that way. `NotchChrome` takes its content as a slot, so a new
module drops in beside the existing ones without touching hover, geometry, or
the panel.

## Not built (yet)

File shelf, ambient HUDs, global hotkey, virtual notch on external displays,
note search, album artwork.

On media specifically: since macOS 15.4 the private MediaRemote framework is
entitlement-gated, so now-playing metadata is not obtainable for arbitrary apps.
Music and Spotify are covered because both ship a scripting dictionary; browsers
and other players are not, and cannot be without a private API.

## License

MIT — see [LICENSE](LICENSE).
