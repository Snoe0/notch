# Lessons

## 2026-08-06 — the add-todo field shipped broken (couldn't be typed into)

**What happened.** v2 added a SwiftUI `TextField` + `@FocusState` next to the
existing AppKit scratchpad inside the borderless non-activating `NSPanel`.
Clicking the field never kept focus: the scratchpad's `updateNSView` re-grabbed
first responder on every render pass, guarded only by a SwiftUI-published flag
that flips *after* the AppKit responder change — a race the scratchpad always
won. All 52 tests passed the whole time.

**Lessons.**

1. In this panel (borderless, `.nonactivatingPanel`), text input goes through
   AppKit representables, period. The codebase already knew this — the
   scratchpad's doc comment explains why `TextEditor` was rejected — and the
   second text field should have followed the precedent instead of trusting
   SwiftUI focus machinery there.
2. Never call `makeFirstResponder` from `updateNSView` on a standing
   condition; grab focus only on a state *transition* tracked in the
   coordinator. A continuous grab is a standing bid to steal the caret from
   every other field in the window.
3. Focus and first-responder behavior is window-server-dependent and invisible
   to `swift test`. When a change adds a second focusable field, say
   explicitly in the hand-off that focus flow is untested and must be
   hand-checked — "52/52 tests pass" reads as "done" otherwise.
