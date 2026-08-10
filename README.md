<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/banner.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/banner-light.png">
  <img src="docs/images/banner.png" width="760" alt="ItsPaint — MS Paint for the Mac. Free and open source, 2.9 MB, no account and no telemetry.">
</picture>

### MS Paint for the Mac.

Open it, draw, close it. **2.9 MB**, free forever, MIT.
No account, no subscription, no trial, no telemetry.

[![Release](https://img.shields.io/github/v/release/joshlin2201/itspaint?sort=semver&style=flat-square&label=release&color=2563eb)](https://github.com/joshlin2201/itspaint/releases)
[![Mac App Store](https://img.shields.io/badge/Mac_App_Store-free-2563eb?style=flat-square)](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-1f2937?style=flat-square)](https://github.com/joshlin2201/itspaint/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-1f2937?style=flat-square)](https://swift.org)
[![MIT](https://img.shields.io/badge/licence-MIT-1f2937?style=flat-square)](LICENSE)
[![tests](https://img.shields.io/github/actions/workflow/status/joshlin2201/itspaint/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)

```
brew tap joshlin2201/itspaint
brew install --cask itspaint
```

**[Download the disk image](https://github.com/joshlin2201/itspaint/releases/latest)** · **[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)**

</div>

---

<div align="center">

<img src="docs/images/markup-reel.gif" alt="Pasting a settings sheet, numbering three steps with badges, and pixelating an API token, in nine seconds">

**Paste a screenshot, number three steps, blur the token.**
Nine seconds, no file saved.

</div>

<br>

## Why this exists

Every few weeks someone asks the internet for MS Paint on a Mac, and the answers
are always the same three. **Preview** cannot make a blank canvas. **Paintbrush**
stopped keeping up with macOS. Everything capable is a gigabyte with a
subscription attached, and half the free ones turn out to be a trial.

ItsPaint is the fourth answer. `⌘N` gives you a blank canvas at the size you
asked for, eleven tools sit on a rail one cell thick, and the whole thing is a
2.9 MB download that puts a window on screen in about half a second.

It is the app you reach for *between* the real tools — mark up the screenshot,
crop the thing, drag it into Slack, close the window without saving.

<br>

## What it does

### Remove a background with no model and no network

<div align="center">

<img src="docs/images/remove-background.gif" alt="A product shot on a flat page, then the same window with the background gone and the checkerboard showing through">

</div>

One command. Four corner-seeded flood selections, unioned. If the page is not
actually separable it says so and changes nothing, instead of handing you a
nearly blank canvas.

**[How it works, in thirty lines of code →](docs/BACKGROUND_REMOVAL.md)**

### And the rest

- **Drag the image straight out** of the window into Slack, Mail or the Finder.
  No save panel, no `Screenshot 2026-08-07 at 11.42.13.png` left on the Desktop.
  The selection if there is one, the whole canvas if not.
- **Paste anything on top of anything.** It arrives floating — drag it, scale it
  from the corners, and if it is bigger than the canvas the canvas grows to hold
  it rather than cropping it.
- **Mark up a screenshot properly.** Auto-numbered step badges, arrows, a
  highlighter with its own ink, and pixelate for whatever you would rather not
  publish.
- **Annotation text that stays readable** on any screenshot, because it carries a
  contrasting rim. One text colour cannot work across a light panel and a dark
  one, so it does not try.
- **Snap to grid** (`⇧⌘'`) at 8 to 64px for shapes, selections and pasted
  content — and never for freehand tools, because a brush stroke that jumped to a
  grid would not be freehand.
- **Fifteen shapes**, four brush nibs, four ways to select, all folded behind one
  rail button each rather than sprawling across the window.
- **Real pixel control** — pointer-centred zoom, nearest-neighbour above 100%, a
  pixel grid, live tool footprints, rotate by any angle with the canvas growing
  to fit the corners.

<div align="center">
<img src="docs/images/editor-window.png" alt="ItsPaint editing a chameleon painting on a transparent canvas">
</div>

<br>

## Install

```bash
brew tap joshlin2201/itspaint
brew install --cask itspaint
```

Or grab the disk image from [Releases](https://github.com/joshlin2201/itspaint/releases),
open it, drag **ItsPaint** to Applications. Or install it free from the
[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12).

Requires macOS 14 Sonoma or later. Universal — one build for Apple silicon and
Intel. Signed with a Developer ID and notarised by Apple, with the ticket stapled
to both the disk image and the app inside it, so the check needs no network and
there is nothing to clear from the Terminal.

Every release ships `checksums.txt`, and you can verify a download before you
open it:

```bash
shasum -a 256 -c checksums.txt
xcrun stapler validate ItsPaint-*.dmg
```

<details>
<summary><b>If macOS says it "could not verify ItsPaint is free of malware"</b></summary>

<br>

**The app is fine and so is your download.** Open **System Settings ▸ Privacy &
Security** and click **Open Anyway**.

This was observed once, on macOS 26.6, with a freshly downloaded 0.12.0 — on the
same disk image that `spctl --assess` accepts and whose stapled ticket validates.
It reads like a first-launch check that went to Apple and did not come back
rather than anything about the build, and it is not reproducible on demand. It is
alarming enough when it happens that it belongs here rather than buried in an
issue.

You can check the download yourself:

```bash
shasum -a 256 -c checksums.txt
codesign --verify --deep --strict --verbose=2 /Volumes/ItsPaint*/ItsPaint.app
spctl -a -vvv -t exec /Volumes/ItsPaint*/ItsPaint.app   # expect: accepted
```

</details>

<br>

## No network, and how to check

ItsPaint never contacts anything. That is a claim, so here is how to falsify it.

Start with the sandbox, because it is the only part that does not require
trusting me. Neither `com.apple.security.network.client` nor `.server` is
requested, so the kernel refuses an outbound connection regardless of what the
code asks for:

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
```

Three entitlements come back — the sandbox itself, read-write access to files
chosen in an open or save panel, and app-scoped bookmarks so recent documents
reopen without re-prompting. Nothing else.

Then check that nothing links against a networking framework, or outside the
system at all:

```bash
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
```

No `CFNetwork`, no `Network.framework`, no bundled dylib — every entry on both
architectures is an Apple framework or the Swift runtime.

Then the source, across every Swift file in the engine and the app:

```bash
grep -rniE 'URLSession|NWConnection|import Network|CFSocket|getaddrinfo' App Packages
```

Zero matches, and `Package.swift` declares no external dependency, so there is no
third-party code hiding behind that.

None of this is a promise about future versions. It is three commands that run
against the build you already have.

> [**Making "no network" checkable**](docs/PROVING_NO_NETWORK.md) explains why
> they are in that order — the entitlements check reports what the kernel will
> permit rather than what the developer wrote, so it holds even if the developer
> is lying. It includes a `sandbox-exec` profile that reproduces the refusal, and
> how to make the same claim falsifiable in your own app.

<br>

## Contributing — the engine needs no Xcode

`Packages/PaintKit` is a **UI-free Swift package**: no AppKit, no SwiftUI, no
third-party dependency. It imports Foundation, CoreGraphics, ImageIO, CoreText
and UniformTypeIdentifiers, and nothing else.

That means most changes to how ItsPaint *draws* can be made and verified with a
text editor and a terminal — no simulator, no GUI session, no Xcode project:

```bash
git clone https://github.com/joshlin2201/itspaint.git
cd itspaint
swift test          # the whole engine suite, in a fresh clone
```

**Five issues are open and labelled [`good first issue`](https://github.com/joshlin2201/itspaint/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)**,
each naming the file and the line to start at:

- [#3](https://github.com/joshlin2201/itspaint/issues/3) — Grow and shrink a selection by a pixel amount
- [#4](https://github.com/joshlin2201/itspaint/issues/4) — Make a selection from the alpha channel
- [#5](https://github.com/joshlin2201/itspaint/issues/5) — Arrowheads as a line style, not a separate shape
- [#6](https://github.com/joshlin2201/itspaint/issues/6) — Flip and rotate the selection, not the whole image
- [#7](https://github.com/joshlin2201/itspaint/issues/7) — Add to and subtract from a selection

[CONTRIBUTING.md](CONTRIBUTING.md) covers the structure, the design constraints,
and what a change has to prove before it lands.

<br>

<details>
<summary><b>Tools and shortcuts</b></summary>

<br>

| Group | Tools |
|---|---|
| **Draw** | Pencil, Brush (round / square / soft / spray), Highlighter (own ink, four colours), Eraser |
| **Insert** | Shape, Text, Step Badge, Fill, Eyedropper |
| **Select** | Rectangle, Ellipse, Lasso, Instant Alpha |
| **Effects** | Pixelate |

Eleven rail buttons — `ToolKind.allCases.count`, and the rail shows every one.
Variations stay inside the tool that owns them rather than becoming another
button: fifteen shapes share the Shape button, four selection modes share Select,
four nibs share Brush.

The Shape tool covers line, curve, arrow, rectangle, rounded rectangle, ellipse,
triangle, right triangle, diamond, pentagon, hexagon, five- and six-point stars,
speech bubble, and polygon.

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| `P` | Pencil | `B` | Brush |
| `H` | Highlighter | `E` | Eraser |
| `U` | Shape | `T` | Text |
| `N` | Step Badge | `K` | Fill |
| `I` | Eyedropper | `M` | Select |
| `R` | Pixelate | `X` | Swap colours |
| `[` / `]` | Change tool size | `Space` | Pan |
| `⌥1`–`⌥9` | Choose a shape | `⇧⌘'` | Snap to grid |
| `⌘K` | Crop to selection | `⌘9` | Fit to window |
| `⇧⌘E` | Export | `⌘V` | Paste as a floating image |

Pinch or `⌘`-scroll to zoom around the pointer. Hold `⌥` to sample a colour
without changing tools. Right-drag uses the second colour. `Esc` cancels the
current shape, text box, selection, floating paste, or options panel.

Instant Alpha selects connected pixels by colour — `⇧`-click adds, `⌥`-click
subtracts, then **Make transparent**.

Pixelate is for visual de-emphasis, not secure redaction. Cover private
information with an opaque filled shape before you export a flattened image.

</details>

<details>
<summary><b>Files and export</b></summary>

<br>

ItsPaint documents use the `.itspaint` package format: a lossless PNG with JSON
metadata for the canvas, colours, and palette.

Export supports PNG, JPEG, TIFF, BMP, GIF, HEIC, AVIF, PDF, and ICO when the
corresponding encoder ships with the installed macOS version. The export panel
has format and scale controls, and formats without alpha are flattened onto the
second colour.

ItsPaint registers as an editor for PNG, JPEG, TIFF, BMP, GIF and HEIC, so it
appears under right-click ▸ **Open With**.

WebP export is not available, because macOS does not provide a WebP encoder.
Text becomes pixels when it is committed.

</details>

<details>
<summary><b>How it is built</b></summary>

<br>

```text
Packages/PaintKit/   UI-free drawing engine, raster operations, undo, and codecs
App/                 AppKit document lifecycle, canvas, and SwiftUI interface
```

PaintKit stores pixels as premultiplied RGBA8 and returns the changed rectangle
from every edit. The canvas redraws only that area, and undo history is bounded
by memory rather than by a fixed number of steps.

[**Background removal without a model**](docs/BACKGROUND_REMOVAL.md) is a worked
example of both layers: four corner-seeded flood selections unioned through the
same combiner `⇧`-click uses, and a remainder guard that declines rather than
returning a nearly blank canvas.

**Using the engine on its own.** PaintKit is a product of the root package, so it
can be a dependency of anything that wants a raster canvas without an editor
around it:

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

```bash
swift test                    # engine, from the repository root
swift test -c release         # engine, including the throughput budgets
xcodebuild -project ItsPaint.xcodeproj -scheme ItsPaint \
  -destination 'platform=macOS' test
```

Xcode 16 or later is needed only for the app shell — the `ItsPaint` scheme and
the AppKit tests that need a GUI session.

[docs/README.md](docs/README.md) has the design notes, architecture, feature
reference, testing guide, and roadmap. [CHANGELOG.md](CHANGELOG.md) has the
version history.

</details>

<br>

<div align="center">

**If ItsPaint saved you a trip to the App Store, a ⭐ helps the next person find it.**

[MIT License](LICENSE) · Built by [Josh Lin](https://github.com/joshlin2201)

</div>
