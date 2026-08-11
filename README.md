<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/icon-light.png">
  <img src="docs/images/icon.png" width="116" alt="">
</picture>

# ItsPaint

### MS Paint for the Mac. Open it, draw, close it.

**2.9 MB** · free on the App Store, no trial · MIT ·
**no network entitlement, so the kernel refuses a socket**

[![Release](https://img.shields.io/github/v/release/joshlin2201/itspaint?sort=semver&style=flat-square&label=release&color=2563eb)](https://github.com/joshlin2201/itspaint/releases)
[![Mac App Store](https://img.shields.io/badge/Mac_App_Store-free-2563eb?style=flat-square)](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)
[![MIT](https://img.shields.io/badge/licence-MIT-1f2937?style=flat-square)](LICENSE)
[![tests](https://img.shields.io/github/actions/workflow/status/joshlin2201/itspaint/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/joshlin2201/itspaint/actions/workflows/ci.yml)

```sh
brew tap joshlin2201/itspaint
brew install --cask itspaint
```

**[Download the disk image](https://github.com/joshlin2201/itspaint/releases/latest)** · **[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12)** · macOS 14+, universal

<img src="docs/images/editor-window.png" alt="ItsPaint editing a chameleon painting on a transparent canvas, with the brush options open">

</div>

## What makes it different

- **2.9 MB, and a window on screen in about half a second.** Everything else
  capable is a gigabyte with a subscription attached, and half the free ones turn
  out to be a trial.
- **No network entitlement.** `com.apple.security.network.client` is not
  requested, so the kernel refuses an outbound socket whatever the code asks for —
  [three commands to check it yourself](#no-network-three-commands-to-prove-it).
- **Background removal with no ML model** and nothing to download: four
  corner-seeded flood selections, unioned, and it declines rather than handing you
  a blank canvas — [thirty lines of code](docs/BACKGROUND_REMOVAL.md).
- **The drawing engine has no UI.** `Packages/PaintKit` imports Foundation,
  CoreGraphics and ImageIO and nothing else, so `swift test` verifies most changes
  with no Xcode and no GUI session.
- **Free, not free-for-now.** No account, no subscription, no trial, no telemetry.

It is the app you reach for *between* the real tools — mark up the screenshot,
crop the thing, drag it into Slack, close the window without saving.

## What it does

### Remove a background with no model and no network

<div align="center">

<img src="docs/images/remove-background.gif" alt="A product shot on a flat page, then the same window with the background gone and the checkerboard showing through">

</div>

One command. Four corner-seeded flood selections, unioned. If the page is not
actually separable it says so and changes nothing, instead of handing you a
nearly blank canvas.

**[How it works, in thirty lines of code →](docs/BACKGROUND_REMOVAL.md)**

Its safety check was also wrong for three releases, in a way worth reading about:
it measured how much of the canvas was background, so the better an image fitted the
feature the more certainly it was refused, while its test stayed green and its
documentation defended it —
**[a guard tuned to its test →](docs/A_GUARD_TUNED_TO_ITS_TEST.md)**

### And the rest

- **Drag the image straight out** into Slack, Mail or the Finder. No save panel, no
  `Screenshot 2026-08-07 at 11.42.13.png` left on your Desktop.
- **Paste anything on top of anything.** It arrives floating, and if it is bigger
  than the canvas the canvas grows rather than cropping it.
- **Mark up a screenshot properly.** Auto-numbered step badges, arrows, a
  highlighter with its own ink, pixelate for what you would rather not publish.
- **Annotation text stays readable** on any screenshot — it carries a contrasting
  rim, because one colour cannot work across a light panel and a dark one.
- **Snap to grid** (`⇧⌘'`) at 8–64px for shapes, selections and pasted content.
  Never for freehand: a stroke that jumped to a grid would not be freehand.
- **Fifteen shapes**, four brush nibs, four ways to select — each folded behind one
  rail button rather than sprawling across the window.
- **Real pixel control** — pointer-centred zoom, nearest-neighbour above 100%, a
  pixel grid, live tool footprints, rotate by any angle.

<div align="center">

<img src="docs/images/markup-reel.gif" alt="Pasting a settings sheet, numbering three steps with badges, and pixelating an API token, in nine seconds">

**Paste a screenshot, number three steps, blur the token.**
Nine seconds, no file saved.

</div>

## Install

```bash
brew tap joshlin2201/itspaint
brew install --cask itspaint
```

Or the [disk image](https://github.com/joshlin2201/itspaint/releases) — open it,
drag **ItsPaint** to Applications. Or the
[Mac App Store](https://apps.apple.com/us/app/itspaint/id6796493980?mt=12), free.

It ships often while it is in beta, so **Watch ▸ Custom ▸ Releases** is the quietest
way to hear about a new build.

| | |
|---|---|
| **Requires** | macOS 14 Sonoma or later |
| **Architecture** | universal — one build for Apple silicon and Intel |
| **Signing** | Developer ID, notarised, ticket stapled to the image *and* the app, so the check needs no network and there is nothing to clear from the Terminal |
| **Download** | 2.9 MB, with a SHA-256 in `checksums.txt` |

```bash
shasum -a 256 -c checksums.txt
xcrun stapler validate ItsPaint-*.dmg
```

If macOS asks you to confirm the first launch, open **System Settings ▸ Privacy &
Security** and click **Open Anyway** — [why that happens](#first-launch).

## No network. Three commands to prove it

Not a promise — a property the kernel enforces. Run these against the copy you
installed:

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
grep -rniE 'URLSession|NWConnection|import Network|CFSocket' App Packages
```

| Command | What comes back |
|---|---|
| `codesign` | three — sandbox, files you pick in a panel, app-scoped bookmarks. No `network.client`, no `.server`, so the kernel refuses a socket whatever the code asks for |
| `otool` | Apple frameworks and the Swift runtime, on both architectures. No `CFNetwork`, no `Network.framework`, no bundled dylib |
| `grep` | nothing. And `Package.swift` declares no dependency, so there is no third-party code behind it |

The entitlements check is first on purpose: it reports what the kernel will
*permit*, not what the developer wrote, so it holds even if the developer is lying.

**[Why that order, and how to make the same claim falsifiable in your own app →](docs/PROVING_NO_NETWORK.md)**

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

It is also a dependency you can use without the app. Add it:

```swift
.package(url: "https://github.com/joshlin2201/itspaint", from: "0.13.1")
```

and take a product shot off its page in four lines, on device, with no model and no
network:

```swift
import PaintKit

let engine = PaintEngine(canvas: try ImageCodec.decode(contentsOf: input))
guard engine.removeBackground() else { fatalError("no background to remove") }
try ImageCodec.encode(engine.canvas, as: .png).write(to: output)
```

That snippet is compiled and run against the published tag rather than written out
here, and the check is the transparent-pixel count before and after, not that it
exited without complaining. On a 60px mark centred on a 400×400 page it takes the
count from 0 to 156,400 — which is 160,000 minus the 3,600 pixels of subject.

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

Eleven rail buttons. Variations live inside the tool that owns them — fifteen
shapes behind Shape, four nibs behind Brush, four modes behind Select — so the
whole set stays available without a button each.

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
.package(url: "https://github.com/joshlin2201/itspaint.git", from: "0.13.1")
```

```swift
import PaintKit

let engine = PaintEngine(width: 800, height: 600)
engine.removeBackground()            // false when the page is not separable
```

[docs/README.md](docs/README.md) has the design notes, architecture, feature
reference, testing guide, and roadmap. [CHANGELOG.md](CHANGELOG.md) has the
version history.

</details>

<a id="first-launch"></a>

<details>
<summary><b>First launch, and the Gatekeeper message</b></summary>

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

<div align="center">

**If ItsPaint saved you a trip to the App Store, a ⭐ helps the next person find it.**

[MIT License](LICENSE) · Built by [Josh Lin](https://github.com/joshlin2201)

</div>
