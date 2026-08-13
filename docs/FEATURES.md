# Feature reference

Every tool and command, what it actually does, and the behaviour that is easy to
miss. Written against the shipping code — if something here is wrong, that is a
bug in one of the two.

---

## Tools

Thirteen rail buttons in three runs. Every one has a single-key shortcut, shown on
hover and in the Tools menu.

### Draw

| | Tool | Behaviour |
|---|---|---|
| `P` | **Pencil** | Always a hard 1px nib. Not size-aware on purpose — that is the promise of the tool; making it size-aware would make it a small brush. |
| `B` | **Brush** | Four tips at 1–96px. Round and square are hard-edged; soft antialiases over the outer ring; **spray is the airbrush** — it scatters coverage weighted to the centre and **keeps spraying while you hold still**, which is the whole feel of it. Flow sets density, and appears only for the spray tip. Seeded randomness, so a given engine sprays reproducibly. Spray used to be its own rail button; it is a nib, not a job. |
| `H` | **Highlighter** | A 4px floor, because the chisel nib clamps there: the size control shows what the stroke will be rather than a number the engine would round up. Arming it raises a smaller size to 4 and hands the old one back when you leave, so one highlighter stroke does not cost you the 1–3px sizes everywhere else. Coverage buffer, so overlapping passes within one stroke **never darken**. Drag back over your own line and it stays one flat tone, the way a real highlighter does. |
| `C` | **Clone** | Copy pixels from one part of the canvas to another, which is how you put back a chunk an AI generator left out. Click once to set the source, then drag where the pixels should go. The pairing is **aligned**: the offset holds across strokes, so you set it once and paint the hole in as many passes as it takes, and it survives until you pick a new source. Every destination reads the canvas as it was before the stroke started, so dragging back across your own source cannot turn the source into a copy of the hole. A source that falls outside the canvas is skipped rather than wrapped. Honours a selection, unlike the brush. |
| `F` | **Soften** | The same cell in its other mode, for hiding the seam a clone leaves. Blurs towards the neighbourhood as it was before the stroke, so holding still does nothing at all — the pixel you get after two hundred events is the pixel you got after one. That is what stops it being a smudge, and a smudge is what turns crisp artwork to mush. Strength runs 15–85%. |
| `E` | **Eraser** | Lays down the *background* colour — which is what makes it read as removing paint. Right-drag inverts that pairing. |

### Insert

| | Tool | Behaviour |
|---|---|---|
| `U` | **Shape** | Fifteen kinds, below. Stroke weight, dash, fill/outline, corner radius, and **Edges**. `A` arms Shape with Arrow in one key. |
| `T` | **Text** | Drag a box and type in place, at the size and font it will land at. `⌘-drag` moves the box while you type. `⌘↩` places it, `⎋` discards. Rasterises on commit. A click instead of a drag gets a one-line box pulled back inside the canvas, so clicking near an edge still gives you something usable. |
| `N` | **Step badge** | Click to drop `1`, `2`, `3`… in the current colour, numeral auto-contrasted. Size follows the brush size. The options set the next number, so a run continued on a second screenshot can start at 4, and "Restart at 1" puts it back. |
| `K` | **Fill** | Scanline flood fill with a tolerance slider (0–32, per channel). A sweep on a real screenshot found coverage stable from 8 through 32, then a cliff at 48 where a probe in dark window chrome went from 4% to 91%. The slider stops at 32 because that is the last value the sweep covered. The engine still accepts 0–255. Explicitly iterative — a recursive fill overflows the stack on any realistic canvas. Filling with the colour already there is a no-op rather than an infinite loop. |
| `I` | **Eyedropper** | Samples into Colour 1. **Hold `⌥` with any tool** to do the same without switching — right-button samples into Colour 2. Never enters undo: a colour pick on the undo stack is a classic way to make ⌘Z feel broken. |

### Select and effects

| | Tool | Behaviour |
|---|---|---|
| `M` | **Select** | Four modes in its options: **rectangle**, **ellipse**, **lasso**, **Instant Alpha**. Instant Alpha selects a connected colour without changing pixels; set tolerance, `⇧`-click to add, `⌥`-click to subtract, then choose **Make transparent**. Its marching ants follow the actual pixel mask rather than its bounds. |
| `R` | **Pixelate** | Mosaic effect. Averages each block to one value for visual obscuring, with a block size of 4–48. This is not secure redaction; use an opaque filled shape for secrets. |
| `S` | **Spotlight** | Drag a box and everything outside it dims, so the eye lands where you meant it to. Dim runs 10–90% and defaults to 45%, which leaves the surrounding UI readable as context. The corners are rounded by 10px. It **scales the colour channels rather than compositing black over them**, so alpha survives: veiling the outside would paint across the checkerboard on anything whose background you had already removed. Drags under 8px on either side do nothing, because a stray click would otherwise dim the entire image. |

**Dragging inside an existing marquee lifts it** and moves it, with no separate
Cut step. Requiring Cut first is the classic reason people conclude a selection
"doesn't do anything". Lifted content backfills with Colour 2.

Transparency is shown over a checkerboard on the canvas, so Instant Alpha's
result is visible before save rather than inferred from a white background.

While content floats: drag to move, arrow keys to nudge one pixel, corner and
edge handles to resize (⇧ for uniform), `↩` to land it, `⎋` to discard. It keeps
its original pixels and re-renders on resize, so scaling down and back up does
not accumulate resampling loss.

---

## Shapes

Fifteen kinds inside the Shape tool, chosen from its gallery — which also arms
the tool, so it is a way *in* rather than a setting you can only reach once you
are already there. `⌥1`–`⌥9` pick the first nine.

**Line · Curve · Arrow · Rectangle · Rounded rectangle · Ellipse · Triangle ·
Right triangle · Diamond · Pentagon · Hexagon · Five-point star · Six-point star ·
Speech bubble · Polygon**

- **Curve** is two steps: drag the chord, release, then drag to bend it. The bend
  point is a point the curve actually passes through, not an off-curve control
  handle — dragging a handle the line never touches is why Bézier editors need
  explaining and this one does not.
- **Polygon** collects corners on each click and closes when you click the first
  one again (or press `↩`). Fewer than three corners is treated as a stray click
  and leaves nothing behind.
- Both are *pending* until they finish: their pixels are on the canvas as a live
  preview with no undo step, so `⎋` leaves no trace and finishing records exactly
  one edit. Anything else you do lands them rather than dropping them.
- **Speech bubble** leaves a gap in its outline where the tail meets the body, so
  it reads as one shape rather than a box with a triangle stuck on.
- The regular shapes (triangle through six-point star) come from **one parametric
  generator** sampled on the ellipse inscribed in the drag rect, so they stretch
  with the drag instead of staying stubbornly regular in a box that is not
  square.

**Edges** are antialiased by default. An outline is rendered by coverage rather than
by stamping a nib along a Bresenham walk, so a diagonal has no staircase and a corner
where two segments meet composites instead of overstamping. Switching it to hard
pixels gives every covered pixel full coverage and nothing in between, which is what
pixel art and nearest-neighbour scaling want. The pencil ignores the setting and is
always hard, because that is the promise of the pencil.

**Every outline** can be solid, dashed or dotted, at any stroke weight; closed
shapes can be outline, fill, or both. Fill uses Colour 2, outline uses Colour 1 —
and right-dragging swaps that, like everywhere else.

Hold `⇧` while dragging to constrain: lines snap to 45°, boxes and ellipses to
squares and circles.

---

## Colour

- **Colour 1 / Colour 2**, overlapped in the rail. Click either for the system
  picker; `X` swaps them.
- **The palette, always visible**, two swatches across the rail. The bottom bar
  shows all 28; the narrower side rail shows the leading 14, truncated by column
  so every swatch keeps its place. Click for Colour 1, right-click for Colour 2.
- Colours you pick that are not in the palette land in a **recent** run in the
  popover, so the fixed 28 never move and the toolbar never changes height.
- `⇧⌘C` opens the fuller swatch popover with hex read-outs and "Other colour…".

---

## Canvas and view

| | |
|---|---|
| **Zoom** | `⌘+` / `⌘−` step the ramp (25% → 1600%); pinch and `⌘`-scroll are continuous and anchored at the pointer; `⌘0` actual size; `⌘9` fit. |
| **Pan** | Hold `Space` and drag, with any tool. |
| **Pixel grid** | `⌘'`, shown once a pixel is comfortably bigger than the line that draws it (4× and above). |
| **Footprint ring** | Follows the pointer for every marking tool, showing exactly which pixels the next stroke covers. Past 4×, the single pixel under the pointer is outlined. |
| **Toolbar position** | `⌥⌘T` moves the rail between left and bottom; remembered across launches. |
| **Escape** | Abandons whatever is in flight: stroke, pending shape, text box, floating paste, selection, options panel. |

---

## Image commands

Flip horizontal / vertical, rotate 90° either way or 180°, invert colours
(**honours the selection** — inverting one region is far more often what you want
on a screenshot), clear image, remove background, image size (`⌘R`), crop to
selection (`⌘K`), trim borders (`⇧⌘T`).

- **Crop to a lasso** crops to the traced shape, clearing everything outside it
  to transparent — cropping to a freeform shape has to mean the shape, not the
  box around it.
- **Trim borders** is tolerant by default (6/255 per channel): a screenshot's
  "solid" border is rarely one exact colour after a lossy format or a shadow, and
  a zero-tolerance trim silently does nothing on exactly the images people most
  want to trim.
- **Remove Background** keys the page out from behind the subject in one
  command — the same flood Instant Alpha uses, seeded automatically at the four
  corners rather than by hand. Four corners, not one, because a subject that
  touches an edge splits the page into separate regions. An enclosed light area
  *inside* the subject is left alone: the flood is connected, and a hole in the
  middle of the artwork is not background.

  It **declines rather than guessing** when the edges are all one region with the
  middle — on a flat image, removing the background would erase the picture — and
  says so, pointing at Instant Alpha for the version you steer yourself.
- A size change **clears undo history**, because patches are addressed in canvas
  coordinates and would restore pixels into the wrong places.

---

## Clipboard, drag and drop

- `⌘V` pastes as **movable floating content**, centred (or at the selection's
  origin). `⇧⌘V` **pastes and fits** — growing the canvas rather than silently
  cropping a screenshot bigger than it.
- Dropping an image from Finder, a browser or any app lands it at the pointer,
  growing the canvas if needed and clamping so it can never land entirely
  off-canvas.
- `⌥⌘C` copies the whole image; **Share…** opens the system share sheet.
- Pasteboard reads prefer the raw file or PNG data over `NSImage`, whose
  representation can arrive scaled or DPI-adjusted.

---

## Signature

`⌃⌘S` (`Tools ▸ Signature…`) opens the signing sheet. Sign in the box, or
**Import Image…** a photo or scan of a signature on paper. Saved signatures
appear as chips at the top of the sheet; clicking one inserts it, and
right-clicking offers Delete.

- **The ink is keyed to transparent**, so a signature lands on artwork without a
  white rectangle behind it. Alpha comes from how dark each pixel is relative to
  its *own local* paper level, estimated per tile and interpolated, which is what
  survives the lighting gradient across a phone photo. Stroke ends stay soft
  rather than stair-stepping.
- **It arrives floating**, at most 40% of the canvas and inset from the
  lower-right. A signature never grows the canvas — that is the difference
  between signing something and pasting something.
- **The ink takes Colour 1**, so a blue-ink signature is one swatch away. A light
  Colour 1 falls back to black rather than saving invisible ink.
- A photo that is nearly blank, or nearly all dark, is **reported rather than
  keyed** — "no signature found" beats handing back a rectangle of noise.
- Signatures live as one PNG each in Application Support and are shared by every
  document. They are not document state: you capture one once and stamp it on
  everything you sign.

No camera capture yet — that needs a camera entitlement. AirDrop a photo from a
phone and use Import Image…

---

## Files and export

**Documents** save as `.itspaint`: a package holding a lossless `canvas.png` plus
`document.json` (size, both colours, palette). Autosave-in-place applies to these
only — an imported PNG is your file and is never re-encoded in the background.

**Export** (`⇧⌘E`) offers format and scale in the save panel:

| Format | Notes |
|---|---|
| PNG, TIFF, GIF | lossless, alpha preserved |
| JPEG, BMP | no alpha — flattened onto Colour 2 first, rather than turning transparency black |
| HEIC, AVIF | modern, lossy, quality slider |
| PDF | the bitmap wrapped in a single-page PDF |
| ICO | fitted and centred into the nearest legal icon square (16–256); a non-square ICO is not a large icon, it is an invalid file |

The format list is filtered by what this machine's ImageIO can **actually
encode**, so it never offers something that will fail at the last step. No WebP:
macOS reads it but ships no encoder.

---

## Menus worth knowing

- **Tools** — every tool by name with its key, a Shape submenu with all fifteen
  shapes, plus Signature…, Swap Colours and Larger / Smaller Brush.
- **View** — zoom commands, pixel grid, Move Toolbar, Colours…
- **Edit** — the usual, plus Invert Selection, Crop to Selection,
  Trim Borders, Swap Colours.
- **Right-click on the canvas** — cut, copy, paste, delete, select all, deselect,
  crop, trim, copy whole image, export, swap colours, image size. A right-click
  that *drags* paints Colour 2 instead; `⌃`-click always opens the menu.

Every menu item routes through the responder chain, so it is enabled only when
something can actually perform it.
