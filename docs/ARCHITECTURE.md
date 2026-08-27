# Anatomy

How the app is put together, in the order you would need to know it to change
something. Every path below is real; every type name matches the source.

---

## The one structural rule

```
App/  ──depends on──▶  Packages/PaintKit/
                       (no AppKit, no SwiftUI, no dependencies)
```

`PaintKit` is a pure Swift package: pixels, tools, selection, undo and codecs,
with no UI framework and nothing third-party. The arrow never points the other
way.

This is what makes the whole tool matrix testable in milliseconds without
launching an app — 338 engine tests cover it directly — and it means a UI
redesign is a view-layer change rather than a rewrite. It has already survived
one: the chrome was rebuilt from a floating cluster to a rail without the engine
changing.

---

## Module map

```
Packages/PaintKit/Sources/PaintKit/
  Pixels/
    RGBA8.swift            premultiplied sRGB pixel, blending
    Geometry.swift         PixelPoint, PixelRect — integers, end to end
    Bitmap.swift           the buffer: fill, blend, map, composite, extract
    Brush.swift            a stamp: shape, size, precomputed coverage mask
    Raster.swift           lines, curves, ellipses, polygons, spray, flood fill
  Colour/
    PaintColour.swift      authoring colour (Double sRGB) + hex + HSB
    Palette.swift          the 28 swatches, and the fg/bg ColourPair
  Tools/
    ToolKind.swift         ToolKind · ShapeKind · SelectionKind · ShapeStyle
    ToolSettings.swift     everything the options panel can change
    PaintEngine.swift      the gesture state machine — the centre of the app
    Selection.swift        FloatingSelection: lifted/pasted content + handles
    SelectionMask.swift    Selection: bounds + optional per-pixel mask
  Undo/
    RectPatch.swift        before/after pixels for one rect
    UndoStack.swift        bounded by bytes, not step count
  Codec/
    CoreGraphicsBridge.swift  Bitmap ⇄ CGImage
    ImageCodec.swift          ImageIO import/export, 9 formats
    ImageTransform.swift      flip, rotate, scale, resize canvas, trim
    TextRenderer.swift        CoreText → bitmap

App/
  ItsPaintApp.swift        NSApplication entry point (no nib)
  MainMenuBuilder.swift    every menu command, in one readable list
  Canvas/
    CanvasNSView.swift     the drawing surface: events, cursors, zoom, text box
    CanvasScrollView.swift NSViewRepresentable + centring clip view + fit
  Document/
    DrawingDocument.swift  NSDocument, .itspaint package, export panel
    DocumentCommands.swift the @IBAction implementations + menu validation
  Model/
    EditorModel.swift      @Observable bridge: engine ⇄ SwiftUI, clipboard, zoom
  UI/
    ToolRail.swift         the rail: tool cells, colour pair, palette
    ToolOptions.swift      the active tool's options, expanded from its button
    EditorView.swift       window layout: canvas, chrome, status, title
    DesignTokens.swift     spacing/size/radius/motion tokens + chrome material
    SizeSheet.swift · Tooltip.swift · CanvasOverlays.swift
    FixedGrid.swift        deterministic grid (see "Grids", below)
```

---

## The data flow

One direction, one currency: **every mutating engine call returns the dirty
rect it touched.**

```
NSEvent ─▶ CanvasNSView.begin/extend/finish
             │
             ├─▶ PaintEngine.beginStroke/continueStroke/endStroke  ──▶ PixelRect
             │
             ├─▶ EditorModel.noteChange(dirty)
             │     ├─ revision &+= 1              (SwiftUI sees this)
             │     ├─ onCanvasChanged  ──▶ DrawingDocument.updateChangeCount
             │     └─ onEditCommitted  ──▶ NSUndoManager.registerUndo
             │
             └─▶ CanvasNSView.invalidate(dirty)   (setNeedsDisplay, rect-scoped)
```

Two things about this are load-bearing:

**The dirty rect scopes both redraw and undo capture.** Returning
`canvas.bounds` from a tool would still be *correct* and would quietly make a
large canvas drop frames. When adding a tool, return the smallest honest rect.

**The view tracks which revision it has already painted.** SwiftUI re-runs
`CanvasScrollView.updateNSView` on *every* observed change — including the
pointer moving — so `repaintIfChanged(revision:)` compares against
`paintedRevision` and does nothing for a change the view painted itself. Without
it, every mouse-moved event costs a full-canvas redraw. There is a test for this
(`paintedRevisionIsNotRepainted`).

---

## The gesture state machine

`PaintEngine.Gesture` is a private enum and the whole interaction model:

| Case | Tools | Committed |
|---|---|---|
| `.freehand` | pencil, brush (including the spray tip), eraser | continuously; one undo step per stroke |
| `.highlight` | highlighter | accumulates coverage, recomposites from the pre-stroke snapshot so overlaps never darken |
| `.shape` | shape tool, pixelate | live preview, rolled back and redrawn each step |
| `.bend` | curve, second step | preview from the chord's snapshot |
| `.region` | select (rectangle/ellipse), pixelate | marquee, no pixels |
| `.lasso` | select (lasso) | traced points → mask |
| `.moveFloating` / `.resizeFloating` | anything, over floating content | |

Three tools have **no** gesture and are driven by the view instead:

- **Text** — the view drags the box, runs an `NSTextView`, then calls
  `drawText(_:in:style:)`.
- **Badge** — a click; `beginStroke` drops it and returns.
- **Polygon / curve** — multi-step. The engine holds `pendingCurve` /
  `pendingPolygon`: pixels are on the canvas as a live preview with **no undo
  step yet**, so abandoning leaves no trace and finishing records exactly one
  edit. Anything else that happens calls `commitPendingShape()`.

### Adding a tool

1. `ToolKind`: add the case, `displayName`, `symbolName`, `shortcut`, and the
   trait properties (`isFreehand`, `usesBrushSize`, `showsBrushPreview`, …).
2. `ToolKind.groups`: put it in a run — but check first whether it is really a
   *variation* of an existing tool (see [PHILOSOPHY](PHILOSOPHY.md), rule 2).
3. `PaintEngine.beginStroke`: branch before the freehand fallthrough. Return the
   dirty rect.
4. `ToolSettings`: add any settings, with clamping in `init`.
5. `EditorModel`: mirror the setting for SwiftUI bindings.
6. `ToolOptions.controls`: add the `case` — the switch is exhaustive, so the
   compiler will tell you.
7. Tests: one that draws with it, one that undoes it. See
   [TESTING](TESTING.md).

### Adding a shape

Most shapes are point lists: add the case to `ShapeKind`, a name, a symbol, and
the corners in `points(in:)`. `drawPolygonShape` gives you fill, outline, stroke
weight and dash for free. Only shapes with their own geometry (callout, curve,
rounded rectangle) need code in `drawShape`.

### Adding an export format

`ImageCodec.Format`: case, `utType`, `displayName`, `fileExtension`,
`supportsAlpha`, `supportsQuality`. `Format.isWritable` checks the machine's
actual ImageIO encoders, and `exportable` filters the panel by it — so a format
this OS cannot write never appears in the list. The codec test
`everyFormatEncodes` will fail if a declared format cannot round-trip.

---

## Selection and floating content

Two types, deliberately separate:

- **`Selection`** — a `PixelRect` plus an *optional* per-pixel mask. `nil` mask
  means "the whole rect", which keeps the common rectangular case free of a
  megabyte of coverage bytes. Ellipse and lasso fill one in. Everything
  downstream (cut, copy, delete, crop, invert) reads `coverage(at:)`, so a
  freeform selection is not a second code path that can drift.
- **`FloatingSelection`** — content lifted or pasted, living *beside* the canvas.
  While it floats the pixels underneath are untouched, so moving costs nothing
  and cancelling leaves no trace. It keeps the original pixels and re-renders
  when resized, so scaling down and back up does not accumulate resampling loss.

Dragging inside a marquee lifts it automatically — no separate Cut step, which
is the classic reason people conclude a selection "doesn't do anything".

---

## Undo

`UndoStack` holds `PixelEdit`s: a name, a before `RectPatch` and an after
`RectPatch`, both scoped to the dirty rect.

- **Bounded by bytes, not steps.** Fifty dots and fifty full-canvas fills differ
  by four orders of magnitude; a step count is the wrong unit. `byteCount` is a
  running total — recomputing it per record made building a long history
  quadratic.
- **Bridged to `NSUndoManager`** by registering the inverse from *inside* each
  replay (`DrawingDocument.replayUndo`/`replayRedo`), so the engine's history and
  the Edit menu stay in lockstep instead of drifting into two stacks.
- **A size change clears history**, because patches are addressed in canvas
  coordinates and would restore pixels into the wrong places.

---

## Document format

`.itspaint` is a **package** (a directory):

```
Sketch.itspaint/
  canvas.png       lossless, the artwork
  document.json    { formatVersion, width, height, foreground, background, palette }
```

The pixels are a PNG rather than a private blob so the artwork is recoverable
with any image tool even if this app disappears. A package written by an older
build, or with a damaged `document.json`, still opens — the artwork is the
document, the rest is preference.

Autosave-in-place is scoped to `.itspaint` only (`autosavingFileType`); an
imported PNG requires an explicit Save.

---

## Concurrency

`NSDocument`'s `read` and `write` are nonisolated because AppKit may run them off
the main thread. This document opts out of both
(`canConcurrentlyReadDocuments`, `canAsynchronouslyWrite` → `false`), which is
what makes the `MainActor.assumeIsolated` blocks inside them a guarantee rather
than a hope. Everything else — engine, model, views — is main-actor.

Two rules learned the hard way, both with comments at the site:

- **Never mutate observable state inside an AppKit layout pass.** SwiftUI will
  rebuild the view tree while AppKit is still walking it, and AppKit then
  messages a view it has released — a segfault inside `isFlipped`, nowhere near
  the cause. `ViewportScrollView.layout()` defers its callback for exactly this.
- **Timers are main-actor and scoped to a window.** The marching-ants timer is
  torn down in `viewDidMoveToWindow`, not `deinit`: a nonisolated `deinit` cannot
  touch a main-actor `Timer`, and a repeating timer holding the view would keep
  it alive anyway.

---

## Grids

`FixedGrid` exists because `LazyVGrid` asks for as much width as it is offered,
and inside a `fixedSize` container — which every panel here is, so the chrome
never resizes with the window — that resolves to the whole screen. The result
was a control rendering hundreds of points wide with three enormous glyphs in
it. Chunking into explicit rows makes the size arithmetic rather than
negotiation. **Use `FixedGrid` for anything inside the chrome.**

---

## Where to start reading

- Changing how something *draws*: `Raster.swift`, then `PaintEngine.drawShape`.
- Changing what a *gesture does*: `PaintEngine.beginStroke` and its siblings.
- Changing the *chrome*: `EditorView` (layout) → `ToolRail` / `ToolOptions`.
- Changing what a *menu* does: `MainMenuBuilder` (the list) and
  `DocumentCommands` (the implementations + validation).
