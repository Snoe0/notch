# Notch — feedback round (2026-08-07)

Nine features from user feedback plus a docs-image refresh and two mid-round
additions, each implemented by a dedicated subagent with its own commit.
Wave 1 ran in parallel (disjoint files); the notes-stack work ran sequentially.
Previous milestone plans live in git history of this file.

## Wave 1 — parallel, disjoint files

- [x] Todos: long items wrap to multiple lines instead of truncating — `712e59e`
- [x] Media: clicking the now-playing strip (artwork/title) opens the source app (Spotify / Apple Music) — `f6d7330`
- [x] Animation: springy expand, quicker eased collapse, staggered content fade — `ca71ec5`
- [x] Docs: re-render `docs/panel-open.png` and `docs/chip.png` on the Tahoe wallpaper instead of the gradient — `5158e17`

## Wave 2 — sequential, shared notes stack

- [x] Notes formatting: ==highlight== / <u>underline</u> markers, Cmd-U & Cmd-Shift-H, dim-amber readable highlight, auto-linked URLs — `8e5d127`
- [x] Notes: "Aa" font menu in the top-right corner (System/Serif/Rounded/Mono, persisted) — `ea5488d` (superseded: moved into Settings by `5b74f57`)
- [x] Notes: freehand sketch canvas (scribble toggle, 3 inks, JSON persistence beside the note) — `232c265`
- [x] Notes: pop out into a floating always-on-top window, placeholder in the panel, no editor races — `7b938a8`

## Wave 3 — user additions (2026-08-07)

- [x] Pomodoro timer: right-flank strip + collapsed chip sliding from the notch's right edge, Glass sound on phase end — `4b9d3ce`
- [x] Settings window (menu bar → Settings…, Cmd-,): feature toggles, flank/column layout, notes font (replaces the in-notes "Aa" control) — `5b74f57`

## Wave 4 — official releases (2026-08-07)

- [x] Developer ID release pipeline: entitlements + usage string, opt-in signing in the scripts, notarize.sh, tag-triggered release workflow with provenance attestation, RELEASING.md — `5b3c737`

## Wrap-up

- [x] Full `swift test` pass after all merges — 149/149
- [x] Push to origin/master
- [x] Review section below

## Review

**What was built.** Ten commits: todo titles wrap; the now-playing strip is
click-through to Spotify/Apple Music (tap gesture, so transport buttons and
focus are untouched); the panel expands with a soft spring and collapses with a
quick ease, content fading in a beat behind the chrome; both README screenshots
now sit on the Tahoe wallpaper; the scratchpad gained clickable auto-detected
links, Cmd-U underline, Cmd-Shift-H highlight (dim amber at 0.3 alpha so white
text stays ~10:1 readable), persisted as `==...==` / `<u>...</u>` markers in the
plain markdown file; a freehand sketch canvas toggles in behind the notes
(strokes as canonical JSON in `~/Documents/NotchNotes/sketch.json`, same
debounced-atomic-write machinery); notes pop out into a floating `.floating`-
level window with a placeholder left in the panel so only one editor is ever
live; a pomodoro timer mirrors the media strip on the notch's right flank with
its own collapsed chip and a permission-free Glass chime; and a Settings window
(status-item menu → Settings…, Cmd-,) holds feature toggles, flank/column
layout, and the notes font — the in-notes "Aa" control was removed the same
day it shipped when the requirement moved settings out of the panel.

**Architecture notes.** Every feature followed the repo's existing seams:
injected side effects (NSWorkspace opener, timer clock, UserDefaults) so logic
is headless-testable; AppKit for anything touching events or first responders
inside the non-activating panel; `PersistedFile` for all persistence. The notch
band generalized from one flank to two, which is what made the pomodoro chip
cheap. One `ScratchpadFontSetting` and one `PanelSettings` live on
`NotchController` and are injected everywhere, so settings apply live in every
host.

**Test suite.** 83 → 149 tests, all passing at every merge point.

**Not verified headlessly — needs a hand pass on hardware.** Animation feel;
key-equivalent routing (Cmd-U / Cmd-Shift-H) and link clicks in the
non-activating panel; menu behavior of the settings and font controls; sketch
flush on fast collapse; pop-out focus flow and window frame persistence; flank
swapping and the both-columns-off degenerate layout; pomodoro chip slide on the
right edge; completion sound audibility.
