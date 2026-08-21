# Testing protocol

456 tests cover the engine and the Mac app. This document explains what each
suite is for, how to write a test that will still be useful in a year, and the
three failure modes that have already cost a day each.

The counts here are the ones the suites print. They were 293 / 211 / 82 for
several releases while the suites reported 408 / 290 / 118, which is the wrong
number to get wrong in the file called *Testing protocol* — a reader checking
whether this project counts carefully starts here.

---

## Running them

```bash
swift test             # engine — run constantly
swift test -c release  # + the throughput guards
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
           -destination 'platform=macOS' test           # app integration
```

The engine suite is fast enough to run on every save. Get in that habit; the app
suite is the one you run before pushing.

CI runs all three on every push and pull request
([`ci.yml`](../.github/workflows/ci.yml)), and the release workflow runs them
again before it will build a tag.

---

## The layers

| Suite | Where | Covers |
|---|---|---|
| **Engine** (291) | `Packages/PaintKit/Tests/PaintKitTests/` | pixels, tools, selection, undo, codecs, transforms |
| **Throughput** (7 of the engine tests; budgets in release) | `PerformanceTests.swift` | stamp / stroke / fill / preview / encode budgets |
| **App** (120) | `AppTests/` | the model, the document, the menus, and what the canvas actually *draws* |

Most coverage belongs in the **engine** suite: it needs no window, no app host
and no main actor, and it runs in milliseconds. Only reach for the app suite when
the thing under test genuinely involves AppKit, the document, or the menu bar.

---

## The rule: assert pixels, not screenshots

```swift
#expect(engine.canvas.pixel(at: PixelPoint(x: 8, y: 8)) == PaintColour(hex: "FF0000")!.rgba8)
```

An image-snapshot diff hands you two similar-looking PNGs and wishes you luck. A
pixel assertion names the pixel that moved. It also runs in microseconds, needs
no Git LFS, and cannot rot when a font renders half a pixel differently on the
next OS.

Where an exact pixel is too brittle, assert the *property* instead — that is
still not a screenshot:

```swift
// The block is uniform: the stripes are gone.
#expect(block.allSatisfy { $0 == sample }, "the block still carries detail")

// Nothing landed outside the nib.
#expect(abs(x - 40) <= 11 && abs(y - 40) <= 11, "stray dot at \(x), \(y)")
```

Every `#expect` that could plausibly fail carries a message saying what the
failure *means*. `Expectation failed` on line 212 is a puzzle; "a dash landed off
the line" is a bug report.

---

## What a new tool needs

Four tests, and they take about ten minutes to write:

1. **It marks the right pixels** — and, where it has an extent, *only* those.
   ```swift
   #expect(marked.allSatisfy { rect.contains($0) }, "\(kind) painted outside its box")
   ```
2. **It undoes to exactly the pixels that were there.** `#expect(engine.canvas == before)`
   catches half-restored patches that a spot check misses.
3. **It is one undo step, named for the Edit menu.**
   `#expect(engine.undoStack.undoActionName == "Spray")` — named for the
   variation, not the tool that owns it, the way a rectangle undoes as
   "Rectangle" rather than "Shape".
4. **The degenerate input does nothing** — an empty string, a zero-size drag, a
   click with no drag. `#expect(!engine.canUndo)` proves it did not record an
   empty edit.

Randomness gets a fifth: **it must be reproducible**. The spray tip owns a seeded
`SprayRandom`, so `#expect(run() == run())` is a real test. Randomness that
cannot be reproduced cannot be tested, and a tool nobody can test silently rots.

---

## Guard tests

A few tests exist to fail when a *decision* is quietly reversed, not when code
breaks. They are cheap and they have all fired at least once:

- `toolSetStaysSmall` — the rail stays ≤ 14 buttons, ≤ 5 per run.
- `shapesAreNotTools` — shapes that differ only by outline never become tools.
- `shortcutsAreUnique`, `shortcutsAvoidReservedKeys` — no collisions, and `X`
  stays swap-colours.
- `railCoversEveryTool` — every tool appears in exactly one rail run.
- `everyToolsItemIsLive`, `canvasContextMenuIsLive` — every menu item is wired to
  a selector something answers. These exist because the Tools items once
  shipped wired to nothing.
- `liveMenuBarIsInstalled` — the running host really has File, Edit and Tools.
  The tests run inside the app host, so this is the actual launch path.
- `paintedRevisionIsNotRepainted` — a change the canvas painted itself does not
  trigger a full redraw. Guards the rect-scoped invalidation the whole view
  depends on.

---

## Throughput guards

Six budgets in `PerformanceTests.swift`, deliberately generous: they exist to
catch an order-of-magnitude regression — an O(canvas) operation sneaking into a
per-event path — not to police microseconds. A tight bound fails on a loaded
machine and teaches everyone to ignore the suite.

They **assert only in release builds**:

```swift
#if DEBUG
let performanceBudgetsApply = false
#else
let performanceBudgetsApply = true
#endif
```

Unoptimised, this engine runs 40–140× slower; a debug timing measures the Swift
compiler, not the algorithm. The six throughput tests run in both builds, but
their time budgets apply only in release. If you touch anything in `Raster`,
`Bitmap` or the stroke path, run the release suite.

---

## Testing the app layer

`AppTests` runs **inside the app host**, which means a real `NSApplication` with a
real document window exists while your test runs. That is what makes
`liveMenuBarIsInstalled` meaningful, and it is also the source of every
hard-to-diagnose failure in this suite. Three rules, each learned from a crash:

**1. Host test views in a window.** A bare `NSView` that has received mouse
events and been marked for display, then deallocated, leaves AppKit holding a
pointer it messages on the next window pass — a segfault inside `isFlipped`,
nowhere near the test that caused it. `makeView(_:)` puts every view in an
offscreen `NSWindow` and keeps it alive.

**2. Never let a test open a modal menu.** `NSMenu.popUpContextMenu` starts a
tracking loop that never returns in a test process; the run hangs until the
timeout kills it. Test the *decision* instead: `contextMenu(for:)` returns the
menu it would show, so the click-versus-drag rule is asserted without popping
anything.

**3. Never mutate observable state inside a layout pass.** SwiftUI rebuilds the
view tree while AppKit is walking it, and AppKit then messages a released view.
If a test crashes the host with `Restarting after unexpected exit`, look for
state written during `layout()` before you look at the test.

When the app suite reports fewer tests than you expect *and* the run still says
`** TEST FAILED **` with no `✘`, a test crashed the host and the runner
restarted: read the log for `Restarting after unexpected exit` and the crash
report in `~/Library/Logs/DiagnosticReports/`.

---

## Rendering tests

`CanvasRenderingTests` renders the real `CanvasNSView` offscreen with
`cacheDisplay(in:to:)` and inspects the resulting pixels — floating content
composited in the right place, resize handles drawn (and *not* drawn on content
too small to hold them), the marquee, zoom scaling.

The one trap: `bitmapImageRepForCachingDisplay` renders at the display's backing
scale, so on a retina machine the result is 2× the view's point size. Sampling it
with point coordinates silently reads the wrong pixel — every probe lands in the
top-left quadrant, which looks exactly like "the overlay was never drawn". The
`Rendered` helper carries the scale for this reason.

Make the fixture *prove* the thing: a test that pastes black content on a black
canvas and asserts the sample is dark cannot fail. Paste mid-grey on black and
assert nothing near-white appears, and now it can.

---

## Before you open a pull request

- [ ] `swift test` passes
- [ ] `swift test -c release` passes if you
      touched the drawing path
- [ ] `xcodebuild … test` passes — and the count went *up*, not sideways
- [ ] The new test fails when you revert the change. A test that passes both ways
      is documentation, not a test.
