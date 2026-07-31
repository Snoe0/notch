# Notch — hover-to-jot scratchpad

**Status:** approved 2026-07-31
**Scope:** v1, notes only

## Purpose

A background macOS app that makes the MacBook notch a target. Move the cursor
into the notch and a panel grows out of it. Type a note, it lands on disk. Move
away and it collapses.

The value is the absence of ceremony: no window to find, no app to switch to, no
save. The gesture — throw the cursor at the top of the screen — is the entire
interface.

## Non-goals for v1

Media controls, file shelf, ambient HUDs, global hotkey, external-display
support, note search and history. Each is deferred, not rejected. Section
"Module slot" describes how they attach later.

## Target

- Apple silicon MacBook with a physical notch, macOS 26+.
- Built for Developer ID signing and notarization. Not sandboxed, not App Store.
- Ad-hoc signed during development.

## Behavior

### States

```
collapsed ──hover 180ms──▶ peek ──click──▶ pinned
    ▲                       │                │
    └──── leave + 250ms ────┘                │
    └────────── Esc / click outside ─────────┘
```

- **collapsed** — nothing is drawn. The panel ignores mouse events entirely, so
  it cannot steal clicks from menu bar items beside the notch.
- **peek** — the panel is open because the cursor is inside it. It collapses
  250ms after the cursor leaves.
- **pinned** — the panel stays open regardless of cursor position. Dismissed by
  Escape or a click outside the panel.

The 180ms open delay and 250ms close grace both exist to prevent flapping when
the user is reaching for a menu bar item near the top of the screen.

### Focus

The panel takes keyboard focus without activating the app. The frontmost
application stays visually active while the user types into the notch.

## Architecture

### Window

One `NSPanel`, created once, permanently sized to the expanded bounds
(620×200pt) and pinned to the top-center of the built-in screen.

- Background fully transparent; the panel is a stage, not a visible window.
- Window level `.statusBar`.
- Collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  so it floats across Spaces and over fullscreen apps.
- Style mask `[.borderless, .nonactivatingPanel]` with `canBecomeKey`
  overridden to `true`. This is what allows typing without app activation.
- `ignoresMouseEvents` is `true` while collapsed, `false` while open.

**The window never resizes.** Expansion is animated by SwiftUI inside the fixed
window. Animating `NSWindow.frame` was rejected: it stutters and interacts badly
with the menu bar.

### Hover detection

Because the panel ignores mouse events while collapsed, it cannot detect its own
hover. Hover comes from `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`.

**Correction (found in testing).** This spec originally claimed global mouse
monitoring needs no permission, because historically only keyboard monitoring
did. That is false on macOS 15.4+: `kTCCServiceListenEvent` (Input Monitoring)
gates *all* global event monitoring. Denying it leaves the hover monitor with no
events and the panel never opens.

The permission-free replacement is `NSTrackingArea` on windows the app owns — a
catcher window sized to the notch while collapsed, the panel's own tracking area
while open — with click-outside dismissal from
`NSWindow.didResignKeyNotification` rather than a global click monitor. Not yet
implemented.

The monitor answers one question: is the cursor inside the current *active rect*?

- collapsed → active rect is the notch rect plus 4pt of slop below it
- open → active rect is the full expanded panel rect, so moving down into the
  panel does not collapse it

### Geometry

Notch dimensions are read from the screen, never hardcoded:

- height — `screen.safeAreaInsets.top`
- width — `screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`

`safeAreaInsets.top == 0` means no notch. The app then stays dormant: no panel,
no monitor, menu bar item still available to quit. Screen reconfiguration
(`NSApplication.didChangeScreenParametersNotification`) recomputes geometry.

### Storage

`ScratchpadStore` is the only component that touches disk.

- Single file: `~/Documents/NotchNotes/scratchpad.md`, UTF-8, plain markdown.
- The containing folder exists so archives and attachments can land beside it
  later without a migration.
- Writes are atomic and debounced 500ms after the last keystroke.
- A `DispatchSource` file watcher reloads the file when it changes externally
  (iCloud sync, another editor).
- **Conflict rule:** if the panel currently has focus, an external change does
  not clobber the in-memory buffer. The reload is deferred until the panel
  collapses.

Deleting the app leaves the notes behind as an ordinary text file. There is no
lock-in and no database.

### Module slot

`NotchChrome` renders the notch silhouette and the expand animation, and hosts
exactly one content module. v1 supplies `ScratchpadView`. A future
`MediaControlsView` or `FileShelfView` conforms to the same slot contract and
needs no change to the panel, hover, geometry, or state machine.

Media controls were deferred for a concrete reason: since macOS 15.4 the private
MediaRemote framework is entitlement-gated, so now-playing metadata (title,
artist, artwork) is not reliably obtainable by third-party apps. Transport
controls alone (play/pause/next via HID key events) still work, and are the
likely shape of a future media module.

## Components

| File | Responsibility |
|---|---|
| `NotchApp.swift` | entry point, `MenuBarExtra`: Reveal notes / Launch at login / Quit |
| `NotchGeometry.swift` | screen metrics → notch rect, collapsed and expanded frames. Pure. |
| `HoverMonitor.swift` | global mouse events → entered / exited the active rect |
| `NotchController.swift` | owns the panel, the state machine, and the timers |
| `NotchPanel.swift` | `NSPanel` subclass and its configuration |
| `NotchChrome.swift` | notch silhouette, expand animation, module slot |
| `ScratchpadView.swift` | the text surface |
| `ScratchpadStore.swift` | load, debounced save, file watch, conflict rule |

`NotchGeometry` and `ScratchpadStore` are pure enough to test without putting a
window on screen. They are where the real test coverage goes.

## Build and distribution

SwiftPM executable package plus `Scripts/bundle.sh`, which assembles `Notch.app`
with an `Info.plist` marking it `LSUIElement` (no Dock icon) and codesigns it.

No `.xcodeproj`. Build, test, bundle, and sign all run from the terminal, which
means the build is verifiable end to end without a GUI. Developer ID signing and
notarization are added to the same script when the app is ready to hand out.

## Testing

- `NotchGeometry` — unit tests over synthetic screen metrics: notch present,
  notch absent, varying safe-area insets and auxiliary area widths.
- `ScratchpadStore` — round-trip through a temporary directory; debounce
  coalescing; external-change reload; the focused-buffer conflict rule.
- State machine transitions — driven by injected clock and synthetic hover
  events, no window required.
- Panel, chrome, and animation are verified manually on device.

## Error handling

- Notes directory missing or uncreatable → the panel still opens and accepts
  text; a non-blocking banner reports that saving is unavailable. Text is never
  silently discarded.
- Write failure → surface the same banner and keep the buffer in memory. The
  next keystroke schedules another attempt, so recovery is automatic once the
  underlying problem clears.
- No notch detected → dormant, as described in Geometry.
- Screen disconnect while pinned → collapse and recompute.

## Open questions

None blocking. `scratchpad.md` as a single file may later want a daily-file
variant (`2026-07-31.md`); the folder layout already permits that without
migration.
