<div align="center">

# ItsPaint

### MS Paint for the Mac. Native, free, and a 2.6 MB download.

A blank canvas at the size you asked for, an image dropped on top of another
one, a screenshot marked up and out the door. No workspace to set up, no
account, no subscription, no trial.

[![CI](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml/badge.svg)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/joshlin2201/itspaint?sort=semver&label=release&color=success)](https://github.com/joshlin2201/itspaint/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://github.com/joshlin2201/itspaint/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

![ItsPaint editing a chameleon painting on a transparent canvas](docs/images/editor-window.png)

<img src="docs/images/markup-reel.gif" width="830" alt="Pasting a settings sheet, numbering three steps with badges, and pixelating an API token, in nine seconds">

<img src="docs/images/remove-background.gif" width="830" alt="A product shot on a flat page, then the same window with the background gone and the checkerboard showing through">

<sub><b>Image ▸ Remove Background</b> — one command, no model, no network, and it declines rather
than guessing when the page is not separable.
<a href="docs/BACKGROUND_REMOVAL.md">How it works, in thirty-five lines</a>.</sub>

</div>

## The Mac never shipped a Paint, and the usual answers each miss something

Preview cannot make a blank canvas. Paintbrush has not kept up with macOS. The
capable editors are a gigabyte and cost money, and several of the free ones turn
out to be a trial. So here is the list people actually write out in those
threads, and what each one is in ItsPaint:

| What people ask for | How it works here |
|---|---|
| A blank canvas at the size I choose | `⌘N`, then `Image ▸ Canvas size…` for exact pixels. Set the size you usually want in Settings and `⌘N` is already right |
| Drop an image on top of another image | Drag it in from the Finder or paste with `⌘V`. A dropped image lands centred on the pointer |
| Move and scale it before it sticks | It arrives floating: drag the image, or drag its corner handles |
| Don't crop it when it's bigger than the canvas | The canvas grows to hold it and the window follows |
| Crop | Drag a selection, then `⌘K` |
| Zoom out far enough to see all of it | `⌘9` fits it to the window, and it goes well below 100% |
| A colour picked off the image, as hex | Eyedropper, or `⌥` from any tool. Every swatch shows its hex |
| Show up in right-click ▸ Open With | Registered as an editor for PNG, JPEG, TIFF, BMP, GIF and HEIC |
| Mark up a screenshot properly | Auto-numbered step badges, arrows, highlighter, and pixelate for anything you'd rather not publish |
| Get it into Slack without saving a file first | Drag the image out of the header, straight into the message |
| Be free, and stay free | MIT, no account, no telemetry, no trial, no upsell |

## Install

```bash
brew install --cask joshlin2201/itspaint/itspaint
```

Or get it free on the [Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12),
or download the disk image from [Releases](https://github.com/joshlin2201/itspaint/releases),
open it, and drag **ItsPaint** to Applications.

Releases are signed with a Developer ID, notarised by Apple, and the ticket is
stapled to both the disk image and the app inside it, so nothing has to be
cleared from the Terminal and there is no Control-click dance.

**If macOS says it "could not verify ItsPaint is free of malware", the app is
fine and so is your download — open System Settings ▸ Privacy & Security and
click Open Anyway.** This was observed once on macOS 26.6 with a freshly
downloaded 0.12.0, on the same disk image that `spctl --assess` accepts and whose
stapled ticket validates. It appears to be a first-launch check that went to
Apple and did not come back rather than anything about the build, and it is not
reproducible on demand — but it is alarming enough when it happens that it
belongs here rather than in an issue. You can confirm the download yourself
before opening it:

```bash
shasum -a 256 -c checksums.txt
codesign --verify --deep --strict --verbose=2 /Volumes/ItsPaint*/ItsPaint.app
spctl -a -vvv -t exec /Volumes/ItsPaint*/ItsPaint.app   # expect: accepted
```

Each release includes `checksums.txt` with SHA-256 hashes, and the stapled ticket
means the notarisation check itself needs no network:

```bash
shasum -a 256 -c checksums.txt
xcrun stapler validate ItsPaint-0.13.0.dmg
```

ItsPaint requires macOS 14 Sonoma or later.

To build from source:

```bash
git clone https://github.com/joshlin2201/itspaint.git
cd itspaint
swift test                # the engine — no Xcode project, no dependencies
open ItsPaint.xcodeproj   # the app — build and run with ⌘R
```

The drawing engine is a plain Swift package declared at the repository root, so
`swift build` and `swift test` run the whole engine suite in a fresh clone with a
command-line Swift toolchain and nothing else. Xcode 16 or later is needed only
for the app shell — the `ItsPaint` scheme, and the AppKit tests that need a GUI
session.

## Highlights

- **Eleven visible tools** for drawing, markup, text, selection, colour, and
  pixelation — `ToolKind.allCases.count`, and the rail shows every one.
- **Drag the image straight out** into Slack, Mail or the Finder — no save panel,
  no file left on the Desktop. The selection if there is one, the whole canvas if
  not.
- **Annotation text stays readable on any screenshot** — a contrasting rim,
  on by default, because one text colour cannot work across a light panel and a
  dark one.
- **Fifteen shapes** with solid, dashed, or dotted outlines and optional fills.
- **A one-cell tool rail** — 34pt, the width of the widest control it carries —
  that moves between the left and bottom of the window.
- **Precise canvas control** with pointer-centred zoom, nearest-neighbour display
  above 100%, pixel grids, and live tool footprints.
- **Snap to grid** (`⇧⌘'`) for shapes, selections and pasted content, at 8 to
  64px — never for freehand tools.
- **Rotate by any angle**, with the canvas growing to fit the corners.
- **Universal and notarised** — one build for Apple silicon and Intel, signed
  with a Developer ID, with the notarisation ticket stapled so the check needs no
  network.
- **Native documents and common exports** with no third-party dependencies,
  accounts, telemetry, or cloud service — and [three commands](#no-network-and-how-to-check)
  that check it.

## Tools

| Group | Tools |
|---|---|
| **Draw** | Pencil, Brush (round / square / soft / spray), Highlighter (own ink, four colours), Eraser |
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
| `H` | Highlighter | `E` | Eraser |
| `U` | Shape | `T` | Text |
| `N` | Step Badge | `K` | Fill |
| `I` | Eyedropper | `M` | Select |
| `R` | Pixelate | | |
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

## No network, and how to check

ItsPaint never contacts anything. That is a claim, so here is how to falsify it.

The sandbox is the part that does not require trusting the source. Neither
`com.apple.security.network.client` nor `.server` is requested, so the kernel
refuses an outbound connection regardless of what the code asks for:

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
```

Three entitlements come back — the sandbox itself, read-write access to the
files chosen in an open or save panel, and app-scoped bookmarks so recent
documents reopen without re-prompting. Nothing else.

Nothing links against a networking framework, and nothing links outside the
system at all:

```bash
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
```

No `CFNetwork`, no `Network.framework`, no bundled dylib — every entry on both
architectures is an Apple framework or the Swift runtime.

In the source, across every Swift file in the engine and the app:

```bash
grep -rniE 'URLSession|NWConnection|import Network|CFSocket|getaddrinfo' App Packages
```

Zero matches. `Package.swift` declares no external dependency, so there is no
third-party code to audit behind that.

None of this is a promise about future versions. It is three commands that run
against the build you have.

[**Making "no network" checkable**](docs/PROVING_NO_NETWORK.md) is why they are in
that order — the entitlements check reports what the kernel will permit rather than
what the developer wrote, so it holds even if the developer is lying. It includes a
short `sandbox-exec` profile that reproduces the refusal, and what to do to make the
same claim falsifiable in your own app.

## Design and implementation

ItsPaint has two layers:

```text
Packages/PaintKit/   UI-free drawing engine, raster operations, undo, and codecs
App/                 AppKit document lifecycle, canvas, and SwiftUI interface
```

PaintKit stores pixels as premultiplied RGBA8 and returns the changed rectangle
from every edit. The canvas redraws only that area, and undo history is bounded
by memory rather than by a fixed number of steps.

[**Background removal without a model**](docs/BACKGROUND_REMOVAL.md) is a
worked example of both layers: four corner-seeded flood selections unioned
through the same combiner `⇧`-click uses, and a coverage guard that declines
rather than returning a nearly blank canvas.

PaintKit imports Foundation, CoreGraphics, ImageIO, CoreText and
UniformTypeIdentifiers, and nothing else — no AppKit, no SwiftUI, no third-party
package. That is why the engine tests need no simulator, no GUI session and no
Xcode project, and why most changes to how ItsPaint draws can be made and
verified with a text editor and a terminal.

### Using the engine on its own

PaintKit is a product of the root package, so it can be a dependency of anything
that wants a raster canvas without an editor around it:

```swift
.package(url: "https://github.com/joshlin2201/itspaint.git", from: "0.12.1")
```

```swift
import PaintKit

let engine = PaintEngine(width: 800, height: 600)
engine.removeBackground()            // false when the page is not separable
```

`0.12.1` is a package tag, not an app release — the app is unchanged from
`0.12.0`, and only tags from `0.12.1` onward carry the root manifest.

Run the test suites with:

```bash
swift test                    # engine, from the repository root
swift test -c release         # engine, including the throughput budgets
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
  -destination 'platform=macOS' test
```

## Release notes

ItsPaint is released and under active development. Builds are signed with a
Developer ID and notarised. Text becomes pixels when committed, and WebP export
is not available because macOS does not provide a WebP encoder.

See [CHANGELOG.md](CHANGELOG.md) for version history and
[docs/README.md](docs/README.md) for the design, architecture, feature reference,
testing guide, and roadmap.

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains
the project structure, design constraints, and test requirements.

<div align="center">

[MIT License](LICENSE) · Built by [Josh Lin](https://github.com/joshlin2201)

</div>
