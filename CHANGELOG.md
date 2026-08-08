# Changelog

Notable changes, newest first. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0 the minor
version may still carry breaking changes to the document format.

## Unreleased

### Added
- **Text carries a contrasting rim, by default.** Annotation text goes on top of
  a screenshot, and a screenshot is not a colour — it is a light sidebar beside a
  dark editor beside a photograph. Any single text colour is illegible somewhere
  in that frame, and "pick a colour that works" cannot be picked once for an
  image the app has never seen. A rim in the opposite tone makes one colour work
  everywhere.

  On by default: text over a screenshot *without* a rim is the defect, and a
  default nobody finds is the same as not having built it. `haloColour: nil`
  turns it off.

  CoreText's negative stroke width looks like the one-attribute shortcut for this
  and is not — it centres the stroke on the glyph outline and eats inward. At 8%
  of the point size that consumed the entire body of "Il", "W" and "Step 1" at
  both 18pt and 40pt; 290 dark pixels became 0. The rim is its own stroke-only
  pass with the filled text drawn over it, which leaves the stroke showing on the
  outside only.
- **Drag the image out of the window.** A handle sits with cut, copy and paste in
  the header; dragging it carries the current selection, or the whole canvas when
  there is none, into Slack, Mail, the Finder, or anything else that accepts a
  PNG. No save panel and no file left behind.

  Every other way out of the app writes a file first — Export asks where, Copy
  needs somewhere to paste. This closes the shortest path, and it is the single
  most-named thing people say they lost when Skitch stopped working.

  Deliberately *in the header* rather than beside the canvas. Every app that has
  this hides it: the demand in the wild is not for the capability, which several
  tools already have, but for an affordance that can be found — people asked for
  the feature in the same threads where they had missed the existing button. It
  is also the one control in that group that is never disabled, since there is
  always a canvas to drag, so it is the one your eye lands on.

## [0.12.1] — 2026-08-07

A package release. **The app is unchanged from 0.12.0** — there is no new disk
image and the Homebrew cask and Mac App Store both still serve 0.12.0.

### Added
- **The engine is declared at the repository root**, so `swift build`,
  `swift test` and `.package(url:)` all work against a fresh clone. Previously
  the only manifest was `Packages/PaintKit/Package.swift`, which meant Swift's
  own tooling could not see a package here at all: tools that look for a root
  manifest — including the Swift Package Index, which reads the repository tree
  non-recursively — found nothing, and `swift test` in a clone failed before it
  started. The root manifest adds no targets and duplicates no source; it points
  `path:` at the same directories, and CI diffs `dump-package` between the two
  manifests so they cannot drift apart.
- `PaintKit` is now a resolvable product:
  `.package(url: "https://github.com/joshlin2201/itspaint.git", from: "0.12.1")`.
  Earlier tags predate the root manifest, so `0.12.1` is the floor.

## [0.12.0] — 2026-08-03

### Added
- **The privacy claim is now checkable rather than asserted.** "No network,
  accounts or telemetry" is the kind of line every app writes, so the README now
  carries the three commands that test it against an installed build: the
  entitlements the binary actually ships with (no `network.client`, no
  `network.server`, so the sandbox refuses a socket whatever the code does), the
  `otool -L` output (no `CFNetwork`, no `Network.framework`, nothing outside the
  system on either architecture), and a `grep` for the networking APIs across
  the source, which returns nothing.
- **A README workflow reel** (`docs/images/markup-reel.gif`): paste a settings
  sheet, drop three step badges, pixelate the API token — nine seconds, 150 KB,
  and every frame is a real editor window rendered by `WindowCaptureTests`,
  driving the same model the app runs. The two jobs macOS Markup cannot do are
  now the first thing the repository shows.
- **A new hero demo scene** (`paint-demo --scene chameleon`, and the default
  when no scene is named): a low-poly chameleon catching a drop of paint,
  painted by the engine — polygon facets, brush-stroke tail spiral, highlighter
  shadow — on a canvas Instant Alpha has fully knocked out. The README window
  capture now comes from `WindowCaptureTests`, which renders a real editor
  window to PNG from inside the app process, so every pixel of the hero image
  is reproducible from this repository.
- **Remove Background** (`Image ▸ Remove Background`) keys the page out from
  behind the subject in one command. It is not a new engine — it is Instant
  Alpha's own span walk, seeded automatically at the four corners at a tolerance
  that survives a real capture. Four corners rather than one because a subject
  touching an edge splits the page into separate regions, and a corner in a
  different region from the other three is the normal case.

  It **declines rather than guessing.** If the flood would take essentially the
  whole canvas — which is what happens on a flat image, where every corner is the
  same region as the middle — nothing changes and the alert points at Instant
  Alpha. A one-click background removal that erases the picture is worse than one
  that says it cannot help.

  This closes one of the three cheap parity gaps against Windows 11 Paint, whose
  version of this is AI-backed and one click; ours is one click and needs no
  model, no network and no NPU.
- **Signature capture** (`⌃⌘S`, `Tools ▸ Signature…`). Sign in the box with a
  trackpad, mouse or tablet, or import a photo of a signature on paper. Either
  way the ink is keyed to transparent and trimmed to itself, so it lands *on*
  the artwork instead of dropping a white patch over it, and it arrives as
  floating content — positioning a signature is the same gesture as positioning
  a paste. Signatures are kept as one keyed PNG each in Application Support, so
  the directory listing is the library and there is no index to fall out of step
  with the files.

  Three decisions worth knowing. **A signature never grows the canvas**, unlike
  a paste: it goes onto a page that already exists, so it scales down to at most
  40% of the canvas and lands lower-right. **The ink is keyed against a local
  paper estimate**, per tile and interpolated, because a phone photo has a
  lighting gradient across it and one paper level for the whole frame either
  eats the pale parts of the strokes or leaves a grey haze. And the strip is
  **paper white in both appearances** — its border, baseline and hint are
  explicitly dark, since `.primary` is white in dark mode and would be invisible
  on it.

  No camera route yet: it needs a camera entitlement and a permission prompt,
  which is a bigger ask than the feature has earned before anyone has used it.
  A photo taken on a phone and AirDropped is the same result through a door that
  is already open.

### Fixed
- **Editing an imported image and quitting threw the edit away, in silence.**
  Trim a screenshot, press `⌘Q`, and nothing asked and nothing saved: the
  document claimed `autosavesInPlace`, which tells AppKit the work is already on
  disk, while `autosavingFileType` returned nil for anything that was not our
  own package, which meant no autosave ever ran. The nil also left the document
  permanently holding unautosaved changes, so every close re-entered an autosave
  that could not happen — the shape of a beachball. Every document now autosaves
  as the type it was opened as. Nothing sets an autosaving delay, so a lossy
  original is still only re-encoded when the document closes, which is when a
  Save would have re-encoded it anyway.
- **A save cost four copies of the artwork, at once, on the main thread.** The
  encoder built the whole file in memory and then handed `Data` another copy of
  it to write — on top of the canvas and the `CGImage` — so saving a
  33-megapixel screenshot briefly needed most of a gigabyte, with the UI held
  for the duration. Core Graphics now encodes straight into the file. Still
  atomic: the bytes land in a sibling temporary that replaces the original only
  once the encode has finished.
- **Undo history was budgeted at 512 MB per document, regardless of canvas.**
  Half the RAM of an 8 GB Mac, retained by one window, and the edits that change
  the canvas *size* — trim, crop, rotate, paste-to-fit — each carry two whole
  canvases. The budget now follows the canvas (about a dozen full-canvas edits,
  floored at 32 MB and capped at 256 MB), so a sketch keeps a deep history and a
  screenshot cannot quietly retain a gigabyte of pixels.
- **The canvas was copied whole on every repaint.** Handing the drawn snapshot
  to Core Graphics memcpy'd the entire raster — 131 MB per repaint on a
  33-megapixel canvas, and again per save, per export, per copy. The image now
  shares the canvas buffer and copy-on-write gives the *next* stroke the fresh
  one, which is the same guarantee for none of the copying.
- **The canvas shadow was recomputed by rendering the canvas offscreen.** A
  layer shadow with no path makes Core Animation blur the layer's own alpha to
  find a silhouette — over the whole artwork, every time it is dirtied. The
  canvas is a rectangle, so it now says so.
- **Trim scanned pixels it had already ruled out.** The column pass walked the
  full height of the image, including the rows the row pass had just proved were
  border. It now walks only the rows that survived — on a screenshot with a
  thick top bar, most of the work was in the part already decided.
- **The Place / Crop / Discard bar outlived the content it acts on.** Placing a
  float and then undoing past it left the bar up over nothing, offering to place
  something that was no longer there, with a blank size chip beside it. The same
  passthrough problem as the badge counter, one property along: the bar asked
  the engine whether anything was floating, and nothing told SwiftUI when the
  answer changed — so it came and went only when some *other* state happened to
  redraw the view around it. The chip looked blank rather than stale precisely
  because it *does* follow `revision`. The flag is mirrored on `EditorModel`
  now, synced wherever a dirty rect is already noted, so every route that can
  lift, place, discard or undo a float is covered by one write.
- **The step badge counter appeared to stick.** `PaintEngine` is deliberately
  UI-free and so not `@Observable`, and both the rail cell and the panel hint
  read the counter through a computed passthrough — invisible to SwiftUI, so
  they showed whatever number they had rendered first and only moved when
  something else happened to invalidate them. The counter is now mirrored on
  `EditorModel` and synced only when it genuinely changes, which keeps the
  notification exact: reading `revision` instead would re-render the rail on
  every mouse-moved event of a stroke to track a number that moves once per
  badge.
- **Undoing a badge left the counter advanced.** The pixels came back and the
  next stamp still skipped a number, so the sequence on the canvas stopped
  matching the one the tool was about to continue. A badge edit now records the
  number it consumed; undo hands it back and redo takes it again. Recorded on
  the edit rather than counted from the stack, because trimming the history
  drops the oldest edits and would silently renumber badges still on screen.

### Changed
- **The selection actions are icons in both orientations.** Labelled, they
  truncated to `In…` and `D…` in the fixed-width side panel; dropping the words
  there left the bottom bar still carrying them, so the same four actions read
  two different ways depending on which edge the toolbar was on. One rule now,
  each with its tooltip and accessibility label.
- **The airbrush is now the brush's spray tip**, not its own rail button. It
  differed from the brush by one thing — whether coverage builds while you hold
  still — so it was a nib, not a job. Tip is now Round / Square / Soft / Spray,
  Flow appears only for Spray, and the rail is eleven cells instead of twelve.
  A spray stroke undoes as "Spray", the way a rectangle undoes as "Rectangle"
  rather than "Shape". `A` is no longer a tool shortcut.
- **The paint bucket now matches loosely by default** (tolerance 16, was 0). On
  a real screenshot an exact-match fill covers nothing at all: once JPEG noise
  and Retina downscaling have been through a "flat" region, no two pixels in it
  are equal. Measured on a capture, the flat blue of a menu bar filled 0.00% at
  tolerance 0. Coverage is stable from 8 through 32 and then falls off a cliff —
  at 48 a probe in dark window chrome jumps from 4% to 91%, because adjacent
  near-blacks in a dark UI are within 48 of each other. 16 clears the noise with
  the cliff still three times away.
- **The brush size stops are 2 / 6 / 14 / 28** (were 1 / 4 / 12 / 28). The brush
  opens at 2, which was not one of them, so the stop row opened with no segment
  selected — indistinguishable from a disabled control. 1px is the pencil's job
  and the slider still reaches it.
- **The step badge's rail cell shows the number it will drop next**, in outline
  weight. It used to read `1` forever while the panel beside it said "Drops 4
  next", and it was the only filled glyph in a rail of outline strokes.
- **The Font row wears the panel's own material.** A stock pop-up button gave
  the Text panel a third control material in four rows, and the only accent-blue
  chrome on screen that was not a selection. The menu is still native; the
  button is not. Each face now previews itself.
- **Bold, italic and underline draw their cells when off.** All three off in an
  empty trough, directly above an Align row where one cell is always filled,
  read as a switched-off control rather than three you can press.
- **The zoom percentage is the Actual Size button.** There was a dedicated cell
  behind a divider *and* a tap gesture on the percentage doing the same thing,
  and the dedicated one wore the glyph that means fit-or-full-screen everywhere
  else. One control now, and it hovers and presses like its neighbours.
- **Tool hints carry only what a pointer cannot show you** — a modifier key or a
  second stage of a gesture. "Drag its edge to move · corners resize · ⌘↩ places
  it" was three clauses in three grammars that wrapped to a second line and made
  the Text panel a different height from every other panel.
- The floating paste bar says **Crop** rather than "Crop to it", and Discard is
  marked as the destructive one instead of matching the reversible action beside
  it.
- One opacity scale (`Tokens.Ink`, `Tokens.Fill`) behind the chrome, replacing
  24 hand-picked values that included 0.5, 0.55, 0.6 and 0.62 for the same job.
  The rail's colour chips are drawn at the same radius as the popover's.

## [0.11.0] — 2026-07-29

**Releases are now signed with a Developer ID and notarised.** The ticket is
stapled to both the disk image and the app inside it, so a first launch works
offline and the install needs no Control-click and no `xattr`.

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

[Unreleased]: https://github.com/joshlin2201/itspaint/compare/v0.12.0...HEAD
[0.12.0]: https://github.com/joshlin2201/itspaint/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/joshlin2201/itspaint/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/joshlin2201/itspaint/releases/tag/v0.10.0
