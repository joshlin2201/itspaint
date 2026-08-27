# Changelog

Notable changes, newest first. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0 the minor
version may still carry breaking changes to the document format.

## [Unreleased]

## [0.20.0] — 2026-08-27

### Added
- **A transparent colour actually paints now — and it rubs paint out.** The app
  has carried alpha end to end since the beginning: the picker offers it, the
  file format keeps it, the bucket has always meant "knock a hole in this". Every
  other tool disagreed silently. Source-over compositing with a fully transparent
  source is arithmetically `out = dst`, so the pencil, the brush, the shapes, the
  text and the **eraser** did precisely nothing and said nothing about it — and
  the eraser paints Colour 2, which is exactly what somebody loads when they want
  a hole. All five compositors take a destination-out branch now: the brush stamp,
  the antialiased stroke the default round brush actually uses, the shape fill, the
  airbrush, and the text, which needs a blend mode because Core Graphics cannot say
  "erase" with a colour. A soft brush erases softly for free.
- **A filled shape drawn with a transparent Colour 2 cuts its interior out**, for
  the same reason. Worth knowing before you load a clear Colour 2 to get the
  eraser working and then draw a filled callout over something you wanted to keep.
  It is one ⌘Z, and the default shape style is outline.
- **A More colours button, in the toolbar where you can see it.** The full
  palette, custom colours and *opacity* were behind ⇧⌘C and a menu item three
  levels down. It sits beside Swap, in the run that button used to hold alone, so
  the rail is not a pixel thicker and the palette does not lose a column to it.
- **Chips say when a colour is see-through.** The same checkerboard the canvas
  draws under transparent pixels, at half its tile, behind any chip or swatch
  whose colour is not solid — and only then, because a texture that is always
  there is a texture people stop seeing. Its arrival is the signal and how
  strongly it shows through is the reading; the exact percentage is in the
  tooltip and in what VoiceOver says.

### Changed
- **The header sheds controls instead of running off the edge.** The window can
  be dragged to 560pt and the header needed 647pt to draw itself with no filename
  in it — so the zoom controls, Share, Duplicate and the Guide were simply outside
  the window, unreachable, with nothing to say they were there. It now steps down
  a ladder as the window narrows, and every rung drops a run whose commands have
  another door. Nothing that is the *only* way to do something is ever shed: the
  drag-out handle has no chord and no menu item, the zoom read-out is the only
  place the window states its zoom, and Share is what the app is for.
- **The tool options panel draws its own controls, all of them.** Six of them
  were still a stock AppKit slider — blue track, chrome knob — sitting in a panel
  whose every other control was drawn by hand. Flow, Corner, Text size, Match,
  Block and the Instant-Alpha tolerance are marks now, each with its name at the
  head of its own line and its value at the end of it, and every track in the
  panel starting and ending at the same x.
- **One tooltip, one rule.** The chip's near edge sits on a fixed line beside the
  chrome it explains and slides *along* that line to follow the control. The rail
  used to offset its chip by a constant, so hovering the ninth tool put the answer
  up beside the first.
- **The colour popover is gone.** It was a weaker copy of the system Colors
  panel, which has an opacity slider, an eyedropper, saved swatches and a recents
  row that survives quitting. ⇧⌘C, the View menu and the new button all open that
  instead. The app's own list of recent colours went with it.

### Fixed
- **Tooltips no longer cut their own text in half.** The chip measured itself for
  one line and drew three, then clipped the rest away with its own rounded
  rectangle. Every size check in the test file bounded the chip from *above*, so
  each line that went missing made them pass more comfortably; what replaced them
  is a check that a longer sentence makes a taller chip.
- **A short window no longer hides the colour block.** The whole rail sat in one
  scroller with its indicators hidden, so the loaded pair and the edge toggle went
  below the fold with nothing to say they had. The palette gives up columns first,
  and then only the tool run scrolls — with a real scroller, and cut at a real
  cell boundary so the last glyph is never sliced through the middle.
- **The bottom bar sheds too.** It was handed all fourteen palette columns
  whatever the window was, so a narrow one ran the colour block off the right-hand
  end. Both edges use one ladder now.
- **A long filename no longer prints over the zoom controls.** The title had a
  layout priority but no ceiling, and the centred cluster is not in its stack — so
  a long name was handed the whole row and drawn on top of the buttons.
- **VoiceOver can reach every value again.** The options panel's step was
  `max(range / 100, 1)`, which is one pixel on a size and the entire range on any
  0-to-1 fraction: Ink, Opacity and Strength had exactly two reachable values.

## [0.19.0] — 2026-08-26

### Added
- **A selection bar.** Make a marquee and the four things people actually do
  next appear at the bottom of the window with their keys printed on them: Crop
  ⌘K, Copy ⌘C, Cut ⌘X, Delete ⌫. They were a menu bar nobody opens mid-gesture
  and three shortcuts you had to already know — people selected a region, found
  Crop to Selection greyed out earlier in the session, and never went back to it.
  It takes the slot the paste bar already owns, so it is never over the work, and
  the paste bar still wins that slot because placing or discarding is the
  decision actually in front of you. Crop and Delete came *out* of the Select
  panel, where they were unlabelled glyphs behind an expander.
- **Image and View menus in the header.** Flip, rotate, resize, invert, remove
  background, trim, the pixel grid, snapping and the toolbar edge. The menu bar
  is the right home for a complete list and the wrong one for something you reach
  for with the pointer on the canvas — on a second display it is on the other
  screen.
- **Copy to Clipboard in the share sheet**, first in the list. macOS does not
  offer one, and pasting into the window already open is the most common thing
  anyone does with a marked-up screenshot.
- **A Guide button in the header**, and a guide for it to open: every tool, what
  it is for, the drag that makes it work, and every shortcut, at
  [sites.fynesite.com/itspaint-guide](https://sites.fynesite.com/itspaint-guide/).

### Fixed
- **Dragging the image out no longer drags the window with it.** The header sits
  inside the titlebar band of a full-size-content window, and macOS moves the
  window for a drag beginning on any view that allows it — which SwiftUI's does.
  Refusing needs a real AppKit view at that spot, and that view then has to start
  the drag itself, so it does: the picture leaves as a file promise, which is what
  carries the filename across the sandbox boundary instead of arriving as "Image".
- **The tooltip is legible.** Its second line — the line doing the teaching — was
  drawn outside the chip, straight onto the artwork, grey on whatever colour the
  picture happened to be. One surface holds both lines now, it appears in 110ms
  rather than 300, and every header chip hangs from one fixed line under the
  header instead of moving with each control, so reading along the row no longer
  means re-finding the text.
- **The selection bar could not have appeared at all.** `hasSelection` forwarded
  to the engine, which is deliberately not observable, so nothing in the window
  was invalidated when a marquee was made. Found by writing the test, not by
  using the app.


## [0.18.0] — 2026-08-25

### Added
- **Edit in ItsPaint, from the Services menu.** Select an image in the Finder, in
  Mail, in a web page — anywhere macOS offers Services — and it opens here. The
  pasteboard the system hands over is the entire grant, so this needs no new
  entitlement and asks for no permission. The supported types are declared under
  `NSSendFileTypes` rather than `NSSendTypes`: every Finder selection offers
  `public.file-url`, so the generic route would have put the item on folders,
  archives and sound files and then done nothing when it was chosen. **Ten files
  at a time, in name order:**
  choosing a service with a folder of screenshots selected is one gesture, and
  without a ceiling it is one gesture that opens two hundred windows. The order
  matters because pasteboard order is whatever the sending app used, so "the
  first ten" would otherwise be a different ten each time.
- **A Shortcuts action, Open Image in ItsPaint.** A markup step can now sit
  inside a shortcut somebody already runs, which is a door into the app that does
  not require remembering it exists. It takes an image or a PDF page and prefers
  a file on disk over the bytes beside it — a document tied to a real path saves
  back where the image came from, and an untitled one sends you to a panel, and
  the wrong branch there still opens a window, so nothing would catch it until a
  save went missing. The Shortcuts picker filters by type
  (`supportedTypeIdentifiers`, because `supportedContentTypes` is macOS 15 and
  this app runs on 14) and the action checks again on the way in, because
  Shortcuts can hand an action a file its picker never offered. The bytes are read
  through an autoclosure so the file branch never maps them: `IntentFile.data`
  reads the file, and for an external file that read has to happen inside the
  security scope the caller has not opened yet.

### Changed
- **Reduce Motion is honoured everywhere, from one place.** The app has
  twenty-six animations and every one of them is one of three tokens, but the
  setting was being checked at the call site: two calls asked, twenty-four did
  not, which is the arithmetic a per-caller guard always ends up with. The
  question moved into `Tokens.Motion`, whose three values are now `Animation?`
  and are `nil` when the system asks for less movement — `nil` is SwiftUI's
  "apply it instantly", so honouring the setting is the same shape as not
  animating, and no call site changed. The two that were asking by hand stopped
  needing to. This is a setting people turn on because movement makes them ill,
  not because they dislike it.
- **The clipboard shortcut and the Services entry now open a window the same
  way.** Both arrive with an image from somewhere else and no document to put it
  in, and both were about to grow their own copy of the "make an untitled
  document, load it, show it" dance.

## [0.17.0] — 2026-08-22

### Added
- **A PDF opens as a page, and saves as a PDF.** ImageIO can write a PDF and
  cannot read one, so opening a contract failed with *isn't an image ItsPaint can
  read* — which made the signature tool a way to sign screenshots and nothing
  else. Pages now come through Core Graphics' own PDF reader, rasterised at 144
  dpi for editing, and saving writes the edited page back into the document it
  came from: the page keeps the size it was printed at rather than becoming its
  pixel count in points, and every page nobody touched is copied through with its
  text still selectable.
- **A page control, for documents that have pages.** It sits at the bottom of the
  window with the paste bar, and only for PDFs. Turning a page folds the current
  page back into the file first, so a signature on page four survives a look at
  page five; the undo stack does not cross the boundary, because a replayed edit
  belongs to the page it was made on.
- **Signing has a button.** It lived only in Tools ▸ Signature… under ⌃⌘S, a
  chord nothing else in the app uses — the one feature nobody would guess was the
  one feature the window never mentioned. It is now in the header beside Share,
  where the things you do to a finished document already are.
- **ItsPaint appears under Open With for PDFs**, at `Alternate` rank. Opening a
  page to draw on it is not the same job as reading a document, and Preview should
  stay the Mac's PDF reader.

### Changed
- **A shape with no outline is filled with the colour you picked.** Fill used
  Colour 2, which is the right answer for the inside of an outlined shape and the
  wrong one when there is no outline to pair it with: choosing Fill on a fresh
  document painted white on white paper, so the shape was invisible and the
  colour in your hand did nothing. Outline still uses Colour 1, Outline and fill
  still uses Colour 1 for the edge and Colour 2 for the inside, and right-dragging
  still swaps the pair.

### Fixed
- **The size slider was unusable with the toolbar along the bottom.** The row
  measures its own width down there, and a `GeometryReader` offers 10pt
  intrinsically — so the slider was a stub you could not drag, while the same
  control in the side rail was full width.
- **The dashed and dotted line options showed a diagonal line.** Three glyphs
  that all read as "a line" for three different stroke patterns; each segment now
  shows the pattern it draws.
- **Export could fail to write the file at all.** The encoder built its output in
  a temporary file *beside* the destination, and a sandboxed app is granted the
  path the save panel returned, not its folder — so the staged path was one the
  app had no right to create. Core Graphics reported that as a destination it
  could not make, and the alert read *Couldn't write the image as PDF*, followed
  by advice to try PNG, which took the same denied route. The staging file now
  lives in the app's own container and the finished bytes are moved onto the
  granted path, with an in-place write as the fallback where even that is
  refused. Present since 0.12.0, when writing moved off the in-memory route.
- **Copy no longer goes dim when nothing is selected.** With a selection it
  copies the selection; without one it copies the image, which is what ⌘C does in
  every viewer people arrive from. A greyed-out Copy said "copying is
  unavailable" while the obvious thing to copy was on screen.
- **Duplicate asks first.** Two overlapping pages beside Share put a second
  untitled window on screen with no warning, which is indistinguishable from
  having lost your place in the one you were working in. The menu item still goes
  straight through, because it says the word.
- **The header's tooltips are the app's own chip.** The system's takes about a
  second and shows no shortcut, which is why the paste clipboard and the drag-out
  handle were reported as unidentifiable glyphs. They now name themselves in
  300ms, with a line of explanation, exactly as the tool rail already did.

## [0.16.4] — 2026-08-21

### Changed
- **Small Core Graphics marks no longer copy the entire canvas twice.** Vector
  drawing now writes directly into the bitmap's copy-on-write storage. Eight
  one-pixel marks on a 96 MB canvas fell from 286 ms to 11 ms in the release
  throughput guard, while the existing orientation and snapshot tests remain
  unchanged.
- **Image export no longer encodes on the main thread.** Accepting the export
  panel captures the canvas and settings as an immutable snapshot, then scales
  and writes that snapshot on a user-initiated background task. Edits made
  after export starts cannot leak into the file.
- **Sharing writes straight to its temporary PNG.** The share path no longer
  retains encoded image data beside the canvas before writing the file.
- **The App Store listing is concise and task-focused.** It removes model and
  competitor comparisons, repeated claims, and dash-heavy phrasing.

## [0.16.3] — 2026-08-13

`v0.16.2` is a tag with no release behind it. Its build failed on a stale
`ItsPaint.xcodeproj`, and the tag ruleset does not allow a published `v*` to be moved
or deleted, so the same changes ship here. As a Swift package either tag resolves.

### Changed
- **PaintKit now declares macOS 12 instead of macOS 14.** The engine has no UI and no
  dependencies and uses no API newer than Monterey; it had the app's deployment target
  because it sits in the app's repository, not because anything in it needed one. That
  is not a floor a consumer can shrug at either — SwiftPM refuses to resolve the
  dependency at all when its target is above yours, so every app on 12 or 13 got a hard
  error instead of a warning. The app still requires macOS 14.

### Fixed
- **Two claims in the README that nothing measured.** "Compiled and run against the
  published tag" was true of one manual run against 0.13.1 and had been written in the
  present tense for four releases; there is now a CI job that builds the four-line
  snippet from a package outside this repository, which also holds the new floor in
  place. And "the count goes from 0 to 156,400" was asserted nowhere — the test using
  that exact fixture checked two pixels. It now counts the page, for all six subject
  sizes.

## [0.16.1] — 2026-08-13
### Fixed
- **A closed-hand cursor could outlive its drag.** `NSCursor.push` is a global stack
  and the pop only happened on mouse-up or Escape, so Command-Tab, a notification
  stealing focus, a sheet opening or closing the document mid-drag each left the
  pointer stuck as a closed hand over every window for the rest of the session. It is
  now handed back when the window resigns key, when it closes, and when the view
  leaves its window. Introduced by the fix directly below it, in the same night.

- **The text box did not grow when you pressed Return.** CoreText drops one trailing
  empty line when it measures, so a Return at the end of the text reported the same
  height as before the keystroke: the box stayed put while the caret dropped below it,
  and it only caught up once a character was typed.
- **Four different guesses at one line of text.** `pointSize * 1.3` in the measurer,
  `* 1.35` where the box grew, `* 1.4` where a clicked box got its minimum height, and
  AppKit's real metrics inside the live editor. The box the caret sat in and the box
  the text landed in were sized by numbers that had never agreed.

  There is now one `TextRenderer.lineHeight(for:)`, and it lays out a line through the
  same framesetter that draws them. The first repair used the font's own
  `ascent + descent + leading`, which sounds authoritative and is not what CoreText
  stacks lines by: for Helvetica those sum to exactly the point size while a laid-out
  line is 25% taller, so every box came out a quarter-line short.
- **The hand never closed while you were dragging.** Hovering over floating content
  showed an open hand and so did carrying it, so the pointer looked identical before
  and during a drag. Space-panning had done this since the beginning and nothing else
  did. Released through one path, because a pushed cursor popped only on mouse-up
  survives an Escape and leaves the pointer stuck as a closed hand.

- **The Help menu only ever apologised.** `ItsPaint Help` called the stock
  `showHelp(_:)`, which needs a help book in the bundle, and there has never been one,
  so the item put up "Help isn't available for ItsPaint." It now opens the README,
  the feature reference and the issue tracker. These go to the browser through
  LaunchServices, which is a handoff rather than a connection: the sandbox still
  requests no network entitlement and the binary still links no networking framework.
- **Committed text was coarser than the text you typed.** The bitmap context did not
  enable subpixel glyph positioning, so every glyph origin was rounded to a whole
  pixel and stem spacing came out uneven. Turned on, along with explicit antialiasing.
  Font smoothing is deliberately left off: subpixel RGB would bake one display's
  stripe order into an image meant to be shared.

  The canvas is still one pixel per pixel, so a commit at 100% zoom on a Retina
  display carries less detail than an editor drawn at the screen's own scale. This
  closes the part of that gap that was ours.
- **Nothing said a selection could be dragged.** With a marquee on screen the pointer
  kept showing a crosshair, including inside the marquee, where a drag lifts the
  pixels and moves them. It shows an open hand there now.

- **A freehand curve came out as a chain of straight chords.** The engine joined
  consecutive mouse samples with a straight line, so a quick drag left a visible
  corner at every sample and read as a low frame rate rather than as a drawing.

  Strokes now follow a Catmull-Rom curve through the samples. Catmull-Rom because it
  passes *through* its control points: the line has to go where the hand went, and a
  curve that merely approaches the samples would be smoother and also somewhere else.
  The stroke trails the pointer by two mouse moves, which is what lets each gap be
  drawn once with a point on either side to shape it, and `endStroke` flushes both.

- **A freehand stroke with a round nib was still aliased.** The coverage renderer
  that fixed diagonal shape outlines now covers freehand too. `.soft` keeps its own
  falloff, `.square` stays hard for pixel art, and the pencil is untouched: its
  promise is landing on the pixels you dragged over, so it gets neither the smoothing
  nor the antialiasing.

### Added
- **Tooltips explain the tools a glyph cannot.** Clone, Select, Pixelate, Spotlight,
  Step badge, Fill, Eyedropper and Highlighter each carry one line under the name
  saying what the first drag does. Deliberately not every tool: a tip on the pencil
  is noise, and once a panel explains everything a reader stops reading any of it.

## [0.16.0] — 2026-08-13
### Added
- **Clone (`C`) and Soften (`F`).** The repair tool: copy pixels from one part of the
  canvas to another, which is how you put back a chunk an AI generator left out of a
  shape. Click once to set the source, then drag where the pixels should go.

  The pairing is aligned, so the offset holds across strokes and you set it once and
  paint the hole in as many passes as it takes. Every destination reads the canvas as
  it was before the stroke began, so dragging back across your own source cannot turn
  the source into a copy of the hole and then a copy of that. A source that falls
  outside the canvas is skipped rather than wrapped, and the pairing is forgotten when
  the canvas is resized, because the coordinates it was expressed in are gone.

  **Soften** is the same cell in its other mode, for the seam a clone leaves. It blurs
  towards the neighbourhood as it was before the stroke, so holding still does nothing
  at all: the pixel after two hundred events is the pixel after one. That is what
  stops it being a smudge, and a smudge is what turns crisp artwork to mush.

  Designed with grok 4.6, which argued against Poisson healing for this job and was
  right: seamless cloning solves towards the boundary colours, so a flat patch pushed
  into a page-bounded hole erases the very point you copied. The star melts. Cheap
  imitations of it do the same smear without the solver.

  The rail was full. The thirteenth cell put it 3pt past what a 800pt window can give,
  so the side palette shows six swatch pairs rather than seven; the rest are one
  `⇧⌘C` away. Relaxing the geometry test instead is the move
  `docs/A_GUARD_TUNED_TO_ITS_TEST.md` exists to warn about.

### Changed
- **The tool options panel is built from clusters rather than labelled rows.** Every
  property used to be a 42pt right-aligned word, a stock `Slider` at `.mini`, a
  trailing number and, for size, a second row of capsules setting the same integer.
  Four pieces saying one word, repeated until the panel was one grey surface.

  The rule now: cover the title and you should still know which tool you are holding.
  Size is a wedge that thickens to the right with the stops as ticks on it. The
  highlighter's opacity control is a wash of the current ink. Spotlight's dim is a
  plate whose darkness is the value. The step badge leads with the number, at 22pt,
  because the number is the thing being set.

  The property names move to VoiceOver, where a name is worth having. **Restart at 1**
  appears only when the next number is not already 1.

### Fixed
- **Diagonal shape outlines were a staircase.** Every outline stamped a hard nib
  along a Bresenham walk, which is exactly right for the pencil and exactly wrong for
  an arrow across a screenshot: at a 3px weight the steps are wide enough to read as
  jagged at 100% zoom. Lines, curves, arrows, polygons, stars, callout tails and
  rounded-rectangle runs are now rendered by coverage, which also fixes the corners,
  because two segments meeting at a join both report partial coverage there instead
  of overstamping.

  **Edges** in the shape options switches it off for pixel art, where a fully covered
  pixel and nothing in between is the point. The pencil is unaffected and always hard.

### Changed
- The README's feature sections are a breakdown rather than a narrative, and no
  longer name one chat app three times.

## [0.15.1] — 2026-08-12
### Fixed
- **`A` worked from the menu and did nothing on the canvas.** The canvas resolves
  its own keys, so a menu equivalent alone was bound in one of the two places the
  twelve tool letters are bound in.
- **Stroke weight vanished on a filled shape, and it was not dead.** `PaintEngine`
  insets a filled rectangle, ellipse, rounded rectangle and callout by the stroke
  size, so the weight is the difference between a box and a smaller box. Only the
  dash row is genuinely ignored, and only that one hides now.
- **One visit to the highlighter took the 1–3px sizes away for the session.**
  Arming it raises the size to its 4px floor, which is what keeps the panel honest,
  but the raise was one-way. The chosen size comes back when a tool can honour it,
  unless it was changed while the floor was in force.
- **VoiceOver could not activate a palette swatch.** The new mouse handling took the
  click, and the SwiftUI tap it replaced was what VoiceOver had been firing.
- Match tops out at 32 rather than 40. 32 is the last value the coverage sweep
  actually covered; 40 sat in the untested gap between the stable band and the cliff.

### Changed
- `A` is bound on the canvas as well as the menu.

## [0.15.0] — 2026-08-12
### Fixed
- **The highlighter said 2px and painted 4px.** Its chisel nib clamps to a 4px
  floor, and nothing told the options panel, so the readout, the slider and the lit
  size stop all described a stroke the engine would never draw. `[` walked 4 → 3 →
  2 → 1 without changing a pixel, which reads as a dead key rather than a clamp.
  The panel now asks the armed tool what sizes it can paint at.
- **Right-clicking a palette swatch opens a menu instead of loading Colour 2**,
  which is what the swatch's own tooltip promised and what the canvas has done
  since the first build. It now loads Colour 2.
- **Stroke weight and dash stayed live on a filled shape**, where the engine draws
  no outline and ignores both. Dragging Stroke from 2 to 28 on a filled box gave
  back the identical box. They now appear only when the shape has an outline.

### Changed
- **`A` draws an arrow.** It is the annotation primitive people actually reach for
  and it was three moves away: press `U`, open the gallery, find one cell in
  fifteen. `A` was unused.
- **Step badges can start at any number.** A run often spans two screenshots and
  the second one starts at 4. Restart-at-1 was the only control, so continuing a
  sequence meant three throwaway badges and three undos.
- **Both Match sliders stop at 40 rather than 128.** The sweep recorded in
  `ToolSettings` found coverage stable from 8 through 32 and then a cliff: at 48 a
  probe in dark window chrome jumps from 4% to 91%. Most of the old track did not
  match more, it flooded the screenshot. Saved documents keep any value they had.

### Added
- **Spotlight.** Drag a box and everything outside it dims, so the eye lands where
  you meant it to. `S`, or the last button on the rail. The dim is adjustable from
  10% to 90% and defaults to 45%.

  It darkens rather than veiling, so transparency survives: compositing black over
  the outside would paint across the checkerboard on anything whose background had
  already been removed. Dragging a second one darkens the first, which is inherent to
  an app that flattens every edit, and undo is the way back.

## [0.14.1] — 2026-08-11

**0.14.0 was tagged and never built.** Its release run died at the first step on
`fatal: depth 0 is not a positive number`, from a `git fetch --depth=0` that the
runner's git accepted three days earlier and version 2.55.0 rejects. Release tags
here are immutable by repository ruleset, which is the correct setting and means a
tag pointing at a broken commit gets superseded rather than moved. There is no
v0.14.0 download, and there never will be.

### Fixed
- **Remove Background declines a page that is already transparent, instead of
  reporting success and changing nothing.** Open a PNG that has already been keyed,
  run the command, and the flood happily selected the transparent page; the subject
  was still there so the remainder guard was satisfied; and clearing already-clear
  pixels succeeded at doing nothing. The command returned success, pushed an undo
  step and marked the document dirty, with no visible change and no message
  explaining why.

  The remainder guard added in 0.13.1 asks *would this erase the picture*. It does
  not ask *would this change anything*, and on an already-keyed image those two come
  apart. There is now a second decline for that case, and it says the same thing the
  other one says, because it is the same fact: there is no background to remove.

  Found by running the four-line snippet from the README against real files and
  counting transparent pixels before and after, rather than checking that the
  program exited zero and wrote a file. Two of four images came back byte-identical
  with success reported. That is the same shape as the bug 0.13.1 fixed and as the
  write-up about it: the check measured something next to the claim.

### Added
- The README shows PaintKit used as a dependency, in four lines that are compiled
  and run against the published tag rather than written out by hand.

## [0.13.1] — 2026-08-08
### Fixed
- **Remove Background no longer refuses the images it is for.** The guard that
  keeps it from erasing a picture compared *coverage* against 92%, so anything
  more than 92% background was declined — which is a logo, an icon, or a product
  shot on a white sweep, i.e. the whole use case. A 60px mark centred on a
  400×400 page is 97.8% background and came back "There's no background to
  remove."

  Coverage was the wrong quantity. The guard exists for the image whose page and
  subject are one region, where keying out the page erases the picture, and that
  shows up as *nothing left over* — at any coverage. It now measures the
  remainder against a small floor that grows slowly (`max(64, count / 4000)`),
  so a subject is never required to be a large fraction of the image.

  Two things hid it. The test fixture was a 40×20 canvas with a 20×8 subject,
  which sits at 80% page and passes comfortably — the constant was satisfied by
  the test and by nothing anyone would open. And `docs/BACKGROUND_REMOVAL.md`
  argued the failure was a deliberate trade, naming the broken case and calling
  it a corner worth buying. It was the centre of the use case. The regression
  test now runs subjects from 8 to 200 pixels square, 99% down to 75% page.

## [0.13.0] — 2026-08-07
### Added
- **Snap to grid** — `⇧⌘'`, with 8, 16, 32 and 64px spacings under View ▸ Grid
  Spacing, remembered across documents and launches.

  Shapes, marquees and pasted content snap. Pencil, brush, highlighter and
  eraser never do: a freehand stroke that jumped to a grid would not be
  freehand.

  It snaps the region's **edges**, not its corner pixels. `PixelRect(corners:)`
  is inclusive, so rounding both corners to multiples of the grid gives sizes of
  `n × grid + 1` — two boxes drawn one under the other would overlap by a row,
  aligned-looking and quietly wrong. Dragging right or down, the last included
  pixel now lands one short of the grid line, and the next box starting on that
  line abuts it exactly.

  The grid draws whenever snapping is on, at any zoom, with every fourth line
  stronger so cells can be counted. Deliberately faint — the first version was
  legible enough to compete with the artwork, which is the wrong job for a guide.
  This is not the pixel grid: that one draws every pixel above 4× zoom, and
  snapping to it would mean nothing, since a drag already lands on whole pixels.

### Fixed
- **An Instant Alpha selection can be moved.** Pressing inside the marquee made
  a *new* selection instead of lifting the one you had just made, so the region
  you selected could never be dragged anywhere. The exclusion was deliberate —
  Instant Alpha usually selects a background covering most of the canvas, and if
  every press inside moved it there would be nowhere left to click to select
  something else — so neither behaviour wins outright now: a press waits, a drag
  lifts and moves, a click in place still re-selects.
- **The options panel said "Size" twice.** The tool's own size row and the
  selection's dimensions carried the same label, with different units under each.
  The second is now "Area" — and a rule separates the two, because what the tool
  in your hand will do and what can be done to the region already selected are
  different subjects that happened to arrive in the same list.

### Changed
- **The chosen segment in a picker is no longer a flat rectangle of accent
  colour.** Everything around it is a considered surface — a blurred material
  under a tint floor, edged with a luminous hairline — and the selection
  indicator was the one thing left that looked like stock SwiftUI. It now carries
  a gentle fall and a rim of its own colour, so it reads as raised rather than
  painted on, while staying unmistakably the accent.
- **Share stopped responding while a tool's options were open.** It is the one
  control in the header that hosts a real `NSButton`, so its popover can anchor
  to itself, and a hosted AppKit view can be occluded for hit-testing by SwiftUI
  siblings drawn later in the stack even where they draw nothing — which is why
  cut, copy and paste kept working beside it. The header band now sits above the
  tool chrome.


### Fixed
- **The highlighter no longer draws in the pen's colour.** It took the current
  foreground and applied its opacity, so the highlighter a fresh document handed
  you was translucent black — a grey smear — and getting yellow meant changing
  the global colour, highlighting, then changing it back before drawing anything
  else. It now keeps its own ink, defaulting to yellow, with green, pink and blue
  beside it and a fifth cell that follows the colour pair for anyone who wants
  something else. The right button still means "the other colour".

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
- **The tool set as it stood**: pencil, brush, airbrush, highlighter, eraser, shape, text,
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

[Unreleased]: https://github.com/joshlin2201/itspaint/compare/v0.19.0...HEAD
[0.19.0]: https://github.com/joshlin2201/itspaint/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/joshlin2201/itspaint/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/joshlin2201/itspaint/compare/v0.16.4...v0.17.0
[0.16.4]: https://github.com/joshlin2201/itspaint/compare/v0.16.3...v0.16.4
[0.16.3]: https://github.com/joshlin2201/itspaint/compare/v0.16.1...v0.16.3
[0.16.1]: https://github.com/joshlin2201/itspaint/compare/v0.16.0...v0.16.1
[0.16.0]: https://github.com/joshlin2201/itspaint/compare/v0.15.1...v0.16.0
[0.15.1]: https://github.com/joshlin2201/itspaint/compare/v0.14.1...v0.15.1
[0.14.1]: https://github.com/joshlin2201/itspaint/compare/v0.13.1...v0.14.1
[0.13.1]: https://github.com/joshlin2201/itspaint/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/joshlin2201/itspaint/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/joshlin2201/itspaint/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/joshlin2201/itspaint/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/joshlin2201/itspaint/releases/tag/v0.10.0
