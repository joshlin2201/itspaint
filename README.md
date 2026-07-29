<div align="center">

# ItsPaint

### Draw on your screenshots. Sketch a thing. Close the window.

**A native Mac paint app that keeps every tool in sight, stays out of your way,
and has zero third-party dependencies.**

[![CI](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml/badge.svg)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/joshlin2201/itspaint?include_prereleases&sort=semver&label=beta)](https://github.com/joshlin2201/itspaint/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://github.com/joshlin2201/itspaint/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

![The ItsPaint editor with a marked-up sketch open](docs/images/editor-window.png)

<sub>Everything in that canvas — dashed box, numbered badges, speech bubble, star,
airbrush spatter, bent curve — was drawn by the engine itself in
<a href="Packages/PaintKit/Sources/PaintDemo">PaintDemo</a>, which builds the sample
by driving the same gesture API the canvas does.
<code>swift run --package-path Packages/PaintKit paint-demo out.png</code>.</sub>

</div>

---

<div align="center">

| **12** | **15** | **up to 9** | **293** |
|:--:|:--:|:--:|:--:|
| tools | shapes | export formats | tests |

</div>

---

## 60 seconds

```bash
# Download the beta .dmg from Releases and drag it to Applications.
# Control-click ItsPaint, choose Open, then confirm Open (notarisation note below).

# Or build it, which takes one command:
git clone https://github.com/joshlin2201/itspaint.git && cd itspaint
open ItsPaint.xcodeproj    # ⌘R
```

Then: paste a screenshot with **⌘V**, hit **N** and click three times to drop
numbered badges, **R** to mosaic a distracting detail, **⌘⇧E** to export.
Close the window. That is the whole product.

---

## The argument

Preview can mark up an image, and a full editor can do almost anything. ItsPaint
sits between them: open an image, draw directly on it, and finish before the
editor becomes a project. The app this descends from was learnable in five
minutes because it hid nothing — every tool, both colours and the whole palette
on screen at once, and the mouse buttons did the obvious thing.

That is worth rebuilding properly. So:

**Nothing is hidden.** Twelve tools, both loaded colours and all 28 swatches,
visible always, in a rail that lives left or bottom (⌥⌘T). A tool's variations
expand from the button you pressed — fifteen shapes behind one Shape button — so
the rail stays a list you read at a glance. *A test fails the build if it grows
past fourteen buttons.*

**It respects the pixel.** Integer coordinates end to end: the pixel you clicked
is the pixel that changed. Nearest-neighbour above 100%. A live footprint ring
shows exactly which pixels the next stroke will cover, and past 4× the single
pixel under the pointer gets outlined.

**It gets out of the way.** No account, no telemetry, no cloud, no Electron, no
update nag, no splash screen. Sandboxed, and it touches only the files you open.

---

## What's in it

| | |
|---|---|
| **Draw** | Pencil · Brush · **Airbrush** · Highlighter · Eraser |
| **Insert** | **Shape** (15 kinds) · Text · **Step badges** · Fill · Eyedropper |
| **Select** | Select — rectangle · ellipse · lasso · **Instant Alpha** · **Pixelate** mosaic |

**Fifteen shapes, one button.** Line, curve *(drag it, then bend it)*, arrow,
rectangle, rounded rectangle, ellipse, triangle, right triangle, diamond,
pentagon, hexagon, five- and six-point star, speech bubble, click-corner
polygon — each solid, **dashed** or dotted, outlined, filled, or both.

**Built for markup, not nostalgia.** A highlighter that refuses to darken where
a stroke crosses itself. Arrows. Crop and trim-borders. Numbered step badges for
walkthroughs. Clipboard paste that lands as *movable* floating content. And a
block-size-controlled mosaic for de-emphasising part of a screenshot.

**Pixelate is a visual effect, not secure redaction.** Do not use it to hide
passwords, tokens or personal data. Cover secrets with an opaque filled shape
before exporting a flattened image.

**Up to nine export formats** — PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF,
ICO — with the exact list matched to the encoders built into your version of
macOS. The save panel includes format and scale pickers, and ICO is fitted to a
legal icon square instead of failing. Documents save as `.itspaint`: a lossless
PNG plus JSON, so your artwork opens in anything even if this app disappears.

### Keyboard

| | | | |
|---|---|---|---|
| `P` pencil | `B` brush | `A` airbrush | `H` highlighter |
| `E` eraser | `U` shape | `T` text | `N` step badge |
| `K` fill | `I` eyedropper | `M` select | `R` pixelate |
| `X` swap colours | `[` `]` size | `⌥1`–`⌥9` shape | `Space` pan |

Pinch or ⌘-scroll zooms continuously **around the pointer**; ⌘+/⌘− snap to the
ramp. Hold `⌥` to sample a colour with any tool. Right-drag paints your second
colour; right-*click* opens the canvas menu. **Escape gets you out of
everything** — half-drawn shape, open text box, selection, floating paste.

---

## Under the hood

```
Packages/PaintKit/      the engine — no UI, no dependencies, 211 tests
  Pixels/               RGBA8, geometry, brushes, rasterisers
  Colour/ Tools/        colour model, palette, tool set, selection, engine
  Undo/ Codec/          rect-scoped patches; Core Graphics + ImageIO bridge
App/                    the shell — AppKit lifecycle, SwiftUI chrome, 82 tests
  Canvas/ Document/     NSView canvas, zoom, cursors; NSDocument + .itspaint
  Model/ UI/            engine ⇄ SwiftUI bridge; rail, options, palette
```

`PaintKit` is UI-free and dependency-free on purpose: it is why the entire tool
matrix is testable in milliseconds without launching an app, and why a UI
redesign is a view-layer change rather than a rewrite.

Decisions that each cost a bug to learn:

- **Every mutating call returns its dirty rect.** Redraw *and* undo capture scope
  to it. It is the single reason a big canvas stays smooth.
- **Undo is bounded by bytes, not steps** — fifty dots and fifty full-canvas
  fills differ by four orders of magnitude — and bridged to `NSUndoManager` by
  registering the inverse from inside each replay, so the two histories cannot
  drift apart.
- **RGBA8 premultiplied sRGB**, chosen so the same buffer serves both our own
  scanline rasterisers and Core Graphics with no conversion.
- **The canvas repaints only what changed.** SwiftUI re-runs a representable on
  every observed change — including the pointer moving — so the view tracks the
  revision it has already painted instead of redrawing everything per mouse-move.
- **Text rasterises on commit**, because a document format carrying live text
  that the PNG export silently flattens is a lie.

### Tests

```bash
swift test --package-path Packages/PaintKit             # engine
swift test -c release --package-path Packages/PaintKit  # + throughput guards
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
           -destination 'platform=macOS' test           # app integration (82)
```

They assert **pixels, not screenshots**: `#expect(canvas.pixel(at: p) == …)`
names the pixel that moved, where an image diff hands you two similar-looking
PNGs and wishes you luck. The six throughput guards assert only in release
builds, because unoptimised timings measure the compiler, not the algorithm.

---

## Install

**Beta `.dmg`** → [Releases](https://github.com/joshlin2201/itspaint/releases).
Drag to Applications. The current beta is **ad-hoc signed, not notarised**, so
Control-click the app → **Open** → **Open** on first launch. If macOS still
blocks it, clear the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/ItsPaint.app
```

Every download is listed with a SHA-256 in `checksums.txt`. Prefer not to trust
a binary? Building takes one command,
and the CI that produces the release is [right here](.github/workflows/release.yml).

**Requires macOS 14 (Sonoma) or later.** Building needs Xcode 16+.

---

## Status: beta, and honest about it

It builds, it runs, the suite is green, and it is what I use for day-to-day
markup. It has not been near the App Store, and released binaries are not
notarised. Known limits, stated plainly:

- **No WebP export** — macOS reads WebP but ships no encoder, and a third-party
  one is a dependency this app refuses to take. AVIF covers the same need.
- **Text is pixels once committed.** Re-editing means undo and retype.
- **The lasso mask rebuilds from the whole path** on each pointer move. Fine for
  paths people actually trace; incremental extension is the upgrade if a very
  long one ever stutters.
- **Next up:** a loupe, adjust-colour sliders, a fuller image dimensions
  dialog, separate border/fill wells.

[`CHANGELOG.md`](CHANGELOG.md) has what changed, and
**[`docs/`](docs/README.md)** has the rest:
[philosophy](docs/PHILOSOPHY.md) · [anatomy](docs/ARCHITECTURE.md) ·
[design language](docs/DESIGN.md) · [feature reference](docs/FEATURES.md) ·
[testing protocol](docs/TESTING.md) · [roadmap](docs/ROADMAP.md) — plus the
original [plan of record](docs/PLAN.md), kept with its own critique because the
reasoning is the useful part.

## Contributing

Issues and PRs welcome. [`CONTRIBUTING.md`](CONTRIBUTING.md) covers the two rules
that matter — *the engine stays UI-free*, and *the rail lists jobs, not
variations* — plus how to run the tests. Good first issues are tagged.

<div align="center">

**[MIT](LICENSE)** · Built by [Josh Lin](https://github.com/joshlin2201) · If it saved you a trip to Photoshop, star it.

</div>
