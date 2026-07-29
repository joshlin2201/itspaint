# Changelog

Notable changes, newest first. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0 the minor
version may still carry breaking changes to the document format.

## [Unreleased]

## [0.11.0] — 2026-07-29

### Added
- **Bold, italic and underline** for text, in the options panel and on
  `⌘B` / `⌘I` / `⌘U`. Applied as real symbolic traits, so a face with a genuine
  bold or italic cut uses it rather than a synthesised slant. Pressing one while
  holding another tool arms the text tool with it.
- **The text box has resize handles**, the same eight the floating selection
  has, and it **grows as you type**. Both boxes now resolve a grab through one
  shared `PixelRect` handle model rather than two implementations.
- **Rotate…** by any angle, with a size preview and one-click stops. The canvas
  grows to the rotated bounding box and the exposed corners take Colour 2. The
  90° turns keep their own exact, lossless path — routing them through the
  resampler would soften an image slightly on every rotation.

### Changed
- **The header is a document header, not a floating chip.** The title is plain
  text with the canvas size and edit state beneath it; the bordered card around
  it drew a box around the emptiest part of the window and made a label look
  like a button. Undo/redo, zoom and Duplicate are now three grouped clusters.
- **The zoom and dimensions readout moved out of the artwork.** It floated at
  the bottom-right — which is where the interesting part of a screenshot
  usually is — so it covered the thing being annotated. What is left near the
  canvas is the pointer position and live drag size, with no capsule, no
  material and no shadow, fading out when the pointer leaves.
- **The options panel is laid out on a grid.** One fixed panel width, one label
  column, and controls that fill what is left, so "Size", "Stroke" and "Flow"
  end at the same x. It used to size itself to whichever row happened to be
  widest, which meant nothing aligned and a control's size carried no meaning —
  "Round / Square / Soft" was three times the width of the fill picker beneath
  it purely because those words are longer. Segments now share their row
  equally, and the four brush-size stops sit in a real track instead of
  trailing the slider as four bare capsules.
- **The default tool is the brush at 2px**, not the 1px pencil. A single hard
  pixel is the right tool to *have*, but at any zoom below 100% it draws a faint
  dotted line, and the app reads as broken before it reads as precise.
- The side rail sheds palette columns on a short window instead of clipping.
  The colour block used to be cut in half and the edge toggle simply gone below
  the fold of a scroll view with hidden indicators, with nothing to say anything
  was missing.
- **The toolbar is one cell thick on either edge — 48pt, down from 86pt at the
  side.** The side rail was a two-column grid that ran the full height of the
  window and left an orphan cell at the end of every five-tool group. It is now
  a single file of buttons: the bottom bar stood on its end, at exactly the same
  thickness, rendered from the same code transposed.
- **The palette is always two swatches across the rail**, in both orientations.
  It used to take as many rows as it needed — seven beside the side rail, and an
  extra one the moment a custom colour was used. A narrower rail now truncates
  by *column* rather than in reading order, so every swatch keeps its place and
  its muted partner; the bottom bar carries all fourteen columns and the side
  rail the leading seven.
- Recently used colours moved from the rail into the colour popover, which
  already listed them. They arrive unpredictably, and a toolbar that changes
  size while you work moves the button you were reaching for.
- Margins tightened: the rail now shares the artwork's 6pt window inset instead
  of sitting on a wider one.

### Fixed
- **Everything typed after the first Return was silently lost.** `CTFrameDraw`
  clips to the box it is given, and the box never grew — so a second line fell
  outside it and was dropped with no error, no overflow and no partial glyph.
  The box now grows to the measured height on every keystroke.
- **Corner resize handles showed a crosshair instead of a diagonal arrow.**
  AppKit publishes no diagonal resize cursor and the corners fell back to
  `.crosshair`; all four are now drawn from one generator rather than depending
  on the private `_windowResizeNorthWestSouthEastCursor`.
- **Picking a tool did not change the pointer.** Cursor rects were rebuilt on
  space-release and on crossing a floating selection's handles, and on nothing
  else — so the canvas kept the previous tool's cursor until something unrelated
  invalidated it. Every tool was affected; the pencil was just the most obvious.
- **A band of transparency checkerboard along the top and bottom edge of every
  document.** The canvas layer deliberately does not mask, so the sheet shadow
  can fall outside the artwork; AppKit pads the dirty rect to cover that shadow,
  and the checkerboard was being painted across all of it rather than clipped to
  the canvas.
- **Pasted and dropped images now scroll into view.** They land at the engine's
  own origin, which on a zoomed or scrolled canvas is routinely off screen — and
  a paste you cannot see is indistinguishable from a paste that did not happen.
  Only the arrival scrolls; dragging content does not chase it.
- The options panel is measured rather than assumed, so a tall panel — the shape
  tool's, with its fifteen-cell gallery — can no longer hang off the bottom of a
  short window.
- The panel now lines up with the tool button it belongs to. The offset was
  computed by dividing the rail-wide cell index, which assumed the tool groups
  packed continuously; by the eyedropper it was a full row low.
- The canvas fit accounts for the window's bottom safe inset, which it was
  previously reserving the rail's inset for instead.

## [0.10.0] — 2026-07-28

First public beta.

### Added
- **Instant Alpha** inside Select: click a connected colour to select it,
  adjust tolerance, `⇧`-click to add and `⌥`-click to subtract. The canvas
  traces the real pixel boundary and **Make transparent** is undoable.
- A checkerboard beneath the artwork makes cleared and imported transparency
  visible before save.
- **Twelve tools**: pencil, brush, airbrush, highlighter, eraser, shape, text,
  numbered step badges, fill, eyedropper, select, and Pixelate.
- **Fifteen shapes** inside one Shape tool — line, curve (drag then bend),
  arrow, rectangle, rounded rectangle, ellipse, triangle, right triangle,
  diamond, pentagon, hexagon, five- and six-point stars, speech bubble, and a
  click-corner polygon — with solid, dashed or dotted outlines.
- **One Select tool** carrying rectangle, ellipse, lasso and Instant Alpha.
- Text that rasterises on commit, with font, size, alignment, and ⌘-drag to
  move the box while typing.
- Export to PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF and ICO, with a format
  and scale picker; Copy Whole Image and Share.
- Rect-scoped undo bounded by bytes rather than step count.
- `.itspaint` documents: a lossless PNG plus JSON metadata, so the artwork is
  recoverable with any image tool.

### Changed
- The left and bottom toolbars now fit their own content: tighter section
  spacing on the side and a single compact colour row along the bottom.
- The title and window actions now share one centred 32-point header line, and
  long filenames truncate cleanly instead of crowding the actions.
- Always-visible chrome: every tool, both loaded colours and all 28 swatches on
  screen at once, in a rail that moves between the left edge and the bottom
  (⌥⌘T).
- Pinch and ⌘-scroll zoom anchored at the pointer; ⌘+/⌘− snap to the ramp.
- Escape leaves any state: a half-drawn shape, a text box, a selection, a
  floating paste, an open options panel.

### Known limits
- The app is **ad-hoc signed, not notarised** — macOS quarantines it on first
  download. See the README for the one-line fix, or build from source.
- No WebP export: this OS reads WebP but ships no encoder, and a third-party
  one would be a dependency this app does not have. AVIF covers the same need.
- Text is pixels once committed; re-editing means undo and retype.

[Unreleased]: https://github.com/joshlin2201/itspaint/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/joshlin2201/itspaint/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/joshlin2201/itspaint/releases/tag/v0.10.0
