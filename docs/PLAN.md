# ItsPaint — plan of record

A modern macOS 26 paint app: the familiarity of the classic tool, rebuilt as a
first-class Tahoe citizen, aimed at what people actually do with a paint app
now — quick drawings and marking up screenshots.

This is a **double plan**: a first pass, an honest critique of it, and the
revised plan that is actually being built. The critique is kept because the
reasoning is the useful part.

---

## Verified environment

Checked on this machine rather than assumed, because the whole plan depends on
whether the Tahoe APIs are actually available:

| | |
|---|---|
| macOS | 26.6 (Darwin 25.6.0) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3, language mode 6, strict concurrency |
| SDK | macOS 26.5 |

Liquid Glass APIs were confirmed by **compiling against the SDK**, not by
reading release notes: `GlassEffectContainer`,
`.glassEffect(.regular.interactive(), in:)`, `.glassEffectID(_:in:)`,
`.clear.tint()`, `ConcentricRectangle(corners: .concentric(minimum:))`,
`.containerShape`, `.buttonStyle(.glassProminent)` all typecheck clean.

---

## Plan A (first pass)

- Single-window document app, feature-parity with the classic toolset.
- SwiftUI `DocumentGroup`; canvas as an `NSViewRepresentable` over Core Graphics.
- All sixteen classic tools, each with its own rail button.
- Undo by snapshotting the whole bitmap per operation.
- Full-canvas redraw on every change.
- Liquid Glass floating tool palette over the canvas.
- XCTest for the model. Ship.

## Critique of Plan A

1. **`DocumentGroup` is too thin.** A custom package format, real undo
   integration, autosave-in-place and control over the opening window are all
   awkward or unreachable there. Discovering that after the tools are built means
   rewriting the document layer underneath them.
2. **Whole-bitmap undo does not scale.** 64 MB per step on a 4000×4000 canvas
   exhausts memory in a few dozen strokes and stutters on every one.
3. **Full-canvas redraw is wasteful** and drops frames on large canvases.
4. **Retina correctness is unstated.** A paint app promises pixel exactness;
   backing scale, an integer pixel grid and nearest-neighbour magnification are
   requirements, not details.
5. **Sixteen tools is the wrong product.** Five separate shape buttons is five
   times the scanning cost for one decision, and airbrush / polygon / magnifier
   are tools almost nobody reaches for now. Parity with 1995 is not the goal;
   familiarity is.
6. **Nothing addresses what people actually do** with a paint app in 2026: paste
   a screenshot, point at something, hide something, crop, send.
7. **Liquid Glass misuse risk.** Glass on the canvas, stacked glass, or glass
   over unpredictable content are all failure modes, and Reduce Transparency
   legibility is a real gate.
8. **"XCTest for the model" is not a strategy.** Rendering correctness needs
   assertions that name the pixel that moved.
9. **Trademark and sandbox entitlements left late** are submission blockers.

## Plan B — what is being built

**Architecture.** `PaintKit`, a pure Swift package with no UI and no third-party
dependencies, holding pixels, tools, undo, selection and codecs. A thin AppKit +
SwiftUI shell consumes it. This is what makes the entire tool matrix testable
without launching an app.

**Document.** `NSDocument`, not `DocumentGroup`. Custom `.itspaint` package
(lossless PNG + JSON metadata, so the artwork is recoverable with any image tool
even if this app disappears) plus flatten-on-export via ImageIO to
PNG/JPEG/TIFF/BMP/GIF/HEIC. **Autosave-in-place is scoped to the native package
only** — an imported PNG is the user's original file and must never be
re-encoded in the background.

**Canvas.** RGBA8 premultiplied sRGB, chosen so the same byte buffer serves both
our own scanline rasterisers and Core Graphics with no conversion. Integer
`PixelPoint`/`PixelRect` throughout, so "the pixel I clicked is the pixel that
changed" actually holds. Nearest-neighbour when magnified.

**Undo.** Rect-scoped patches bounded by **bytes, not step count** — fifty dots
and fifty full-canvas fills differ by four orders of magnitude, so a count limit
is the wrong unit. Bridged to `NSUndoManager` by registering the inverse from
inside each replay, so the engine's history and the Edit menu stay in lockstep
instead of drifting into two stacks.

**Tools — twelve rail buttons at the time, and everything else inside them.**

| Group | Tools |
|---|---|
| Draw | Pencil, Brush, **Airbrush**, **Highlighter**, Eraser |
| Insert | **Shape** (15 kinds), Text, **Step badge**, Fill, Eyedropper |
| Select | **Select** (rectangle · ellipse · lasso · Instant Alpha), **Pixelate** |

The governing rule is simple: *the rail lists jobs; a tool's own options list
its variations.* Fifteen shapes — line, curve, arrow, rectangle,
rounded rectangle, ellipse, triangle, right triangle, diamond, pentagon,
hexagon, two stars, speech bubble, polygon — live inside the Shape tool, and
most of them come from one parametric point generator rather than a rasteriser
each. The magnifier stays gone: ⌘+/⌘− and the always-visible zoom control
already cover it.

**Chrome.** A glass rail on the left (⌥⌘T moves it to the bottom) holding every
tool, both loaded colours and all twenty-eight swatches, plus the active tool's
options expanded from the button that owns them. Nothing that matters is behind
a popover — that is what made the original learnable — and the rail genuinely
takes its space rather than covering the artwork. See `DESIGN.md`.

**Testing.** Deterministic pixel assertions rather than image snapshots: they
run in milliseconds, need no Git LFS or third-party package, and name the exact
pixel that moved instead of showing two similar-looking PNGs. Currently **372
tests** (263 engine, 109 app), including a byte-identical open-then-write guard.
The six throughput guards apply their time budgets only in release builds,
because debug timings measure the compiler rather than the algorithm.

---

## Status

> The forward-looking version of this section now lives in
> [ROADMAP.md](ROADMAP.md); this one is kept as the record of what the original
> plan committed to and what actually landed.

Done: engine, all twelve tools at the time and fifteen shapes, selection/clipboard/crop,
Pixelate, undo, document + codecs, the rail-and-options UI, export with
format and scale, 293 tests at the time, app builds and runs.

Next, in order:
1. Icon (Icon Composer), accessibility pass, Reduce Transparency verification.
2. Submission: signing, Privacy Manifest is written, screenshots, App Store
   Connect.

Cleared since the last revision of this plan: the text tool (drag a box, type,
⌘↩ places it — rasterised on commit through `TextRenderer`), the lasso as a
true per-pixel mask rather than its bounding box, and the canvas size / scale
dialogs wired to `ImageTransform`.

## Known limits, stated plainly

- **Freehand strokes take one copy-on-write buffer copy per gesture** to capture
  the undo baseline. Sub-millisecond at typical canvas sizes; tiled incremental
  capture is the upgrade path if a profile ever demands it.
- **No Metal.** Core Graphics is comfortably fast at these sizes. The renderer
  boundary exists so a GPU compositor can slot in, but adding one now would be
  speculative.
- **Text is rasterised on commit**, not kept editable. That is the honest model
  for a paint app; re-editing means undo and retype.
- **No WebP export.** ImageIO on this OS reads it but ships no encoder, and a
  third-party one is a dependency this app does not have. AVIF covers the same
  need and is written by the system.
- **The airbrush and the badge counter are per-document**, not per-app: a new
  window starts at badge 1.
- **The lasso mask is rebuilt from the whole traced path on every pointer
  move.** Fine for the paths people actually trace; incremental extension is the
  upgrade path if a very long trace ever stutters.
- **Name screen completed for the public beta.** On 2026-07-29, the USPTO
  combined-mark search returned no exact `ItsPaint` record, and the documented
  expanded `its` + `paint` search returned no confusingly similar software
  mark. A separate web and App Store screen found no competing software product
  using the name. This is a practical knock-out search, not a legal opinion;
  counsel-led clearance remains a gate for a paid or App Store launch.

## Distribution dependencies

The App Store Connect record, code-signing identities, provisioning, pricing,
and submission require access to the Apple Developer account. The repository
already carries the entitlements, Privacy Manifest, document types, and
exported UTI.
