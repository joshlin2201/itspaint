# Design language

The surface grammar of the app: what the chrome is made of, what each rule buys,
and where the exceptions are. Values here are the real ones in
[`App/UI/DesignTokens.swift`](../App/UI/DesignTokens.swift) — if you change one,
change it here too.

For *why* the app is shaped this way at all, see [PHILOSOPHY](PHILOSOPHY.md).
This document is about how it looks and feels once that is settled.

> **History.** Until 2026-07-28 this app used a floating glass cluster at the
> bottom of the window with a trailing options pill ("Direction C,
> canvas-first"). It was elegant, but it hid the palette behind a popover. The
> rail replaced it because *visible beats beautiful* when the product claim is
> "learnable in five minutes". The old direction's tokens, elevation model and
> legibility rules survived intact; its anatomy did not.

---

## Anatomy

```
┌──────────────────────────────────────────────────────────────┐
│ ●●●  [ Sketch.png ]                        [ ↶ ↷ ⧉ ]         │  transparent titlebar
│ ┌──────┐ ┌───────────────────┐                               │
│ │ rail │ │ tool options      │  ← expands from the button    │
│ │      │ └───────────────────┘    you pressed                │
│ │ ▣ ▣  │                                                     │
│ │ ▣ ▣  │            artwork, inset — never underneath        │
│ │ ──   │            the rail                                 │
│ │ ▣ ▣  │                                                     │
│ │ ──   │                                                     │
│ │ 1 2 ⇄│  ← the two loaded colours, overlapped               │
│ │ ▦▦   │  ← the palette, two swatches across                 │
│ │ ──   │                                                     │
│ │  ⊟   │  ← move the toolbar (⌥⌘T)                           │
│ └──────┘                        [ ⊕ 412, 88 │ 1000×640 │ 90% ]│  status
└──────────────────────────────────────────────────────────────┘
```

**One permanent surface, one cell thick.** The rail holds every tool, both
colours and the palette. It lives on the left by default and moves to the bottom
(⌥⌘T, remembered across launches). Both orientations render from the same
components, transposed for the available axis: the tools are a single file of
buttons either way, the swap button sits beside the colour pair at the bottom
and beneath it at the side, and the palette is two swatches across the rail in
both.

**A side rail is thin or it is a panel.** Width taken from the artwork is taken
permanently, on the axis a picture usually needs most — so the side rail is the
bottom bar stood on its end, at exactly the same thickness, rather than a grid
of cells that grows to the height of the window.

**The options panel belongs to a button.** It expands beside the selected cell —
which carries a chevron toward it — and dismisses the moment you touch the
canvas. It is a step in *choosing how to draw*, not an inspector that sits over
your artwork while you work.

**The artwork is inset, not underlapped.** A permanent rail covering the left of
the picture would mean dragging the canvas around to see what is behind it. Only
the options panel floats.

**The status strip floats bottom-right**: pointer position, canvas size, zoom
with steppers. It is pure read-out, so it gets the lightest surface of anything.

---

## Tokens

| | |
|---|---|
| **Spacing** | 2 hair · 5 tight · 8 base · 10 snug · 14 comfortable · 20 safe inset |
| **Controls** | 16 swatch · 18 colour swap · 24 segment · 24 colour well · 26 pill action · 26 title chip · 34 tool cell |
| **Radii** | 16 rail · 12 panel · 11 cell · 10 well · 8 chip · 7 segment track · 5 segment inner · 4 swatch |
| **Rail** | run = 1 × 34 = **34pt**; cross = **34.08pt** (the overlapped colour pair, the widest thing in it); **thickness ≈48pt on either edge** |
| **Elevation** | 0.5pt hairline · 18pt shadow radius · 7pt y-offset |
| **Motion** | 0.22s smooth (panel resize) · 0.12s ease-out (micro) · 0.07s (press) |

**Everything in the rail is built to `Rail.cross`.** The palette
(2 × 16 + 2 = 34), the separators and the colour pair share one edge with the
single-cell tool run, so the column has one edge rather than five.

**One thickness serves both edges** — not two constants that happen to agree.
The side rail and the bottom bar carry the same controls across their short
axis, so a single number is the only version of this that cannot drift apart
when one of them gains a row. `ToolbarGeometryTests` fails the build if it
does.

**Radii are concentric by construction.** A cell inside the rail is
`16 − 5 = 11`, so the gap around each corner stays visually constant instead of
the inner shape looking pinched.

---

## Surfaces and elevation

**Exactly two levels.** The rail, the options panel, the title chip and the
status strip sit at the same height; popovers sit above them. Nothing else
lifts.

The shared material (`ChromeSurface`) is a blur with a **fixed tint floor** over
it, plus a 0.5pt luminous hairline. The tint floor is the important part: label
contrast stays constant whether the chrome sits over white artwork, black
artwork, or the boundary between them — the case that breaks a pure vibrancy
panel. The blur contributes only a hint of what is underneath.

Under **Reduce Transparency** the material becomes fully opaque rather than a
slightly-less-tinted version of itself. The fallback is a real surface, not a
weaker illusion of one.

---

## Colour

**Colour is never invented.** Chrome values resolve to system semantic colours or
to the material's own label colours, so the app tracks appearance, accent,
Increase Contrast and Reduce Transparency for free.

The **accent means exactly one thing**: this is the armed tool, or the selected
option. Nothing else in the chrome uses it. That is why the swatch grid marks the
loaded colours with a ring in the swatch's *own* contrast colour rather than an
accent border — an accent ring there would collide with "selected tool", and an
outer ring would shift every neighbour by a pixel as selection moved.

The **palette is fixed** at 28 swatches in two rows of fourteen. They are muscle
memory and must not move, so custom colours live in the popover instead of
displacing them — and a rail narrower than fourteen columns truncates by
*column*, never in reading order, so every swatch keeps its place and its muted
partner. Truncating in reading order would show fourteen dark colours and no
white at all.

**The grid is always two swatches across the rail.** Not "as many rows as it
needs": the rail's declared thickness is a constant the canvas inset is computed
from before any layout pass runs, so a palette that grows a third row makes that
constant describe a bar smaller than the one on screen and the artwork slides
under it. That is exactly what used to happen the first time anyone picked a
custom colour.

The two loaded colours are **overlapped, front over back**, the way the original
arranged them: it says "one is in front of the other" without a word of
explanation. Click either to open the system picker; click a swatch for Colour 1,
right-click it for Colour 2 — the same button mapping the canvas itself uses, so
the palette teaches the canvas.

---

## Type

Mapped to system sizes so the app honours accessibility text settings. Nothing
informational goes below 10.5pt — the platform's equivalent of a 12px floor.
Numbers that update live (position, size, zoom, slider read-outs) are
`monospacedDigit()` so they do not jitter.

Labels in the chrome never wrap. A control whose label breaks across two lines
("Str / oke") is a sizing bug, not a layout to accommodate: the panel is
`fixedSize` and every label carries `lineLimit(1)`.

---

## Iconography

**SF Symbols only**, never an emoji, never a bespoke glyph where the system ships
the right one. Two deliberate exceptions:

- **The paint bucket.** SF Symbols has no bucket. The droplet the system offers
  reads as the eyedropper's cousin — the one tool it must not be confused with —
  so the rail and the cursor draw a tipped pail with a drip (`DrawnGlyph.bucket`).
- **Cursors.** Each tool's pointer is its own glyph over a white halo,
  hot-spotted where the tool actually marks: the pencil's tip, the bucket's lip,
  the centre for click tools. Once the footprint ring is big enough to aim with
  (≥12 screen points) the cursor disappears entirely, because at that size it
  covers the very pixels it is pointing at.

Symbols are chosen conservatively: the app targets macOS 14, so anything from SF
Symbols 6 renders blank there. Two were swapped for SF 1 equivalents for exactly
this reason.

---

## Legibility over unknown artwork

Anything drawn *on* the canvas has to survive white, black, or a hard edge
between them. Three treatments, all two-tone:

- **Marching ants** — a white base line under a dashed black one, animated at
  display cadence by a fraction of a dash. A coarse step reads as a strobe; this
  reads as motion. The timer runs only while there is a selection, and
  invalidates only the selection's own rect.
- **The footprint ring** — light casing under a dark ring.
- **Cursors** — glyph over a white halo.

The lasso's ants follow the **traced outline**, not its bounding box. Drawing the
box would tell the user the selection is a rectangle, which is exactly the lie
the freeform tool exists to avoid.

Instant Alpha follows the same rule at pixel precision: its ants trace every
exposed edge in the mask, including holes. Cleared pixels reveal a semantic
system-colour checkerboard beneath the image, so transparency remains legible
in both appearances and under accessibility contrast settings.

---

## Motion

Motion explains a state change; it never decorates. Three durations and no more:
the panel resizing because its content genuinely changed (0.22s, a hair of
bounce), micro-transitions for hover and selection (0.12s), and press feedback
(0.07s — short enough to read as contact rather than animation).

The chrome dims to 55% while a drag is in flight, so the marching ants are never
competing with it for attention.

---

## Zoom, and why fit is exempt from the ramp

⌘+ / ⌘− step a **discrete ramp** (0.25 · 0.5 · 1 · 2 · 4 · 8 · 16). Coarse on
purpose: an arbitrary 137% makes a paint app's pixels shimmer.

**Fit and gestures are exempt.** Pinch and ⌘-scroll scale *continuously*,
anchored on the canvas pixel under the pointer — jumping 100% → 200% mid-pinch
feels broken. And a canvas that wants 92% snapping down to 50% would waste half
the window. At fit you are looking at the whole picture; at a ramp step you are
editing pixels.

Two failure modes worth knowing, because both shipped once:

- Anchoring must be measured **before** the zoom changes. Converting the pointer
  through the view *after* mixes two geometries and throws the canvas into a
  corner.
- The anchor is only chased on axes where the artwork is bigger than the
  viewport. On the others the clip view centres the canvas, and forcing an origin
  there is what pinned it to the corner.

---

## Accessibility

- Every tool is reachable by a single keypress; every cell carries an
  accessibility label and the `.isSelected` trait.
- Selection is never carried by fill alone: under **Increase Contrast** every
  cell gains an outline.
- **Reduce Transparency** swaps the material for an opaque surface.
- Tooltips name the tool *and* its shortcut, so the chrome teaches its own
  keyboard.

---

## Small windows

The rail scrolls rather than overflowing, and the options panel is clamped to the
window rather than running off it. A toolbar that runs off the bottom of a short
window is worse than one that scrolls; a panel you cannot reach is not a panel.

---

## The weakness, stated plainly

The side rail costs ~86pt of window; the bottom rail costs only ~50pt. On a
small display that is real estate the artwork would otherwise have. The trade is deliberate — see
[PHILOSOPHY](PHILOSOPHY.md), rule 1 — and it is mitigated rather than denied: the
rail moves to the bottom for wide-and-short work, and it scrolls when the window
is genuinely too small.

---

## Evidence

Screenshots in this repo are of the **real running app**, captured from the real
window, and the sample artwork in them is generated by the engine itself
(`swift run paint-demo`).

The README hero is generated too, rather than made in a design tool:

```bash
swift run paint-demo --banner docs/images/banner.png
```

It writes four files from one invocation — a dark and light banner, and a dark and
light icon — and the README picks between them with `<picture>` +
`prefers-color-scheme`.

**The icon needs a light twin for a non-obvious reason.** The app icon is a *white*
squircle. On a dark page the white is the edge; on GitHub's light theme it is white
on white, the container disappears, and what is left is a blue stroke, a yellow band
and a red arrow floating loose in the text. Found by forcing
`prefers-color-scheme: light` and looking at it — nothing in the markup says so. The
light variant sits on a faint plate with a hairline, built from `fill` plus four
`fillEllipse` corners because PaintKit has no rounded-rect fill and does not need
one for a paint app. A single near-black PNG
is a full-width black slab above a white page for everyone in the light theme.

`ReadmeBanner` composes it out of PaintKit — the light field is written per
pixel, the wordmark is `TextRenderer`. So the
page header is reproducible from a clean checkout, it moves when the icon moves,
and it is itself a demonstration that the engine composes images. A hand-edited
PNG sitting in `docs/images` would be none of those.

**Name the weight, and know which names lie.** The wordmark is
`.AppleSystemUIFontBlack` (`.SFNS-Black`, wght 1000), not Bold — 188pt in Bold is
the weight a UI button uses and reads generic at display size. The dot-prefixed
names are the only route to the system font and every wrong one fails silently:
`"SF Pro Display"` and `"SFProDisplay-Bold"` return **Helvetica**, `".SFNS-Black"`
returns **Times New Roman**, and `".AppleSystemUIFontSemibold"` returns Helvetica
because the ladder has holes. Verified by comparing `CTFontCopyPostScriptName`
against the request, which is the only way to notice.

**A ramp nobody can see still bands.** The first backdrop went `11151D` to
`070910` — a 13-level delta that reads as nothing, and produced 33 visible
horizontal stripes, because red, green and blue each cross their rounding
boundary on a different row. It is now a radial falloff written per pixel with a
±0.5-level `(x ^ y) & 1` dither, which leaves no boundary coarse enough to read
as a stripe.

**A stacked-ellipse shadow is a dark ellipse.** Six of them under the icon, over
a field the light had already lifted, read as a smudge behind the icon rather
than as shadow. Removed — the light does the grounding, and one fewer object is
the better composition.

**It carries the lockup and nothing else, and that is the point.** The first
version was 2400×1000 with the tagline, a metadata line and a screenshot of the
app inside it. GitHub renders a README at about 390 points wide on a phone, and
everything inside an image scales with the image — so the wordmark arrived around
ten points tall and "Free · MIT · 2.9 MB · no account, no telemetry" was
unreadable. **Text baked into a wide graphic cannot reflow.** Tagline, badges and
screenshots are markdown and separate images now, each getting the full container
width at any size.

The first version of it stacked 26 translucent ellipses to make a glow and
compounded them into a near-opaque white disc that swallowed the wordmark
entirely. **Render it and look at it.** Alpha that reads as subtle in the source
is not subtle after twenty-six passes.

Offscreen render tests
(`AppTests/CanvasRenderingTests.swift`) assert actual drawn pixels for floating
content, handles, marquee and zoom — they cannot be fooled by a stale process,
which a screenshot can. A passing suite is necessary and never sufficient for a
visual claim: look at the window.
