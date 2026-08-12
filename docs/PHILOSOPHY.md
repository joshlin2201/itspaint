# Design philosophy

Why this app is shaped the way it is. Every rule here has cost something to
follow; where it has, that cost is stated rather than hidden.

---

## The premise

The app this descends from was learnable in five minutes by people who had never
read a manual. That was not an accident of 1995 simplicity — it was three
properties, and they are reproducible:

1. **Everything was visible.** Tools, both loaded colours, the whole palette, all
   on screen at once. Nothing to discover.
2. **It cost nothing to open.** No splash, no project, no template picker. You
   opened it, drew, and closed it.
3. **The mouse did the obvious thing.** Left drew with one colour, right drew
   with the other. No modes to remember you were in.

Everything below follows from wanting those three back, on a machine where
people mostly want to draw on a screenshot rather than paint a picture.

---

## The five rules

### 1. Nothing that matters is hidden

Twelve tools, both loaded colours and a palette are on screen at all times. A
popover you have to know about is a worse control than a swatch you can already
see.

**The cost, stated plainly:** the rail takes 48pt of window on whichever edge it
is on. That is the price of never making someone hunt for a tool, and it is
worth it — an earlier revision of this app put the palette behind a popover and
it was measurably harder to use.

**Where the rule bends, and why.** The bottom bar has the window's width and
carries all 28 swatches; the side rail has only its own 48pt of width and
carries the leading 14. The alternative was a rail three cells thick and the
full height of the window — which is a panel, and a panel that permanently eats
width is a worse trade than fourteen swatches one click away. Both orientations
still show two swatches across, and both keep the classic column pairing, so a
colour is always where the eye expects it.

### 2. The rail lists jobs; a tool's options list its variations

Fifteen shapes live behind **one** Shape button. Four selection modes live
behind **one** Select button. Five rail buttons that differ only in the outline
they emit is five times the scanning cost for one decision.

This is enforced, not aspirational: `toolSetStaysSmall` fails the build past
fourteen rail buttons, and past five in any one run. When a feature seems to want
a new button, the first question is which existing tool owns it.

### 3. Raw pixel control is a promise, not a feature

Integer coordinates end to end. `PixelPoint` and `PixelRect` are `Int`-based, and
nothing in the drawing path converts to floating point and back. The pixel you
clicked is the pixel that changed — at any zoom, with any tool.

Consequences that fall out of this and are not negotiable:

- Nearest-neighbour above 100%. A paint app that blurs its own pixels at 800% is
  lying about what you drew.
- The live footprint ring, and the outlined pixel under the pointer past 4×.
- Bresenham rather than a Core Graphics stroke for the pencil, so a 1px line has
  no half-covered antialiased neighbours.

### 4. The app never lies about what it did

The clearest example is **Pixelate**: the tool averages each block to a single
value and calls the result a mosaic. It helps de-emphasise part of an image; it
does not promise secure redaction. Secrets need an opaque cover in a flattened
export.

The same rule elsewhere:

- **Text rasterises on commit.** A document format carrying live text that the
  PNG export silently flattens is a lie about what you saved.
- **Autosave-in-place is scoped to `.itspaint` documents only.** An imported PNG
  is *your* file; re-encoding it in the background is data loss waiting to
  happen.
- **A dead control is a defect.** Settings… stays disabled until there is a
  setting worth showing. The Tools menu was shipped once with eleven items wired
  to nothing; the test that now proves every menu item is answerable exists
  because of it.

### 5. Escape gets you out; nothing traps you

One key abandons whatever is in flight — a half-drawn curve, an open text box, a
live stroke, a floating paste, a selection, an open options panel. A pending
shape that has not been committed leaves *no* undo step, so abandoning it leaves
no trace at all.

---

## What this app is not

Saying no is most of the design. These are settled, not open questions:

| Not this | Because |
|---|---|
| A layer stack | Layers are the feature that turns "draw on a screenshot" into "learn a compositing model". Floating selections cover the actual need: paste, move, place. |
| A vector editor | Shapes rasterise on release. Keeping them editable means a scene graph, a selection model for objects, and a document format that no other tool can read. |
| Non-destructive filters | Same argument. The one adjustment that exists (invert) is an undoable edit like everything else. |
| An airbrush texture library, brush engines, blend modes | Depth for painters, weight for everyone else. The tool set is deliberately shallow and wide. |
| Cloud, accounts, telemetry, update nags | It is a local editor. It has no network code at all. |
| Electron, or any third-party dependency | `PaintKit` has zero dependencies; the app has zero beyond Apple's frameworks. The small binary is a consequence of that, not an optimisation target. |

---

## Trades already made, and what would reopen them

- **No Metal.** Core Graphics is comfortably fast at these canvas sizes and the
  rasterisers are our own scanline code. The renderer boundary exists so a GPU
  compositor could slot in. *Reopens if:* a profile shows frame drops at sizes
  people actually use.
- **Whole-buffer copy per gesture** to capture the undo baseline.
  Sub-millisecond at typical sizes. *Reopens if:* a 4000×4000 canvas stutters at
  stroke start — the fix is tiled incremental capture.
- **The lasso mask rebuilds from the whole path** on every pointer move.
  *Reopens if:* a very long trace stutters; the fix is incremental extension.
- ~~**Ad-hoc signing, not notarised.**~~ **Closed in 0.11.0** — the reopen
  condition below fired and this entry outlived it. Releases are signed with a
  Developer ID and notarised in CI, and the ticket is stapled to both the disk
  image and the app inside it. *Was: downloads require a one-time Gatekeeper
  override. Reopens if: the project adds Developer ID signing and notarisation
  through CI.*

---

## How to argue with this document

Bring the case, not the preference. A change to these rules should say which
rule, what it costs to keep, and what it buys to break. The plan of record in
[`PLAN.md`](PLAN.md) keeps the original design *and* its critique for exactly
that reason: the reasoning is the useful part, and a decision whose reasoning is
lost gets re-litigated every six months.
