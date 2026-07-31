# Notch — v1 scratchpad

Plan: `docs/superpowers/plans/2026-07-31-notch-scratchpad.md`
Spec: `docs/superpowers/specs/2026-07-31-notch-scratchpad-design.md`

- [x] Task 0 — SwiftPM package, Info.plist, bundle script — `0f65f09`
- [x] Task 1 — notch geometry from screen metrics — `5dfc2df`
- [x] Task 2 — scratchpad store: debounced atomic writes, external reload — `6867686`
- [x] Task 3 — collapsed/peek/pinned state machine — `b744a96`
- [x] Task 4 — transparent non-activating panel under the notch — `4fe78fd`
- [x] — geometry fix: asymmetric auxiliary areas — `cc4471b`
- [x] Task 5 — global hover monitoring, click to pin — `e991161`
- [x] Task 6 — notch chrome and content slot — `6df5235`
- [x] Task 7 — scratchpad view wired to disk — `3741e54`
- [x] Task 8 — menu bar, login item, display-change handling — `9135383`
- [ ] Task 9 — end-to-end pass (**manual walkthrough pending**) and README

## Review

**What was built.** A menu-bar-only app that pins a fixed-size transparent
`NSPanel` under the notch and animates a scratchpad out of it on hover. Notes go
to `~/Documents/NotchNotes/scratchpad.md`. Hover-to-peek, click-to-pin, Escape to
close. No permission prompts.

**Deviations from the spec.**

1. *Geometry, corrected against hardware.* The spec assumed the notch is centred
   on the screen. Measuring this machine showed the auxiliary areas are
   asymmetric — 665pt left, 662pt right — putting the true notch at x 665–850,
   1.5pt right of screen centre. The rect is now derived from the auxiliary
   boundaries directly. A regression test pins the measured values.

2. *Escape monitor return type.* `NSEvent`'s `Sendable` conformance is
   explicitly unavailable, so `MainActor.assumeIsolated` could not return an
   `NSEvent?`. It returns a `Bool` and the event is selected outside the isolated
   closure. Behaviour is identical.

3. *`AppDelegate.revealNotes()` isolation.* Declared `@MainActor` rather than
   wrapping the body in `assumeIsolated`. `applicationDidFinishLaunching` gets
   its isolation from the protocol; a plain method does not, and capturing a
   nonisolated `self` into an isolated closure trips Swift 6's sending check.

4. *Screen-change handling.* The plan ordered the panel front after
   repositioning. That fights the state machine, which was just dismissed to
   `.collapsed` — it would leave a visible, empty panel at the new position.
   The handler now re-applies the current state so visibility, frame, and hover
   rect all reconcile from one source of truth.

**Test coverage.** 22 tests across geometry, storage, and the state machine.
Panel placement, chrome, animation, and focus behaviour were not automated —
noted here because they are precisely the parts no test protects.

**Deferred.** Media controls, file shelf, ambient HUDs, global hotkey, virtual
notch on external displays, note search. All attach to `NotchChrome`'s content
slot.
