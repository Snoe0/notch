# Notch v2 — Media Controls, To-dos, Open-Sourcing

Date: 2026-08-06
Status: approved

## Context

Notch v1 is a scratchpad living in the MacBook notch: one fixed 620×200
`NSPanel` pinned under the notch, a collapsed/peek/pinned state machine driven
by cursor polling, and a `ScratchpadStore` that persists to
`~/Documents/NotchNotes/scratchpad.md` with debounced atomic writes and a
directory watcher. `NotchChrome` renders the surface with a content slot that
was designed to take new modules.

v2 adds media controls and a to-do list, and prepares the project for a public
GitHub release with a DMG-based installer.

## Layout

The panel keeps its single fixed window and content-only animation. Height
grows 200 → 260; width stays 620.

```
┌──────────────┬──[ notch ]──┬─────────────┐
│ ♫ Title      │   (notch    │   (empty)   │  ← top strip, notch height
│   ⏮ ⏯ ⏭    │  clearance) │             │
├──────────────┴─────────────┴─────────────┤
│ ☐ ship v2            │  notes input…     │
│ ☐ email Sam          │                   │
│ [ add a todo… ]      │                   │
└──────────────────────────────────────────┘
```

- **Top strip** — notch-height row. `NotchChrome` currently pads the entire
  top by the notch height; it changes to a three-part row: media strip (left),
  notch-width spacer (center), empty strip (right). Side widths fall out of
  existing geometry: the panel is centered on the notch, so each side is
  `(panelWidth − notchWidth) / 2`.
- **Bottom area** — two columns: to-do list (left), notes input (right),
  divided by a hairline.

## Media controls (`MediaController`)

- New `@MainActor ObservableObject` in NotchKit.
- Reads and controls **Music.app and Spotify only**, via AppleScript executed
  through `/usr/bin/osascript` as a child `Process` off the main thread.
  No private frameworks (MediaRemote is blocked since macOS 15.4).
- Polls every 2 seconds **only while the panel is open**. Consequences: the
  Automation permission prompt ("Notch wants to control Music") first appears
  on first panel open, not at launch; zero cost while collapsed.
- Published state: `nowPlaying: NowPlaying?` with title, artist, isPlaying,
  and source app.
- Source selection: the app currently playing wins; if both are paused, the
  most recently playing wins; if neither app is running, the strip shows a
  quiet idle state (dimmed ⏮ ⏯ ⏭, no text).
- ⏮ ⏯ ⏭ send `previous track` / `playpause` / `next track` to the selected
  app only.
- The scripting layer sits behind a protocol (e.g. `MediaScripting`) so
  source-selection and parsing logic is unit-tested with a fake; only the
  `osascript` adapter is untested glue.
- Script errors (app not running, permission denied) degrade to the idle
  state. No banners, no retries beyond the next poll tick.

## To-do list (`TodoStore`)

- New `@MainActor ObservableObject` in NotchKit owning
  `~/Documents/NotchNotes/todos.md`.
- File format: one `- [ ] item` / `- [x] item` line per todo, plain markdown,
  editable in any editor. The file is rewritten from the in-memory list on
  save; non-checklist lines are not preserved (documented in README).
- Model: `TodoItem { id: UUID, text: String, isDone: Bool }`. Parsing and
  serialization are pure functions with unit tests.
- UI behavior: checkbox click toggles done (rendered struck-through, stays in
  the list), hover reveals a × that deletes, a small field at the bottom
  appends on return. List scrolls if it outgrows its column.
- External edits reload through the same directory-watcher pattern as the
  scratchpad, suppressed while the add-field has focus.

## Persistence refactor (`PersistedFile`)

`ScratchpadStore`'s machinery — debounced save task, atomic write with
directory creation, save-error surfacing, directory watcher that survives
inode swaps, external-reload suppression while editing — is extracted into a
shared helper (`PersistedFile`). `ScratchpadStore` and `TodoStore` both build
on it. Observable behavior of the scratchpad is unchanged; existing
`ScratchpadStoreTests` keep passing.

## Views

- `MediaControlsView` — compact strip: title/artist (truncating, small type)
  plus three borderless buttons. Fits ~215×notch-height.
- `TodoListView` — checkbox rows + add field.
- `PanelContentView` — composes the top strip and the two columns; replaces
  the bare `ScratchpadView` in the content slot. `ScratchpadView` becomes the
  notes column.
- `NotchChrome` gains the top-row layout described above; everything else
  (transitions, clip shape, shadow) is unchanged.

## Unchanged

State machine, cursor polling, hover rects, panel window behavior,
Input Monitoring permission story, menu bar items, launch-at-login.

New permission: one Automation prompt per media app, on first panel open.

## Distribution & open-sourcing

- **License**: MIT, © 2026 Yuri Korolev, at repo root.
- **README**: rewritten for a public audience — what it is, screenshot
  placeholder, install (DMG + one-line curl of the DMG from latest release),
  build-from-source, both permission prompts explained, file locations,
  contributing note, license badge.
- **.gitignore**: ensure `build/` and `.build/` artifacts are ignored and
  untracked; committed binaries removed from the index.
- **DMG**: `Scripts/make-dmg.sh` builds `build/Notch.dmg` via `hdiutil` with
  the classic drag-to-/Applications layout (app + Applications symlink).
- **Release workflow**: `.github/workflows/release.yml` on tag push `v*`:
  build, test, bundle, make DMG, attach to a GitHub Release.
  - Signing is parameterized: if `MACOS_CERTIFICATE`-style secrets are
    present, sign with Developer ID and notarize with `notarytool` + staple;
    otherwise fall back to ad-hoc signing (current state). The owner is
    obtaining a Developer ID; adding secrets flips notarization on with no
    workflow edits.
- **CI workflow**: `.github/workflows/ci.yml` runs `swift test` on pushes and
  PRs (macOS runner).
- **Publishing**: `gh repo create --public` + push happens only after the
  owner reviews the finished state. No Claude attribution anywhere in
  history, commits, or docs.

## Testing

- Existing: geometry, state machine, scratchpad store, smoke — unchanged and
  passing.
- New: todo markdown round-trip (parse/serialize), `TodoStore` persistence and
  external-reload (via `TemporaryDirectory`), `MediaController` source
  selection and command routing with a fake `MediaScripting`.
- Manual: panel open/close feel, media prompt flow, DMG install on a clean
  account.

## v2.1 addendum (2026-08-06, after first hands-on test)

**Add-field fix.** Focus in the panel is grabbed only on the transition into
the pinned state, never continuously; the todo add field becomes an
AppKit-backed `NSTextField`, matching the scratchpad's `NSTextView` rationale
(SwiftUI focus machinery is unreliable in a borderless non-activating panel).

**Album artwork.** `MediaSnapshot` carries artwork identity; artwork bytes are
fetched only when the track changes (Music: AppleScript `artwork 1` raw data;
Spotify: `artwork url` + URLSession), cached per track, published by
`MediaController` as an image. Shown small in the media strip and larger in
the popout.

**Now-playing popout.** Music and Spotify post public
`DistributedNotificationCenter` notifications on playback changes
(`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) with
title/artist/state in userInfo — no polling, no permission. `MediaController`
listens always; when a track starts or changes while the panel is collapsed,
the chrome shows a small non-interactive now-playing lozenge under the notch
for ~3 seconds (artwork + title), spring-animated like the panel. Hovering
into the notch during a popout follows the normal open flow. While collapsed,
AppleScript (artwork/metadata refinement) runs only if Automation permission
is already granted — checked silently via
`AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded = false` — so
the permission prompt still first appears on a user-initiated panel open,
never because a song changed in the background.

## Non-goals (v2)

- Now-playing from browsers or other apps (needs private API).
- Album artwork.
- Always-visible collapsed-state UI beside the notch.
- Homebrew tap (revisit post-release).
- Preserving arbitrary markdown in todos.md.
