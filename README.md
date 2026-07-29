<div align="center">

# ItsPaint

### A focused paint app for macOS.

Open an image, make a quick edit, and export it without setting up a workspace.
ItsPaint keeps its drawing tools, colours, and palette visible in one native Mac
window.

[![CI](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml/badge.svg)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/joshlin2201/itspaint?include_prereleases&sort=semver&label=beta)](https://github.com/joshlin2201/itspaint/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://github.com/joshlin2201/itspaint/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

![ItsPaint showing a feature tour drawn with the app](docs/images/editor-window.png)

<sub>The artwork in this screenshot was produced by PaintKit, the same engine
used by the editor. The sample is reproducible with
<code>swift run --package-path Packages/PaintKit paint-demo out.png</code>.</sub>

</div>

## Highlights

- **Twelve visible tools** for drawing, markup, text, selection, colour, and
  pixelation.
- **Fifteen shapes** with solid, dashed, or dotted outlines and optional fills.
- **A compact tool rail** that moves between the left and bottom edges of the
  window.
- **Precise canvas control** with pointer-centred zoom, nearest-neighbour display
  above 100%, pixel grids, and live tool footprints.
- **Native documents and common exports** with no third-party dependencies,
  accounts, telemetry, or cloud service.

## Install

Download the latest beta from [Releases](https://github.com/joshlin2201/itspaint/releases),
open the disk image, and drag **ItsPaint** to Applications.

The beta is ad-hoc signed and is not yet notarised. On first launch,
Control-click **ItsPaint**, choose **Open**, then confirm **Open**. If macOS
continues to block the app, clear its download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/ItsPaint.app
```

Each release includes `checksums.txt` with SHA-256 hashes for the downloads.
ItsPaint requires macOS 14 Sonoma or later.

To build from source:

```bash
git clone https://github.com/joshlin2201/itspaint.git
cd itspaint
open ItsPaint.xcodeproj
```

Build and run the **ItsPaint** scheme with `⌘R`. Xcode 16 or later is required.

## Tools

| Group | Tools |
|---|---|
| **Draw** | Pencil, Brush, Airbrush, Highlighter, Eraser |
| **Insert** | Shape, Text, Step Badge, Fill, Eyedropper |
| **Select** | Rectangle, Ellipse, Lasso, Instant Alpha |
| **Effects** | Pixelate |

The Shape tool includes line, curve, arrow, rectangle, rounded rectangle,
ellipse, triangle, right triangle, diamond, pentagon, hexagon, five- and
six-point stars, speech bubble, and polygon.

Instant Alpha selects connected pixels by colour. Use `⇧`-click to add to the
selection, `⌥`-click to subtract, then choose **Make transparent**.

Pixelate is intended for visual de-emphasis, not secure redaction. Use an opaque
filled shape to cover private information before exporting a flattened image.

## Everyday workflow

Paste an image with `⌘V` or open it from Finder. Add arrows, shapes, text, step
badges, highlights, or freehand marks. Floating pasted content and selections can
be moved or resized before they are placed. Export with `⇧⌘E`, or save an
editable `.itspaint` document.

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| `P` | Pencil | `B` | Brush |
| `A` | Airbrush | `H` | Highlighter |
| `E` | Eraser | `U` | Shape |
| `T` | Text | `N` | Step Badge |
| `K` | Fill | `I` | Eyedropper |
| `M` | Select | `R` | Pixelate |
| `X` | Swap colours | `[` / `]` | Change tool size |
| `Space` | Pan | `⌥1`–`⌥9` | Choose a shape |

Pinch or `⌘`-scroll to zoom around the pointer. Hold `⌥` to sample a colour
without changing tools. Right-drag uses the second colour. `Esc` cancels the
current shape, text box, selection, floating paste, or options panel.

## Files and export

ItsPaint documents use the `.itspaint` package format: a lossless PNG with JSON
metadata for the canvas, colours, and palette.

Export supports PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF, and ICO when the
corresponding encoder is available in the installed macOS version. The export
panel includes format and scale controls. Formats without alpha are flattened
onto the second colour.

## Design and implementation

ItsPaint has two layers:

```text
Packages/PaintKit/   UI-free drawing engine, raster operations, undo, and codecs
App/                 AppKit document lifecycle, canvas, and SwiftUI interface
```

PaintKit stores pixels as premultiplied RGBA8 and returns the changed rectangle
from every edit. The canvas redraws only that area, and undo history is bounded
by memory rather than by a fixed number of steps.

Run the test suites with:

```bash
swift test --package-path Packages/PaintKit
swift test -c release --package-path Packages/PaintKit
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
  -destination 'platform=macOS' test
```

## Release notes

ItsPaint is in public beta. Released builds are ad-hoc signed and not notarised.
Text becomes pixels when committed, and WebP export is not available because
macOS does not provide a WebP encoder.

See [CHANGELOG.md](CHANGELOG.md) for version history and
[docs/README.md](docs/README.md) for the design, architecture, feature reference,
testing guide, and roadmap.

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains
the project structure, design constraints, and test requirements.

<div align="center">

[MIT License](LICENSE) · Built by [Josh Lin](https://github.com/joshlin2201)

</div>
