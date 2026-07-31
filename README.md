# Notch

A scratchpad that lives in your MacBook's notch. Move the cursor up, type, walk away.
Everything you write goes to `~/Documents/NotchNotes/scratchpad.md` as plain markdown.

## Requirements

macOS 14+, a Mac with a physical notch, Swift 6 toolchain.

## Build and run

```bash
swift test              # geometry, storage, and state machine
./Scripts/bundle.sh     # produces build/Notch.app, ad-hoc signed
open build/Notch.app
```

The app has no Dock icon. It lives in the menu bar.

## Use

- Rest the cursor on the notch — the panel springs open after a beat
- Click it to pin it, then type
- Escape or a click elsewhere closes it
- Menu bar → Reveal Notes in Finder opens the notes folder

## Permissions

On first launch macOS asks for **Input Monitoring**. Hover detection currently
uses `NSEvent.addGlobalMonitorForEvents`, and on macOS 15.4+ *all* global event
monitoring is gated behind `kTCCServiceListenEvent` — not just keyboard
monitoring, as was the case historically. Deny it and the panel never opens,
because the hover monitor receives no events.

Grant it under System Settings → Privacy & Security → Input Monitoring. macOS
does not re-prompt after a denial; to get the prompt back:

```bash
tccutil reset ListenEvent com.yurikorolev.Notch
```

This is heavier than a notes app should require. The permission-free
alternative is `NSTrackingArea` on windows the app already owns — a small
catcher window over the notch while collapsed, and the panel's own tracking
area while open — with click-outside dismissal driven by
`NSWindow.didResignKeyNotification` instead of a global click monitor. That
rework is not done yet.

## How it works

The parts worth knowing before changing anything:

**The window never resizes.** One `NSPanel` is created at the full expanded
size (620×200) and pinned under the notch. Opening and closing animate SwiftUI
content *inside* that fixed window. Animating `NSWindow.frame` instead stutters
and fights the menu bar.

**Hover cannot come from the panel.** While collapsed the panel sets
`ignoresMouseEvents = true` so it never swallows clicks meant for menu bar items
beside the notch — and a window ignoring mouse events cannot detect its own
hover. So `HoverMonitor` watches `NSEvent.mouseLocation` instead. It needs both
a global *and* a local monitor: global monitors never fire for events routed to
our own app, so once the panel is key only the local one sees the cursor.

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

## Shipping to other people

Replace the ad-hoc signature in `Scripts/bundle.sh`:

```bash
codesign --force --options runtime --sign "Developer ID Application: YOUR NAME (TEAMID)" "$APP"
xcrun notarytool submit --keychain-profile notch --wait "$APP.zip"
xcrun stapler staple "$APP"
```

Note that Launch at Login only works for a properly signed app in
`/Applications`; `SMAppService.register()` fails for an ad-hoc build run from a
scratch directory, and the failure is logged rather than fatal.

## Layout

- `Sources/NotchKit` — geometry, storage, state machine, panel, views
- `Sources/Notch` — `@main` shell and menu bar
- `Tests/NotchKitTests` — headless tests for the pure parts

`NotchGeometry`, `ScratchpadStore`, and `NotchStateMachine` contain no AppKit,
which is what makes them testable without putting a window on screen. Keep it
that way.

`NotchChrome` takes its content as a slot, so a media or file-shelf module drops
in beside the scratchpad without touching hover, geometry, or the panel.

## Not built (yet)

Media controls, file shelf, ambient HUDs, global hotkey, virtual notch on
external displays, note search.

On media specifically: since macOS 15.4 the private MediaRemote framework is
entitlement-gated, so now-playing metadata (title, artist, artwork) is not
reliably obtainable by third-party apps. Transport controls alone — play/pause,
next, previous via HID key events — still work, and are the likely shape of a
future media module.
