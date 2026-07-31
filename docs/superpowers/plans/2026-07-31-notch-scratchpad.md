# Notch Scratchpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a background macOS app that expands a scratchpad out of the MacBook notch on hover and saves what you type to a markdown file.

**Architecture:** One fixed-size transparent `NSPanel` pinned under the notch; SwiftUI animates the content inside it so the window never resizes. Hover comes from a global mouse monitor (no permissions required) because the panel ignores mouse events while collapsed. Geometry and storage are pure, headless-testable types in a `NotchKit` library; the executable target is a thin shell.

**Tech Stack:** Swift 6, SwiftUI + AppKit, SwiftPM (no `.xcodeproj`), swift-testing, `codesign`.

**User decisions (already made):**
- v1 is notes only — media controls, file shelf, and ambient HUDs are deferred.
- Interaction is hover-to-peek plus click-to-pin.
- Built to be Developer ID signable and shareable later; not sandboxed, not App Store.
- Notes are one endless scratchpad, not a list of discrete notes.
- Storage is markdown on disk at `~/Documents/NotchNotes/scratchpad.md`.
- Physical-notch Macs only; external displays are ignored.
- Build system A: SwiftPM executable plus a bundle script, chosen over an Xcode project.

**Spec:** `docs/superpowers/specs/2026-07-31-notch-scratchpad-design.md`

---

### Task 0: Package scaffold and app bundle

**Goal:** A signed, launchable `Notch.app` with no Dock icon and a working menu bar item, built entirely from the terminal.

**Files:**
- Create: `Package.swift`
- Create: `Sources/Notch/NotchApp.swift`
- Create: `Sources/NotchKit/NotchKit.swift`
- Create: `Tests/NotchKitTests/SmokeTests.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/bundle.sh`
- Create: `.gitignore`

**Acceptance Criteria:**
- [ ] `swift build` and `swift test` both succeed
- [ ] `Scripts/bundle.sh` produces `build/Notch.app`, ad-hoc signed
- [ ] Launching the app shows a menu bar item and no Dock icon
- [ ] Quit from the menu bar terminates the app

**Verify:** `swift test` → all tests pass; `./Scripts/bundle.sh && open build/Notch.app` → menu bar item appears, Dock does not

**Steps:**

- [ ] **Step 1: Initialise the repository**

```bash
cd /Users/yurikorolev/Desktop/NotchProject
git init
```

- [ ] **Step 2: Write `.gitignore`**

```
.build/
build/
.DS_Store
*.xcuserdatad
```

- [ ] **Step 3: Write `Package.swift`**

The library/executable split exists so tests can `@testable import NotchKit` without linking against a target that owns `@main`.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchKit", path: "Sources/NotchKit"),
        .executableTarget(name: "Notch", dependencies: ["NotchKit"], path: "Sources/Notch"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"], path: "Tests/NotchKitTests"),
    ]
)
```

- [ ] **Step 4: Write `Sources/NotchKit/NotchKit.swift`**

A placeholder so the target compiles before real types land in Task 1.

```swift
/// Namespace marker for the NotchKit library.
public enum NotchKit {
    public static let version = "0.1.0"
}
```

- [ ] **Step 5: Write the smoke test**

`Tests/NotchKitTests/SmokeTests.swift`:

```swift
import Testing
@testable import NotchKit

@Test func libraryIsLinked() {
    #expect(NotchKit.version == "0.1.0")
}
```

- [ ] **Step 6: Write `Sources/Notch/NotchApp.swift`**

There must be no `main.swift` in this target, or `@main` will conflict.

```swift
import SwiftUI

@main
struct NotchApp: App {
    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "note.text") {
            Button("Quit Notch") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 7: Write `Resources/Info.plist`**

`LSUIElement` is what removes the Dock icon and stops the app from taking focus.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Notch</string>
    <key>CFBundleDisplayName</key>     <string>Notch</string>
    <key>CFBundleIdentifier</key>      <string>com.yurikorolev.Notch</string>
    <key>CFBundleExecutable</key>      <string>Notch</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
```

- [ ] **Step 8: Write `Scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Notch.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Notch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "built $APP"
```

Then: `chmod +x Scripts/bundle.sh`

- [ ] **Step 9: Verify**

Run: `swift test`
Expected: `Test run with 1 test passed`

Run: `./Scripts/bundle.sh && open build/Notch.app`
Expected: a note icon appears in the menu bar; nothing appears in the Dock. Quit from that menu.

- [ ] **Step 10: Commit**

```bash
git add .gitignore Package.swift Sources Tests Resources Scripts docs
git commit -m "feat: scaffold SwiftPM package and app bundle script"
```

---

### Task 1: Notch geometry

**Goal:** Pure, tested math that turns screen metrics into the notch rect, the fixed panel frame, and the collapsed hover rect.

**Files:**
- Create: `Sources/NotchKit/NotchGeometry.swift`
- Create: `Tests/NotchKitTests/NotchGeometryTests.swift`

**Acceptance Criteria:**
- [ ] `NotchGeometry(metrics:)` returns `nil` for a screen with no notch
- [ ] The notch rect is centred horizontally and flush with the top of the screen
- [ ] The panel frame is centred on the notch and anchored to the screen top
- [ ] The collapsed hover rect adds slop below and beside the notch, never above it
- [ ] All math respects a non-zero screen origin

**Verify:** `swift test --filter NotchGeometryTests` → all tests pass

**Steps:**

- [ ] **Step 1: Write the failing tests**

`Tests/NotchKitTests/NotchGeometryTests.swift`. Coordinates are AppKit screen coordinates: origin bottom-left, y increasing upward, so the notch lives at high y.

```swift
import Testing
import CoreGraphics
@testable import NotchKit

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    topInset: 32,
    auxiliaryTopLeftWidth: 596,
    auxiliaryTopRightWidth: 596
)

@Test func notchRectIsCenteredAndFlushWithScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    #expect(geometry.notchRect.width == 320)   // 1512 - 596 - 596
    #expect(geometry.notchRect.height == 32)
    #expect(geometry.notchRect.midX == 756)
    #expect(geometry.notchRect.maxY == 982)
}

@Test func screenWithoutNotchHasNoGeometry() {
    let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        topInset: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )
    #expect(NotchGeometry(metrics: external) == nil)
}

@Test func screenWithInsetButNoAuxiliaryAreasIsTreatedAsNotchless() {
    let ambiguous = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        topInset: 32,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )
    #expect(NotchGeometry(metrics: ambiguous) == nil)
}

@Test func panelIsCenteredOnNotchAndAnchoredToScreenTop() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    #expect(geometry.panelFrame.size == NotchGeometry.expandedSize)
    #expect(geometry.panelFrame.midX == geometry.notchRect.midX)
    #expect(geometry.panelFrame.maxY == 982)
}

@Test func collapsedHoverRectAddsSlopBelowButNeverAboveTheScreen() throws {
    let geometry = try #require(NotchGeometry(metrics: mbp14))
    let hover = geometry.collapsedHoverRect

    #expect(hover.maxY == 982)
    #expect(hover.minY == geometry.notchRect.minY - NotchGeometry.hoverSlop)
    #expect(hover.contains(CGPoint(x: 756, y: 948)))   // just under the notch
    #expect(!hover.contains(CGPoint(x: 100, y: 975)))  // menu bar, far left
}

@Test func geometryRespectsANonZeroScreenOrigin() throws {
    let shifted = ScreenMetrics(
        frame: CGRect(x: -1512, y: 300, width: 1512, height: 982),
        topInset: 32,
        auxiliaryTopLeftWidth: 596,
        auxiliaryTopRightWidth: 596
    )
    let geometry = try #require(NotchGeometry(metrics: shifted))
    #expect(geometry.notchRect.midX == -756)
    #expect(geometry.notchRect.maxY == 1282)
    #expect(geometry.panelFrame.maxY == 1282)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL — `cannot find 'ScreenMetrics' in scope`

- [ ] **Step 3: Write the implementation**

`Sources/NotchKit/NotchGeometry.swift`:

```swift
import CoreGraphics

/// The only facts about a display that the geometry needs. Extracted from
/// `NSScreen` at the edge of the app so the math stays testable headlessly.
public struct ScreenMetrics: Equatable, Sendable {
    public let frame: CGRect
    public let topInset: CGFloat
    public let auxiliaryTopLeftWidth: CGFloat
    public let auxiliaryTopRightWidth: CGFloat

    public init(
        frame: CGRect,
        topInset: CGFloat,
        auxiliaryTopLeftWidth: CGFloat,
        auxiliaryTopRightWidth: CGFloat
    ) {
        self.frame = frame
        self.topInset = topInset
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }
}

/// Where the notch is and where the panel that hangs off it should sit.
/// All rects are in AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    /// The fixed size of the panel window. It never changes; the content
    /// inside it animates instead.
    public static let expandedSize = CGSize(width: 620, height: 200)

    /// Extra margin around the notch that still counts as "hovering", so the
    /// cursor does not have to land pixel-perfectly inside it.
    public static let hoverSlop: CGFloat = 4

    public let notchRect: CGRect
    public let panelFrame: CGRect

    public init?(metrics: ScreenMetrics) {
        let notchWidth = metrics.frame.width
            - metrics.auxiliaryTopLeftWidth
            - metrics.auxiliaryTopRightWidth

        // A notch requires both a top inset and auxiliary areas flanking it.
        // An inset without them is some other kind of screen and is ignored.
        guard metrics.topInset > 0,
              metrics.auxiliaryTopLeftWidth > 0,
              metrics.auxiliaryTopRightWidth > 0,
              notchWidth > 0
        else { return nil }

        let centerX = metrics.frame.midX
        let top = metrics.frame.maxY

        notchRect = CGRect(
            x: centerX - notchWidth / 2,
            y: top - metrics.topInset,
            width: notchWidth,
            height: metrics.topInset
        )

        let size = Self.expandedSize
        panelFrame = CGRect(
            x: centerX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The region that counts as hovering while the panel is closed.
    /// Grows sideways and downward only — never above the screen edge.
    public var collapsedHoverRect: CGRect {
        let slop = Self.hoverSlop
        return CGRect(
            x: notchRect.minX - slop,
            y: notchRect.minY - slop,
            width: notchRect.width + slop * 2,
            height: notchRect.height + slop
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchKit/NotchGeometry.swift Tests/NotchKitTests/NotchGeometryTests.swift
git commit -m "feat: compute notch, panel, and hover rects from screen metrics"
```

---

### Task 2: Scratchpad store

**Goal:** Load, debounce-save, and externally-reload `scratchpad.md`, with the rule that the in-memory buffer wins while the user is editing.

**Files:**
- Create: `Sources/NotchKit/ScratchpadStore.swift`
- Create: `Tests/NotchKitTests/ScratchpadStoreTests.swift`
- Create: `Tests/NotchKitTests/TemporaryDirectory.swift`

**Acceptance Criteria:**
- [ ] Existing file contents load on init
- [ ] Text is written to disk after the debounce interval
- [ ] Several rapid edits produce exactly one write
- [ ] An external change to the file reloads into memory when the user is not editing
- [ ] An external change does not clobber the buffer while the user is editing
- [ ] A failed write surfaces `saveError` and keeps the text in memory

**Verify:** `swift test --filter ScratchpadStoreTests` → all tests pass

**Steps:**

- [ ] **Step 1: Write the temp-directory helper**

`Tests/NotchKitTests/TemporaryDirectory.swift`:

```swift
import Foundation

/// A scratch directory that deletes itself when the test releases it.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "notch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var scratchpad: URL { url.appending(path: "scratchpad.md") }

    func write(_ text: String) throws {
        try text.write(to: scratchpad, atomically: true, encoding: .utf8)
    }

    func read() throws -> String {
        try String(contentsOf: scratchpad, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/NotchKitTests/ScratchpadStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import NotchKit

private let fastDebounce = Duration.milliseconds(20)
private let afterDebounce = Duration.milliseconds(200)

@Test @MainActor func loadsExistingFileOnInit() throws {
    let dir = try TemporaryDirectory()
    try dir.write("gate 34, 6:40pm")

    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    #expect(store.text == "gate 34, 6:40pm")
}

@Test @MainActor func startsEmptyWhenNoFileExists() throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    #expect(store.text == "")
}

@Test @MainActor func writesTextToDiskAfterTheDebounceInterval() async throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    store.text = "wifi pw: hunter2"
    try await Task.sleep(for: afterDebounce)

    #expect(try dir.read() == "wifi pw: hunter2")
}

@Test @MainActor func coalescesRapidEditsIntoASingleWrite() async throws {
    let dir = try TemporaryDirectory()
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)

    for character in "hello" {
        store.text.append(character)
    }
    try await Task.sleep(for: afterDebounce)

    #expect(store.writeCount == 1)
    #expect(try dir.read() == "hello")
}

@Test @MainActor func reloadsExternalChangesWhenTheUserIsNotEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.write("original")
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = false

    try dir.write("changed on another device")
    try await Task.sleep(for: afterDebounce)

    #expect(store.text == "changed on another device")
}

@Test @MainActor func keepsTheInMemoryBufferWhileTheUserIsEditing() async throws {
    let dir = try TemporaryDirectory()
    try dir.write("original")
    let store = ScratchpadStore(directory: dir.url, debounce: fastDebounce)
    store.isEditing = true
    store.text = "what I am typing right now"

    try dir.write("changed on another device")
    try await Task.sleep(for: afterDebounce)

    #expect(store.text == "what I am typing right now")
}

@Test @MainActor func reportsAnErrorWhenTheDirectoryCannotBeUsed() async throws {
    // A path under an existing *file* can never be created as a directory.
    let dir = try TemporaryDirectory()
    try dir.write("blocking file")
    let impossible = dir.scratchpad.appending(path: "nested")

    let store = ScratchpadStore(directory: impossible, debounce: fastDebounce)
    store.text = "this cannot be saved"
    try await Task.sleep(for: afterDebounce)

    #expect(store.saveError != nil)
    #expect(store.text == "this cannot be saved")
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter ScratchpadStoreTests`
Expected: FAIL — `cannot find 'ScratchpadStore' in scope`

- [ ] **Step 4: Write the implementation**

`Sources/NotchKit/ScratchpadStore.swift`. Note the file watcher watches the *directory*, not the file: atomic writes replace the file's inode, which would silently kill a watcher attached to the file itself.

```swift
import Foundation
import Combine

/// Owns `scratchpad.md`. The only type in the app that touches disk.
@MainActor
public final class ScratchpadStore: ObservableObject {
    /// The live buffer. Assigning to it schedules a debounced save.
    @Published public var text: String = "" {
        didSet {
            guard text != lastLoadedText else { return }
            scheduleSave()
        }
    }

    /// Set by the view while the text field has focus. External changes are
    /// not applied while this is true, so remote edits never eat live typing.
    @Published public var isEditing: Bool = false

    /// Non-nil when the last save attempt failed. Surfaced as a banner.
    @Published public private(set) var saveError: String?

    /// Number of completed disk writes. Instrumentation for tests.
    public private(set) var writeCount = 0

    public let fileURL: URL
    public var directoryURL: URL { fileURL.deletingLastPathComponent() }

    private let debounce: Duration
    private var saveTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastLoadedText = ""

    public init(directory: URL, debounce: Duration = .milliseconds(500)) {
        self.fileURL = directory.appending(path: "scratchpad.md")
        self.debounce = debounce
        load()
        startWatching()
    }

    deinit { watcher?.cancel() }

    /// The app's real notes location.
    public static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "NotchNotes")
    }

    // MARK: - Loading

    private func load() {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        lastLoadedText = contents
        text = contents
    }

    private func reloadIfChangedExternally() {
        guard !isEditing else { return }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        guard contents != text else { return }
        lastLoadedText = contents
        text = contents
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.write()
        }
    }

    /// Write immediately, bypassing the debounce. Called when the panel closes.
    public func flush() async {
        saveTask?.cancel()
        await write()
    }

    private func write() async {
        let contents = text
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            lastLoadedText = contents
            writeCount += 1
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Watching

    /// Watches the containing directory rather than the file, because atomic
    /// writes swap the file's inode and orphan a file-level watcher.
    private func startWatching() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadIfChangedExternally() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ScratchpadStoreTests`
Expected: PASS, 7 tests

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchKit/ScratchpadStore.swift Tests/NotchKitTests/ScratchpadStoreTests.swift Tests/NotchKitTests/TemporaryDirectory.swift
git commit -m "feat: persist the scratchpad with debounced atomic writes and external reload"
```

---

### Task 3: State machine

**Goal:** The collapsed/peek/pinned transitions with their open delay and close grace period, tested headlessly.

**Files:**
- Create: `Sources/NotchKit/NotchStateMachine.swift`
- Create: `Tests/NotchKitTests/NotchStateMachineTests.swift`

**Acceptance Criteria:**
- [ ] Hovering for longer than the open delay moves collapsed → peek
- [ ] Passing through the notch faster than the open delay does not open it
- [ ] Leaving while peeking collapses after the grace period
- [ ] Returning during the grace period cancels the collapse
- [ ] Clicking while peeking pins the panel
- [ ] While pinned, hover is ignored; only `dismiss()` closes it

**Verify:** `swift test --filter NotchStateMachineTests` → all tests pass

**Steps:**

- [ ] **Step 1: Write the failing tests**

`Tests/NotchKitTests/NotchStateMachineTests.swift`:

```swift
import Testing
@testable import NotchKit

@MainActor
private func machine() -> NotchStateMachine {
    NotchStateMachine(openDelay: .milliseconds(20), closeDelay: .milliseconds(20))
}

private let settle = Duration.milliseconds(120)
private let beforeDelay = Duration.milliseconds(5)

@Test @MainActor func hoveringOpensThePanelAfterTheOpenDelay() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)

    #expect(notch.state == .collapsed)   // not yet
    try await Task.sleep(for: settle)
    #expect(notch.state == .peek)
}

@Test @MainActor func passingThroughTheNotchDoesNotOpenIt() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: beforeDelay)
    notch.hoverChanged(inside: false)

    try await Task.sleep(for: settle)
    #expect(notch.state == .collapsed)
}

@Test @MainActor func leavingCollapsesAfterTheGracePeriod() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.hoverChanged(inside: false)
    #expect(notch.state == .peek)        // grace period still running
    try await Task.sleep(for: settle)
    #expect(notch.state == .collapsed)
}

@Test @MainActor func returningDuringTheGracePeriodKeepsItOpen() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.hoverChanged(inside: false)
    try await Task.sleep(for: beforeDelay)
    notch.hoverChanged(inside: true)

    try await Task.sleep(for: settle)
    #expect(notch.state == .peek)
}

@Test @MainActor func clickingWhilePeekingPinsThePanel() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)

    notch.click()
    #expect(notch.state == .pinned)
}

@Test @MainActor func pinnedIgnoresHoverAndClosesOnlyOnDismiss() async throws {
    let notch = machine()
    notch.hoverChanged(inside: true)
    try await Task.sleep(for: settle)
    notch.click()

    notch.hoverChanged(inside: false)
    try await Task.sleep(for: settle)
    #expect(notch.state == .pinned)

    notch.dismiss()
    #expect(notch.state == .collapsed)
}

@Test @MainActor func clickingWhileCollapsedDoesNothing() {
    let notch = machine()
    notch.click()
    #expect(notch.state == .collapsed)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NotchStateMachineTests`
Expected: FAIL — `cannot find 'NotchStateMachine' in scope`

- [ ] **Step 3: Write the implementation**

`Sources/NotchKit/NotchStateMachine.swift`:

```swift
import Foundation
import Combine

public enum NotchState: Equatable, Sendable {
    /// Nothing drawn. The panel ignores mouse events.
    case collapsed
    /// Open because the cursor is inside it. Closes when the cursor leaves.
    case peek
    /// Open until explicitly dismissed. Hover is ignored.
    case pinned

    public var isOpen: Bool { self != .collapsed }
}

/// The open/close policy, with no AppKit in it so it can be tested headlessly.
///
/// The two delays exist to stop the panel flapping when the user is reaching
/// for a menu bar item near the top of the screen.
@MainActor
public final class NotchStateMachine: ObservableObject {
    @Published public private(set) var state: NotchState = .collapsed

    private let openDelay: Duration
    private let closeDelay: Duration
    private var pendingTransition: Task<Void, Never>?

    public init(
        openDelay: Duration = .milliseconds(180),
        closeDelay: Duration = .milliseconds(250)
    ) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
    }

    public func hoverChanged(inside: Bool) {
        switch (state, inside) {
        case (.collapsed, true):  transition(to: .peek, after: openDelay)
        case (.collapsed, false): cancelPending()
        case (.peek, false):      transition(to: .collapsed, after: closeDelay)
        case (.peek, true):       cancelPending()
        case (.pinned, _):        break
        }
    }

    public func click() {
        guard state == .peek else { return }
        cancelPending()
        state = .pinned
    }

    public func dismiss() {
        cancelPending()
        state = .collapsed
    }

    private func transition(to next: NotchState, after delay: Duration) {
        cancelPending()
        pendingTransition = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.state = next
        }
    }

    private func cancelPending() {
        pendingTransition?.cancel()
        pendingTransition = nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NotchStateMachineTests`
Expected: PASS, 7 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchKit/NotchStateMachine.swift Tests/NotchKitTests/NotchStateMachineTests.swift
git commit -m "feat: add collapsed/peek/pinned state machine with anti-flap delays"
```

---

### Task 4: The panel and a visible placeholder

**Goal:** A transparent, non-activating `NSPanel` pinned under the real notch, showing a coloured placeholder rectangle so its placement can be seen and judged.

**Files:**
- Create: `Sources/NotchKit/NotchPanel.swift`
- Create: `Sources/NotchKit/ScreenMetrics+NSScreen.swift`
- Create: `Sources/NotchKit/NotchController.swift`
- Modify: `Sources/Notch/NotchApp.swift`

**Acceptance Criteria:**
- [ ] `swift build` succeeds
- [ ] Running the app shows a red placeholder hanging directly below the notch, horizontally centred
- [ ] The placeholder floats above the menu bar and stays put when switching Spaces
- [ ] Clicking a menu bar item beside the notch still works — the panel does not steal it
- [ ] On a Mac with no notch the app launches, logs that it is dormant, and shows no panel

**Verify:** `swift build && ./Scripts/bundle.sh && open build/Notch.app` → red rectangle sits flush under the notch

**Steps:**

- [ ] **Step 1: Bridge `NSScreen` to `ScreenMetrics`**

`Sources/NotchKit/ScreenMetrics+NSScreen.swift`:

```swift
import AppKit

extension ScreenMetrics {
    /// Reads the notch-relevant metrics off a real screen.
    public init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width ?? 0
        )
    }
}

extension NotchGeometry {
    /// Geometry for the built-in display, or nil when it has no notch.
    public static func forBuiltInScreen() -> NotchGeometry? {
        guard let screen = NSScreen.screens.first(where: {
            ScreenMetrics(screen: $0).topInset > 0
        }) else { return nil }
        return NotchGeometry(metrics: ScreenMetrics(screen: screen))
    }
}
```

- [ ] **Step 2: Write the panel**

`Sources/NotchKit/NotchPanel.swift`. `canBecomeKey` is the load-bearing override: without it the text view can never receive keystrokes; with `.nonactivatingPanel` alongside it, the frontmost app keeps its active appearance while you type.

```swift
import AppKit
import SwiftUI

public final class NotchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(frame: CGRect, content: some View) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: content)
        setFrame(frame, display: true)
    }

    /// `NSWindow` conforms to `NSCoding`, so declaring a designated
    /// initializer above forces this one to be provided. It is never used.
    public required init?(coder: NSCoder) {
        fatalError("NotchPanel is not loaded from a nib")
    }

    /// While collapsed the panel must be invisible to the mouse, or it would
    /// swallow clicks meant for menu bar items sitting next to the notch.
    public func setInteractive(_ interactive: Bool) {
        ignoresMouseEvents = !interactive
    }
}
```

- [ ] **Step 3: Write the controller with a placeholder view**

`Sources/NotchKit/NotchController.swift`. Hover and real content arrive in Tasks 5 and 6; for now it just proves placement.

```swift
import AppKit
import SwiftUI

/// Owns the panel and drives it from the state machine.
@MainActor
public final class NotchController {
    private var panel: NotchPanel?
    private let geometry: NotchGeometry?

    public init() {
        geometry = NotchGeometry.forBuiltInScreen()
    }

    public func start() {
        guard let geometry else {
            print("Notch: no built-in notch on this Mac — staying dormant.")
            return
        }
        let panel = NotchPanel(frame: geometry.panelFrame, content: PlaceholderView())
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.red.opacity(0.6))
                .frame(width: 320, height: 120)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
```

- [ ] **Step 4: Wire the controller into the app**

Replace `Sources/Notch/NotchApp.swift` with:

```swift
import SwiftUI
import NotchKit

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "note.text") {
            Button("Quit Notch") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let controller = NotchController()
            controller.start()
            self.controller = controller
        }
    }
}
```

- [ ] **Step 5: Verify on screen**

Run: `./Scripts/bundle.sh && open build/Notch.app`
Expected: a translucent red rectangle hangs directly below the notch, centred. Switch to another Space — it follows. Click a menu bar item near the notch — it responds normally.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchKit/NotchPanel.swift Sources/NotchKit/ScreenMetrics+NSScreen.swift Sources/NotchKit/NotchController.swift Sources/Notch/NotchApp.swift
git commit -m "feat: pin a transparent non-activating panel under the notch"
```

---

### Task 5: Hover monitoring and live state

**Goal:** Move the cursor into the notch and the placeholder appears; move away and it disappears; click to pin it.

**Files:**
- Create: `Sources/NotchKit/HoverMonitor.swift`
- Modify: `Sources/NotchKit/NotchController.swift`

**Acceptance Criteria:**
- [ ] Resting the cursor on the notch shows the placeholder after a short delay
- [ ] Sweeping the cursor quickly past the notch does not open it
- [ ] Moving down into the open panel keeps it open
- [ ] Moving away closes it after the grace period
- [ ] Clicking the open panel pins it; Escape closes it
- [ ] No Accessibility permission prompt appears at any point

**Verify:** `./Scripts/bundle.sh && open build/Notch.app` → hover the notch; the placeholder appears and behaves as above

**Steps:**

- [ ] **Step 1: Write the hover monitor**

`Sources/NotchKit/HoverMonitor.swift`. Two monitors are required: the global one does not fire for events delivered to our own app, so once the panel is key, only the local monitor sees the cursor.

```swift
import AppKit

/// Reports whether the cursor is inside a rect, using global mouse monitoring.
///
/// Mouse monitoring needs no Accessibility permission — only keyboard
/// monitoring does — so the app prompts for nothing.
@MainActor
public final class HoverMonitor {
    /// The region that currently counts as "inside". Swapped by the controller
    /// when the panel opens, so moving into the panel is still "inside".
    public var activeRect: CGRect = .zero

    /// Fired only when the inside/outside answer actually changes.
    public var onChange: ((Bool) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isInside = false

    private static let events: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
    ]

    public init() {}

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }
    }

    public func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }

    // No deinit: `NSEvent.removeMonitor` is main-thread-only and `deinit` is not
    // actor-isolated in Swift 6. The monitor lives as long as the app does, so
    // teardown goes through `stop()` instead.

    private func evaluate() {
        let inside = activeRect.contains(NSEvent.mouseLocation)
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }
}
```

- [ ] **Step 2: Drive the panel from the state machine**

Replace `Sources/NotchKit/NotchController.swift` with:

```swift
import AppKit
import SwiftUI
import Combine

/// Owns the panel and wires hover → state machine → panel visibility.
@MainActor
public final class NotchController {
    private let geometry: NotchGeometry?
    private let hover = HoverMonitor()
    private let machine = NotchStateMachine()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    public init() {
        geometry = NotchGeometry.forBuiltInScreen()
    }

    public func start() {
        guard let geometry else {
            print("Notch: no built-in notch on this Mac — staying dormant.")
            return
        }

        let panel = NotchPanel(
            frame: geometry.panelFrame,
            content: PlaceholderView(machine: machine)
        )
        panel.setInteractive(false)
        panel.orderFrontRegardless()
        self.panel = panel

        hover.activeRect = geometry.collapsedHoverRect
        hover.onChange = { [weak self] inside in
            self?.machine.hoverChanged(inside: inside)
        }
        hover.start()

        machine.$state
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &cancellables)

        watchForClicks()
    }

    /// The panel accepts the mouse only while open, and the hover region grows
    /// to the whole panel so moving down into it does not close it.
    ///
    /// Collapsing orders the panel out rather than merely hiding its content.
    /// That is what releases key status — `resignKey()` must never be called
    /// directly — and it guarantees a collapsed panel can swallow nothing.
    private func apply(_ state: NotchState) {
        guard let geometry, let panel else { return }
        hover.activeRect = state.isOpen ? geometry.panelFrame : geometry.collapsedHoverRect
        panel.setInteractive(state.isOpen)

        switch state {
        case .collapsed: panel.orderOut(nil)
        case .peek:      panel.orderFrontRegardless()
        case .pinned:    panel.makeKeyAndOrderFront(nil)
        }
    }

    /// A click inside the open panel pins it; a click anywhere else dismisses it.
    ///
    /// Both monitors are needed. The global one never fires for events routed
    /// to our own app, so once the panel accepts the mouse only the local one
    /// sees clicks landing on it.
    private func watchForClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick() }
            return event
        }
    }

    private func handleClick() {
        guard let geometry else { return }
        if geometry.panelFrame.contains(NSEvent.mouseLocation) {
            machine.click()
        } else {
            machine.dismiss()
        }
    }
}

private struct PlaceholderView: View {
    @ObservedObject var machine: NotchStateMachine

    var body: some View {
        VStack(spacing: 0) {
            if machine.state.isOpen {
                Rectangle()
                    .fill(machine.state == .pinned ? .green.opacity(0.6) : .red.opacity(0.6))
                    .frame(width: 320, height: 120)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: machine.state)
    }
}
```

- [ ] **Step 3: Verify on screen**

Run: `./Scripts/bundle.sh && open build/Notch.app`
Expected: rest on the notch → red block springs down. Move away → it retracts. Click it → turns green and stays. Click elsewhere → closes. No permission dialog ever appears.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchKit/HoverMonitor.swift Sources/NotchKit/NotchController.swift
git commit -m "feat: open and pin the panel from global mouse hover"
```

---

### Task 6: Notch chrome

**Goal:** Replace the placeholder with the real shape — a panel that reads as growing out of the notch — and give it a slot for content.

**Files:**
- Create: `Sources/NotchKit/NotchChrome.swift`
- Modify: `Sources/NotchKit/NotchController.swift`

**Acceptance Criteria:**
- [ ] The open panel is a black surface whose top edge is flush with the notch and whose bottom corners are rounded
- [ ] It is at least as wide as the notch and never narrower
- [ ] The expand animation is a spring that reads as growing downward from the notch
- [ ] Arbitrary content can be passed in via a trailing closure
- [ ] Collapsed state renders nothing at all

**Verify:** `./Scripts/bundle.sh && open build/Notch.app` → hovering shows a black rounded panel that appears to extend the notch

**Steps:**

- [ ] **Step 1: Write the chrome**

`Sources/NotchKit/NotchChrome.swift`:

```swift
import SwiftUI

/// The visible surface that hangs off the notch, and the slot its content
/// lives in. v1 fills the slot with the scratchpad; media controls or a file
/// shelf would drop into the same place without touching anything else.
public struct NotchChrome<Content: View>: View {
    private let state: NotchState
    private let notchWidth: CGFloat
    private let content: () -> Content

    private static var cornerRadius: CGFloat { 22 }

    public init(
        state: NotchState,
        notchWidth: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.notchWidth = notchWidth
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            if state.isOpen {
                surface
                    .transition(
                        .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: state)
    }

    private var surface: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: notchWidth)
            .background(.black)
            // Square at the top so the panel merges into the notch and the
            // screen edge; rounded at the bottom so it reads as a lozenge.
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: Self.cornerRadius,
                    bottomTrailingRadius: Self.cornerRadius,
                    topTrailingRadius: 0
                )
            )
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: Self.cornerRadius,
                    bottomTrailingRadius: Self.cornerRadius,
                    topTrailingRadius: 0
                )
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }
}
```

- [ ] **Step 2: Use it in the controller**

In `Sources/NotchKit/NotchController.swift`, delete the `PlaceholderView` struct and change the panel construction inside `start()` from:

```swift
        let panel = NotchPanel(
            frame: geometry.panelFrame,
            content: PlaceholderView(machine: machine)
        )
```

to:

```swift
        let panel = NotchPanel(
            frame: geometry.panelFrame,
            content: NotchRoot(machine: machine, notchWidth: geometry.notchRect.width)
        )
```

Then add this view at the bottom of the same file:

```swift
/// Bridges the observable state machine into the chrome.
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    let notchWidth: CGFloat

    var body: some View {
        NotchChrome(state: machine.state, notchWidth: notchWidth) {
            Color.clear
        }
    }
}
```

- [ ] **Step 3: Verify on screen**

Run: `./Scripts/bundle.sh && open build/Notch.app`
Expected: hovering the notch springs open a black panel with rounded bottom corners, flush with the notch, appearing to grow downward from it.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchKit/NotchChrome.swift Sources/NotchKit/NotchController.swift
git commit -m "feat: render the notch chrome with a content slot"
```

---

### Task 7: The scratchpad

**Goal:** Type into the notch and have it saved, with focus handled so typing never steals the frontmost app's activation.

**Files:**
- Create: `Sources/NotchKit/ScratchpadView.swift`
- Modify: `Sources/NotchKit/NotchController.swift`

**Acceptance Criteria:**
- [ ] Pinning the panel focuses the text field automatically
- [ ] Typed text appears in `~/Documents/NotchNotes/scratchpad.md` within a second
- [ ] The frontmost app keeps its active appearance while typing in the notch
- [ ] Text survives quitting and relaunching the app
- [ ] Escape dismisses the panel and flushes the pending save
- [ ] A save failure shows a banner and does not discard the text

**Verify:** `./Scripts/bundle.sh && open build/Notch.app`, type a line, then `cat ~/Documents/NotchNotes/scratchpad.md` → the line is there

**Steps:**

- [ ] **Step 1: Write the scratchpad view**

`Sources/NotchKit/ScratchpadView.swift`:

```swift
import SwiftUI

public struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore
    let isPinned: Bool
    @FocusState private var isFocused: Bool

    public init(store: ScratchpadStore, isPinned: Bool) {
        self.store = store
        self.isPinned = isPinned
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            editor
            if let error = store.saveError {
                banner(error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .onChange(of: isPinned) { _, pinned in isFocused = pinned }
        .onChange(of: isFocused) { _, focused in store.isEditing = focused }
    }

    private var editor: some View {
        TextEditor(text: $store.text)
            .focused($isFocused)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .tint(.white)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text(isPinned ? "type…" : "click to write")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }

    private func banner(_ message: String) -> some View {
        Label("Not saved: \(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}
```

- [ ] **Step 2: Put the scratchpad in the chrome's slot**

In `Sources/NotchKit/NotchController.swift`, add a store property next to the other properties:

```swift
    private let store = ScratchpadStore(directory: ScratchpadStore.defaultDirectory)
```

Change the panel construction inside `start()` to pass the store through:

```swift
        let panel = NotchPanel(
            frame: geometry.panelFrame,
            content: NotchRoot(
                machine: machine,
                store: store,
                notchWidth: geometry.notchRect.width
            )
        )
```

Replace the `NotchRoot` struct at the bottom of the file with:

```swift
private struct NotchRoot: View {
    @ObservedObject var machine: NotchStateMachine
    @ObservedObject var store: ScratchpadStore
    let notchWidth: CGFloat

    var body: some View {
        NotchChrome(state: machine.state, notchWidth: notchWidth) {
            ScratchpadView(store: store, isPinned: machine.state == .pinned)
        }
    }
}
```

- [ ] **Step 3: Handle Escape and flush on close**

In `NotchController`, add an Escape monitor and a flush. Add this call at the end of `start()`:

```swift
        watchForEscape()
```

Add these two methods to `NotchController`:

```swift
    /// Escape closes the panel. A local monitor is enough because the panel is
    /// key whenever it is pinned, which is the only time Escape should apply.
    private func watchForEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            return MainActor.assumeIsolated {
                guard let self, self.machine.state == .pinned else { return event }
                self.machine.dismiss()
                return nil   // swallow it so the text view never sees Escape
            }
        }
    }

    /// Never leave a pending debounced write unwritten when the panel closes.
    private func flushOnClose(_ state: NotchState) {
        guard state == .collapsed else { return }
        Task { await store.flush() }
    }
```

Add the monitor property alongside `clickMonitor`:

```swift
    private var escapeMonitor: Any?
```

And call the flush from `apply(_:)` by adding this as its final line:

```swift
        flushOnClose(state)
```

- [ ] **Step 4: Verify on screen**

Run: `./Scripts/bundle.sh && open build/Notch.app`

Expected sequence:
1. Hover the notch → panel opens showing `click to write`
2. Click it → placeholder becomes `type…`, cursor blinks, and the app behind stays visually active
3. Type `gate 34, 6:40pm`
4. Press Escape → panel closes
5. `cat ~/Documents/NotchNotes/scratchpad.md` → prints `gate 34, 6:40pm`
6. Quit and relaunch, hover the notch → the text is still there

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchKit/ScratchpadView.swift Sources/NotchKit/NotchController.swift
git commit -m "feat: type notes into the notch and save them to disk"
```

---

### Task 8: Menu bar, login item, and screen changes

**Goal:** Round the app off — reveal the notes folder, launch at login, and survive display reconfiguration.

**Files:**
- Create: `Sources/NotchKit/LaunchAtLogin.swift`
- Modify: `Sources/NotchKit/NotchController.swift`
- Modify: `Sources/Notch/NotchApp.swift`

**Acceptance Criteria:**
- [ ] The menu bar item offers Reveal Notes, Launch at Login, and Quit
- [ ] Reveal Notes opens `~/Documents/NotchNotes` in Finder
- [ ] Toggling Launch at Login registers/unregisters the app and the state persists across relaunch
- [ ] Plugging or unplugging a display does not misplace the panel
- [ ] Closing the lid to an external display collapses the panel rather than stranding it

**Verify:** `./Scripts/bundle.sh && open build/Notch.app` → exercise each menu item; connect/disconnect a display and confirm the panel stays correct

**Steps:**

- [ ] **Step 1: Write the login-item helper**

`Sources/NotchKit/LaunchAtLogin.swift`:

```swift
import ServiceManagement

/// Thin wrapper over SMAppService so the menu does not import ServiceManagement.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Notch: could not change login item — \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Recompute geometry when displays change**

In `Sources/NotchKit/NotchController.swift`, change the `geometry` property from a `let` to a `var`:

```swift
    private var geometry: NotchGeometry?
```

Add this call at the end of `start()`:

```swift
        watchForScreenChanges()
```

Add this method to `NotchController`:

```swift
    /// Display changes move the notch. Collapse first so nothing is stranded
    /// mid-animation, then re-place the panel against the new geometry.
    private func watchForScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.machine.dismiss()
                self.geometry = NotchGeometry.forBuiltInScreen()

                guard let geometry = self.geometry else {
                    self.panel?.orderOut(nil)
                    return
                }
                self.panel?.setFrame(geometry.panelFrame, display: true)
                self.panel?.orderFrontRegardless()
                self.hover.activeRect = geometry.collapsedHoverRect
            }
        }
    }
```

- [ ] **Step 3: Expose the notes folder**

Add this method to `NotchController`:

```swift
    public func revealNotes() {
        try? FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }
```

- [ ] **Step 4: Build the real menu**

Replace `Sources/Notch/NotchApp.swift` with:

```swift
import SwiftUI
import NotchKit

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "note.text") {
            MenuContent(revealNotes: { delegate.revealNotes() })
        }
    }
}

private struct MenuContent: View {
    let revealNotes: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Button("Reveal Notes in Finder", action: revealNotes)
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
        Divider()
        Button("Quit Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let controller = NotchController()
            controller.start()
            self.controller = controller
        }
    }

    func revealNotes() {
        MainActor.assumeIsolated { controller?.revealNotes() }
    }
}
```

- [ ] **Step 5: Verify on screen**

Run: `./Scripts/bundle.sh && open build/Notch.app`
Expected: the menu shows all three items. Reveal Notes opens Finder at `NotchNotes` with `scratchpad.md` selected. Toggling Launch at Login sticks after quit and relaunch. Connecting a display leaves the panel correctly placed under the notch.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchKit/LaunchAtLogin.swift Sources/NotchKit/NotchController.swift Sources/Notch/NotchApp.swift
git commit -m "feat: add menu bar actions, login item, and display-change handling"
```

---

### Task 9: End-to-end pass and README

**Goal:** Confirm the whole thing works as specified, and leave instructions for building and signing it.

**Files:**
- Create: `README.md`
- Create: `tasks/todo.md`

**Acceptance Criteria:**
- [ ] `swift test` passes with every test from Tasks 1–3
- [ ] Every acceptance criterion from Tasks 4–8 is re-checked on the running app
- [ ] `README.md` documents build, test, bundle, run, and the Developer ID path
- [ ] `tasks/todo.md` records the completed work and a review section

**Verify:** `swift test` → all pass; manual walkthrough of the README's usage section succeeds

**Steps:**

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: PASS — 1 smoke + 6 geometry + 7 store + 7 state machine = 21 tests

- [ ] **Step 2: Walk the manual checklist**

Run `./Scripts/bundle.sh && open build/Notch.app`, then confirm each:

1. Sweeping the cursor past the notch does not open it
2. Resting on the notch opens it after a beat
3. Moving down into the panel keeps it open
4. Moving away closes it
5. Clicking pins it and focuses the text field
6. The frontmost app keeps its active appearance while typing
7. Text lands in `~/Documents/NotchNotes/scratchpad.md`
8. Escape closes and saves
9. Text survives relaunch
10. Editing the file in another editor while the panel is closed shows the new text on next open
11. Clicking a menu bar item beside the notch is not intercepted
12. No permission prompts ever appeared

- [ ] **Step 3: Write `README.md`**

````markdown
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

- Rest the cursor on the notch — the panel springs open
- Click it to pin it, then type
- Escape or a click elsewhere closes it
- Menu bar → Reveal Notes in Finder opens the notes folder

## Shipping to other people

Replace the ad-hoc signature in `Scripts/bundle.sh`:

```bash
codesign --force --options runtime --sign "Developer ID Application: YOUR NAME (TEAMID)" "$APP"
xcrun notarytool submit --keychain-profile notch --wait "$APP.zip"
xcrun stapler staple "$APP"
```

## Layout

- `Sources/NotchKit` — geometry, storage, state machine, panel, views
- `Sources/Notch` — `@main` shell and menu bar
- `Tests/NotchKitTests` — headless tests for the pure parts

`NotchChrome` takes its content as a slot, so a media or file-shelf module drops
in beside the scratchpad without touching hover, geometry, or the panel.
````

- [ ] **Step 4: Write `tasks/todo.md`**

```markdown
# Notch — v1 scratchpad

Plan: `docs/superpowers/plans/2026-07-31-notch-scratchpad.md`
Spec: `docs/superpowers/specs/2026-07-31-notch-scratchpad-design.md`

- [x] Task 0 — SwiftPM package, Info.plist, bundle script
- [x] Task 1 — notch geometry from screen metrics
- [x] Task 2 — scratchpad store: debounced atomic writes, external reload
- [x] Task 3 — collapsed/peek/pinned state machine
- [x] Task 4 — transparent non-activating panel under the notch
- [x] Task 5 — global hover monitoring, click to pin
- [x] Task 6 — notch chrome and content slot
- [x] Task 7 — scratchpad view wired to disk
- [x] Task 8 — menu bar, login item, display-change handling
- [x] Task 9 — end-to-end pass and README

## Review

**What was built.** A menu-bar-only app that pins a fixed-size transparent
NSPanel under the notch and animates a scratchpad out of it on hover. Notes go
to `~/Documents/NotchNotes/scratchpad.md`.

**Deviations from the spec.** <record any, or "none">

**Test coverage.** 21 tests across geometry, storage, and the state machine.
Panel placement, chrome, and animation were verified manually — noted here
because they are the parts no test protects.

**Deferred.** Media controls, file shelf, ambient HUDs, global hotkey, virtual
notch on external displays, note search.
```

- [ ] **Step 5: Commit**

```bash
git add README.md tasks/todo.md
git commit -m "docs: add README and task review"
```

---

## Deferred to later plans

Media controls (transport-only, given the macOS 15.4+ MediaRemote entitlement gate), file shelf, ambient HUDs, global hotkey, virtual notch on external displays, and note search. Each attaches to the `NotchChrome` content slot.
