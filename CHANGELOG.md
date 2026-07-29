# Changelog

Notable changes, newest first. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0 the minor
version may still carry breaking changes to the document format.

## [Unreleased]

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

[Unreleased]: https://github.com/joshlin2201/itspaint/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/joshlin2201/itspaint/releases/tag/v0.10.0
